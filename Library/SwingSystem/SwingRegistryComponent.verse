using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# 役割：区画の中のスイングの台帳。各人の swing_runner（ロープを引くときに相手を探す）と、倍率の元（swing_modifier_component）を覚える。外からは倍率の結果（GetStats）を読むだけ（書き換えはスイング側だけが行う）
# 置き方：エディターで entity に付ける。区画（game_scope_component の配下。無ければ世界）に 1 つ。スイング側・倍率の側が最初に 1 回だけ FindScopedComponent で探して覚える
# 前提・注意：無くてもスイングは動くが、ロープを引く・倍率（swing_modifier_component）はこれが要る。だれがスイング中かはここでは持たない（Agent.IsSwinging[] / Agent.GetSwingState() でタグを見る）
swing_registry_component<public> := class<final_super>(component):

    var<private> Runners:[agent]swing_runner = map{}
    var<private> Modifiers:[]swing_modifier_component = array{}

    # 倍率の元が足された・外された・掛ける相手が変わったときに Signal する（swing_runner が Await して倍率を作り直す）
    ModifiersChangedEvent<internal>:event() = event(){}

    # Agent に掛かっている倍率をすべて重ねた結果（掛かっていなければ swing_stats{}）
    GetStats<public>(Agent:agent)<transacts>:swing_stats =
        var Result:swing_stats = swing_stats{}
        for (Modifier : Modifiers, Modifier.IsAppliedTo[Agent]):
            set Result = Result.Apply(Modifier.GetModifier())
        Result

    SetRunner<internal>(Agent:agent, Runner:swing_runner):void =
        if (set Runners[Agent] = Runner) {}

    ForgetRunner<internal>(Agent:agent, Runner:swing_runner):void =
        if (Current := Runners[Agent], Current = Runner):
            set Runners = Runners.RemoveKey(Agent)

    FindRunner<internal>(Agent:agent)<decides><reads>:swing_runner =
        Runners[Agent]

    AddModifier<internal>(Modifier:swing_modifier_component):void =
        if (not Modifiers.Find[Modifier]):
            set Modifiers += array{Modifier}
            NotifyModifiersChanged()

    RemoveModifier<internal>(Modifier:swing_modifier_component):void =
        if (Index := Modifiers.Find[Modifier], Rest := Modifiers.RemoveElement[Index]):
            set Modifiers = Rest
            NotifyModifiersChanged()

    NotifyModifiersChanged<internal>():void =
        ModifiersChangedEvent.Signal()
