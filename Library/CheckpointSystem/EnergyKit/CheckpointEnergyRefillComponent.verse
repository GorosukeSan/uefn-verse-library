using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { AbilitySystem }
using { EnergySystem }
using { ItemSystem }
using { PlayerSystem }
using { CheckpointSystem }

# 役割：区画のどれかのチェックポイント（checkpoint_component）にだれかが乗るたびに、エネルギー（EnergySystem の energy_component）を満タンにする（Fill）。満たす先は置いた場所で決まる：
#   - この entity か子孫に energy_component があれば（FindEnergy。能力が使う FindEnergyFor の 1 番目と同じ）、それだけ（能力の entity に置いた、付与された全員で分け合うエネルギーなど）。同じ entity に能力（ability_component の派生）があれば、どれかを付与されている人が乗ったときだけ
#   - 無ければ、乗った人のエネルギー：その人（agent）に付いた energy_component と、持ち物（アイテム）の energy_component（FindEnergy）すべて
#   プレイヤーの slot の下（ロードアウトの中など）に置いたときは、持ち主が乗ったときだけ満たす
# 置き方：エディターで、区画（game_scope_component の entity）の中の entity に付ける（区画が無ければ世界のどこか）。乗った知らせ（checkpoint_reached_event）は区画の根から下へ届くので、区画の外や inventory の中（アイテムの entity）に置くと届かない。アイテムのエネルギーを満たすなら、区画の中の別の entity に置く（乗った人の持ち物を満たす）
# 同じ entity：満たす energy_component（子でもよい。無くてもよい）。能力（hover_ability_component など）と付与の component。区画の根など、関係のない energy_component を子孫に持つ entity には置かない（そのどれかを満たしてしまう）
# 知らせ：満たしたとき、RefilledEvent に（乗った人, 満たした energy_component）で届く（もう満タンだったものは満たさず、届かない）
# 前提：エネルギーの「使う側」（hover・jetpack など）はこの部品を知らない。チェックポイントに乗った知らせを受けて満たすだけ
checkpoint_energy_refill_component<public> := class<final_super>(component):

    RefilledEventInternal<private><final>:event(tuple(agent, energy_component)) = event(tuple(agent, energy_component)){}

    # エネルギーを満たしたときに、（チェックポイントに乗った人, 満たした energy_component）で届く（Await / Subscribe する。外から Signal はできない）
    RefilledEvent<public><final>:listenable(tuple(agent, energy_component)) = MakeProxyListenable(RefilledEventInternal)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Reached := checkpoint_reached_event[SceneEvent]):
            RefillFor(Reached.Agent)
        false

    # Agent がチェックポイントに乗ったときと同じように満たす（チェックポイントを通さずに満たしたいとき）。満たしたものがあれば true
    # 満たす処理（Fill）と知らせ（RefilledEvent）は巻き戻せないので <decides> にはできない
    TryRefillFor<public>(Agent:agent):logic =
        RefillFor(Agent)

    RefillFor<private>(Agent:agent):logic =
        if (AppliesTo[Agent]):
            var Refilled:logic = false
            for (Energy : GetTargets(Agent), not Energy.IsFull[]):
                Energy.Fill()
                RefilledEventInternal.Signal((Agent, Energy))
                set Refilled = true
            Refilled
        else:
            false

    # 持ち主がいれば持ち主だけ。同じ entity に能力があれば、どれかを付与されている人だけ
    AppliesTo<private>(Agent:agent)<decides><transacts>:void =
        if (Owner := Entity.FindOwningPlayer[]):
            Owner = Agent
        Abilities := Entity.GetAbilities()
        if (Abilities.Length > 0):
            Granted := for (Ability : Abilities, Ability.IsGranted[Agent]):
                Ability
            Granted.Length > 0

    # 満たす先（この entity か子孫の energy_component、無ければ Agent 自身と持ち物の energy_component）
    GetTargets<private>(Agent:agent)<transacts>:[]energy_component =
        if (Own := Entity.FindEnergy[]):
            array{Own}
        else:
            AgentEnergy := if (Energy := Agent.GetComponent[energy_component]) then array{Energy} else array{}
            ItemEnergy := for (Item : Agent.GetAgentItems(), Energy := Item.FindEnergy[]):
                Energy
            AgentEnergy + ItemEnergy
