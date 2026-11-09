using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { /Fortnite.com/Characters }
using { PlayerSystem }
using { MovementSystem }
using { CharacterSystem }
using { CharacterSystem.MoveKit }
using { CharacterSystem.BuffKit }
using { CharacterSystem.SurfaceKit }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Character ツールセット（宛先 "character"）。独自キャラクター（CharacterSystem の character_motor_component）を MCP から動かす
#   移動の入力（walk の SetMoveInput）・世界の向きへの移動・ジャンプ・ダッシュ・テレポート・速度・重力・左右の入力のしかた（walk の SetSideStyle）、動きの JSON の再生（入力の時刻表 / 通る点の列）と記録
#   プレイヤーは番号（core.players と同じ）で指す。体はその人が動かしている character_motor_component（Entity.FindCharacterMotorFor）
# 置き方：受け箱と同じ entity に付けるとよい
# 知らせ：長くかかるもの（move の seconds・play）は "accepted" を返し、終わったら [MCPC] {"event":"move_done" / "play_done",...}
# タグ：自分の entity に mcp_controllable_tag と mcp_session_restorable_tag（状態のキー "characters"：人ごとの位置・速度・重力）。タグの名前 custom_character_tag を知らせる
# 前提・注意：入力は walk の今の歩く向き（GetWalkBasis：Space（View / World / Facing / SideView）と左右の入力のしかた。TankTurn は体の向き）に合わせて世界の向きから直す（move_world・move_to・play の points）。段差を登る処理は CharacterSystem に無い
mcp_character_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider, mcp_session_restorable):

    # 同じツールセットを複数置くときの名前（空なら "character" だけで届く）
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    # 人ごとの「動きの番号」。新しい move / play / stop で増やし、古い待ちはこれを見て止まる
    var<private> Generation:[agent]int = map{}
    # 記録中の人
    var<private> Recorders:[agent]mcp_character_recorder = map{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
        RoleTags.Add(Entity, mcp_session_restorable_tag{})

    OnEndSimulation<override>():void =
        for (Recorder : Recorders):
            Recorder.Stop()
        set Recorders = map{}
        set Generation = map{}
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "character"

    McpId<override>()<transacts>:string = InstanceId

    McpTagEntries<override>()<transacts>:[]mcp_tag_entry =
        array{McpFindOnlyTagEntry("custom_character_tag", custom_character_tag), McpFindOnlyTagEntry("character_modified_tag", character_modified_tag), McpFindOnlyTagEntry("character_surface_tag", character_surface_tag)}

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "独自キャラクターを動かしている人の一覧。data に [\{player,pos,velocity,grounded\}]", array{})
            McpTool("state", "体の状態（位置・速度 cm/s・接地・状態・重力の倍率・変更の倍率・ダッシュ中か・左右の入力のしかた side_style / side_style_base・動く床 ground_velocity / inherited_velocity / riding）", array{McpArg("player", "player", "番号")})
            McpTool("move", "移動の入力を入れる（walk の SetMoveInput と同じ。forward = 前、left = 左。長さ 1 まで）。seconds を渡すとその秒数のあと 0 に戻す（終わりに move_done）", array{McpArg("player", "player", "番号"), McpArg("input", "json", "\{forward,left\} か [forward,left]"), McpOptArg("seconds", "float", "この秒数だけ入れる")})
            McpTool("move_world", "世界の向き（cm の向き。長さは使わない）へ歩かせる。walk の Space に合わせて毎フレーム入力に直す。seconds（既定 1）のあと止める（move_done）", array{McpArg("player", "player", "番号"), McpArg("dir", "vector3", "向き"), McpOptArg("seconds", "float", "秒（既定 1.0）"), McpOptArg("scale", "float", "入力の強さ 0〜1（既定 1）")})
            McpTool("move_to", "世界の位置へ歩かせる（水平の距離が tolerance 以下で止まる。着いたら move_done。ゲームが体を別の場所へ移したら reason = moved_away）", array{McpArg("player", "player", "番号"), McpArg("pos", "vector3", "行き先（cm）"), McpOptArg("tolerance", "float", "着いたとみなす距離 cm（既定 60）"), McpOptArg("timeout", "float", "秒（既定 15）")})
            McpTool("stop", "入力を 0 にし、move / play を止める（brake = true なら水平の速度も 0）", array{McpArg("player", "player", "番号"), McpOptArg("brake", "bool", "水平の速度も 0 にする")})
            McpTool("jump", "ジャンプさせる（跳べなければ failed）", array{McpArg("player", "player", "番号")})
            McpTool("dash", "ダッシュさせる（出せなければ failed）", array{McpArg("player", "player", "番号")})
            McpTool("teleport", "足元を pos へ（当たりを見ない）。keep_velocity が false（既定）なら速度を 0 に", array{McpArg("player", "player", "番号"), McpArg("pos", "vector3", "位置（cm。足元）"), McpOptArg("keep_velocity", "bool", "速度を残す")})
            McpTool("set_velocity", "速度を決める（cm/s。世界の向き）", array{McpArg("player", "player", "番号"), McpArg("velocity", "vector3", "速度")})
            McpTool("add_velocity", "速度を足す（cm/s）", array{McpArg("player", "player", "番号"), McpArg("delta", "vector3", "足す速度")})
            McpTool("set_gravity_scale", "重力の倍率（1 で既定、0 で無重力）", array{McpArg("player", "player", "番号"), McpArg("scale", "float", "倍率")})
            McpTool("set_side_style", "左右の入力のしかた（walk の基本。SetSideStyle と同じ）を変える。turn = 動く向きへ回る、strafe = 前を向いたまま横へ（カニ歩き）、tank_turn = その場で回る、toggle = 切り替えのボタンと同じ。バフが決めているあいだはそちらが優先。reply に今のしかたと基本", array{McpArg("player", "player", "番号"), McpArg("style", "string", "turn / strafe / tank_turn / toggle")})
            McpTool("play", "動きの JSON を再生する（終わりに play_done）。steps：[\{t,move,world,jump,dash,teleport,stop\}]（t 秒に入力）／points：[\{pos,jump,dash,wait,teleport\}]（順に歩いて通る）", array{McpArg("player", "player", "番号"), McpArg("motion", "json", "\{steps:[...]\} か \{points:[...], tolerance, timeout\}")})
            McpTool("record_start", "動きの記録を始める（interval 秒ごとの位置・速度・接地と、ジャンプ・ダッシュなどの出来事）", array{McpArg("player", "player", "番号"), McpOptArg("interval", "float", "秒（既定 0.1）")})
            McpTool("record_stop", "記録を止めて返す。data に \{interval,samples:[\{t,pos,velocity,grounded\}],actions:[\{t,action\}],points:[\{pos\}]\}（points はそのまま play に渡せる）", array{McpArg("player", "player", "番号")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        if (Tool = "list"):
            Items := for (Index -> Player : Entity.McpGetPlayers(), Motor := Entity.FindCharacterMotorFor[Player]):
                McpObject(array{McpField("player", "{Index}"), McpField("pos", McpVector(Motor.Entity.GetGlobalTransform().Translation)),
                    McpField("velocity", McpVector(Motor.GetVelocity())), McpField("grounded", if (Motor.IsGrounded[]) then "true" else "false")})
            McpOkData("{Items.Length} characters", McpArray(Items))
        else if (Player := Call.FindPlayer["player"]):
            if (Motor := Entity.FindCharacterMotorFor[Player]):
                HandleMotor(Call, Player, Motor)
            else:
                McpFail("failed", "no custom character for player {Call.GetStringOr("player", "")}")
        else:
            McpFail("no_player", Call.GetStringOr("player", ""))

    HandleMotor<private>(Call:mcp_call, Player:player, Motor:character_motor_component):mcp_reply =
        Tool := Call.Tool
        if (Tool = "state"):
            McpOkData("ok", MotorStateJson(Motor))
        else if (Tool = "move"):
            if (Input := ReadInput[Call.FindArg["input"]]):
                if (Walk := Motor.FindCharacterWalk[]):
                    Gen := NextGeneration(Player)
                    Walk.SetMoveInput(Input)
                    if (Seconds := Call.FindFloat["seconds"]):
                        spawn{ReleaseAfter(Call, Player, Gen, Walk, Seconds)}
                        McpOk("accepted")
                    else:
                        McpOk("input {Input.Forward},{Input.Left}")
                else:
                    McpFail("failed", "no character_walk_component")
            else:
                McpBadArg("input")
        else if (Tool = "move_world"):
            if (Dir := Call.FindVector["dir"]):
                if (Walk := Motor.FindCharacterWalk[]):
                    Gen := NextGeneration(Player)
                    Seconds := Clamp(Call.GetFloatOr("seconds", 1.0), 0.0, 600.0)
                    Scale := Clamp(Call.GetFloatOr("scale", 1.0), 0.0, 1.0)
                    spawn{SteerFor(Call, Player, Gen, Motor, Walk, Dir, Seconds, Scale)}
                    McpOk("accepted")
                else:
                    McpFail("failed", "no character_walk_component")
            else:
                McpBadArg("dir")
        else if (Tool = "move_to"):
            if (Target := Call.FindVector["pos"]):
                if (Walk := Motor.FindCharacterWalk[]):
                    Gen := NextGeneration(Player)
                    Tolerance := Clamp(Call.GetFloatOr("tolerance", 60.0), 5.0, 10000.0)
                    Timeout := Clamp(Call.GetFloatOr("timeout", 15.0), 0.1, 600.0)
                    spawn{WalkToNotify(Call, Player, Gen, Motor, Walk, Target, Tolerance, Timeout)}
                    McpOk("accepted")
                else:
                    McpFail("failed", "no character_walk_component")
            else:
                McpBadArg("pos")
        else if (Tool = "stop"):
            NextGeneration(Player)
            if (Walk := Motor.FindCharacterWalk[]):
                Walk.SetMoveInput(vector3{})
            if (Call.GetLogicOr("brake", false) = true):
                V := Motor.GetVelocity()
                Motor.SetVelocity(vector3{Up := V.Up})
            McpOk("stopped")
        else if (Tool = "jump"):
            if (Jumper := Motor.Entity.GetComponent[character_jump_component]):
                Jumped := Jumper.Jump()
                if (Jumped?) then McpOk("jumped") else McpFail("failed", "cannot jump now")
            else:
                McpFail("failed", "no character_jump_component")
        else if (Tool = "dash"):
            if (Dasher := Motor.Entity.GetComponent[character_dash_component]):
                Dashed := Dasher.Dash()
                if (Dashed?) then McpOk("dashed") else McpFail("failed", "cannot dash now")
            else:
                McpFail("failed", "no character_dash_component")
        else if (Tool = "teleport"):
            if (Pos := Call.FindVector["pos"]):
                Motor.TeleportTo(Pos)
                if (Call.GetLogicOr("keep_velocity", false) = false):
                    Motor.SetVelocity(vector3{})
                McpOk("teleported")
            else:
                McpBadArg("pos")
        else if (Tool = "set_velocity"):
            if (V := Call.FindVector["velocity"]):
                Motor.SetVelocity(V)
                McpOk("set")
            else:
                McpBadArg("velocity")
        else if (Tool = "add_velocity"):
            if (V := Call.FindVector["delta"]):
                Motor.AddVelocity(V)
                McpOk("added")
            else:
                McpBadArg("delta")
        else if (Tool = "set_gravity_scale"):
            if (Scale := Call.FindFloat["scale"]):
                Motor.SetGravityScale(Clamp(Scale, -100.0, 100.0))
                McpOk("set")
            else:
                McpBadArg("scale")
        else if (Tool = "set_side_style"):
            if (Walk := Motor.FindCharacterWalk[]):
                Name := Call.GetStringOr("style", "")
                if (Name = "toggle"):
                    Walk.SwitchSideStyle()
                    McpOk("side_style {SideStyleName(Walk.GetSideStyle())} base {SideStyleName(Walk.GetBaseSideStyle())}")
                else if (Style := ReadSideStyle[Name]):
                    Walk.SetSideStyle(Style)
                    McpOk("side_style {SideStyleName(Walk.GetSideStyle())} base {SideStyleName(Walk.GetBaseSideStyle())}")
                else:
                    McpBadArg("style")
            else:
                McpFail("failed", "no character_walk_component")
        else if (Tool = "play"):
            if (Motion := Call.FindObject["motion"]):
                Gen := NextGeneration(Player)
                spawn{Play(Call, Player, Gen, Motor, Motion)}
                McpOk("accepted")
            else:
                McpBadArg("motion")
        else if (Tool = "record_start"):
            if (Old := Recorders[Player]):
                Old.Stop()
            Interval := Clamp(Call.GetFloatOr("interval", 0.1), 0.02, 10.0)
            Recorder := mcp_character_recorder{Motor := Motor, IntervalSeconds := Interval}
            if (set Recorders[Player] = Recorder) {}
            Recorder.Start()
            McpOk("recording")
        else if (Tool = "record_stop"):
            if (Recorder := Recorders[Player]):
                Recorder.Stop()
                var Kept:[agent]mcp_character_recorder = map{}
                for (Key -> Value : Recorders, Key <> Player):
                    if (set Kept[Key] = Value) {}
                set Recorders = Kept
                McpOkData("{Recorder.GetSampleCount()} samples", Recorder.ToJson())
            else:
                McpFail("failed", "not recording")
        else:
            McpFail("unknown_tool", Tool)

    # ---- 人ごとの動きの番号 ----

    NextGeneration<private>(Agent:agent)<transacts>:int =
        Next := (if (G := Generation[Agent]) then G else 0) + 1
        if (set Generation[Agent] = Next) {}
        Next

    IsCurrent<private>(Agent:agent, Gen:int)<transacts><decides>:void =
        Generation[Agent] = Gen

    # ---- 待つもの（spawn する） ----

    ReleaseAfter<private>(Call:mcp_call, Agent:agent, Gen:int, Walk:character_walk_component, Seconds:float)<suspends>:void =
        Sleep(Clamp(Seconds, 0.0, 600.0))
        if (IsCurrent[Agent, Gen]):
            Walk.SetMoveInput(vector3{})
            Call.Notify("move_done", "\{\"ok\":true\}")
        else:
            Call.Notify("move_done", "\{\"ok\":false,\"reason\":\"replaced\"\}")

    SteerFor<private>(Call:mcp_call, Agent:agent, Gen:int, Motor:character_motor_component, Walk:character_walk_component, Dir:vector3, Seconds:float, Scale:float)<suspends>:void =
        Start := GetSimulationElapsedTime()
        var Replaced:logic = false
        var Previous:vector3 = Motor.Entity.GetGlobalTransform().Translation
        loop:
            if (not IsCurrent[Agent, Gen] or not Motor.IsSimulating[]):
                set Replaced = true
                break
            if (GetSimulationElapsedTime() - Start >= Seconds):
                break
            # ゲームが体を別の場所へ移した（リスポーン・リザルトの舞台など）ならやめる
            Now := Motor.Entity.GetGlobalTransform().Translation
            if (DistanceSquaredXY(Now, Previous) > JumpAwayCm * JumpAwayCm):
                set Replaced = true
                break
            set Previous = Now
            Walk.SetMoveInput(McpWorldToMoveInput(Walk, Motor, Dir) * Scale)
            Sleep(0.0)
        if (not Replaced?):
            Walk.SetMoveInput(vector3{})
        Call.Notify("move_done", if (Replaced?) then "\{\"ok\":false,\"reason\":\"replaced\"\}" else "\{\"ok\":true\}")

    WalkToNotify<private>(Call:mcp_call, Agent:agent, Gen:int, Motor:character_motor_component, Walk:character_walk_component, Target:vector3, Tolerance:float, Timeout:float)<suspends>:void =
        Result := WalkTo(Agent, Gen, Motor, Walk, Target, Tolerance, Timeout)
        if (IsCurrent[Agent, Gen]):
            Walk.SetMoveInput(vector3{})
        Pos := Motor.Entity.GetGlobalTransform().Translation
        Call.Notify("move_done", McpObject(array{McpField("ok", if (Result = "reached") then "true" else "false"), McpField("reason", McpQuote(Result)), McpField("pos", McpVector(Pos))}))

    # Target へ歩く。"reached" / "timeout" / "replaced" を返す（入力は残す。呼ぶ側が 0 にする）
    WalkTo<private>(Agent:agent, Gen:int, Motor:character_motor_component, Walk:character_walk_component, Target:vector3, Tolerance:float, Timeout:float)<suspends>:string =
        Start := GetSimulationElapsedTime()
        var Result:string = "timeout"
        var Previous:vector3 = Motor.Entity.GetGlobalTransform().Translation
        loop:
            if (not IsCurrent[Agent, Gen] or not Motor.IsSimulating[]):
                set Result = "replaced"
                break
            Pos := Motor.Entity.GetGlobalTransform().Translation
            # ゲームが体を別の場所へ移した（クリアでリザルトの舞台へ・リスポーンなど）ならやめる
            if (DistanceSquaredXY(Pos, Previous) > JumpAwayCm * JumpAwayCm):
                set Result = "moved_away"
                break
            set Previous = Pos
            Gap := vector3{Left := Target.Left - Pos.Left, Forward := Target.Forward - Pos.Forward}
            GapLength := Gap.Length()
            if (GapLength <= Tolerance):
                set Result = "reached"
                break
            if (GetSimulationElapsedTime() - Start >= Timeout):
                break
            # 近づいたら弱める（行き過ぎない）
            Strength := Clamp(GapLength / 150.0, 0.35, 1.0)
            Walk.SetMoveInput(McpWorldToMoveInput(Walk, Motor, Gap) * Strength)
            Sleep(0.0)
        Result

    # 動きの JSON を再生する
    Play<private>(Call:mcp_call, Agent:agent, Gen:int, Motor:character_motor_component, Motion:[string]value)<suspends>:void =
        Walk:?character_walk_component = if (W := Motor.FindCharacterWalk[]) then option{W} else false
        var Ok:logic = true
        var Reason:string = "done"
        var Done:int = 0
        var Total:int = 0
        if (StepsValue := Motion["steps"], Steps := StepsValue.AsArray[]):
            set Total = Steps.Length
            Start := GetSimulationElapsedTime()
            for (Step : Steps, Ok?):
                if (O := Step.AsObject[]):
                    At := if (TV := O["t"], T := McpValueToFloat[TV]) then T else 0.0
                    loop:
                        if (not IsCurrent[Agent, Gen] or not Motor.IsSimulating[]):
                            set Ok = false
                            set Reason = "replaced"
                            break
                        if (GetSimulationElapsedTime() - Start >= At):
                            break
                        Sleep(0.0)
                    if (Ok?):
                        ApplyStep(Motor, O)
                        set Done += 1
            if (Ok?, EndValue := Motion["end"], End := McpValueToFloat[EndValue]):
                loop:
                    if (not IsCurrent[Agent, Gen] or GetSimulationElapsedTime() - Start >= End):
                        break
                    Sleep(0.0)
        else if (PointsValue := Motion["points"], Points := PointsValue.AsArray[]):
            set Total = Points.Length
            Tolerance := if (X := Motion["tolerance"], F := McpValueToFloat[X]) then Clamp(F, 5.0, 10000.0) else 60.0
            Timeout := if (X := Motion["timeout"], F := McpValueToFloat[X]) then Clamp(F, 0.1, 600.0) else 10.0
            for (Index -> Point : Points, Ok?):
                if (O := Point.AsObject[], Target := McpValueToVector[O["pos"]]):
                    if (TeleportValue := O["teleport"], McpValueToLogic[TeleportValue] = true):
                        Motor.TeleportTo(Target)
                        Motor.SetVelocity(vector3{})
                    else if (WalkComponent := Walk?):
                        if (JumpValue := O["jump"], McpValueToLogic[JumpValue] = true, Jumper := Motor.Entity.GetComponent[character_jump_component]):
                            Jumper.Jump()
                        if (DashValue := O["dash"], McpValueToLogic[DashValue] = true, Dasher := Motor.Entity.GetComponent[character_dash_component]):
                            Dasher.Dash()
                        Result := WalkTo(Agent, Gen, Motor, WalkComponent, Target, Tolerance, Timeout)
                        if (Result <> "reached"):
                            set Ok = false
                            set Reason = "{Result} at point {Index}"
                    else:
                        set Ok = false
                        set Reason = "no character_walk_component"
                    if (Ok?, WaitValue := O["wait"], Wait := McpValueToFloat[WaitValue], Wait > 0.0):
                        if (WalkComponent := Walk?):
                            WalkComponent.SetMoveInput(vector3{})
                        Sleep(Clamp(Wait, 0.0, 600.0))
                    if (Ok?):
                        set Done += 1
                else:
                    set Ok = false
                    set Reason = "bad point {Index}"
        else:
            set Ok = false
            set Reason = "motion needs steps or points"
        if (IsCurrent[Agent, Gen], WalkComponent := Walk?):
            WalkComponent.SetMoveInput(vector3{})
        Pos := Motor.Entity.GetGlobalTransform().Translation
        Call.Notify("play_done", McpObject(array{McpField("ok", McpLogic(Ok)), McpField("reason", McpQuote(Reason)), McpField("done", "{Done}"), McpField("total", "{Total}"), McpField("pos", McpVector(Pos))}))

    # steps の 1 つを当てる（move = 入力、world = 世界の向き（その時の向きで 1 回直す）、jump / dash、teleport = 位置、stop = 入力 0）
    ApplyStep<private>(Motor:character_motor_component, O:[string]value):void =
        if (Walk := Motor.FindCharacterWalk[]):
            if (MoveValue := O["move"], Input := ReadInput[MoveValue]):
                Walk.SetMoveInput(Input)
            else if (WorldValue := O["world"], Dir := McpValueToVector[WorldValue]):
                Walk.SetMoveInput(McpWorldToMoveInput(Walk, Motor, Dir))
            if (StopValue := O["stop"], McpValueToLogic[StopValue] = true):
                Walk.SetMoveInput(vector3{})
        if (TeleportValue := O["teleport"], Pos := McpValueToVector[TeleportValue]):
            Motor.TeleportTo(Pos)
            Motor.SetVelocity(vector3{})
        if (JumpValue := O["jump"], McpValueToLogic[JumpValue] = true, Jumper := Motor.Entity.GetComponent[character_jump_component]):
            Jumper.Jump()
        if (DashValue := O["dash"], McpValueToLogic[DashValue] = true, Dasher := Motor.Entity.GetComponent[character_dash_component]):
            Dasher.Dash()

    # ---- 状態の書き出し・復元（キー "characters"。人ごとの位置・速度・重力の倍率。プレイヤーは番号で当てる） ----

    McpSessionKey<override>()<transacts>:string = "characters"

    McpSessionSave<override>(Context:mcp_session_context):string =
        Items := for (Index -> Player : Context.Players, Motor := Entity.FindCharacterMotorFor[Player]):
            McpObject(array{McpField("player", "{Index}"), McpField("pos", McpVector(Motor.Entity.GetGlobalTransform().Translation)),
                McpField("velocity", McpVector(Motor.GetVelocity())), McpField("gravity_scale", McpNumber(Motor.GetGravityScale()))})
        McpArray(Items)

    McpSessionRestore<override>(Context:mcp_session_context, State:value):string =
        var Restored:int = 0
        var Skipped:int = 0
        if (Items := State.AsArray[]):
            for (Item : Items):
                if (O := Item.AsObject[], Index := McpValueToInt[O["player"]], Pos := McpValueToVector[O["pos"]]):
                    if (Player := Context.FindPlayer[Index], Motor := Entity.FindCharacterMotorFor[Player]):
                        Motor.TeleportTo(Context.ClaimPosition(Pos))
                        Motor.SetVelocity(if (V := McpValueToVector[O["velocity"]]) then V else vector3{})
                        if (G := McpValueToFloat[O["gravity_scale"]]):
                            Motor.SetGravityScale(G)
                        set Restored += 1
                    else:
                        set Skipped += 1
            "ok restored={Restored} skipped={Skipped}"
        else:
            "bad_state"

# 1 フレームでこれより遠くへ移ったら、ゲームが体を移した（テレポート）とみなして、歩かせるのをやめる（cm）
JumpAwayCm<internal>:float = 800.0

# 水平の距離の 2 乗
DistanceSquaredXY<internal>(A:vector3, B:vector3)<transacts>:float =
    DL := A.Left - B.Left
    DF := A.Forward - B.Forward
    DL * DL + DF * DF

# 体の状態の JSON
McpMotorStateJson<public>(Motor:character_motor_component)<transacts>:string =
    States := for (State : array{character_motor_state.Grounded, character_motor_state.Airborne, character_motor_state.Rising, character_motor_state.Falling, character_motor_state.Moving, character_motor_state.Still}, Motor.IsInState[State]):
        McpQuote(MotorStateName(State))
    Dashing := if (Dasher := Motor.Entity.GetComponent[character_dash_component], Dasher.IsDashing[]) then "true" else "false"
    # 左右の入力のしかた（walk が無ければ出さない）。side_style = 今のしかた（バフ込み）、side_style_base = walk の基本
    SideFields:[]string = if (Walk := Motor.FindCharacterWalk[]) then array{McpField("side_style", McpQuote(SideStyleName(Walk.GetSideStyle()))), McpField("side_style_base", McpQuote(SideStyleName(Walk.GetBaseSideStyle())))} else array{}
    # 動く床（ride が無ければ riding は出さない）。ground_velocity = 乗っている床の速度、inherited_velocity = 床から離れたときに受け継いだ水平の速度（着地で 0）
    Riding := if (Ride := Motor.Entity.GetComponent[character_ride_component]) then (if (Ride.FindRidingEntity[]) then "true" else "false") else ""
    RideFields:[]string = if (Riding <> "") then array{McpField("riding", Riding)} else array{}
    McpObject(array{McpField("pos", McpVector(Motor.Entity.GetGlobalTransform().Translation)), McpField("velocity", McpVector(Motor.GetVelocity())),
        McpField("grounded", if (Motor.IsGrounded[]) then "true" else "false"), McpField("states", McpArray(States)), McpField("gravity_scale", McpNumber(Motor.GetGravityScale())),
        McpField("speed_multiplier", McpNumber(Motor.GetSpeedMultiplier())), McpField("jump_multiplier", McpNumber(Motor.GetJumpMultiplier())),
        McpField("extra_air_jumps", "{Motor.GetExtraAirJumps()}"), McpField("dashing", Dashing),
        McpField("ground_velocity", McpVector(Motor.GetGroundVelocity())), McpField("inherited_velocity", McpVector(Motor.GetInheritedVelocity()))} + SideFields + RideFields)

MotorStateJson<internal>(Motor:character_motor_component)<transacts>:string =
    McpMotorStateJson(Motor)

MotorStateName<internal>(State:character_motor_state)<computes>:string =
    case (State):
        character_motor_state.Grounded => "grounded"
        character_motor_state.Airborne => "airborne"
        character_motor_state.Rising => "rising"
        character_motor_state.Falling => "falling"
        character_motor_state.Moving => "moving"
        character_motor_state.Still => "still"

# 左右の入力のしかたの名前（MCP で使う。turn / strafe / tank_turn）
SideStyleName<internal>(Style:character_side_style)<computes>:string =
    case (Style):
        character_side_style.Turn => "turn"
        character_side_style.Strafe => "strafe"
        character_side_style.TankTurn => "tank_turn"

# 名前から左右の入力のしかた（turn / strafe / tank_turn。Turn / Strafe / TankTurn も受ける）。どれでもなければ失敗する
ReadSideStyle<internal>(Name:string)<transacts><decides>:character_side_style =
    Found := for (Style : array{character_side_style.Turn, character_side_style.Strafe, character_side_style.TankTurn}, SideStyleName(Style) = Name or SideStyleTitle(Style) = Name):
        Style
    Found[0]

SideStyleTitle<internal>(Style:character_side_style)<computes>:string =
    case (Style):
        character_side_style.Turn => "Turn"
        character_side_style.Strafe => "Strafe"
        character_side_style.TankTurn => "TankTurn"

# 入力（{"forward","left"} か [forward, left]）。長さは 1 までに縮める
ReadInput<internal>(V:value)<transacts><decides>:vector3 =
    Raw := McpReadInputRaw[V]
    Length := Raw.Length()
    if (Length > 1.0) then Raw / Length else Raw

McpReadInputRaw<internal>(V:value)<transacts><decides>:vector3 =
    if (Items := V.AsArray[]):
        Items.Length = 2
        vector3{Forward := McpValueToFloat[Items[0]], Left := McpValueToFloat[Items[1]]}
    else:
        O := V.AsObject[]
        Forward := if (X := O["forward"]) then McpValueToFloat[X] else 0.0
        Left := if (X := O["left"]) then McpValueToFloat[X] else 0.0
        vector3{Forward := Forward, Left := Left}

# 世界の向き Dir を、walk の今の歩く向き（GetWalkBasis：Space と左右の入力のしかたに合わせた軸）での移動の入力（forward = 前、left = 左。長さ 1）に直す
#   SideView は前の軸が vector3{} なので left だけになる。TankTurn は体の向きが前で、left は「その方向へ回る」入力になる（横にある行き先へは回ってから進む）
#   Motor は前の版との互換のために残している（使わない）
McpWorldToMoveInput<public>(Walk:character_walk_component, Motor:character_motor_component, Dir:vector3)<transacts>:vector3 =
    Horizontal := vector3{Forward := Dir.Forward, Left := Dir.Left}
    Length := Horizontal.Length()
    if (Length < 0.0001):
        return vector3{}
    Unit := Horizontal / Length
    Basis := Walk.GetWalkBasis()
    vector3{Forward := DotProduct(Unit, Basis(0)), Left := DotProduct(Unit, Basis(1))}

# 1 人の動きの記録（record_start で作り、record_stop で JSON にする）
mcp_character_recorder<internal> := class<internal>:
    Motor<internal>:character_motor_component
    IntervalSeconds<internal>:float
    # 記録する数の上限（約 5 分 / 0.1 秒）
    MaxSamples<internal>:int = 3000

    var<private> Samples:[]string = array{}
    var<private> Points:[]string = array{}
    var<private> Actions:[]string = array{}
    var<private> Running:logic = false
    var<private> Generation:int = 0
    var<private> StartSeconds:float = 0.0
    var<private> Subscription:?cancelable = false

    Start<internal>():void =
        set Generation += 1
        set Running = true
        set StartSeconds = GetSimulationElapsedTime()
        set Subscription = option{Motor.ActionEvent.Subscribe(OnAction)}
        spawn{Run(Generation)}

    Stop<internal>():void =
        set Running = false
        set Generation += 1
        if (S := Subscription?):
            S.Cancel()
        set Subscription = false

    GetSampleCount<internal>()<transacts>:int = Samples.Length

    OnAction<internal>(Action:character_action):void =
        if (Running?, Actions.Length < MaxSamples):
            T := GetSimulationElapsedTime() - StartSeconds
            set Actions += array{McpObject(array{McpField("t", McpNumber(T)), McpField("action", McpQuote(ActionName(Action)))})}

    Run<private>(MyGeneration:int)<suspends>:void =
        loop:
            if (not Running? or Generation <> MyGeneration or not Motor.IsSimulating[] or Samples.Length >= MaxSamples):
                break
            T := GetSimulationElapsedTime() - StartSeconds
            Pos := Motor.Entity.GetGlobalTransform().Translation
            set Samples += array{McpObject(array{McpField("t", McpNumber(T)), McpField("pos", McpVector(Pos)), McpField("velocity", McpVector(Motor.GetVelocity())),
                McpField("grounded", if (Motor.IsGrounded[]) then "true" else "false")})}
            set Points += array{McpObject(array{McpField("pos", McpVector(Pos))})}
            Sleep(IntervalSeconds)

    ToJson<internal>()<transacts>:string =
        McpObject(array{McpField("interval", McpNumber(IntervalSeconds)), McpField("samples", McpArray(Samples)), McpField("actions", McpArray(Actions)), McpField("points", McpArray(Points))})

ActionName<internal>(Action:character_action)<computes>:string =
    case (Action):
        character_action.Jumped => "jumped"
        character_action.AirJumped => "air_jumped"
        character_action.Dashed => "dashed"
        character_action.Landed => "landed"
        character_action.LeftGround => "left_ground"
        character_action.StartedMoving => "started_moving"
        character_action.StoppedMoving => "stopped_moving"
        character_action.HitWall => "hit_wall"
