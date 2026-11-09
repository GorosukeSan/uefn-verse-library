using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { PickupSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Pickup ツールセット（宛先 "pickup"）。拾える物（PickupSystem の pickup_component）の一覧・拾わせる・戻す・隠す、効果を与える（拾った物はそのまま）・プレイヤーの効果の一覧・終える
#   拾える物は entity の番号か名前で指す。プレイヤーは番号
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag と mcp_session_restorable_tag（キー "pickups"：拾える物の出ている / 消えている）。タグの名前 pickup_effect_tag を知らせる
mcp_pickup_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider, mcp_session_restorable):

    # 同じツールセットを複数置くときの名前（空なら "pickup" だけで届く）
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
            McpTool("list", "拾える物の一覧。data に [\{id,name,display_name,available,pos\}]", array{})
            McpTool("pick", "拾わせる（拾ったときと同じ。効果を与えて隠す）", array{McpArg("pickup", "entity", "拾える物"), McpArg("player", "player", "番号")})
            McpTool("grant", "拾える物の効果だけを与える（拾える物はそのまま）", array{McpArg("pickup", "entity", "拾える物"), McpArg("player", "player", "番号")})
            McpTool("restore", "戻す（また拾えるようにする）", array{McpArg("pickup", "entity", "拾える物")})
            McpTool("hide", "隠す（拾えなくする）", array{McpArg("pickup", "entity", "拾える物")})
            McpTool("effects", "プレイヤーが受けている効果。data に [\{id,effect_id,remaining\}]", array{McpArg("player", "player", "番号")})
            McpTool("end_effects", "プレイヤーの効果をすべて終える", array{McpArg("player", "player", "番号")})

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
                    if (Picked?) then McpOk("picked") else McpFail("failed", "cannot pick（出ていない・組の外・絞り込み）")
                else if (Tool = "grant"):
                    Granted := Entity.GrantPickupEffect(Player, Pickup.Effect, Pickup.Entity.GetGlobalTransform(), option{Pickup.Entity})
                    if (Effect := Granted?):
                        McpOkData("granted", McpObject(array{McpField("id", "{Inbox.GetHandle(Effect)}")}))
                    else:
                        McpFail("failed", "effect not granted（Ignore の重ねがけなど）")
                else:
                    McpFail("unknown_tool", Tool)
            else:
                McpFail("no_player", Call.GetStringOr("player", ""))
        else:
            McpFail("no_entity", "pickup（pickup_component の entity）")

    FindPickups<private>()<transacts>:[]pickup_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Pickup : World.FindDescendantComponents(pickup_component)) { Pickup }
        else:
            array{}

    # ---- 状態（キー "pickups"：{"<キー>":true/false}。キーは名前か置いた位置） ----

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
