using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { PlayerSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Player toolset (destination "player"). Player list, position, teleport (the Fortnite character), agent tags (has / add / remove), joining and leaving groups (player_group_component)
#   Players are addressed by index (same as core.players; the order of the playspace's GetPlayers). Groups by entity id or mcp_name_component name
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag on its own entity. Reports the tag name player_state_tag (find only). Tags added to agents from MCP are removed when it stops
# Requirements, caveats: the body of a custom character (CharacterSystem) is driven by CharacterKit's character toolset. This one is for the Fortnite character
mcp_player_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider):

    # Name used when the same toolset is placed more than once (when empty, "player" alone reaches it)
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
            McpTool("list", "List of players. data: [\{index,has_character,pos,tags,groups\}] (tags = the named tags present, groups = ids of the groups joined)", array{})
            McpTool("get_position", "Position (cm), facing and velocity (cm/s) of the Fortnite character", array{McpArg("player", "player", "player index")})
            McpTool("teleport", "Moves the Fortnite character (writes the body entity's transform)", array{McpArg("player", "player", "player index"), McpArg("pos", "vector3", "position (cm)"), McpOptArg("yaw", "float", "yaw (degrees)")})
            McpTool("has_tag", "Whether the agent has the tag (reply is true / false)", array{McpArg("player", "player", "player index"), McpArg("tag", "string", "tag name (core.tags)")})
            McpTool("add_tag", "Adds a tag to the agent (<concrete> tags only; removed when this toolset stops)", array{McpArg("player", "player", "player index"), McpArg("tag", "string", "tag name")})
            McpTool("remove_tag", "Removes a tag added from MCP (all = true removes every tag of that type)", array{McpArg("player", "player", "player index"), McpArg("tag", "string", "tag name"), McpOptArg("all", "bool", "also remove tags added by other parts (default false)")})
            McpTool("groups", "List of groups (player_group_component). data: [\{id,name,members\}]", array{})
            McpTool("join_group", "Joins the group (player_group_component.Join; also leaves sibling groups if so configured)", array{McpArg("player", "player", "player index"), McpArg("group", "entity", "group entity")})
            McpTool("leave_group", "Leaves the group", array{McpArg("player", "player", "player index"), McpArg("group", "entity", "group entity")})
            McpTool("state", "Number of players and of tags added from MCP", array{})

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
                        McpFail("failed", "{Entry.Name} is not <concrete> (find only)")
                else if (Call.GetLogicOr("all", false) = true):
                    if (AddedTags.Remove[Player, Entry.TagType]) {}
                    if (Player.RemoveAllTags[Entry.TagType]) then McpOk("removed all {Entry.Name}") else McpFail("failed", "no {Entry.Name}")
                else if (AddedTags.Remove[Player, Entry.TagType]):
                    McpOk("removed {Entry.Name}")
                else:
                    McpFail("failed", "{Entry.Name} was not added by MCP")
            else:
                McpFail("bad_args", "unknown tag {Call.GetStringOr("tag", "")} (core.tags)")
        else if (Tool = "join_group" or Tool = "leave_group"):
            if (GroupEntity := Call.FindEntity["group"], Group := GroupEntity.GetComponent[player_group_component]):
                if (Tool = "join_group"):
                    Group.Join(Player)
                    McpOk("joined members={Group.GetMemberCount()}")
                else:
                    Group.Leave(Player)
                    McpOk("left members={Group.GetMemberCount()}")
            else:
                McpFail("no_entity", "group (an entity with player_group_component)")
        else:
            McpFail("unknown_tool", Tool)

    FindGroups<private>()<transacts>:[]player_group_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Group : World.FindDescendantComponents(player_group_component)) { Group }
        else:
            array{}
