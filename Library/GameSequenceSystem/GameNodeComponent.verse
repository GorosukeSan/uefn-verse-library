using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# Notification that a node was entered (derived from the activation signal activated_event, so parts waiting for activation start on it)
# Direction: downward from the node's entity (SendDown)
# Sender: game_node_component. Receivers: parts under the node. Not consumed
game_node_entered_event<public> := class(activated_event):
    # The node entered
    Node<public>:game_node_component

# Why the node was exited
game_node_exit_reason<public> := enum:
    # A transition's conditions were satisfied and the sequence advanced to the next node (or ended)
    Transitioned
    # The sequence stopped (Stop, end of round, end of simulation)
    Stopped
    # Moved to another node by JumpTo / Restart
    Jumped

# Notification that a node was exited (derived from the deactivation signal deactivated_event, so parts waiting for activation stop on it)
# Direction: downward from the node's entity (SendDown)
# Sender: game_node_component. Receivers: parts under the node. Not consumed
game_node_exited_event<public> := class(deactivated_event):
    # The node exited
    Node<public>:game_node_component
    # The reason for exiting
    Reason<public>:game_node_exit_reason

# Role: one stage of the game flow. On entering, notifies activation to its descendants; on exiting, deactivation. Waits until one of its child transitions can advance
# Placement: attach to an entity in the editor
# Parent: directly under the entity of game_sequence_component
# Children: entities with transitions (game_transition_component). Features that should run only during this stage go here too
# Notifies: sends game_node_entered_event / game_node_exited_event downward and fires EnteredEvent / ExitedEvent
# From outside: entering and exiting are decided by game_sequence_component (Start / JumpTo / Restart / Stop)
game_node_component<public> := class<final_super>(component):

    # The order used to pick the first node when FirstNode of game_sequence_component is empty (smaller first). With several equal values, which one is picked is unspecified
    @editable_number(int):
        ToolTip := NodeOrderToolTip
        Categories := array{GameSequenceCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0

    var<private> Active:logic = false

    EnteredEventInternal<private><final>:event() = event(){}

    # Fires when this stage is entered (same timing as game_node_entered_event) (Await / Subscribe; cannot be Signaled from outside)
    EnteredEvent<public><final>:listenable(tuple()) = MakeProxyListenable(EnteredEventInternal)

    ExitedEventInternal<private><final>:event(game_node_exit_reason) = event(game_node_exit_reason){}

    # Fires with the reason when this stage is exited (same timing as game_node_exited_event) (Await / Subscribe; cannot be Signaled from outside)
    ExitedEvent<public><final>:listenable(game_node_exit_reason) = MakeProxyListenable(ExitedEventInternal)

    TransitionChangedEvent<private>:event() = event(){}

    # Succeeds from entering this stage until exiting it (from game_node_entered_event to game_node_exited_event)
    IsActive<public>()<decides><reads>:void =
        Active?

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (condition_changed_event[SceneEvent]):
            TransitionChangedEvent.Signal()
        false

    # Called by game_sequence_component. Does nothing when already entered
    Enter<internal>():void =
        if (Active?):
            return
        set Active = true
        Entity.SendDown(game_node_entered_event{Node := Self})
        EnteredEventInternal.Signal()

    # Called by game_sequence_component. Does nothing when not entered
    Exit<internal>(Reason:game_node_exit_reason):void =
        if (not Active?):
            return
        set Active = false
        Entity.SendDown(game_node_exited_event{Node := Self, Reason := Reason})
        ExitedEventInternal.Signal(Reason)

    # Waits until one of the direct child transitions can advance and returns it
    AwaitTransition<internal>()<suspends>:game_transition_component =
        loop:
            if (Transition := FindReadyTransition[]):
                return Transition
            TransitionChangedEvent.Await()

    # Among the transitions that can advance now, the one with the largest Priority. When several with the same Priority can advance, which one is picked is unspecified (give them different Priorities)
    FindReadyTransition<public>()<decides><transacts>:game_transition_component =
        var Best:?game_transition_component = false
        for:
            Transition : Entity.GetChildComponents(game_transition_component)
            Transition.IsReady[]
        do:
            if (Current := Best?, Current.Priority >= Transition.Priority):
            else:
                set Best = option{Transition}
        Best?
