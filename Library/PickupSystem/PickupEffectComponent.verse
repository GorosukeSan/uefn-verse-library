using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { PickupSystem.TooltipKit }

# What to do when a player who already has the same effect (same EffectId) picks it up again
pickup_effect_stack_mode<public> := enum:
    # Add the new effect's DurationSeconds to the remaining time of the ongoing effect (the new effect is not started)
    Extend
    # Reset the remaining time of the ongoing effect to the new effect's DurationSeconds (the new effect is not started)
    Refresh
    # Add another copy (the parts inside take effect twice. Up to MaxStacks; when reached, Refresh the copy ending soonest)
    Stack
    # End the ongoing effect and start the new one
    Replace
    # Do nothing while the effect is ongoing (the new effect is not started)
    Ignore
    # Raise the Tier of the ongoing effect by 1 (up to MaxTier) and reset the remaining time to the new effect's DurationSeconds (the new effect is not started)
    #   The parts inside read the tier with Entity.FindPickupEffect[].GetTier() / TierChangedEvent and change their strength
    Tier

# Tag on the owner (agent) while receiving an effect (pickup_effect_component). One per effect
#   Which effect it is can be read from the EffectId of Entity.GetActivePickupEffects(Agent). The parts inside also add per-effect tags (e.g. character_speed_modified_tag in CharacterSystem's BuffKit)
pickup_effect_tag<public> := class(player_state_tag):

# Notification that an effect started or ended
# Direction: from the effect entity to the root (SendUp; reaches the player's slot and then the player_manager_component entity)
# Sender: pickup_effect_component (Effect). Receivers: ancestor components of the slot (the game root etc.). Not consumed
pickup_effect_changed_event<public> := class(scene_event):
    # The effect that started / ended (sender)
    Effect<public>:pickup_effect_component
    # Agent receiving the effect (owner)
    Agent<public>:agent
    # true if started, false if ended
    Started<public>:logic

# Kind of effect notification delivered on the owner's side (pickup_effect_owner_event.Notice)
pickup_effect_notice<public> := enum:
    # The effect started (Instant effects too; Ended follows right after)
    Started
    # The same effect (same EffectId) was picked up again, but no new effect was started; the ongoing one took over (StackMode Extend / Refresh / Ignore, or the Stack limit). Read the remaining time with Effect.GetRemainingSeconds
    Renewed
    # The effect ended (timer, End, EndPickupEffectsFor). Not delivered when it disappeared because the owner left etc.
    Ended

# Effect notification (owner's side). Received by parts inside the owner's loadout / character, such as the pickup HUD
# Direction: from the owner's slot entity downward (SendDown; every entity under the slot: loadout, character, widget views, effect prefabs)
# Sender: pickup_effect_component (the picked-up effect). Receivers: components under the slot (HudKit's pickup_effect_hud_component etc.). Not consumed
# Delivered at the same time as pickup_effect_changed_event (SendUp; received by the slot's ancestors = the game root etc.). Renewed is delivered only here
pickup_effect_owner_event<public> := class(scene_event):
    # The ongoing effect. For Started / Ended, the same as the picked-up effect. For Renewed, the effect whose remaining time was extended (took over)
    Effect<public>:pickup_effect_component
    # The picked-up effect (the one that sent the notification). For Renewed, the one that disappears right away without starting (read the look (card_info_component) from this one)
    Picked<public>:pickup_effect_component
    # Agent receiving the effect (owner)
    Agent<public>:agent
    # What happened
    Notice<public>:pickup_effect_notice

# Role: the "effect base" placed on the root of an effect prefab. Handles the owner (the picker), the lifetime (DurationSeconds) and stacking of the same effect (StackMode), and tells the parts inside when the lifetime starts and ends through signals
#   Start: on the frame after creation, sends an activate signal raised by the owner (activated_by_agent_event) to this entity and its descendants. The parts inside (buffs, ability grants, stage signals, HUD text, anything driven by the activate signal) start from it
#   End: after DurationSeconds or on End, sends the deactivate signal (deactivated_event) and then removes this entity (the effect prefab). The parts inside revert on the deactivate signal or in OnEndSimulation
#   If a part inside sends activation_finished_event (ActivationSystem) upward (e.g. a single-use action cell), the effect ends there
#   The parts inside learn the owner through FindOwningPlayer (effects are created under the player's slot) or the Agent of the activate signal, and the picked-up object (orb) through Entity.FindPickupEffect[].FindSource[]. Parts that know nothing about this component (library parts driven by the activate signal) work as they are
# Placement: attach in the editor to the root entity of the effect prefab. Put the parts inside on the same entity or children (use child entities when you need two parts of the same type)
#   The prefab is created under the agent's slot by an orb (pickup_component's Effect) or by Entity.GrantPickupEffect(Agent, Prefab, Origin, Source) from code. The created entity is positioned at the picked-up object
#   It also works when placed in the editor somewhere that has an owner (inside a loadout etc.) (owner = that place's owner, from the frame after start)
# When: DurationSeconds from the frame after creation (0 means forever; ends with End or EndPickupEffectsFor). With Instant, ends on the frame after the activate signal is sent (one-shot effects)
# Notifies: StartedEvent / EndedEvent (owner), pickup_effect_changed_event (SendUp), pickup_effect_owner_event (SendDown from the owner's slot. Started / Renewed / Ended)
# Tags: pickup_effect_tag on the owner while the effect lasts
# From outside: End / AddSeconds / GetRemainingSeconds / IsActive / FindOwner / FindSource / GetOriginTransform. Entity.FindPickupEffect[] (ancestor effect), Entity.GetActivePickupEffects(Agent), Entity.EndPickupEffectsFor(Agent)
# Requirements: does not start where there is no owner (logs to the output log and disappears)
pickup_effect_component<public> := class<final_super>(component):

    # Seconds the effect lasts. 0 means forever (until End, EndPickupEffectsFor or the owner leaves). Default 10
    @editable_number(float):
        ToolTip := EffectDurationToolTip
        Categories := array{PickupEffectCategory}
        MinValue := option{0.0}
        MaxValue := option{3600.0}
    DurationSeconds<public>:float = 10.0
    # When on, ends on the frame after the activate signal is sent (one-shot effects such as shortening the timer). DurationSeconds is not used. Default off
    @editable:
        ToolTip := EffectInstantToolTip
        Categories := array{PickupEffectCategory}
    Instant<public>:logic = false
    # Identifies the same effect. StackMode applies between effects of the same player with the same EffectId. Empty treats every pickup as a separate effect (always stacks). Default empty
    @editable:
        ToolTip := EffectIdToolTip
        Categories := array{PickupEffectCategory}
    EffectId<public>:string = ""
    # What to do when a player who already has the same effect picks it up (Extend / Refresh / Stack / Replace / Ignore). Default Extend
    @editable:
        ToolTip := EffectStackModeToolTip
        Categories := array{PickupEffectCategory}
    StackMode<public>:pickup_effect_stack_mode = pickup_effect_stack_mode.Extend
    # When StackMode is Stack, the maximum number of copies at the same time. 0 means no limit. Default 0
    @editable_number(int):
        ToolTip := EffectMaxStacksToolTip
        Categories := array{PickupEffectCategory}
        MinValue := option{0}
        MaxValue := option{100}
    MaxStacks<public>:int = 0
    # When StackMode is Tier, the maximum tier. Default 3
    @editable_number(int):
        ToolTip := EffectMaxTierToolTip
        Categories := array{PickupEffectCategory}
        MinValue := option{1}
        MaxValue := option{100}
    MaxTier<public>:int = 3

    StartedEventInternal<private><final>:event(agent) = event(agent){}
    TierChangedEventInternal<private><final>:event(int) = event(int){}

    # Fires with the new tier each time the tier goes up (picking the same effect up again with StackMode = Tier, or RaiseTier)
    TierChangedEvent<public><final>:listenable(int) = MakeProxyListenable(TierChangedEventInternal)
    EndedEventInternal<private><final>:event(agent) = event(agent){}

    # Fires with the owner when the effect starts (after the activate signal is sent) (Await / Subscribe it; it cannot be Signaled from outside)
    StartedEvent<public><final>:listenable(agent) = MakeProxyListenable(StartedEventInternal)

    # Fires with the owner when the effect ends (after the deactivate signal is sent, before removal)
    EndedEvent<public><final>:listenable(agent) = MakeProxyListenable(EndedEventInternal)

    var<private> Owner:?agent = false
    var<private> Source:?entity = false
    var<private> OriginTransform:transform = transform{}
    var<private> Started:logic = false
    var<private> Finished:logic = false
    var<private> EndSeconds:float = 0.0
    # Tier (from 1)
    var<private> Tier:int = 1
    # Persistent marker (Persistent of GrantPickupEffect. Lasts until End / EndPickupEffectsFor regardless of DurationSeconds)
    var<private> Persistent:logic = false
    WakeEventInternal<private>:event() = event(){}
    OwnerTags<private>:player_tag_holder = player_tag_holder{}

    OnSimulate<override>()<suspends>:void =
        # Wait one frame so that every part of the prefab has finished OnBeginSimulation before the signal is sent
        Sleep(0.0)
        if (Finished? or Started?):
            return
        ReadGrant()
        if (Agent := Owner?):
            ShouldBegin := ResolveStacking(Agent)
            if (ShouldBegin?):
                Begin(Agent)
                RunTimer()
            Finish()
        else:
            Print("[pickup_effect_component] No owner, so the effect does not start (create it under a player's slot: GrantPickupEffect / pickup_component)")
            Finish()

    OnEndSimulation<override>():void =
        # Removed before ending (the owner left etc.) (the parts inside revert in their own OnEndSimulation)
        if (not Finished?):
            set Finished = true
            OwnerTags.RemoveAll()
            if (Started?, Agent := Owner?):
                EndedEventInternal.Signal(Agent)
        (super:)OnEndSimulation()

    # When a part inside reports that it has finished its job (activation_finished_event; e.g. a single-use grant from CharacterSystem's CellKit), end the effect (next frame)
    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activation_finished_event[SceneEvent], Started?, not Finished?):
            spawn{EndNextFrame()}
        false

    # Wait one frame before ending so we do not stop from inside a notification (no deactivate signal while a delivery is in progress)
    EndNextFrame<private>()<suspends>:void =
        Sleep(0.0)
        End()

    # End now: sends the deactivate signal, removes the owner's tag and removes this entity (the effect prefab). Does nothing if already ended
    End<public>():void =
        Finish()

    # Add Seconds to the remaining time (negative shortens it). Does nothing for endless (DurationSeconds = 0) or Instant effects
    AddSeconds<public>(Seconds:float):void =
        if (not IsEndless[], not Instant?, not Finished?):
            set EndSeconds = Max(EndSeconds, GetSimulationElapsedTime()) + Seconds
            WakeEventInternal.Signal()

    # Set the remaining time to Seconds. Does nothing for endless or Instant effects
    SetRemainingSeconds<public>(Seconds:float):void =
        if (not IsEndless[], not Instant?, not Finished?):
            set EndSeconds = GetSimulationElapsedTime() + Seconds
            WakeEventInternal.Signal()

    # Remaining seconds. -1 for endless effects. DurationSeconds before start, 0 after the end
    GetRemainingSeconds<public>()<transacts>:float =
        if (Finished?):
            0.0
        else if (IsEndless[]):
            -1.0
        else if (not Started?):
            DurationSeconds
        else:
            Max(EndSeconds - GetSimulationElapsedTime(), 0.0)

    # Succeeds if the effect does not end by time (DurationSeconds is 0, or it was granted as Persistent. Instant excluded)
    IsEndless<public>()<decides><transacts>:void =
        not Instant?
        DurationSeconds <= 0.0 or Persistent?

    # Succeeds if granted as Persistent (the forever marker; e.g. an effect held from the start of a stage)
    IsPersistent<public>()<decides><transacts>:void =
        Persistent?

    # Current tier (from 1. Goes up when picked up again with StackMode = Tier)
    GetTier<public>()<transacts>:int =
        Tier

    # Raise the tier by 1 (up to MaxTier). true if it went up (TierChangedEvent fires)
    RaiseTier<public>():logic =
        if (Tier >= MaxTier or Finished?):
            return false
        set Tier += 1
        TierChangedEventInternal.Signal(Tier)
        true

    # Succeeds if the effect has started and has not ended yet
    IsActive<public>()<decides><transacts>:void =
        Started?
        not Finished?

    # The owner (agent receiving the effect). Fails if not decided yet (the first frame after creation) or if there is no owner
    FindOwner<public>()<decides><transacts>:agent =
        Owner?

    # The object that gave the effect (the picked-up orb entity). Fails if granted from code without a Source
    FindSource<public>()<decides><transacts>:entity =
        Source?

    # World transform of the picked-up object at pickup time (the Origin passed when granted from code)
    GetOriginTransform<public>()<transacts>:transform =
        OriginTransform

    # Succeeds if this effect is ongoing for Agent as an effect with the same EffectId (used for the stacking decision)
    IsSameEffectFor<internal>(Agent:agent, Id:string)<decides><transacts>:void =
        EffectId = Id
        Owner? = Agent
        not Finished?

    # Succeeds if this is Agent's effect (on the first frame, before the owner is decided, looks at the creator's marker). Fails for ended effects
    IsForAgent<internal>(Agent:agent)<decides><transacts>:void =
        not Finished?
        if (Known := Owner?):
            Known = Agent
        else:
            Entity.GetComponent[pickup_effect_grant_component].Agent = Agent

    # Read the owner, the source object and the transform from the creator (pickup_effect_grant_component) or from the owner of the place where it was put
    ReadGrant<private>():void =
        if (Grant := Entity.GetComponent[pickup_effect_grant_component]):
            set Owner = option{Grant.Agent}
            set Source = Grant.Source
            set OriginTransform = Grant.Origin
            set Persistent = Grant.Persistent
        else:
            if (Player := Entity.FindOwningPlayer[]):
                set Owner = option{Player}
            set OriginTransform = Entity.GetGlobalTransform()

    # How to handle an effect the player already has. true if this effect should start
    ResolveStacking<private>(Agent:agent):logic =
        if (EffectId = ""):
            return true
        Others := Entity.GetActivePickupEffects(Agent).FilterSameEffect(Self, EffectId)
        if (Others.Length = 0):
            return true
        if (StackMode = pickup_effect_stack_mode.Replace):
            for (Other : Others):
                Other.End()
            return true
        if (StackMode = pickup_effect_stack_mode.Stack and (MaxStacks <= 0 or Others.Length < MaxStacks)):
            return true
        # The ongoing effect that takes over instead of starting (notify the owner's side with Renewed)
        var Kept:?pickup_effect_component = false
        if (StackMode = pickup_effect_stack_mode.Extend):
            if (First := Others[0]):
                First.AddSeconds(DurationSeconds)
                set Kept = option{First}
        else if (StackMode = pickup_effect_stack_mode.Refresh):
            if (First := Others[0]):
                First.SetRemainingSeconds(Max(First.GetRemainingSeconds(), DurationSeconds))
                set Kept = option{First}
        else if (StackMode = pickup_effect_stack_mode.Tier):
            # Raise the tier and reset the time
            if (First := Others[0]):
                First.RaiseTier()
                First.SetRemainingSeconds(Max(First.GetRemainingSeconds(), DurationSeconds))
                set Kept = option{First}
        else if (StackMode = pickup_effect_stack_mode.Stack):
            # Limit reached: extend the copy ending soonest
            var Soonest:?pickup_effect_component = false
            for (Other : Others):
                if (Current := Soonest?):
                    if (Other.GetRemainingSeconds() < Current.GetRemainingSeconds()):
                        set Soonest = option{Other}
                else:
                    set Soonest = option{Other}
            if (Found := Soonest?):
                Found.SetRemainingSeconds(Max(Found.GetRemainingSeconds(), DurationSeconds))
            set Kept = Soonest
        else:
            # Ignore: change nothing (only notify the pickup)
            if (First := Others[0]):
                set Kept = option{First}
        if (Found := Kept?):
            NotifyOwner(Agent, Found, pickup_effect_notice.Renewed)
        false

    Begin<private>(Agent:agent):void =
        set Started = true
        set EndSeconds = GetSimulationElapsedTime() + DurationSeconds
        OwnerTags.Add(Agent, pickup_effect_tag{})
        Entity.SendActivatedBy(Agent)
        StartedEventInternal.Signal(Agent)
        Entity.SendUp(pickup_effect_changed_event{Effect := Self, Agent := Agent, Started := true})
        NotifyOwner(Agent, Self, pickup_effect_notice.Started)

    # Send the effect notification (pickup_effect_owner_event) under the owner's slot. Not sent if not under a slot
    NotifyOwner<private>(Agent:agent, Target:pickup_effect_component, Notice:pickup_effect_notice):void =
        if (Slot := Entity.FindOwningSlot[]):
            Slot.Entity.SendDown(pickup_effect_owner_event{Effect := Target, Picked := Self, Agent := Agent, Notice := Notice})

    RunTimer<private>()<suspends>:void =
        if (Instant?):
            # Let the parts inside finish their one-shot work on the activate signal before ending
            Sleep(0.0)
        else if (IsEndless[]):
            loop:
                WakeEventInternal.Await()
                if (Finished?):
                    break
        else:
            loop:
                Remaining := EndSeconds - GetSimulationElapsedTime()
                if (Finished? or Remaining <= 0.0):
                    break
                race:
                    Sleep(Remaining)
                    WakeEventInternal.Await()

    Finish<private>():void =
        if (Finished?):
            return
        set Finished = true
        if (Started?, Agent := Owner?):
            Entity.SendDeactivated()
            OwnerTags.RemoveAll()
            EndedEventInternal.Signal(Agent)
            Entity.SendUp(pickup_effect_changed_event{Effect := Self, Agent := Agent, Started := false})
            NotifyOwner(Agent, Self, pickup_effect_notice.Ended)
        WakeEventInternal.Signal()
        Entity.RemoveFromParent()

# Role: marker that GrantPickupEffect attaches to the root of an effect prefab. Holds who, from what and where it was granted (pickup_effect_component reads it on the next frame)
#   If the prefab has no pickup_effect_component on its root, logs to the output log and adds a default pickup_effect_component
# Placement: attached at runtime by GrantPickupEffect (not placed in the editor)
pickup_effect_grant_component<public> := class<final_super><internal>(component):
    # Agent receiving the effect (owner)
    Agent<public>:agent
    # Object that gave the effect (the picked-up orb entity). May be false when granted from code
    Source<public>:?entity
    # World transform of the source object when granted
    Origin<public>:transform
    # true lasts until End / EndPickupEffectsFor regardless of the effect's DurationSeconds (e.g. an effect held from the start of a stage)
    Persistent<public>:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (not Entity.GetComponent[pickup_effect_component]):
            Print("[pickup_effect_grant_component] The effect prefab has no pickup_effect_component on its root. Adding the default (10 s)")
            Entity.AddComponents(array{pickup_effect_component{Entity := Entity}})

# Create one instance of the effect prefab Prefab for Agent and give it to them. Placed under the agent's slot (created by the scope's or world's player_manager_component) with world transform Origin
#   Source is the object that gave the effect (the orb entity; the parts inside read it with FindSource[]. false if none). Returns the created entity. false if no slot is found (the agent is not participating)
#   Stacking of the same effect (StackMode) is decided by the created effect on the next frame (when it does not start, e.g. Extend, the created entity disappears right away)
(InEntity:entity).GrantPickupEffect<public>(Agent:agent, Prefab:concrete_subtype(entity), Origin:transform, Source:?entity):?entity =
    # Prefab{} cannot be written on the parameter itself (V3545), so copy it into a variable first
    PrefabType:concrete_subtype(entity) = Prefab
    GrantPickupEffectWith(InEntity, Agent, PrefabType{}, Origin, Source, false)

# Same as GrantPickupEffect, but lasts until End / EndPickupEffectsFor regardless of the effect's DurationSeconds (Persistent; e.g. an effect held from the start of a stage)
#   (Adding a named optional parameter to an extension method makes calls that pass it by name a type error, so this is a separate function)
(InEntity:entity).GrantPersistentPickupEffect<public>(Agent:agent, Prefab:concrete_subtype(entity), Origin:transform, Source:?entity):?entity =
    PrefabType:concrete_subtype(entity) = Prefab
    GrantPickupEffectWith(InEntity, Agent, PrefabType{}, Origin, Source, true)

# Give an assembled entity (pickup_effect_component on its root) to Agent as an effect (the body of GrantPickupEffect; for tests or code that assembles effects). false if no slot is found
(InEntity:entity).GrantPickupEffectEntity<public>(Agent:agent, Effect:entity, Origin:transform, Source:?entity):?entity =
    GrantPickupEffectWith(InEntity, Agent, Effect, Origin, Source, false)

# Body of GrantPickupEffectEntity (with a Persistent choice)
GrantPickupEffectWith<internal>(InEntity:entity, Agent:agent, Effect:entity, Origin:transform, Source:?entity, Persistent:logic):?entity =
    if (Manager := InEntity.FindScopedComponent[player_manager_component], Player := player[Agent], Slot := Manager.FindSlot[Player]):
        Effect.AddComponents(array{pickup_effect_grant_component{Entity := Effect, Agent := Agent, Source := Source, Origin := Origin, Persistent := Persistent}})
        Slot.Entity.AddEntities(array{Effect})
        Effect.SetGlobalTransform(Origin)
        option{Effect}
    else:
        Print("[pickup] No slot found for the agent to give the effect to (one player_manager_component is needed in the scope or the world. Effects cannot be given to agents who are not participating)")
        false

# The effect base (pickup_effect_component) on InEntity or an ancestor. Fails if not inside an effect prefab
(InEntity:entity).FindPickupEffect<public>()<decides><transacts>:pickup_effect_component =
    InEntity.FindNearestAncestorComponent[pickup_effect_component]

# Effects Agent is currently receiving (including those on their first frame before starting; ended ones excluded). The order is unspecified
(InEntity:entity).GetActivePickupEffects<public>(Agent:agent)<transacts>:[]pickup_effect_component =
    if (Manager := InEntity.FindScopedComponent[player_manager_component], Player := player[Agent], Slot := Manager.FindSlot[Player]):
        for (Effect : Slot.Entity.FindDescendantComponents(pickup_effect_component), Effect.IsForAgent[Agent]):
            Effect
    else:
        array{}

# End every effect Agent is currently receiving right now (game-flow reset, leaving the map, etc.). Returns the number ended
(InEntity:entity).EndPickupEffectsFor<public>(Agent:agent):int =
    Effects := InEntity.GetActivePickupEffects(Agent)
    for (Effect : Effects):
        Effect.End()
    Effects.Length

# Those of Effects, other than Exclude, with the same EffectId for the same agent
(Effects:[]pickup_effect_component).FilterSameEffect<internal>(Exclude:pickup_effect_component, Id:string)<transacts>:[]pickup_effect_component =
    for (Effect : Effects, Effect <> Exclude, Agent := Exclude.FindOwner[], Effect.IsSameEffectFor[Agent, Id]):
        Effect
