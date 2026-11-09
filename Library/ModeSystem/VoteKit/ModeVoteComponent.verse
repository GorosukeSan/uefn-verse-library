using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { ModeSystem }
using { ModeSystem.TooltipKit }

# Notification that someone's vote changed (voted, withdrawn, or all cleared)
# Direction: the whole scope (SendScoped; the whole world without a scope)
# Sender: mode_vote_component. Receivers: screens that show vote counts, etc. Not consumed
mode_vote_changed_event<public> := class(scene_event):
    # The mode_vote_component that sent it
    Vote<public>:mode_vote_component
    # The player whose vote changed. false when all votes were cleared
    Agent<public>:?agent
    # The mode that player now votes for. false when withdrawn
    Mode<public>:?game_mode_component

# Role: collects the players' votes and has the mode_select_component on the same entity decide the mode by majority (it only handles the decision; the selectable modes and the accepting period stay with mode_select_component)
# Placement: attach in the editor to the same entity as mode_select_component
# How it decides: once every player in the scope has voted (or, when MajorityEnds is true, as soon as a majority voted for the same mode), calls TrySelect with the mode that has the most votes. On a tie, the mode with the smaller Order. No votes are accepted after the decision (votes are cleared when mode_select_component stops accepting or is cleared)
# Notifies: sends mode_vote_changed_event to the whole scope and fires VoteChangedEvent
# From outside: TryVote / Unvote (from screen buttons etc.); query the current votes with GetVoteCount / FindVote
# Requirements: one player_manager_component in the scope (or the world)
mode_vote_component<public> := class<final_super>(component):

    # true decides as soon as a majority voted for the same mode. false waits until everyone voted. Default false
    @editable:
        ToolTip := ModeVoteMajorityEndsToolTip
        Categories := array{ModeCategory}
    MajorityEnds<public>:logic = false

    var<private> Votes:[agent]game_mode_component = map{}
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Manager:?player_manager_component = false

    VoteChangedEventInternal<private><final>:event(tuple(agent, ?game_mode_component)) = event(tuple(agent, ?game_mode_component)){}

    # Fires each time someone votes or withdraws, with (the player, the mode they now vote for; false when withdrawn) (Await / Subscribe; cannot be signaled from outside)
    VoteChangedEvent<public><final>:listenable(tuple(agent, ?game_mode_component)) = MakeProxyListenable(VoteChangedEventInternal)

    VotesClearedEventInternal<private><final>:event() = event(){}

    # Fires when all votes are cleared at once (end of accepting, Clear). VoteChangedEvent does not fire then, so anything that shows vote counts subscribes to this too (Await / Subscribe; cannot be signaled from outside)
    VotesClearedEvent<public><final>:listenable(tuple()) = MakeProxyListenable(VotesClearedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        var NewSubscriptions:[]cancelable = array{}
        if (Selector := Entity.GetComponent[mode_select_component]):
            set NewSubscriptions += array{Selector.SelectedEvent.Subscribe(OnSelectedChanged)}
        set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)
        if (Found := Manager?):
            set NewSubscriptions += array{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
        set Subscriptions = NewSubscriptions

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Votes = map{}
        set Manager = false
        (super:)OnEndSimulation()

    # Sets Agent's vote to Mode (a vote can be changed). true if it took effect. false when there is no mode_select_component, it is not accepting, a mode is already decided, or Mode is not one of its child modes. If this vote completes the count, the mode is decided on the spot
    TryVote<public>(Agent:agent, Mode:game_mode_component):logic =
        if:
            Selector := Entity.GetComponent[mode_select_component]
            Selector.IsActive[]
            not Selector.FindSelected[]
            Mode.Entity.GetParent[] = Entity
        then:
            if (Previous := Votes[Agent], Previous = Mode):
                return true
            if (set Votes[Agent] = Mode) {}
            NotifyVoteChanged(option{Agent}, option{Mode})
            TryDecide(Selector)
            true
        else:
            false

    # Withdraws Agent's vote. Does nothing if the agent has not voted
    Unvote<public>(Agent:agent):void =
        if (Votes[Agent]):
            RemoveVote(Agent)
            NotifyVoteChanged(option{Agent}, false)

    # Number of votes for Mode (votes of players who left are not counted)
    GetVoteCount<public>(Mode:game_mode_component)<transacts>:int =
        var Count:int = 0
        for (Agent -> Voted : Votes, Voted = Mode, IsPresent[Agent]):
            set Count += 1
        Count

    # The mode Agent votes for. Fails if the agent has not voted
    FindVote<public>(Agent:agent)<decides><transacts>:game_mode_component =
        Votes[Agent]

    OnSelectedChanged<private>(Mode:?game_mode_component):void =
        # When the selection is cleared (end of accepting, Clear), clear the votes too
        if (not Mode?):
            ClearVotes()

    OnPlayerRemoved<private>(Player:player):void =
        Unvote(Player)
        if (Selector := Entity.GetComponent[mode_select_component], Selector.IsActive[], not Selector.FindSelected[]):
            TryDecide(Selector)

    ClearVotes<private>():void =
        if (Votes.Length > 0):
            set Votes = map{}
            NotifyVoteChanged(false, false)
            VotesClearedEventInternal.Signal()

    RemoveVote<private>(Agent:agent):void =
        set Votes = Votes.RemoveKey(Agent)

    # If the conditions to decide are met, calls TrySelect with the mode that has the most votes (the smaller Order on a tie)
    TryDecide<private>(Selector:mode_select_component):void =
        PlayerCount := GetPlayerCount()
        if (PlayerCount <= 0):
            return
        var Best:?game_mode_component = false
        var BestCount:int = 0
        var VotedCount:int = 0
        for (Mode : Selector.GetModes()):
            Count := GetVoteCount(Mode)
            set VotedCount += Count
            if (Count > BestCount):
                set Best = option{Mode}
                set BestCount = Count
        if (Winner := Best?):
            if (VotedCount >= PlayerCount or (MajorityEnds? and BestCount * 2 > PlayerCount)):
                Selector.TrySelect(Winner)

    GetPlayerCount<private>()<transacts>:int =
        if (Found := Manager?):
            Found.GetPlayerCount()
        else:
            0

    # Succeeds if Agent is currently in the game (has a slot). Fails without a player_manager_component
    IsPresent<private>(Agent:agent)<decides><transacts>:void =
        Manager?.FindSlot[player[Agent]]

    NotifyVoteChanged<private>(Agent:?agent, Mode:?game_mode_component):void =
        Entity.SendScoped(mode_vote_changed_event{Vote := Self, Agent := Agent, Mode := Mode})
        if (Voter := Agent?):
            VoteChangedEventInternal.Signal((Voter, Mode))
