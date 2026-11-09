using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SpawnSystem }
using { SpawnSystem.PrefabKit }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Spawn toolset (destination "spawn"). Spawns and despawns prefabs through placed spawners (SpawnSystem's spawn_prefab_component and spawner_component), starts and stops them
#   A spawner is addressed by entity id or mcp_name_component name (the "id" of list). The prefab is the one set on the spawner (Verse cannot create a prefab from a name)
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag on its own entity
mcp_spawn_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # Name used when the same toolset is placed more than once (when empty, "spawn" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "spawn"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "List of spawners. data: [\{id,name,kind,count,max,running,pos\}] (kind is prefab or spawner)", array{})
            McpTool("spawn", "Spawns count instances at the places decided by spawn_prefab_component. data: [\{id\}] of the spawned entities", array{McpArg("spawner", "entity", "spawner"), McpOptArg("count", "int", "count (default 1)")})
            McpTool("spawn_at", "Spawns one instance at an arbitrary position with spawn_prefab_component", array{McpArg("spawner", "entity", "spawner"), McpArg("pos", "vector3", "position (cm)"), McpOptArg("yaw", "float", "yaw (degrees)")})
            McpTool("despawn", "Removes one entity the spawner spawned", array{McpArg("spawner", "entity", "spawner"), McpArg("entity", "entity", "entity to remove (an id returned by spawn)")})
            McpTool("despawn_all", "Removes everything the spawner spawned", array{McpArg("spawner", "entity", "spawner")})
            McpTool("start", "Starts the spawner_component", array{McpArg("spawner", "entity", "spawner")})
            McpTool("stop", "Stops the spawner_component (spawned instances disappear)", array{McpArg("spawner", "entity", "spawner")})
            McpTool("refill", "Refills the spawner_component once, right now", array{McpArg("spawner", "entity", "spawner")})
            McpTool("spawned", "What the spawner currently has out. data: [\{id,pos\}]", array{McpArg("spawner", "entity", "spawner")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            var Items:[]string = array{}
            if (World := Entity.GetSimulationEntity[]):
                for (Spawner : World.FindDescendantComponents(spawn_prefab_component)):
                    set Items += array{McpObject(array{McpField("id", "{Inbox.GetHandle(Spawner.Entity)}"), McpField("name", McpQuote(Spawner.Entity.GetMcpName())), McpField("kind", "\"prefab\""),
                        McpField("count", "{Spawner.GetSpawnedCount()}"), McpField("max", "{Spawner.MaxCount}"), McpField("pos", McpVector(Spawner.Entity.GetGlobalTransform().Translation))})}
                for (Spawner : World.FindDescendantComponents(spawner_component)):
                    set Items += array{McpObject(array{McpField("id", "{Inbox.GetHandle(Spawner.Entity)}"), McpField("name", McpQuote(Spawner.Entity.GetMcpName())), McpField("kind", "\"spawner\""),
                        McpField("count", "{Spawner.GetSpawnedCount()}"), McpField("running", if (Spawner.IsRunning[]) then "true" else "false"), McpField("pos", McpVector(Spawner.Entity.GetGlobalTransform().Translation))})}
            McpOkData("{Items.Length} spawners", McpArray(Items))
        else if (Target := Call.FindEntity["spawner"]):
            if (Prefab := Target.GetComponent[spawn_prefab_component]):
                HandlePrefab(Call, Prefab)
            else if (Spawner := Target.GetComponent[spawner_component]):
                HandleSpawner(Call, Spawner)
            else:
                McpFail("no_entity", "spawner (an entity with spawn_prefab_component or spawner_component)")
        else:
            McpFail("no_entity", "spawner")

    HandlePrefab<private>(Call:mcp_call, Spawner:spawn_prefab_component):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "spawn"):
            Count := Clamp(Call.GetIntOr("count", 1), 1, 1000)
            Spawned := Spawner.Spawn(Count)
            McpOkData("{Spawned.Length} spawned", McpArray(for (E : Spawned) { McpObject(array{McpField("id", "{Inbox.GetHandle(E)}")}) }))
        else if (Tool = "spawn_at"):
            if (Pos := Call.FindVector["pos"]):
                Yaw := Call.GetFloatOr("yaw", 0.0)
                Spawned := Spawner.TrySpawnAt(transform{Translation := Pos, Rotation := MakeRotationFromYawPitchRollDegrees(Yaw, 0.0, 0.0)})
                if (E := Spawned?):
                    McpOkData("spawned", McpObject(array{McpField("id", "{Inbox.GetHandle(E)}")}))
                else:
                    McpFail("failed", "MaxCount reached")
            else:
                McpBadArg("pos")
        else if (Tool = "despawn"):
            if (E := Call.FindEntity["entity"]):
                Spawner.Despawn(E)
                McpOk("despawned")
            else:
                McpFail("no_entity", "entity")
        else if (Tool = "despawn_all"):
            Before := Spawner.GetSpawnedCount()
            Spawner.DespawnAll()
            McpOk("despawned {Before}")
        else if (Tool = "spawned"):
            McpOkData("{Spawner.GetSpawnedCount()} spawned", McpArray(for (E : Spawner.GetSpawned()) { McpObject(array{McpField("id", "{Inbox.GetHandle(E)}"), McpField("pos", McpVector(E.GetGlobalTransform().Translation))}) }))
        else:
            McpFail("unknown_tool", "{Tool} (spawn_prefab_component supports spawn / spawn_at / despawn / despawn_all / spawned)")

    HandleSpawner<private>(Call:mcp_call, Spawner:spawner_component):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "start"):
            Spawner.Start()
            McpOk("started")
        else if (Tool = "stop"):
            Spawner.Stop()
            McpOk("stopped")
        else if (Tool = "refill"):
            Spawner.RefillNow()
            McpOk("count={Spawner.GetSpawnedCount()}")
        else if (Tool = "despawn_all"):
            Spawner.ClearAll()
            McpOk("cleared")
        else if (Tool = "spawned"):
            McpOkData("{Spawner.GetSpawnedCount()} spawned", McpArray(for (S : Spawner.GetSpawned()) { McpObject(array{McpField("id", "{Inbox.GetHandle(S.Entity)}"), McpField("pos", McpVector(S.Entity.GetGlobalTransform().Translation))}) }))
        else:
            McpFail("unknown_tool", "{Tool} (spawner_component supports start / stop / refill / despawn_all / spawned)")
