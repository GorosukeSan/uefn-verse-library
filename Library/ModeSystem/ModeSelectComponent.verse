using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { ModeSystem.TooltipKit }

# Notification that the selected mode changed (decided, changed or cleared)
# Direction: the whole scope (SendScoped; the whole world without a scope)
# Sender: mode_select_component. Receivers: mode_selected_condition_component, screens that show the mode, etc. Not consumed
mode_changed_event<public> := class(scene_event):
    # The mode_select_component that sent it
    Selector<public>:mode_select_component
    # The newly selected mode. false when cleared
    Mode<public>:?game_mode_component

# Role: holds the selectable modes (child game_mode_components) and remembers the mode decided by TrySelect while accepting. Sends mode_changed_event to the whole scope when decided, changed or cleared. The selection is cleared when accepting ends
# Placement: attach to an entity in the editor. One per scope (or world) (conditions and screens find it with FindScopedComponent)
# Children: entities with game_mode_component, one each directly under it (the candidate order is each mode's Order)
# When it accepts: from the activation signal (activated_event) to the deactivation signal (deactivated_event). From the start of the simulation when ActiveOnBegin is true. Activate / Deactivate can also be called from code
# How it decides: when AllowReselect is false, the first decided mode stays (later TrySelect calls do nothing until cleared). When true, a later TrySelect can change it. To decide by majority vote, place mode_vote_component on the same entity (VoteKit)
# Notifies: sends mode_changed_event to the whole scope and fires SelectedEvent
# From outside: TrySelect / Clear / Activate / Deactivate. Query the current state with IsActive / FindSelected / IsSelected / GetModes
mode_select_component<public> := class<final_super>(component):

    # true accepts from the start of the simulation. false waits for the activation signal. Default false
    @editable:
        ToolTip := ModeActiveOnBeginToolTip
        Categories := array{ModeCategory}
    ActiveOnBegin<public>:logic = false

    # true lets TrySelect change the mode after it is decided. false keeps the first decided mode. Default false
    @editable:
        ToolTip := ModeAllowReselectToolTip
        Categories := array{ModeCategory}
    AllowReselect<public>:logic = false

    # The selected mode. false when not decided
    var<private> Selected<public>:?game_mode_component = false
    var<private> Active:logic = false

    SelectedEventInternal<private><final>:event(?game_mode_component) = event(?game_mode_component){}

    # Fires when a mode is decided or changed (option{Mode}) and when the selection is cleared (false) (Await / Subscribe; cannot be signaled from outside)
    SelectedEvent<public><final>:listenable(?game_mode_component) = MakeProxyListenable(SelectedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        set Active = false
        Clear()
        (super:)OnEndSimulation()

    # Starts accepting (TrySelect takes effect). Does nothing if already accepting
    Activate<public>():void =
        set Active = true

    # Stops accepting and clears the selection (sends mode_changed_event{Mode := false} if a mode was decided)
    Deactivate<public>():void =
        set Active = false
        Clear()

    # Succeeds while accepting (from Activate to Deactivate)
    IsActive<public>()<decides><transacts>:void =
        Active?

    # The selected mode. Fails when not decided
    FindSelected<public>()<decides><transacts>:game_mode_component =
        Selected?

    # Succeeds if Mode is selected
    IsSelected<public>(Mode:game_mode_component)<decides><transacts>:void =
        Selected? = Mode

    # List of selectable modes. Returns the game_mode_components of the direct children by ascending Order (grandchildren ignored; the order among equal Orders is unspecified)
    GetModes<public>()<transacts>:[]game_mode_component =
        SortModesByOrder(Entity.GetChildComponents(game_mode_component))

    # While accepting, decides on Mode and sends mode_changed_event{Mode := option{Mode}} to the whole scope. true if it took effect. Does nothing and returns false when not accepting, when already decided and AllowReselect is false, or when Mode is already selected
    TrySelect<public>(Mode:game_mode_component):logic =
        if (not Active?):
            return false
        if (Current := Selected?):
            if (Current = Mode or not AllowReselect?):
                return false
        set Selected = option{Mode}
        Entity.SendScoped(mode_changed_event{Selector := Self, Mode := Selected})
        SelectedEventInternal.Signal(Selected)
        true

    # Clears the selection (does nothing when not decided). Sends mode_changed_event{Mode := false} to the whole scope. While accepting, TrySelect can decide again afterwards
    Clear<public>():void =
        if (Selected?):
            set Selected = false
            Entity.SendScoped(mode_changed_event{Selector := Self, Mode := false})
            SelectedEventInternal.Signal(false)

# Sorts Modes by ascending Order (keeps the order among equal Orders)
SortModesByOrder<internal>(Modes:[]game_mode_component)<transacts>:[]game_mode_component =
    var Sorted:[]game_mode_component = array{}
    for (Mode : Modes):
        var Inserted:logic = false
        var Next:[]game_mode_component = array{}
        for (Existing : Sorted):
            if (not Inserted?, Mode.Order < Existing.Order):
                set Next += array{Mode}
                set Inserted = true
            set Next += array{Existing}
        if (not Inserted?):
            set Next += array{Mode}
        set Sorted = Next
    Sorted
