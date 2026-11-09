using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { ActivationSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Entity ツールセット（宛先 "entity"）。entity を探す（タグ・名前・子孫）、位置・回転・大きさを読む / 書く、有効 / 無効、タグの付け外し、起動・停止の合図、component の一覧
#   entity は番号（このツールセットや entity.find が返す "id"。セッションの中で変わらない）か、mcp_name_component の名前で指す
#   タグは名前で指す（core.tags の一覧。ゲームのタグは mcp_tag_provider で名前を知らせる。付け外しは <concrete> のタグだけ）
# 置き方：受け箱（mcp_inbox_component）と同じ entity に付けるとよい（どこでもよい）
# タグ：自分の entity に mcp_controllable_tag。MCP から付けたタグは覚えておき、止まるときに外す
# 前提・注意：Verse から entity の名前（エディターの表示名）・component の型の名前は読めない（v43.00 時点）。名前は mcp_name_component で付ける
mcp_entity_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "entity" だけで届く）
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    # MCP から付けたタグ（止まるときに外す）
    AddedTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})

    OnEndSimulation<override>():void =
        AddedTags.RemoveAll()
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "entity"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("find", "entity を探す（tag・name・root のどれか。root だけなら子孫すべて）。data に [\{id,name,pos\}]", array{McpOptArg("tag", "string", "タグの名前（core.tags）"), McpOptArg("name", "string", "mcp_name_component の名前"), McpOptArg("root", "entity", "この entity の子孫から探す（既定は世界）"), McpOptArg("limit", "int", "返す数の上限（既定 200）")})
            McpTool("info", "entity の情報（親・子の数・component の数・付いている名前つきタグ・位置）", array{McpArg("entity", "entity", "対象")})
            McpTool("children", "直下の子。data に [\{id,name\}]", array{McpArg("entity", "entity", "対象")})
            McpTool("parent", "親（最上位なら simulation entity の番号）", array{McpArg("entity", "entity", "対象")})
            McpTool("get_transform", "位置（cm）・回転（度）・大きさ", array{McpArg("entity", "entity", "対象"), McpOptArg("space", "string", "global（既定）か local")})
            McpTool("set_transform", "位置・回転・大きさを変える（渡したものだけ）", array{McpArg("entity", "entity", "対象"), McpOptArg("pos", "vector3", "位置（cm）"), McpOptArg("rot", "json", "\{yaw,pitch,roll\}（度）か [yaw,pitch,roll]"), McpOptArg("scale", "vector3", "大きさ"), McpOptArg("space", "string", "global（既定）か local")})
            McpTool("move_by", "位置をずらす（世界の向き、cm）", array{McpArg("entity", "entity", "対象"), McpArg("delta", "vector3", "ずらす量（cm）")})
            McpTool("enable", "entity の component（enableable なもの。mesh など）を有効にする", array{McpArg("entity", "entity", "対象"), McpOptArg("recursive", "bool", "子孫も（既定 false）")})
            McpTool("disable", "entity の component（enableable なもの）を無効にする", array{McpArg("entity", "entity", "対象"), McpOptArg("recursive", "bool", "子孫も（既定 false）")})
            McpTool("has_tag", "タグが付いているか（reply が true / false）", array{McpArg("entity", "entity", "対象"), McpArg("tag", "string", "タグの名前")})
            McpTool("add_tag", "タグを付ける（<concrete> のタグだけ。このツールセットが止まると外れる）", array{McpArg("entity", "entity", "対象"), McpArg("tag", "string", "タグの名前")})
            McpTool("remove_tag", "MCP から付けたタグを外す（all = true なら、その型のタグを全部外す）", array{McpArg("entity", "entity", "対象"), McpArg("tag", "string", "タグの名前"), McpOptArg("all", "bool", "ほかの部品が付けたものも外す（既定 false）")})
            McpTool("activate", "起動の合図（activated_event。player を渡すと activated_by_agent_event）を entity とその子孫へ送る", array{McpArg("entity", "entity", "対象"), McpOptArg("player", "player", "起こした人")})
            McpTool("deactivate", "停止の合図（deactivated_event）を entity とその子孫へ送る", array{McpArg("entity", "entity", "対象")})
            McpTool("components", "component の一覧（型の名前は読めないので、番号・有効か・MCP の受け口なら名前）", array{McpArg("entity", "entity", "対象")})
            McpTool("state", "このツールセットの状態（MCP から付けたタグの数・番号の数）", array{})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        if (Tool = "find"):
            Find(Call)
        else if (Tool = "state"):
            McpOkData("added_tags={AddedTags.GetCount()}", McpObject(array{McpField("added_tags", "{AddedTags.GetCount()}")}))
        else if (Target := Call.FindEntity["entity"]):
            HandleEntity(Call, Target)
        else:
            McpFail("no_entity", Call.GetStringOr("entity", ""))

    HandleEntity<private>(Call:mcp_call, Target:entity):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "info"):
            Parent := if (P := Target.GetParent[]) then "{Inbox.GetHandle(P)}" else "null"
            TagNames := for (Entry : Inbox.GetTagEntries(), Target.ContainsTag[Entry.TagType]) { Entry.Name }
            McpOkData("id={Inbox.GetHandle(Target)}", McpObject(array{
                McpField("id", "{Inbox.GetHandle(Target)}"), McpField("name", McpQuote(Target.GetMcpName())), McpField("parent", Parent),
                McpField("children", "{Target.GetEntities().Length}"), McpField("components", "{Target.GetComponents().Length}"),
                McpField("tags", McpStringArray(TagNames)), McpField("transform", TransformJson(Target.GetGlobalTransform()))}))
        else if (Tool = "children"):
            Items := for (Child : Target.GetEntities()) { EntityJson(Inbox, Child, false) }
            McpOkData("{Items.Length} children", McpArray(Items))
        else if (Tool = "parent"):
            if (P := Target.GetParent[]):
                McpOkData("id={Inbox.GetHandle(P)}", EntityJson(Inbox, P, false))
            else:
                McpFail("no_entity", "no parent")
        else if (Tool = "get_transform"):
            Local := if (Call.GetStringOr("space", "global") = "local") then true else false
            T := if (Local?) then Target.GetLocalTransform() else Target.GetGlobalTransform()
            McpOkData("{T.Translation.Left},{T.Translation.Up},{T.Translation.Forward}", TransformJson(T))
        else if (Tool = "set_transform"):
            SetTransform(Call, Target)
        else if (Tool = "move_by"):
            if (Delta := Call.FindVector["delta"]):
                T := Target.GetGlobalTransform()
                Target.SetGlobalTransform(transform{Translation := T.Translation + Delta, Rotation := T.Rotation, Scale := T.Scale})
                McpOkData("moved", TransformJson(Target.GetGlobalTransform()))
            else:
                McpBadArg("delta")
        else if (Tool = "enable" or Tool = "disable"):
            On := if (Tool = "enable") then true else false
            Count := SetEnabled(Target, On, Call.GetLogicOr("recursive", false))
            McpOk("{Count} components")
        else if (Tool = "has_tag" or Tool = "add_tag" or Tool = "remove_tag"):
            if (TagName := Call.FindString["tag"], Entry := Inbox.FindTagEntry[TagName]):
                HandleTag(Call, Target, Entry)
            else:
                McpFail("bad_args", "unknown tag {Call.GetStringOr("tag", "")}（core.tags）")
        else if (Tool = "activate"):
            if (Agent := Call.FindAgent["player"]):
                Target.SendActivatedBy(Agent)
            else if (Call.HasArg["player"]):
                return McpFail("no_player", Call.GetStringOr("player", ""))
            else:
                Target.SendActivated()
            McpOk("activated")
        else if (Tool = "deactivate"):
            Target.SendDeactivated()
            McpOk("deactivated")
        else if (Tool = "components"):
            Items := for (Index -> Component : Target.GetComponents()):
                var Fields:[]string = array{McpField("index", "{Index}"), McpField("simulating", if (Component.IsSimulating[]) then "true" else "false")}
                if (Switch := enableable[Component]):
                    set Fields += array{McpField("enabled", if (Switch.IsEnabled[]) then "true" else "false")}
                if (Controllable := mcp_controllable[Component]):
                    set Fields += array{McpField("mcp_toolset", McpQuote(Controllable.McpToolset())), McpField("mcp_id", McpQuote(Controllable.McpId()))}
                if (Named := mcp_name_component[Component]):
                    set Fields += array{McpField("mcp_name", McpQuote(Named.McpName))}
                if (mcp_session_restorable[Component]):
                    set Fields += array{McpField("restorable", "true")}
                McpObject(Fields)
            McpOkData("{Items.Length} components", McpArray(Items))
        else:
            McpFail("unknown_tool", Tool)

    Find<private>(Call:mcp_call):mcp_reply =
        Inbox := Call.Inbox
        Limit := Clamp(Call.GetIntOr("limit", 200), 1, 5000)
        var Root:?entity = false
        if (Call.HasArg["root"]):
            if (R := Call.FindEntity["root"]):
                set Root = option{R}
            else:
                return McpFail("no_entity", "root")
        else if (World := Entity.GetSimulationEntity[]):
            set Root = option{World}
        if (not Root?):
            return McpFail("failed", "not in the scene")
        From := if (R := Root?) then R else Entity
        var Found:[]entity = array{}
        if (TagName := Call.FindString["tag"]):
            if (Entry := Inbox.FindTagEntry[TagName]):
                set Found = for (E : From.FindDescendantEntitiesWithTag(Entry.TagType)) { E }
            else:
                return McpFail("bad_args", "unknown tag {TagName}（core.tags）")
            if (Name := Call.FindString["name"]):
                set Found = for (E : Found, E.GetMcpName() = Name) { E }
        else if (Name := Call.FindString["name"]):
            set Found = for (E : From.FindDescendantEntitiesWithTag(mcp_name_tag), E.GetMcpName() = Name) { E }
        else if (Call.HasArg["root"]):
            set Found = for (E : From.FindDescendantEntities(entity), E <> From) { E }
        else:
            return McpFail("bad_args", "tag, name or root")
        Items := for (Index -> E : Found, Index < Limit) { EntityJson(Inbox, E, true) }
        McpOkData("{Found.Length} found", McpArray(Items))

    SetTransform<private>(Call:mcp_call, Target:entity):mcp_reply =
        Local := if (Call.GetStringOr("space", "global") = "local") then true else false
        T := if (Local?) then Target.GetLocalTransform() else Target.GetGlobalTransform()
        var Next:transform = T
        if (Call.HasArg["pos"]):
            if (Pos := Call.FindVector["pos"]):
                set Next = transform{Translation := Pos, Rotation := Next.Rotation, Scale := Next.Scale}
            else:
                return McpBadArg("pos")
        if (Call.HasArg["rot"]):
            if (Rot := McpReadRotation[Call.FindArg["rot"]]):
                set Next = transform{Translation := Next.Translation, Rotation := Rot, Scale := Next.Scale}
            else:
                return McpBadArg("rot")
        if (Call.HasArg["scale"]):
            if (Scale := Call.FindVector["scale"]):
                set Next = transform{Translation := Next.Translation, Rotation := Next.Rotation, Scale := Scale}
            else:
                return McpBadArg("scale")
        if (Local?):
            Target.SetLocalTransform(Next)
        else:
            Target.SetGlobalTransform(Next)
        McpOkData("set", TransformJson(Next))

    HandleTag<private>(Call:mcp_call, Target:entity, Entry:mcp_tag_entry):mcp_reply =
        Tool := Call.Tool
        if (Tool = "has_tag"):
            McpOk(if (Target.ContainsTag[Entry.TagType]) then "true" else "false")
        else if (Tool = "add_tag"):
            if (NewTag := Entry.MakeTag[]):
                AddedTags.Add(Target, NewTag)
                McpOk("added {Entry.Name}")
            else:
                McpFail("failed", "{Entry.Name} is not <concrete>（find only）")
        else:
            if (Call.GetLogicOr("all", false) = true):
                if (AddedTags.Remove[Target, Entry.TagType]) {}
                if (Target.RemoveAllTags[Entry.TagType]):
                    McpOk("removed all {Entry.Name}")
                else:
                    McpFail("failed", "no {Entry.Name}")
            else if (AddedTags.Remove[Target, Entry.TagType]):
                McpOk("removed {Entry.Name}")
            else:
                McpFail("failed", "{Entry.Name} was not added by MCP（all = true で全部外す）")

    # Target の enableable な component を切り替える。数を返す
    SetEnabled<private>(Target:entity, On:logic, Recursive:logic):int =
        var Count:int = 0
        Entities := if (Recursive?) then array{Target} + (for (E : Target.FindDescendantEntities(entity), E <> Target) { E }) else array{Target}
        for (E : Entities, Component : E.GetComponents(), Switch := enableable[Component]):
            if (On?):
                Switch.Enable()
            else:
                Switch.Disable()
            set Count += 1
        Count

# entity 1 つ（{"id","name","pos"}。WithPos が false なら位置を付けない）
McpEntityJson<public>(Inbox:mcp_inbox_component, Target:entity, WithPos:logic)<transacts>:string =
    var Fields:[]string = array{McpField("id", "{Inbox.GetHandle(Target)}"), McpField("name", McpQuote(Target.GetMcpName()))}
    if (WithPos?):
        set Fields += array{McpField("pos", McpVector(Target.GetGlobalTransform().Translation))}
    McpObject(Fields)

EntityJson<internal>(Inbox:mcp_inbox_component, Target:entity, WithPos:logic)<transacts>:string =
    McpEntityJson(Inbox, Target, WithPos)

# transform（{"pos","rot","scale"}）
McpTransformJson<public>(T:transform)<transacts>:string =
    McpObject(array{McpField("pos", McpVector(T.Translation)), McpField("rot", McpRotation(T.Rotation)), McpField("scale", McpVector(T.Scale))})

TransformJson<internal>(T:transform)<transacts>:string =
    McpTransformJson(T)

# 回転の引数（{"yaw","pitch","roll"}（度。無い軸は 0）か [yaw, pitch, roll]）。読めなければ失敗する
McpReadRotation<public>(V:value)<transacts><decides>:rotation =
    if (Items := V.AsArray[]):
        Items.Length = 3
        MakeRotationFromYawPitchRollDegrees(McpValueToFloat[Items[0]], McpValueToFloat[Items[1]], McpValueToFloat[Items[2]])
    else:
        O := V.AsObject[]
        Yaw := if (X := O["yaw"]) then McpValueToFloat[X] else 0.0
        Pitch := if (X := O["pitch"]) then McpValueToFloat[X] else 0.0
        Roll := if (X := O["roll"]) then McpValueToFloat[X] else 0.0
        MakeRotationFromYawPitchRollDegrees(Yaw, Pitch, Roll)

# 役割：この entity の世界の transform を、状態の書き出し・復元（SessionKit の session.snapshot / restore）に入れる
# 置き方：状態に入れたい entity に付ける（動く足場・動かした物など）
# キー：Key（空なら mcp_name_component の名前、それも無ければ置いた位置）に "transform:" を付けたもの
mcp_restore_transform_component<public> := class<final_super>(component, mcp_session_restorable):

    # 状態のキー（空なら名前か置いた位置）
    @editable:
        ToolTip := McpRestoreKeyToolTip
        Categories := array{McpCategory}
    Key<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    var<private> StartKey:string = ""

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        # 置いた位置のキーは、動く前（開始のとき）の位置で決める
        set StartKey = if (Key <> "") then Key else Entity.GetMcpKey()
        RoleTags.Add(Entity, mcp_session_restorable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpSessionKey<override>()<transacts>:string = "transform:{StartKey}"

    McpSessionSave<override>(Context:mcp_session_context):string =
        McpTransformJson(Entity.GetGlobalTransform())

    McpSessionRestore<override>(Context:mcp_session_context, State:value):string =
        if (O := State.AsObject[], Pos := McpValueToVector[O["pos"]]):
            T := Entity.GetGlobalTransform()
            Rot := if (R := McpReadRotation[O["rot"]]) then R else T.Rotation
            Scale := if (S := McpValueToVector[O["scale"]]) then S else T.Scale
            Entity.SetGlobalTransform(transform{Translation := Pos, Rotation := Rot, Scale := Scale})
            "ok"
        else:
            "bad_state"
