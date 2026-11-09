using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { SpawnSystem }
using { SpawnSystem.PrefabKit }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Spawn ツールセット（宛先 "spawn"）。置いてある出し手（SpawnSystem の spawn_prefab_component と spawner_component）でプレハブを出す・消す、動かす・止める
#   出し手は entity の番号か mcp_name_component の名前で指す（list の "id"）。プレハブは出し手に設定したもの（Verse はプレハブを名前から作れない）
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag
mcp_spawn_toolset_component<public> := class<final_super>(component, mcp_controllable):

    # 同じツールセットを複数置くときの名前（空なら "spawn" だけで届く）
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
            McpTool("list", "出し手の一覧。data に [\{id,name,kind,count,max,running,pos\}]（kind は prefab か spawner）", array{})
            McpTool("spawn", "spawn_prefab_component の決めた場所に count 個出す。data に出した entity の [\{id\}]", array{McpArg("spawner", "entity", "出し手"), McpOptArg("count", "int", "数（既定 1）")})
            McpTool("spawn_at", "spawn_prefab_component で好きな位置に 1 つ出す", array{McpArg("spawner", "entity", "出し手"), McpArg("pos", "vector3", "位置（cm）"), McpOptArg("yaw", "float", "向き（度）")})
            McpTool("despawn", "出し手が出したもの 1 つを消す", array{McpArg("spawner", "entity", "出し手"), McpArg("entity", "entity", "消すもの（spawn の返した id）")})
            McpTool("despawn_all", "出し手が出したものを全部消す", array{McpArg("spawner", "entity", "出し手")})
            McpTool("start", "spawner_component を動かす", array{McpArg("spawner", "entity", "出し手")})
            McpTool("stop", "spawner_component を止める（出したものは消える）", array{McpArg("spawner", "entity", "出し手")})
            McpTool("refill", "spawner_component を今すぐ 1 回分補充する", array{McpArg("spawner", "entity", "出し手")})
            McpTool("spawned", "出し手が出しているもの。data に [\{id,pos\}]", array{McpArg("spawner", "entity", "出し手")})

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
                McpFail("no_entity", "spawner（spawn_prefab_component か spawner_component の entity）")
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
                    McpFail("failed", "MaxCount に届いている")
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
            McpFail("unknown_tool", "{Tool}（spawn_prefab_component は spawn / spawn_at / despawn / despawn_all / spawned）")

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
            McpFail("unknown_tool", "{Tool}（spawner_component は start / stop / refill / despawn_all / spawned）")
