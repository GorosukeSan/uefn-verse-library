using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { PickupSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Pickup toolset (destination "pickup"). Lists pickups (PickupSystem's pickup_component); pick, restore, hide, grant the effect (the pickup stays), list and end a player's effects
#   A pickup is addressed by entity id or name. Players by index
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag and mcp_session_restorable_tag on its own entity (key "pickups": whether each pickup is shown / hidden). Reports the tag name pickup_effect_tag
mcp_pickup_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider, mcp_session_restorable):

    # Name used when the same toolset is placed more than once (when empty, "pickup" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
        RoleTags.Add(Entity, mcp_session_restorable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "pickup"

    McpId<override>()<transacts>:string = InstanceId

    McpTagEntries<override>()<transacts>:[]mcp_tag_entry =
        array{McpFindOnlyTagEntry("pickup_effect_tag", pickup_effect_tag)}

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "List of pickups. data: [\{id,name,display_name,available,pos\}]", array{})
            McpTool("pick", "Makes the player pick it up (same as a real pickup: grants the effect and hides it)", array{McpArg("pickup", "entity", "pickup"), McpArg("player", "player", "player index")})
            McpTool("grant", "Grants only the pickup's effect (the pickup stays)", array{McpArg("pickup", "entity", "pickup"), McpArg("player", "player", "player index")})
            McpTool("restore", "Restores it (can be picked up again)", array{McpArg("pickup", "entity", "pickup")})
            McpTool("hide", "Hides it (cannot be picked up)", array{McpArg("pickup", "entity", "pickup")})
            McpTool("effects", "Effects the player currently has. data: [\{id,effect_id,remaining\}]", array{McpArg("player", "player", "player index")})
            McpTool("end_effects", "Ends all of the player's effects", array{McpArg("player", "player", "player index")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Items := for (Pickup : FindPickups()):
                McpObject(array{McpField("id", "{Inbox.GetHandle(Pickup.Entity)}"), McpField("name", McpQuote(Pickup.Entity.GetMcpName())), McpField("display_name", McpQuote(Pickup.DisplayName)),
                    McpField("available", if (Pickup.IsAvailable[]) then "true" else "false"), McpField("pos", McpVector(Pickup.Entity.GetGlobalTransform().Translation))})
            McpOkData("{Items.Length} pickups", McpArray(Items))
        else if (Tool = "effects" or Tool = "end_effects"):
            if (Player := Call.FindPlayer["player"]):
                if (Tool = "effects"):
                    Items := for (Effect : Entity.GetActivePickupEffects(Player)):
                        McpObject(array{McpField("id", "{Inbox.GetHandle(Effect.Entity)}"), McpField("effect_id", McpQuote(Effect.EffectId)), McpField("remaining", McpNumber(Effect.GetRemainingSeconds()))})
                    McpOkData("{Items.Length} effects", McpArray(Items))
                else:
                    McpOk("ended {Entity.EndPickupEffectsFor(Player)}")
            else:
                McpFail("no_player", Call.GetStringOr("player", ""))
        else if (Target := Call.FindEntity["pickup"], Pickup := Target.GetComponent[pickup_component]):
            if (Tool = "restore"):
                Pickup.Restore()
                McpOk("restored")
            else if (Tool = "hide"):
                Pickup.Hide()
                McpOk("hidden")
            else if (Player := Call.FindPlayer["player"]):
                if (Tool = "pick"):
                    Picked := Pickup.TryPickup(Player)
                    if (Picked?) then McpOk("picked") else McpFail("failed", "cannot pick (hidden, outside the group, or filtered out)")
                else if (Tool = "grant"):
                    Granted := Entity.GrantPickupEffect(Player, Pickup.Effect, Pickup.Entity.GetGlobalTransform(), option{Pickup.Entity})
                    if (Effect := Granted?):
                        McpOkData("granted", McpObject(array{McpField("id", "{Inbox.GetHandle(Effect)}")}))
                    else:
                        McpFail("failed", "effect not granted (e.g. stacking with Ignore)")
                else:
                    McpFail("unknown_tool", Tool)
            else:
                McpFail("no_player", Call.GetStringOr("player", ""))
        else:
            McpFail("no_entity", "pickup (an entity with pickup_component)")

    FindPickups<private>()<transacts>:[]pickup_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Pickup : World.FindDescendantComponents(pickup_component)) { Pickup }
        else:
            array{}

    # ---- State (key "pickups": {"<key>":true/false}; the key is the name or the placed position) ----

    McpSessionKey<override>()<transacts>:string = "pickups"

    McpSessionSave<override>(Context:mcp_session_context):string =
        McpObject(for (Pickup : FindPickups()) { McpField(Pickup.Entity.GetMcpKey(), if (Pickup.IsAvailable[]) then "\"1\"" else "\"0\"") })

    McpSessionRestore<override>(Context:mcp_session_context, State:value):string =
        if (O := State.AsObject[]):
            Pairs := for (Pickup : FindPickups(), V := O[Pickup.Entity.GetMcpKey()], Available := McpValueToLogic[V]) { (Pickup, Available) }
            for (Pair : Pairs):
                if (Pair(1)?):
                    Pair(0).Restore()
                else:
                    Pair(0).Hide()
            "ok restored={Pairs.Length}"
        else:
            "bad_state"
