using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { ActivationSystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Entity toolset (destination "entity"). Finds entities (tag, name, descendants), reads / writes position, rotation and scale, enable / disable, adds / removes tags, activation / deactivation signals, component list
#   An entity is addressed by id (the "id" returned by this toolset / entity.find; stable within the session) or by its mcp_name_component name
#   Tags are addressed by name (the core.tags list; game tags report their names through mcp_tag_provider; only <concrete> tags can be added / removed)
# Placement: best attached to the same entity as the inbox (mcp_inbox_component) (any entity works)
# Tags: mcp_controllable_tag on its own entity. Tags added from MCP are remembered and removed when it stops
# Requirements, caveats: Verse cannot read entity names (the editor display name) or component type names (as of v43.00). Give names with mcp_name_component
mcp_entity_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "entity" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    # Tags added from MCP (removed when it stops)
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
            McpTool("find", "Finds entities (by tag, name or root; root alone means all descendants). data: [\{id,name,pos\}]", array{McpOptArg("tag", "string", "tag name (core.tags)"), McpOptArg("name", "string", "mcp_name_component name"), McpOptArg("root", "entity", "search the descendants of this entity (default: the whole world)"), McpOptArg("limit", "int", "maximum number returned (default 200)")})
            McpTool("info", "Entity info (parent, child count, component count, named tags present, position)", array{McpArg("entity", "entity", "target")})
            McpTool("children", "Direct children. data: [\{id,name\}]", array{McpArg("entity", "entity", "target")})
            McpTool("parent", "Parent (the simulation entity's id for a top-level entity)", array{McpArg("entity", "entity", "target")})
            McpTool("get_transform", "Position (cm), rotation (degrees), scale", array{McpArg("entity", "entity", "target"), McpOptArg("space", "string", "global (default) or local")})
            McpTool("set_transform", "Changes position, rotation and scale (only the ones given)", array{McpArg("entity", "entity", "target"), McpOptArg("pos", "vector3", "position (cm)"), McpOptArg("rot", "json", "\{yaw,pitch,roll\} (degrees) or [yaw,pitch,roll]"), McpOptArg("scale", "vector3", "scale"), McpOptArg("space", "string", "global (default) or local")})
            McpTool("move_by", "Offsets the position (world axes, cm)", array{McpArg("entity", "entity", "target"), McpArg("delta", "vector3", "offset (cm)")})
            McpTool("enable", "Enables the entity's enableable components (mesh etc.)", array{McpArg("entity", "entity", "target"), McpOptArg("recursive", "bool", "descendants too (default false)")})
            McpTool("disable", "Disables the entity's enableable components", array{McpArg("entity", "entity", "target"), McpOptArg("recursive", "bool", "descendants too (default false)")})
            McpTool("has_tag", "Whether the tag is present (reply is true / false)", array{McpArg("entity", "entity", "target"), McpArg("tag", "string", "tag name")})
            McpTool("add_tag", "Adds a tag (<concrete> tags only; removed when this toolset stops)", array{McpArg("entity", "entity", "target"), McpArg("tag", "string", "tag name")})
            McpTool("remove_tag", "Removes a tag added from MCP (all = true removes every tag of that type)", array{McpArg("entity", "entity", "target"), McpArg("tag", "string", "tag name"), McpOptArg("all", "bool", "also remove tags added by other parts (default false)")})
            McpTool("activate", "Sends the activation signal (activated_event; with player, activated_by_agent_event) to the entity and its descendants", array{McpArg("entity", "entity", "target"), McpOptArg("player", "player", "the agent who activated it")})
            McpTool("deactivate", "Sends the deactivation signal (deactivated_event) to the entity and its descendants", array{McpArg("entity", "entity", "target")})
            McpTool("components", "List of components (type names cannot be read, so: index, enabled, and the name if it is an MCP receiver)", array{McpArg("entity", "entity", "target")})
            McpTool("state", "State of this toolset (number of tags added from MCP, number of ids)", array{})

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
                McpFail("bad_args", "unknown tag {Call.GetStringOr("tag", "")} (core.tags)")
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
                return McpFail("bad_args", "unknown tag {TagName} (core.tags)")
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
                McpFail("failed", "{Entry.Name} is not <concrete> (find only)")
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
                McpFail("failed", "{Entry.Name} was not added by MCP (all = true removes them all)")

    # Toggles Target's enableable components. Returns the count
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

# One entity ({"id","name","pos"}; no position when WithPos is false)
McpEntityJson<public>(Inbox:mcp_inbox_component, Target:entity, WithPos:logic)<transacts>:string =
    var Fields:[]string = array{McpField("id", "{Inbox.GetHandle(Target)}"), McpField("name", McpQuote(Target.GetMcpName()))}
    if (WithPos?):
        set Fields += array{McpField("pos", McpVector(Target.GetGlobalTransform().Translation))}
    McpObject(Fields)

EntityJson<internal>(Inbox:mcp_inbox_component, Target:entity, WithPos:logic)<transacts>:string =
    McpEntityJson(Inbox, Target, WithPos)

# transform ({"pos","rot","scale"})
McpTransformJson<public>(T:transform)<transacts>:string =
    McpObject(array{McpField("pos", McpVector(T.Translation)), McpField("rot", McpRotation(T.Rotation)), McpField("scale", McpVector(T.Scale))})

TransformJson<internal>(T:transform)<transacts>:string =
    McpTransformJson(T)

# Rotation argument ({"yaw","pitch","roll"} (degrees; missing axes are 0) or [yaw, pitch, roll]). Fails when unreadable
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

# Role: includes this entity's world transform in state snapshot / restore (SessionKit's session.snapshot / restore)
# Placement: attach to any entity whose state you want included (moving platforms, moved objects etc.)
# Key: "transform:" followed by Key (when empty, the mcp_name_component name, or failing that the placed position)
mcp_restore_transform_component<public> := class<final_super>(component, mcp_session_restorable):

    # State key (when empty, the name or the placed position)
    @editable:
        ToolTip := McpRestoreKeyToolTip
        Categories := array{McpCategory}
    Key<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    var<private> StartKey:string = ""

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        # The placed-position key is decided from the position before it moves (at start)
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
