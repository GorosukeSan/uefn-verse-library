using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# Role: registry of the swings in a scope. Remembers each player's swing_runner (used to find the other side when pulling a rope) and the modifier sources (swing_modifier_component). From outside you only read the combined modifier (GetStats); only the swing side writes
# Placement: attach to an entity in the editor. One per scope (under a game_scope_component; the world if there is none). The swing side and the modifier side look it up once with FindScopedComponent and remember it
# Requirements / notes: swings work without it, but pulling a rope and modifiers (swing_modifier_component) need it. It does not track who is swinging (look at the tags with Agent.IsSwinging[] / Agent.GetSwingState())
swing_registry_component<public> := class<final_super>(component):

    var<private> Runners:[agent]swing_runner = map{}
    var<private> Modifiers:[]swing_modifier_component = array{}

    # Signaled when a modifier source is added / removed or its targets change (swing_runner Awaits it and rebuilds the modifier)
    ModifiersChangedEvent<internal>:event() = event(){}

    # Every modifier applied to Agent, combined (swing_stats{} if none is applied)
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
