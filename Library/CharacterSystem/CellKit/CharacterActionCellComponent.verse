using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# Actions that use action cells (each use spends one cell)
character_cell_action<public> := enum:
    # Jump once more in the air (MoveKit's jump. The body's remaining AirJumps are used first; once gone, jump with a cell)
    AirJump
    # Short dash (MoveKit's dash. Possible on a RequiresGrant body as long as there is a cell)
    Boost
    # In the air, kick off a nearby wall and jump away from it (MoveKit's jump. The WallKick* values)
    WallKick

# One cell grant (returned by character_action_cell_component.AddGrant). Makes Action usable and adds Cells cells
#   With Refills, the cells are refilled whenever the body lands (timed effect. It ends when RemoveGrant is called)
#   Without Refills, the grant disappears once the cells are used up (ExhaustedEvent. Single-use effect)
character_cell_grant<public> := class<unique><internal>:
    Action<public>:character_cell_action
    Cells<public>:int
    Refills<public>:logic
    ExhaustedEventInternal<internal><final>:event() = event(){}
    # Arrives when the cells are used up and this grant disappears (non-Refills grants only)
    ExhaustedEvent<public>:listenable(tuple()) = MakeProxyListenable(ExhaustedEventInternal)
    var Active<internal>:logic = true

    # Succeeds while still attached (fails once used up or removed by RemoveGrant)
    IsActive<public>()<decides><transacts>:void =
        Active?

# Role: action cells. Holds the charge (cells) shared by air jump, boost and wall kick. Each use spends one
#   Cells come from grants (character_cell_grant): one grant makes its Action usable and raises capacity and remaining by Cells (capacity up to MaxCells)
#   Usable when some attached grant has the Action and at least 1 cell remains. Every action spends from the same pool
#   The remaining cells are counted as "single-use" and "refilled on landing"; spending takes from the single-use part first. When the single-use part reaches 0, non-Refills grants (single-use effects) disappear (ExhaustedEvent)
#   The part from Refills grants (timed effects, effects from the start of the stage) is refilled on landing (the single-use part is not)
#   When a grant is removed (RemoveGrant), capacity drops by its share and the remaining cells are cut to the capacity
# Placement: in the editor, attach to the same entity as character_motor_component (MoveKit's jump / dash look here). Grants come from CellKit's character_action_cell_grant_component (effect prefab) or AddGrant in code
# Notifications: ChangedEvent (remaining / capacity changed), SpentEvent (spent, with the action used)
# From outside: AddGrant / RemoveGrant / CanUse / TrySpend / GetCells / GetSingleUseCells / GetCapacity / HasAction / Refill
character_action_cell_component<public> := class<final_super>(component):

    # Maximum number of cells (never more than this, however many grants are stacked). Default 6
    @editable_number(int):
        ToolTip := CellMaxCellsToolTip
        Categories := array{CharacterCellCategory}
        MinValue := option{1}
        MaxValue := option{20}
    MaxCells<public>:int = 6
    # When on, while a Refills grant is attached, also refill when clinging to a wall / ceiling (same as landing). Default off
    @editable:
        ToolTip := CellRefillOnClingToolTip
        Categories := array{CharacterCellCategory}
    RefillOnCling<public>:logic = false

    ChangedEventInternal<private><final>:event() = event(){}
    SpentEventInternal<private><final>:event(character_cell_action) = event(character_cell_action){}

    # Arrives whenever remaining or capacity changes
    ChangedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(ChangedEventInternal)
    # Arrives whenever a cell is spent, with the action used
    SpentEvent<public><final>:listenable(character_cell_action) = MakeProxyListenable(SpentEventInternal)

    var<private> Grants:[]character_cell_grant = array{}
    # Remaining: the share of single-use grants (not refilled on landing) and the share of refilled grants. Spending takes from the single-use share first
    var<private> SingleLeft:int = 0
    var<private> RefillLeft:int = 0
    var<private> Motor:?character_motor_component = false
    var<private> Subscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Found := Entity.GetComponent[character_motor_component]):
            set Motor = option{Found}
            set Subscription = option{Found.PostMoveEvent.Subscribe(OnPostMove)}
        else:
            Print("[character_action_cell_component] no character_motor_component on the same entity (cells will not refill on landing)")

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        (super:)OnEndSimulation()

    # Adds a grant: makes Action usable and raises capacity and remaining by Cells (up to MaxCells in total). Pass the returned grant to RemoveGrant to remove it
    AddGrant<public>(Action:character_cell_action, Cells:int, Refills:logic):character_cell_grant =
        Grant := character_cell_grant{Action := Action, Cells := Max(Cells, 0), Refills := Refills}
        set Grants += array{Grant}
        if (Refills?):
            set RefillLeft += Grant.Cells
        else:
            set SingleLeft += Grant.Cells
        ClampToMax()
        ChangedEventInternal.Signal()
        Grant

    # Removes a grant (timed out, effect stopped). Capacity drops by its share and the remaining cells are cut to the capacity. Does nothing if already removed
    RemoveGrant<public>(Grant:character_cell_grant):void =
        if (Grant.Active?):
            set Grant.Active = false
            set Grants = for (Other : Grants, Other <> Grant) { Other }
            set SingleLeft = Min(SingleLeft, SumCells(false))
            set RefillLeft = Min(RefillLeft, SumCells(true))
            ClampToMax()
            ChangedEventInternal.Signal()

    # Capacity (sum of Cells of the attached grants. Up to MaxCells)
    GetCapacity<public>()<transacts>:int =
        Min(SumCells(false) + SumCells(true), MaxCells)

    # Remaining (single-use share plus refilled share)
    GetCells<public>()<transacts>:int =
        SingleLeft + RefillLeft

    # The part of the remaining cells not refilled on landing (from single-use grants)
    GetSingleUseCells<public>()<transacts>:int =
        SingleLeft

    # Succeeds if some attached grant has Action (remaining is not checked)
    HasAction<public>(Action:character_cell_action)<decides><transacts>:void =
        Found := for (Grant : Grants, Grant.Action = Action) { Grant }
        Found.Length > 0

    # Succeeds if Action can be used now (a grant exists and at least 1 cell remains)
    CanUse<public>(Action:character_cell_action)<decides><transacts>:void =
        HasAction[Action]
        SingleLeft + RefillLeft > 0

    # Spends one cell to perform Action. false if not possible (nothing changes)
    #   Takes from the single-use share first. When it reaches 0, the single-use grants disappear (ExhaustedEvent)
    TrySpend<public>(Action:character_cell_action):logic =
        if (not CanUse[Action]):
            return false
        if (SingleLeft > 0):
            set SingleLeft -= 1
            SpentEventInternal.Signal(Action)
            if (SingleLeft <= 0):
                ExhaustSingleUse()
        else:
            set RefillLeft -= 1
            SpentEventInternal.Signal(Action)
        ChangedEventInternal.Signal()
        true

    # Refills the refillable share to full (does nothing without a refillable grant. The single-use share is not refilled). Called automatically on landing
    Refill<public>():void =
        Target := Min(SumCells(true), Max(MaxCells - SingleLeft, 0))
        if (RefillLeft < Target):
            set RefillLeft = Target
            ChangedEventInternal.Signal()

    # Sum of Cells of the grants whose Refills equals Refills
    SumCells<private>(Refills:logic)<transacts>:int =
        var Sum:int = 0
        for (Grant : Grants, Grant.Refills = Refills):
            set Sum += Grant.Cells
        Sum

    # Cuts the total remaining to MaxCells (from the single-use share first)
    ClampToMax<private>():void =
        Over := SingleLeft + RefillLeft - MaxCells
        if (Over > 0):
            Cut := Min(Over, SingleLeft)
            set SingleLeft -= Cut
            set RefillLeft = Max(RefillLeft - (Over - Cut), 0)

    # Used up: removes the non-Refills grants and sends each one's ExhaustedEvent
    ExhaustSingleUse<private>():void =
        Spent := for (Grant : Grants, not Grant.Refills?) { Grant }
        for (Grant : Spent):
            set Grant.Active = false
        set Grants = for (Grant : Grants, Grant.Refills?) { Grant }
        set SingleLeft = 0
        for (Grant : Spent):
            Grant.ExhaustedEventInternal.Signal()

    OnPostMove<private>(DeltaTime:float):void =
        if (Found := Motor?):
            if (Found.IsGrounded[] or (RefillOnCling? and Found.IsClinging[])):
                Refill()

# Role: from the activation signal to the deactivation signal, adds a grant to the custom character body's action cells (character_action_cell_component). Put it in a PickupSystem effect prefab to make an action usable on pickup
#   Makes Action usable and adds Cells cells
#   Single-use (RefillOnLanding off): when the cells are used up the grant disappears and activation_finished_event is sent up (in an effect prefab, the effect ends). Even inside a timed effect, it ends once used up
#   Timed (RefillOnLanding on): while the effect lasts, cells are refilled on landing even after being used up. Removed by the deactivation signal (the effect timing out)
#   Which body it affects: (1) the body on this entity or an ancestor, (2) the owner's body (under the player's slot: effect prefab or loadout), (3) the body of the agent in an activation signal that says who triggered it
# Placement: in the editor, attach to the root of a PickupSystem effect prefab (same entity as pickup_effect_component) or a child. The body must carry character_action_cell_component
# When: from the activation signal to the deactivation signal. From start with ActiveOnBegin
# Notifications: when used up, activation_finished_event up from its own entity (SendUp)
# From outside: Apply / Remove / IsApplied
character_action_cell_grant_component<public> := class<final_super>(component):

    # Action to make usable. Default AirJump
    @editable:
        ToolTip := CellGrantActionToolTip
        Categories := array{CharacterCellCategory}
    Action<public>:character_cell_action = character_cell_action.AirJump
    # Number of cells to add. Default 1
    @editable_number(int):
        ToolTip := CellGrantCellsToolTip
        Categories := array{CharacterCellCategory}
        MinValue := option{1}
        MaxValue := option{20}
    Cells<public>:int = 1
    # When on, cells are refilled on landing while attached (for timed effects). When off, disappears once used up. Default off
    @editable:
        ToolTip := CellGrantRefillToolTip
        Categories := array{CharacterCellCategory}
    RefillOnLanding<public>:logic = false
    # When on, adds from start without waiting for the activation signal. Default off
    @editable:
        ToolTip := CellGrantActiveOnBeginToolTip
        Categories := array{CharacterCellCategory}
    ActiveOnBegin<public>:logic = false

    var<private> Grant:?character_cell_grant = false
    var<private> CellsComponent:?character_action_cell_component = false
    var<private> Watch:?cancelable = false

    OnSimulate<override>()<suspends>:void =
        if (ActiveOnBegin?):
            Sleep(0.0)
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Remove()
        false

    OnEndSimulation<override>():void =
        Remove()
        (super:)OnEndSimulation()

    # Adds the grant to the body's action cells (does nothing if already added). Activator is a hint for finding the body
    Apply<public>(Activator:?agent):void =
        if (Grant?):
            return
        if (Motor := FindTargetMotor[Activator], Found := Motor.Entity.GetComponent[character_action_cell_component]):
            Made := Found.AddGrant(Action, Cells, RefillOnLanding)
            set Grant = option{Made}
            set CellsComponent = option{Found}
            set Watch = option{Made.ExhaustedEvent.Subscribe(OnExhausted)}
        else:
            Print("[character_action_cell_grant_component] no action cells to affect (character_action_cell_component on the same entity as character_motor_component)")

    # Removes the added grant (does nothing if not added)
    Remove<public>():void =
        Watch.CancelIfSet()
        set Watch = false
        if (Made := Grant?, Found := CellsComponent?):
            Found.RemoveGrant(Made)
        set Grant = false
        set CellsComponent = false

    # Succeeds if currently added (fails once used up)
    IsApplied<public>()<decides><transacts>:void =
        Made := Grant?
        Made.IsActive[]

    # Used up: cleans up its own share and notifies upward that its job is done (in an effect prefab, the effect ends)
    OnExhausted<private>():void =
        Watch.CancelIfSet()
        set Watch = false
        set Grant = false
        set CellsComponent = false
        Entity.SendUp(activation_finished_event{})

    FindTargetMotor<private>(Activator:?agent)<decides><transacts>:character_motor_component =
        if (Above := Entity.FindCharacterMotorAbove[]):
            Above
        else if (Owner := Entity.FindOwningPlayer[], Motor := Entity.FindCharacterMotorFor[Owner]):
            Motor
        else:
            Entity.FindCharacterMotorFor[Activator?]
