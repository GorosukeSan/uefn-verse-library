using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { PlayerSystem }
using { SceneGraphSystem }
using { InputSystem }
using { InputSystem.TooltipKit }

# Role: while active, adds InputMapping to every player; when InputAction is pressed, sends player_input_triggered_event to the whole zone and fires TriggeredEvent with the agent who pressed
# Placement: attach to an entity in the editor. Any number per entity (each handles a different mapping). The same InputMapping may be used by several (stopping one does not cut the input of the ones still running)
# Parent: wherever the activation signal arrives (for the game flow, the node's entity or a descendant)
# When: from the activation signal (activated_event) to the deactivation signal (deactivated_event). From the start of the simulation when ActiveOnBegin is true. Activate / Deactivate may also be called from code
# Notifies: sends player_input_triggered_event to the whole zone and fires TriggeredEvent
# Requirements: one player_manager_component in the zone (or the world)
player_input_component<public> := class<final_super>(component):

    # When true, accepts input from the start of the simulation. When false, from the activation signal (default false)
    @editable:
        ToolTip := InputActiveOnBeginToolTip
        Categories := array{InputCategory}
    ActiveOnBegin<public>:logic = false

    # The key mapping added to every player while accepting input (default MenuNavigationMapping)
    @editable:
        ToolTip := InputMappingToolTip
        Categories := array{InputCategory, InputMappingCategory}
    InputMapping<public>:input_mapping = MenuNavigationMapping
    # The action whose press is notified. Choose one contained in InputMapping (default NextTab = E key, RB on gamepad)
    @editable:
        ToolTip := InputActionToolTip
        Categories := array{InputCategory, InputActionCategory}
    InputAction<public>:input_action(logic) = NextTab

    TriggeredEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the agent who pressed every time InputAction is pressed (Await / Subscribe; cannot be Signaled from outside)
    TriggeredEvent<public><final>:listenable(agent) = MakeProxyListenable(TriggeredEventInternal)

    Views<private>:player_view_set = player_view_set{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    # Starts accepting input (adds InputMapping to everyone present and to late joiners). Does nothing when already accepting
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # Stops accepting input (removes InputMapping from everyone. Mappings of other player_input_components still running for the same player are re-added). Does nothing when not accepting
    Deactivate<public>():void =
        Views.Deactivate()

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # Succeeds while active
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        player_input_view_component:
            Entity := ViewEntity
            Source := Self
            Player := Slot.Player

    # Called from the view. Notifies the press to the whole zone and to TriggeredEvent
    NotifyTriggered<internal>(Player:player):void =
        Entity.SendScoped(player_input_triggered_event{Input := Self, Agent := Player, Action := InputAction})
        TriggeredEventInternal.Signal(Player)

# Role: handles one player's key mapping and the notification when pressed
# Placement: created at runtime by player_input_component (not placed in the editor)
# When: waits frame by frame until the player's input (player_input) is available (right after joining or right after the simulation starts it may not be yet), then adds InputMapping and subscribes to InputAction. Does nothing when the player leaves before it is available
# Requirements: when stopping, after removing InputMapping, re-adds the InputMappings of other player_input_view_components still running for the same player (under the same slot).
#   input_mapping cannot be compared (there is no equality check), so all are re-added without telling whether they are the same mapping. Assumes the engine does not count AddInputMapping (same as HoldInputMapping in InputHelpers)
#   ⚠ Unverified: if the engine does count AddInputMapping, the re-added ones stay until the end. Whether an input mid-press is cut when a mapping is removed and re-added in the same frame
player_input_view_component<public> := class<final_super>(component):

    # The player_input_component that created this view
    Source<public>:player_input_component
    # The player this view handles
    Player<public>:player

    var Subscription<private>:?cancelable = false
    # The input InputMapping was added to (from adding until removal)
    var AddedTo<private>:?player_input = false

    # Succeeds while InputMapping is added (fails before the input is available and after stopping)
    IsMappingAdded<internal>()<decides><transacts>:void =
        AddedTo?

    OnSimulate<override>()<suspends>:void =
        MaybeInput := Player.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            PlayerInput.AddInputMapping(Source.InputMapping)
            set AddedTo = option{PlayerInput}
            ActionSubscription := PlayerInput.GetInputEvents(Source.InputAction).TriggerActivationEvent.Subscribe(OnTriggered)
            set Subscription = option{ActionSubscription}

    OnEndSimulation<override>():void =
        Subscription.CancelIfSet()
        set Subscription = false
        if (PlayerInput := AddedTo?):
            set AddedTo = false
            PlayerInput.RemoveInputMapping(Source.InputMapping)
            RestoreOtherMappings(PlayerInput)
        (super:)OnEndSimulation()

    # Re-adds the InputMappings of other views still running under the same slot (so their input is not cut even if the removed mapping was the same one)
    RestoreOtherMappings<private>(PlayerInput:player_input):void =
        if (Slot := Entity.GetParent[]):
            for:
                ViewEntity : Slot.GetEntities()
                Other := ViewEntity.GetComponent[player_input_view_component]
                Other <> Self
                Other.IsMappingAdded[]
            do:
                PlayerInput.AddInputMapping(Other.Source.InputMapping)

    OnTriggered<private>(Payload:tuple(player, logic)):void =
        if (Payload(1)?):
            Source.NotifyTriggered(Player)
