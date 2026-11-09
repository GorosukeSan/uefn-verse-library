using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { PlayerSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Player ツールセット（宛先 "player"）。プレイヤーの一覧・位置・テレポート（Fortnite のキャラクター）、agent のタグ（ある？・付ける・外す）、組（player_group_component）への出入り
#   プレイヤーは番号（core.players と同じ。playspace の GetPlayers の順）で指す。組は entity の番号か mcp_name_component の名前で指す
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag。タグの名前 player_state_tag（探すだけ）を知らせる。MCP から agent に付けたタグは止まるときに外す
# 前提・注意：独自キャラクター（CharacterSystem）の体を動かすのは CharacterKit の character ツールセット。こちらは Fortnite のキャラクター
mcp_player_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider):

    # 同じツールセットを複数置くときの名前（空なら "player" だけで届く）
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    AddedTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})

    OnEndSimulation<override>():void =
        AddedTags.RemoveAll()
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "player"

    McpId<override>()<transacts>:string = InstanceId

    McpTagEntries<override>()<transacts>:[]mcp_tag_entry =
        array{McpFindOnlyTagEntry("player_state_tag", player_state_tag), McpFindOnlyTagEntry("controlled_movement_tag", controlled_movement_tag)}

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "プレイヤーの一覧。data に [\{index,has_character,pos,tags,groups\}]（tags は名前つきタグのうち付いているもの、groups は入っている組の id）", array{})
            McpTool("get_position", "Fortnite のキャラクターの位置（cm）・向き・速度（cm/s）", array{McpArg("player", "player", "番号")})
            McpTool("teleport", "Fortnite のキャラクターを移す（体の entity の transform を書く）", array{McpArg("player", "player", "番号"), McpArg("pos", "vector3", "位置（cm）"), McpOptArg("yaw", "float", "向き（度）")})
            McpTool("has_tag", "agent にタグが付いているか（reply が true / false）", array{McpArg("player", "player", "番号"), McpArg("tag", "string", "タグの名前（core.tags）")})
            McpTool("add_tag", "agent にタグを付ける（<concrete> のタグだけ。このツールセットが止まると外れる）", array{McpArg("player", "player", "番号"), McpArg("tag", "string", "タグの名前")})
            McpTool("remove_tag", "MCP から付けたタグを外す（all = true ならその型を全部）", array{McpArg("player", "player", "番号"), McpArg("tag", "string", "タグの名前"), McpOptArg("all", "bool", "ほかの部品が付けたものも外す（既定 false）")})
            McpTool("groups", "組（player_group_component）の一覧。data に [\{id,name,members\}]", array{})
            McpTool("join_group", "組に入れる（player_group_component.Join。兄弟の組から出す設定ならそれも）", array{McpArg("player", "player", "番号"), McpArg("group", "entity", "組の entity")})
            McpTool("leave_group", "組から出す", array{McpArg("player", "player", "番号"), McpArg("group", "entity", "組の entity")})
            McpTool("state", "プレイヤーの数・MCP から付けたタグの数", array{})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Groups := FindGroups()
            Items := for (Index -> Player : Entity.McpGetPlayers()):
                TagNames := for (Entry : Inbox.GetTagEntries(), Player.ContainsTag[Entry.TagType]) { Entry.Name }
                GroupIds := for (Group : Groups, Group.IsMember[Player]) { "{Inbox.GetHandle(Group.Entity)}" }
                var Fields:[]string = array{McpField("index", "{Index}")}
                if (Character := Player.GetFortCharacter[], Body := Character.GetEntity[]):
                    set Fields += array{McpField("has_character", "true"), McpField("pos", McpVector(Body.GetGlobalTransform().Translation))}
                else:
                    set Fields += array{McpField("has_character", "false")}
                set Fields += array{McpField("tags", McpStringArray(TagNames)), McpField("groups", McpArray(GroupIds))}
                McpObject(Fields)
            McpOkData("{Items.Length} players", McpArray(Items))
        else if (Tool = "groups"):
            Items := for (Group : FindGroups()):
                Members := for (Member : Group.GetMembers()) { "{Entity.McpGetPlayerIndex(Member)}" }
                McpObject(array{McpField("id", "{Inbox.GetHandle(Group.Entity)}"), McpField("name", McpQuote(Group.Entity.GetMcpName())), McpField("members", McpArray(Members))})
            McpOkData("{Items.Length} groups", McpArray(Items))
        else if (Tool = "state"):
            McpOkData("players={Entity.McpGetPlayers().Length}", McpObject(array{McpField("players", "{Entity.McpGetPlayers().Length}"), McpField("added_tags", "{AddedTags.GetCount()}")}))
        else if (Player := Call.FindPlayer["player"]):
            HandlePlayer(Call, Player)
        else:
            McpFail("no_player", Call.GetStringOr("player", ""))

    HandlePlayer<private>(Call:mcp_call, Player:player):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "get_position"):
            if (Character := Player.GetFortCharacter[], Body := Character.GetEntity[]):
                T := Body.GetGlobalTransform()
                Velocity := Character.GetLinearVelocity() * 100.0
                Pos := T.Translation
                McpOkData("{Pos.Left},{Pos.Up},{Pos.Forward}", McpObject(array{McpField("pos", McpVector(Pos)), McpField("rot", McpRotation(T.Rotation)), McpField("velocity", McpVector(Velocity))}))
            else:
                McpFail("failed", "no character")
        else if (Tool = "teleport"):
            if (Pos := Call.FindVector["pos"]):
                if (Character := Player.GetFortCharacter[], Body := Character.GetEntity[]):
                    T := Body.GetGlobalTransform()
                    Rot := if (Yaw := Call.FindFloat["yaw"]) then MakeRotationFromYawPitchRollDegrees(Yaw, 0.0, 0.0) else T.Rotation
                    Body.SetGlobalTransform(transform{Translation := Pos, Rotation := Rot, Scale := T.Scale})
                    McpOk("teleported")
                else:
                    McpFail("failed", "no character")
            else:
                McpBadArg("pos")
        else if (Tool = "has_tag" or Tool = "add_tag" or Tool = "remove_tag"):
            if (TagName := Call.FindString["tag"], Entry := Inbox.FindTagEntry[TagName]):
                if (Tool = "has_tag"):
                    McpOk(if (Player.ContainsTag[Entry.TagType]) then "true" else "false")
                else if (Tool = "add_tag"):
                    if (NewTag := Entry.MakeTag[]):
                        AddedTags.Add(Player, NewTag)
                        McpOk("added {Entry.Name}")
                    else:
                        McpFail("failed", "{Entry.Name} is not <concrete>（find only）")
                else if (Call.GetLogicOr("all", false) = true):
                    if (AddedTags.Remove[Player, Entry.TagType]) {}
                    if (Player.RemoveAllTags[Entry.TagType]) then McpOk("removed all {Entry.Name}") else McpFail("failed", "no {Entry.Name}")
                else if (AddedTags.Remove[Player, Entry.TagType]):
                    McpOk("removed {Entry.Name}")
                else:
                    McpFail("failed", "{Entry.Name} was not added by MCP")
            else:
                McpFail("bad_args", "unknown tag {Call.GetStringOr("tag", "")}（core.tags）")
        else if (Tool = "join_group" or Tool = "leave_group"):
            if (GroupEntity := Call.FindEntity["group"], Group := GroupEntity.GetComponent[player_group_component]):
                if (Tool = "join_group"):
                    Group.Join(Player)
                    McpOk("joined members={Group.GetMemberCount()}")
                else:
                    Group.Leave(Player)
                    McpOk("left members={Group.GetMemberCount()}")
            else:
                McpFail("no_entity", "group（player_group_component の entity）")
        else:
            McpFail("unknown_tool", Tool)

    FindGroups<private>()<transacts>:[]player_group_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Group : World.FindDescendantComponents(player_group_component)) { Group }
        else:
            array{}
