using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：1 人分の能力（スイング・ジェットパックなど）の基底。付与されているあいだ、その人について派生の RunFor を動かし、剥奪されると止める（RunFor は race で止められる。後片付けは RunFor の中の defer で行う）
# 付与の仕方は能力の側では決めない。同じ entity に付与の component（ability_grant_players / ability_grant_item / ability_grant_condition など）を置いて付け替えるか、コードから Grant / Revoke を呼ぶ
# 置き方：直接は置かない（派生を置く）。1 entity に何個置いてもよい（同じ entity の付与の component は、その entity の能力すべてを付与する）
# 前提・注意：同じ人に複数の付与元から付与されても RunFor は 1 つだけ動く（付与の回数を数え、すべて剥奪されたときに止める）
ability_component<public> := class<abstract><final_super>(component):

    var<private> GrantCounts:[agent]int = map{}
    # 人ごとに、RunFor を始めるたびに 1 増やす番号。剥奪してすぐ付与し直したときに、前の RunFor を止めるため
    var<private> Generations:[agent]int = map{}

    StopEvent<private>:event() = event(){}
    GrantedEventInternal<private><final>:event(agent) = event(agent){}
    RevokedEventInternal<private><final>:event(agent) = event(agent){}

    # 付与されて RunFor を始めたときに、その人で届く（Await / Subscribe する。外から Signal はできない）
    GrantedEvent<public><final>:listenable(agent) = MakeProxyListenable(GrantedEventInternal)

    # すべての付与元から剥奪されて止めたときに、その人で届く
    RevokedEvent<public><final>:listenable(agent) = MakeProxyListenable(RevokedEventInternal)

    # 派生が実装する。Agent に付与されているあいだ動く。剥奪されると race で止められるので、戻らなくてよい（戻ったら、付与が続いていても能力はそこで終わる）
    RunFor<protected>(Agent:agent)<suspends>:void

    # Agent に付与する（付与の回数を 1 増やす）。0 から 1 になったときに RunFor を始め、GrantedEvent を届ける
    Grant<public>(Agent:agent):void =
        Count := GetGrantCount(Agent)
        if (set GrantCounts[Agent] = Count + 1) {}
        if (Count = 0):
            Generation := (if (Current := Generations[Agent]) then Current else 0) + 1
            if (set Generations[Agent] = Generation) {}
            spawn{RunGranted(Agent, Generation)}
            GrantedEventInternal.Signal(Agent)

    # Agent から剥奪する（付与の回数を 1 減らす）。0 になったときに RunFor を止め、RevokedEvent を届ける。付与されていなければ何もしない
    Revoke<public>(Agent:agent):void =
        Count := GetGrantCount(Agent)
        if (Count <= 0):
            return
        if (set GrantCounts[Agent] = Count - 1) {}
        if (Count = 1):
            StopEvent.Signal()
            RevokedEventInternal.Signal(Agent)

    # 付与の回数にかかわらず、全員から剥奪して止める
    RevokeAll<public>():void =
        for (Agent : GetGrantedAgents()):
            if (set GrantCounts[Agent] = 0) {}
            StopEvent.Signal()
            RevokedEventInternal.Signal(Agent)

    # Agent に付与されている（RunFor が動いている）なら成功する
    IsGranted<public>(Agent:agent)<decides><transacts>:void =
        GrantCounts[Agent] > 0

    # 今付与されている人（並び順は決まっていない）
    GetGrantedAgents<public>()<transacts>:[]agent =
        for (Agent -> Count : GrantCounts, Count > 0):
            Agent

    OnEndSimulation<override>():void =
        RevokeAll()
        (super:)OnEndSimulation()

    GetGrantCount<private>(Agent:agent)<transacts>:int =
        if (Count := GrantCounts[Agent]) then Count else 0

    RunGranted<private>(Agent:agent, Generation:int)<suspends>:void =
        race:
            RunFor(Agent)
            AwaitStop(Agent, Generation)

    # 止める知らせ（だれかの剥奪）のたびに、自分がまだ付与されていて、自分の番号が最新かを見る。
    # 知らせの中身（だれか）で比べると、RevokeAll が同じ tick に続けて Signal したとき、最初の知らせで起きた人が自分あての知らせを取りこぼすため
    AwaitStop<private>(Agent:agent, Generation:int)<suspends>:void =
        loop:
            StopEvent.Await()
            if (not IsGranted[Agent] or not Generations[Agent] = Generation):
                return

# InEntity に付いている能力（ability_component の派生）をすべて返す
(InEntity:entity).GetAbilities<public>()<reads>:[]ability_component =
    for (Component : InEntity.GetComponents(), Ability := ability_component[Component]):
        Ability
