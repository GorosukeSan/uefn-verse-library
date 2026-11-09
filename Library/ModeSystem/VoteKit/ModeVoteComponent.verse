using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { ModeSystem }
using { ModeSystem.TooltipKit }

# だれかの投票が変わった知らせ（投票した・取り消した・全部消えた）
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：mode_vote_component。受け手：票数を出す画面など。消費しない
mode_vote_changed_event<public> := class(scene_event):
    # 送った mode_vote_component
    Vote<public>:mode_vote_component
    # 投票を変えた人。全員の票が消えたときは false
    Agent<public>:?agent
    # その人が今投票しているモード。取り消したときは false
    Mode<public>:?game_mode_component

# 役割：参加者の投票を集め、多数決で同じ entity の mode_select_component にモードを決めさせる（決め方だけを受け持つ。選べるモード・受け付ける期間は mode_select_component のまま）
# 置き方：エディターで、mode_select_component と同じ entity に付ける
# 決め方：区画の参加者が全員投票したら（MajorityEnds が true なら、過半数が同じモードに入れた時点で）、票の一番多いモードを TrySelect する。同数なら Order の小さいモード。決まったあとは票を受け付けない（mode_select_component が受け付けをやめるか Clear されると、票は消える）
# 知らせ：mode_vote_changed_event を区画全体へ送り、VoteChangedEvent に届ける
# 外から：TryVote / Unvote（画面のボタンなどから）、GetVoteCount / FindVote で今の票を問い合わせる
# 前提：区画（または世界）に player_manager_component が 1 つ
mode_vote_component<public> := class<final_super>(component):

    # true なら過半数が同じモードに入れた時点で決める。false なら全員が投票してから。既定 false
    @editable:
        ToolTip := ModeVoteMajorityEndsToolTip
        Categories := array{ModeCategory}
    MajorityEnds<public>:logic = false

    var<private> Votes:[agent]game_mode_component = map{}
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Manager:?player_manager_component = false

    VoteChangedEventInternal<private><final>:event(tuple(agent, ?game_mode_component)) = event(tuple(agent, ?game_mode_component)){}

    # だれかが投票・取り消しをするたびに、（その人, 今投票しているモード。取り消しなら false）で届く（Await / Subscribe する。外から Signal はできない）
    VoteChangedEvent<public><final>:listenable(tuple(agent, ?game_mode_component)) = MakeProxyListenable(VoteChangedEventInternal)

    VotesClearedEventInternal<private><final>:event() = event(){}

    # 全員の票がまとめて消えたとき（受け付けの終わり・Clear）に届く。VoteChangedEvent はこのときは届かないので、票数を表示している側はこれも購読する（Await / Subscribe する。外から Signal はできない）
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

    # Agent の票を Mode にする（入れ直しもできる）。効いたら true。mode_select_component が無い・受け付けていない・もう決まっている・Mode がその子のモードでないときは false。投票で全員がそろえば、その場でモードが決まる
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

    # Agent の票を取り消す。投票していなければ何もしない
    Unvote<public>(Agent:agent):void =
        if (Votes[Agent]):
            RemoveVote(Agent)
            NotifyVoteChanged(option{Agent}, false)

    # Mode に入っている票の数（退出した人の票は数えない）
    GetVoteCount<public>(Mode:game_mode_component)<transacts>:int =
        var Count:int = 0
        for (Agent -> Voted : Votes, Voted = Mode, IsPresent[Agent]):
            set Count += 1
        Count

    # Agent が投票しているモード。投票していなければ失敗する
    FindVote<public>(Agent:agent)<decides><transacts>:game_mode_component =
        Votes[Agent]

    OnSelectedChanged<private>(Mode:?game_mode_component):void =
        # 選びが消えた（受け付けの終わり・Clear）ら、票も消す
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

    # 決める条件がそろっていれば、票の一番多いモード（同数なら Order の小さいもの）を TrySelect する
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

    # Agent が今参加している（slot がある）なら成功する。player_manager_component が無ければ失敗する
    IsPresent<private>(Agent:agent)<decides><transacts>:void =
        Manager?.FindSlot[player[Agent]]

    NotifyVoteChanged<private>(Agent:?agent, Mode:?game_mode_component):void =
        Entity.SendScoped(mode_vote_changed_event{Vote := Self, Agent := Agent, Mode := Mode})
        if (Voter := Agent?):
            VoteChangedEventInternal.Signal((Voter, Mode))
