using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { EnergySystem.TooltipKit }

# Notification that the energy amount changed
# Direction: from the energy_component's entity upward (SendUp). Sent only when the amount differs from the last notified one (after a Spend[], sent after physics in the same frame (TickEvents.PostPhysics))
# Receivers: ancestors (for an item, up to the owning player). Not consumed
energy_changed_event<public> := class(scene_event):
    # The energy_component that sent it (ratio via Energy.GetRatio(), max via Energy.GetMax())
    Energy<public>:energy_component
    # The amount after the change (0 to max)
    Amount<public>:float
    # Difference from the last notified amount. Positive when increased, negative when decreased
    Delta<public>:float

# Role: holds an amount of energy. Starts full with StartFull, otherwise at 0. Sends energy_changed_event upward when the amount changes
# Placement: attach to an entity in the editor (the entity of the ability or item that uses energy, or a child of it). For per-player energy, attach it at run time to the player (the agent's entity) (abilities find it with FindEnergyFor)
# From outside: change the amount with Consume / Restore / SetAmount / Fill / SetMax (energy_changed_event and ChangedEvent at once on a change). To subtract only when there is enough, write if (Energy.Spend[10.0]) (fails and changes nothing when not enough; notifies after physics in the same frame)
#   The amount is clamped to 0..max (GetMax). MaxEnergy is the initial max set in the editor; after SetMax, read the max with GetMax
# When: subscribes to TickEvents.PostPhysics and sends the notification for what Spend[] subtracted (nothing on frames without a Spend[])
# ⚠ Unverified: whether a Spend[] inside PrePhysics or OnSimulate is notified in the PostPhysics of that same frame (in UEFN; at worst the next frame)
energy_component<public> := class<final_super>(component):

    # Initial maximum set in the editor (default 100.0). After SetMax, read the max with GetMax
    @editable_number(float):
        ToolTip := MaxEnergyToolTip
        Categories := array{EnergyCategory, EnergyAmountCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MaxEnergy<public>:float = 100.0
    # true (default) starts full. false starts at 0 (fill it with a checkpoint or a restore before use)
    @editable:
        ToolTip := EnergyStartFullToolTip
        Categories := array{EnergyCategory, EnergyAmountCategory}
    StartFull<public>:logic = true

    # Current amount (0 to max). 0.0 if no amount-changing function was called before the simulation started
    var<private> CurrentAmount<public>:float = 0.0

    ChangedEventInternal<private><final>:event(float) = event(float){}

    # Fires with the new amount each time it changes (same timing as energy_changed_event) (Await / Subscribe; cannot be signaled from outside)
    ChangedEvent<public><final>:listenable(float) = MakeProxyListenable(ChangedEventInternal)

    var Initialized<private>:logic = false
    var MaxOverride<private>:?float = false
    var NotifiedAmount<private>:float = 0.0
    var NotifyPending<private>:logic = false
    var FlushSubscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        EnsureInitialized()
        set FlushSubscription = option{TickEvents.PostPhysics.Subscribe(OnPostPhysics)}

    OnEndSimulation<override>():void =
        FlushSubscription.CancelIfSet()
        set FlushSubscription = false
        (super:)OnEndSimulation()

    # Current maximum. Same as MaxEnergy until SetMax is called
    GetMax<public>()<reads>:float =
        if (Override := MaxOverride?) then Override else MaxEnergy

    # Succeeds if the amount is 0 or less
    IsEmpty<public>()<decides><reads>:void =
        CurrentAmount <= 0.0

    # Succeeds if the amount is at or above the maximum (GetMax)
    IsFull<public>()<decides><reads>:void =
        CurrentAmount >= GetMax()

    # Succeeds if the amount is at least Amount (checks whether Spend[] would succeed, without changing the amount). Fails if Amount is negative
    HasEnough<public>(Amount:float)<decides><reads>:void =
        Amount >= 0.0
        CurrentAmount >= Amount

    # Amount / max (0.0 to 1.0). 0.0 when the max is 0
    GetRatio<public>()<reads>:float =
        CurrentMax := GetMax()
        if (CurrentMax > 0.0):
            CurrentAmount / CurrentMax
        else:
            0.0

    # Subtracts Amount if the amount is at least Amount. Fails and changes nothing if not enough (or Amount is negative). Usable in an if condition (e.g. if (Energy.Spend[10.0]):)
    # The amount (CurrentAmount) changes at once. The notification (SendUp, Signal) cannot be rolled back, so energy_changed_event and ChangedEvent are sent after physics in the same frame (TickEvents.PostPhysics) (if the amount is changed earlier with Consume etc., everything is sent together then)
    Spend<public>(Amount:float)<decides><transacts>:void =
        EnsureInitialized()
        HasEnough[Amount]
        set CurrentAmount = CurrentAmount - Amount
        set NotifyPending = true

    # Subtracts Amount. Never fails; stops at 0 when not enough (e.g. subtracting every frame while hovering). Sends energy_changed_event upward at once on a change
    Consume<public>(Amount:float):void =
        EnsureInitialized()
        SetEnergy(CurrentAmount - Amount)

    # Adds Amount. The part above the max is discarded. Sends energy_changed_event upward at once on a change
    Restore<public>(Amount:float):void =
        EnsureInitialized()
        SetEnergy(CurrentAmount + Amount)

    # Sets the amount to Value (clamped to 0..max). Sends energy_changed_event upward at once on a change. When called before the simulation starts, StartFull does not overwrite it at the start
    SetAmount<public>(Value:float):void =
        EnsureInitialized()
        SetEnergy(Value)

    # Fills to the maximum. Sends energy_changed_event upward at once on a change
    Fill<public>():void =
        EnsureInitialized()
        SetEnergy(GetMax())

    # Changes the maximum to NewMax (negative becomes 0). If the current amount exceeds the new max, clamps it and sends energy_changed_event upward
    # When called before the amount is set (before the simulation starts), does not notify; the simulation starts with the new max (full with StartFull)
    SetMax<public>(NewMax:float):void =
        set MaxOverride = option{Max(NewMax, 0.0)}
        if (Initialized?):
            SetEnergy(CurrentAmount)

    # Fixes the initial amount (the max with StartFull, otherwise 0). Only once
    EnsureInitialized<private>()<transacts>:void =
        if (not Initialized?):
            set Initialized = true
            set CurrentAmount = if (StartFull?) then GetMax() else 0.0
            set NotifiedAmount = CurrentAmount

    SetEnergy<private>(Value:float):void =
        set CurrentAmount = Clamp(Value, 0.0, GetMax())
        Notify()

    OnPostPhysics<private>(DeltaTime:float):void =
        if (NotifyPending?):
            Notify()

    # If the amount differs from the last notified one, sends energy_changed_event upward and fires ChangedEvent
    Notify<private>():void =
        set NotifyPending = false
        if (CurrentAmount <> NotifiedAmount):
            Delta := CurrentAmount - NotifiedAmount
            set NotifiedAmount = CurrentAmount
            Entity.SendUp(energy_changed_event{Energy := Self, Amount := CurrentAmount, Delta := Delta})
            ChangedEventInternal.Signal(CurrentAmount)

# The energy_component on InEntity itself, or else the first found among its descendants. With several descendants it is unspecified which one is returned (assumes only one is placed). Fails if none
(InEntity:entity).FindEnergy<public>()<decides><transacts>:energy_component =
    if (Energy := InEntity.GetComponent[energy_component]):
        Energy
    else:
        first (Energy : InEntity.FindDescendantComponents(energy_component)):
            Energy

# Finds the energy an ability (e.g. an ability_component subclass on InEntity) uses for Agent. In order:
#   1. the energy_component on InEntity itself or its descendants (FindEnergy). Placed on an item's entity, it is that item's energy. Everyone granted shares the same amount
#   2. the energy_component on Agent (the player's entity) itself. Per-player energy (does not search the inventory)
# Fails if neither exists (the ability runs without using energy)
(InEntity:entity).FindEnergyFor<public>(Agent:agent)<decides><transacts>:energy_component =
    if (Energy := InEntity.FindEnergy[]):
        Energy
    else:
        Agent.GetComponent[energy_component]

# The energy_component on InEntity itself or its descendants (FindEnergy), or else one on an ancestor (nearest first). Fails if none
# Place one energy_component at the root of a loadout or custom character and every part inside uses the same energy
(InEntity:entity).FindEnergyAbove<public>()<decides><transacts>:energy_component =
    if (Energy := InEntity.FindEnergy[]):
        Energy
    else:
        var Current:?entity = if (Parent := InEntity.GetParent[]) then option{Parent} else false
        var Found:?energy_component = false
        loop:
            if (Found?):
                break
            if (Candidate := Current?):
                if (Energy := Candidate.GetComponent[energy_component]):
                    set Found = option{Energy}
                set Current = if (Parent := Candidate.GetParent[]) then option{Parent} else false
            else:
                break
        Found?
