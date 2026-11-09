using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { MCPSystem.TooltipKit }

# Role tag attached to the entity of a part that can receive commands. The inbox (mcp_inbox_component) collects mcp_controllable from the components of entities with this tag
# The component that implements mcp_controllable attaches it itself (added in OnBeginSimulation, removed in OnEndSimulation, because MCP cannot write tags)
mcp_controllable_tag<public> := class<concrete>(tag){}

# Command receiver (toolset). A component implements it and attaches mcp_controllable_tag to its own entity
#   The destination "to" is "toolset" or "toolset@instance" (when several parts of the same toolset exist; the instance is McpId)
#   The inbox answers undeclared tools (unknown_tool) and missing required arguments (bad_args) before calling McpHandle
mcp_controllable<public> := interface:
    # Toolset name ("entity", "widget" etc.; lowercase ASCII)
    McpToolset<public>()<transacts>:string
    # Instance name (when empty, "toolset" alone reaches it; "toolset@name" also reaches it)
    McpId<public>()<transacts>:string
    # Descriptions of the tools it accepts (collected by describe)
    McpTools<public>()<transacts>:[]mcp_tool
    # Runs the tool and returns the reply. Work that does not finish in the same frame is spawned; return "accepted" right away and notify with Call.Notify when done
    #   Make it idempotent (when the inbox is rebuilt, a command whose reply was not yet seen may arrive again)
    #   Do not trust the values read (conversions that can fail go in Call.Find*[] / if; check ranges)
    McpHandle<public>(Call:mcp_call):mcp_reply

# ---- Names (Verse cannot read entity names, so attach this to any entity you address by name from MCP) ----

# Tag that mcp_name_component attaches to its own entity
mcp_name_tag<public> := class<concrete>(tag){}

# Role: gives an entity a name that MCP can address (the name in entity.find, the argument "entity":"<name>", widget screens, session keys etc.)
# Placement: attach to any entity you want to address by name. The same name may appear more than once (find returns them all; an argument that addresses one picks the first found)
mcp_name_component<public> := class<final_super>(component):
    # The name (alphanumeric recommended; empty is the same as not attached)
    @editable:
        ToolTip := McpNameToolTip
        Categories := array{McpCategory}
    McpName<public>:string = ""

    var<private> TagKey:?tag_key = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(mcp_name_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        (super:)OnEndSimulation()

# Name of the mcp_name_component on InEntity; empty when none
(InEntity:entity).GetMcpName<public>()<reads>:string =
    if (Named := InEntity.GetComponent[mcp_name_component]) then Named.McpName else ""

# ---- Tag names (Verse tags are types, so looking one up from a string needs a name -> type table) ----

# A named tag type. With Concrete it can also be added and removed (abstract tags can only be searched and checked)
mcp_tag_entry<public> := class<final>:
    Name<public>:string
    TagType<public>:castable_subtype(tag)
    Concrete<public>:?castable_concrete_subtype(tag) = false

# A tag usable for find, add and remove (concrete type)
McpTagEntry<public>(Name:string, TagType:castable_concrete_subtype(tag))<transacts>:mcp_tag_entry =
    mcp_tag_entry{Name := Name, TagType := TagType, Concrete := option{TagType}}

# A tag for find and check only (an abstract base etc.)
McpFindOnlyTagEntry<public>(Name:string, TagType:castable_subtype(tag))<transacts>:mcp_tag_entry =
    mcp_tag_entry{Name := Name, TagType := TagType}

# Implemented by parts that tell MCP their tag names (collected when entity.find / player.has_tag etc. turn a tag name into a type)
#   Attach mcp_controllable_tag to the implementing component's entity (the inbox collects by that tag; implementing mcp_controllable is not required)
mcp_tag_provider<public> := interface:
    McpTagEntries<public>()<transacts>:[]mcp_tag_entry

# Creates a new tag from Entry's tag type. Fails for an abstract tag (no Concrete)
(Entry:mcp_tag_entry).MakeTag<public>()<transacts><decides>:tag =
    TagType:castable_concrete_subtype(tag) = Entry.Concrete?
    TagType{}

# ---- State snapshot / restore (the base of session_restorable; collected by SessionKit's session toolset) ----

# Role tag attached to the entity of a part whose state can be snapshotted and restored (the implementing component attaches it itself)
mcp_session_restorable_tag<public> := class<concrete>(tag){}

# Implemented by parts that can write their state to JSON and restore it from JSON (session_restorable in DESIGN)
#   The key must stay the same across sessions ("character", or one built from the name / placed position such as "countdown@race")
mcp_session_restorable<public> := interface:
    # Stable key (when the same key appears more than once, the one collected later overwrites)
    McpSessionKey<public>()<transacts>:string
    # Writes the current state as a JSON string (object or array)
    McpSessionSave<public>(Context:mcp_session_context):string
    # Restores State (the JSON returned by McpSessionSave, parsed again). Returns a short result text ("ok" or why it could not restore)
    McpSessionRestore<public>(Context:mcp_session_context, State:value):string

# Context passed on snapshot / restore. Players are matched by "the index in that run" (the order of core.players)
#   When fewer players than saved are present the extras are dropped; when more, the missing ones stay as they are (by design; see README)
#   When restored positions are closer than MinSeparationCm, ClaimPosition shifts them to the left (Left) (no collision sweep)
mcp_session_context<public> := class<internal>:
    # Current players (in index order)
    Players<public>:[]player
    # Minimum distance between restored positions (cm)
    MinSeparationCm<public>:float = 120.0

    var<private> Claimed:[]vector3 = array{}

    # Returns a position where Desired may be placed and remembers it as used. When close to a remembered position, shifts left by MinSeparationCm at a time (up to 16 times)
    ClaimPosition<public>(Desired:vector3)<transacts>:vector3 =
        var Position:vector3 = Desired
        var Tries:int = 0
        loop:
            if (Tries >= 16 or not IsCrowded[Position]):
                break
            set Tries += 1
            set Position = Desired + vector3{Left := MinSeparationCm * (Tries * 1.0)}
        set Claimed += array{Position}
        Position

    IsCrowded<private>(Position:vector3)<transacts><decides>:void =
        Near := for (Other : Claimed, DistanceSquared(Other, Position) < MinSeparationCm * MinSeparationCm) { Other }
        Near.Length > 0

    # Player at Index. Fails when absent
    FindPlayer<public>(Index:int)<transacts><decides>:player =
        Players[Index]

# Creates an mcp_session_context (for calling snapshot / restore from outside SessionKit, or in tests)
MakeMcpSessionContext<public>(Players:[]player, MinSeparationCm:float)<transacts>:mcp_session_context =
    mcp_session_context{Players := Players, MinSeparationCm := MinSeparationCm}

# Builds a key from the placed position ("@left,up,forward" in rounded cm). Used as the key of unnamed parts (a placed object keeps the same key as long as it does not move)
McpPositionKey<public>(Position:vector3)<transacts>:string =
    "@{McpRoundText(Position.Left)},{McpRoundText(Position.Up)},{McpRoundText(Position.Forward)}"

# The name when present, otherwise the placed-position key
(InEntity:entity).GetMcpKey<public>()<transacts>:string =
    Name := InEntity.GetMcpName()
    if (Name <> "") then Name else McpPositionKey(InEntity.GetGlobalTransform().Translation)

# Text of the float rounded to an integer ("x" when out of range or not finite)
McpRoundText<public>(F:float)<transacts>:string =
    if (F.IsFinite[], F > -9.0e15, F < 9.0e15, R := Round[F]) then "{R}" else "x"

# Remembers the tags one component attached to entities and removes only its own when it stops (used e.g. when a toolset component attaches mcp_controllable_tag)
# Usage: hold RoleTags:mcp_role_tags = mcp_role_tags{}, call RoleTags.Add(Entity, mcp_controllable_tag{}) in OnBeginSimulation and RoleTags.RemoveAll() in OnEndSimulation
mcp_role_tags<public> := class:
    var<private> Keys:[]tuple(entity, tag_key, tag) = array{}

    # Attaches Tag to Target (pass a freshly created Tag on every call)
    Add<public>(Target:entity, Tag:tag)<transacts>:void =
        set Keys += array{(Target, Target.AddTag(Tag), Tag)}

    # Removes the tags attached to Target whose type is TagType (including subtypes). Succeeds when at least one was removed
    Remove<public>(Target:entity, TagType:castable_subtype(tag))<transacts><decides>:void =
        var Kept:[]tuple(entity, tag_key, tag) = array{}
        var Removed:int = 0
        for (Item : Keys):
            if (Item(0) = Target, TagType[Item(2)]):
                if (Target.RemoveTag[Item(1)]) {}
                set Removed += 1
            else:
                set Kept += array{Item}
        set Keys = Kept
        Removed > 0

    # Removes every tag attached through this holder
    RemoveAll<public>()<transacts>:void =
        for (Item : Keys):
            if (Item(0).RemoveTag[Item(1)]) {}
        set Keys = array{}

    # Number of tags currently attached
    GetCount<public>()<transacts>:int = Keys.Length
