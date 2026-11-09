using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Game }
using { ActivationSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# State of the game flow (game_sequence_component)
game_sequence_state<public> := enum:
    # Not started yet
    Idle
    # Advancing through nodes
    Running
    # Stopped by Stop or the end of the round
    Stopped
    # Advanced to the last transition (empty Target)
    Finished
    # Stopped because there is no first node, the Target has no node, etc.
    Failed

# Name of the state ("Idle" etc., in English). For debug display and logs
(State:game_sequence_state).ToString<public>()<computes>:string =
    case (State):
        game_sequence_state.Idle => "Idle"
        game_sequence_state.Running => "Running"
        game_sequence_state.Stopped => "Stopped"
        game_sequence_state.Finished => "Finished"
        game_sequence_state.Failed => "Failed"

# Notification that the state of the game flow changed
# Direction: from the entity of game_sequence_component to the root (SendUp)
# Sender: game_sequence_component. Receivers: ancestor components (a director outside the sequence, etc.). Not consumed
game_sequence_state_changed_event<public> := class(scene_event):
    # The sequence that sent it
    Sequence<public>:game_sequence_component
    # The state after the change
    State<public>:game_sequence_state

# Role: advances the game flow from the first node. Moves to the next node every time a node's transition can advance, and ends at a transition without Target
# Placement: attach to an entity in the editor. One per sequence. Any number may be placed in a level (each advances only the nodes directly under it and never mixes with other sequences. It is never looked up from the world or a zone, so no zone is needed either)
# Children: entities with nodes (game_node_component), directly under it
# When to start: when StartOnRoundStart is true, starts at round start and stops at round end (every sequence with true starts at the same time). When StartOnActivate is true, starts on the activation signal and stops on the deactivation signal (placed under a node of another sequence, it runs only during that node). When StartOnBegin is true, starts at simulation start. All may be false, with Start called from code
# With several games in the same level: turn StartOnRoundStart off and start with that game's start (the StartOnActivate signal or Start)
# Notifies: sends game_sequence_state_changed_event upward and fires StateChangedEvent
# From outside: Start / Stop / Restart / JumpTo. Query the current state with IsRunning / State / CurrentNode
# Requirements: one frame is left between nodes (so transitions do not keep cycling within the same frame). When Stop and Start / Restart / JumpTo arrive in the same frame, they are processed in arrival order (stop, then start again)
game_sequence_component<public> := class<final_super>(component):

    # The node entered first (entity with game_node_component). Empty picks the direct child node with the smallest Order. Default empty
    @editable:
        ToolTip := FirstNodeToolTip
        Categories := array{GameSequenceCategory}
    FirstNode<public>:?entity = false

    # When true, starts at round start and stops at round end. Default true
    @editable:
        ToolTip := SequenceStartOnRoundStartToolTip
        Categories := array{GameSequenceCategory}
    StartOnRoundStart<public>:logic = true

    # When true, starts on the activation signal (activated_event: the parent node entered, the round start of activate_on_round_component, etc.) and stops on the deactivation signal (deactivated_event). The received signal is consumed here and not delivered to the parts under the nodes (they run on the node entered signal). Default false
    @editable:
        ToolTip := SequenceStartOnActivateToolTip
        Categories := array{GameSequenceCategory}
    StartOnActivate<public>:logic = false

    # When true, starts at simulation start (after waiting one frame). Default false
    @editable:
        ToolTip := SequenceStartOnBeginToolTip
        Categories := array{GameSequenceCategory}
    StartOnBegin<public>:logic = false

    # The current state. Idle when not started yet
    var<private> State<public>:game_sequence_state = game_sequence_state.Idle
    # The node currently entered. false when none
    var<private> CurrentNode<public>:?game_node_component = false
    # The reason of the last Failed. Stays until the next failure even after leaving Failed. false when it never failed
    var<private> LastError<public>:?game_node_error = false
    Rounds<private>:round_watcher = round_watcher{}
    # Stop was called and the sequence has not stopped yet (RunFrom sees it and stops. Start etc. requested after that are accepted once stopped)
    var<private> StopRequested:logic = false

    # Whether there is a Start / Restart / JumpTo request not yet accepted
    var<private> HasRequest:logic = false
    # The node to enter for the request. false means the first node
    var<private> RequestedNode:?game_node_component = false
    # The result when the current node's transition became ready (used only inside RunFrom)
    var<private> Transition:?game_transition_component = false

    StateChangedEventInternal<private><final>:event(game_sequence_state) = event(game_sequence_state){}

    # Fires with the new state every time the state changes (same timing as game_sequence_state_changed_event) (Await / Subscribe; cannot be Signaled from outside)
    StateChangedEvent<public><final>:listenable(game_sequence_state) = MakeProxyListenable(StateChangedEventInternal)

    RequestEvent<private>:event() = event(){}
    StopEvent<private>:event() = event(){}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnRoundStart?):
            Started := Rounds.Start(Entity, OnRoundStarted, Stop)
            if (not Started?):
                Print("[game_sequence_component] fort_round_manager not found (StartOnRoundStart has no effect)")

    OnEndSimulation<override>():void =
        Rounds.Stop()
        (super:)OnEndSimulation()

    # With StartOnActivate, Starts on the activation signal, Stops on the deactivation signal, and consumes the signal (not delivered to the parts under the nodes)
    OnReceive<override>(SceneEvent:scene_event):logic =
        if (not StartOnActivate?):
            false
        else if (activated_event[SceneEvent]):
            Start()
            true
        else if (deactivated_event[SceneEvent]):
            Stop()
            true
        else:
            false

    OnSimulate<override>()<suspends>:void =
        if (StartOnBegin?):
            # Wait one frame so that every node in the same tree has finished OnBeginSimulation before entering
            TickEvents.PrePhysics.Await()
            Start()
        loop:
            if (HasRequest?):
                StartNode := RequestedNode
                set HasRequest = false
                set RequestedNode = false
                RunSequence(StartNode)
            else:
                RequestEvent.Await()

    # Starts the sequence from the first node. Does nothing when already running (use Restart to start over). Right after Stop (not fully stopped yet), starts once stopped
    Start<public>():void =
        if (IsRunning[], not StopRequested?):
            return
        Request(false)

    # Stops the sequence (the current node is exited with Reason Stopped). The state becomes Stopped. Does nothing when not running
    Stop<public>():void =
        set HasRequest = false
        set RequestedNode = false
        if (IsRunning[]):
            set StopRequested = true
            StopEvent.Signal()

    # Starts over from the first node. Same as Start when not running. Right after Stop, starts once stopped
    Restart<public>():void =
        Request(false)

    # Moves to Node (the current node is exited with Reason Jumped). Starts from Node when not running. Node need not be directly under this sequence. Right after Stop, starts from Node once stopped (Reason is Stopped)
    JumpTo<public>(Node:game_node_component):void =
        Request(option{Node})

    # Succeeds while advancing through nodes (while State is Running)
    IsRunning<public>()<decides><transacts>:void =
        State = game_sequence_state.Running

    # The first node. With FirstNode set, the game_node_component of that entity (fails when it is not attached; does not search the children). Empty picks the direct child node with the smallest Order (grandchildren are not searched). Fails when there is none
    FindFirstNode<public>()<decides><transacts>:game_node_component =
        if (FirstNodeEntity := FirstNode?):
            FirstNodeEntity.GetComponent[game_node_component]
        else:
            var Best:?game_node_component = false
            for (Node : Entity.GetChildComponents(game_node_component)):
                if (Current := Best?, Current.Order <= Node.Order):
                else:
                    set Best = option{Node}
            Best?

    OnRoundStarted<private>()<suspends>:void =
        Start()

    # Accepts a request. While stopping (StopRequested), it is kept rather than dropped, and once RunFrom has stopped the OnSimulate loop starts again with this request (processed in arrival order)
    Request<private>(Node:?game_node_component):void =
        set HasRequest = true
        set RequestedNode = Node
        RequestEvent.Signal()

    RunSequence<private>(StartNode:?game_node_component)<suspends>:void =
        if (Node := StartNode?):
            RunFrom(Node)
        else if (First := FindFirstNode[]):
            RunFrom(First)
        else:
            Fail(game_node_empty_error{})

    RunFrom<private>(StartNode:game_node_component)<suspends>:void =
        SetState(game_sequence_state.Running)
        var Node:game_node_component = StartNode
        defer:
            if (LastNode := CurrentNode?):
                LastNode.Exit(game_node_exit_reason.Stopped)
            set CurrentNode = false
            # The sequence has ended, so a pending stop request counts as done (not left over when ending with Finished / Failed)
            set StopRequested = false
            if (State = game_sequence_state.Running):
                SetState(game_sequence_state.Stopped)
        loop:
            # Stop / JumpTo may also arrive while not awaiting (while entering a node, while waiting for the next frame), so check the flags
            # Check the stop request first (a request that came after Stop stays in HasRequest and is accepted by the OnSimulate loop once stopped)
            if (StopRequested?):
                set StopRequested = false
                return
            if (HasRequest?):
                Requested := RequestedNode
                set HasRequest = false
                set RequestedNode = false
                if (Target := Requested?):
                    set Node = Target
                else if (First := FindFirstNode[]):
                    set Node = First
                else:
                    Fail(game_node_empty_error{})
                    return
            set CurrentNode = option{Node}
            Node.Enter()
            set Transition = false
            if (not StopRequested?, not HasRequest?):
                race:
                    block:
                        Ready := Node.AwaitTransition()
                        set Transition = option{Ready}
                    StopEvent.Await()
                    RequestEvent.Await()
            if (Ready := Transition?):
                set Transition = false
                Node.Exit(game_node_exit_reason.Transitioned)
                set CurrentNode = false
                if (Target := Ready.Target?):
                    if (NextNode := Target.GetComponent[game_node_component]):
                        set Node = NextNode
                    else:
                        Fail(game_node_not_found_error{Target := Target})
                        return
                else:
                    SetState(game_sequence_state.Finished)
                    return
                # Enter the next node on the next frame so transitions do not keep cycling within the same frame (Stop / JumpTo in between are checked at the top of the loop)
                TickEvents.PrePhysics.Await()
            else:
                Node.Exit(if (StopRequested?) then game_node_exit_reason.Stopped else game_node_exit_reason.Jumped)
                set CurrentNode = false

    SetState<private>(NewState:game_sequence_state):void =
        set State = NewState
        Entity.SendUp(game_sequence_state_changed_event{Sequence := Self, State := NewState})
        StateChangedEventInternal.Signal(NewState)

    Fail<private>(Error:game_node_error):void =
        set LastError = option{Error}
        SetState(game_sequence_state.Failed)
