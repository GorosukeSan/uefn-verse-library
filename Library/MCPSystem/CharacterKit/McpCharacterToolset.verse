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
using { CharacterSystem.CellKit }
using { CharacterSystem.BuffKit }
using { CharacterSystem.SurfaceKit }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Character toolset (destination "character"). Drives a custom character (CharacterSystem's character_motor_component) from MCP
#   Move input (walk's SetMoveInput), walking in a world direction, jump, dash, teleport, velocity, gravity, side-input style (walk's SetSideStyle), playback of motion JSON (a timetable of inputs / a list of points to pass) and recording
#   Players are addressed by index (same as core.players). The body is the character_motor_component that player drives (Entity.FindCharacterMotorFor)
# Placement: best attached to the same entity as the inbox
# Notifications: long-running tools (move with seconds, play) return "accepted" and emit [MCPC] {"event":"move_done" / "play_done",...} when done
# Tags: mcp_controllable_tag and mcp_session_restorable_tag on its own entity (state key "characters": position, velocity and gravity per player). Reports the tag name custom_character_tag
# Requirements, caveats: world directions are converted to input according to walk's current walk basis (GetWalkBasis: Space (View / World / Facing / SideView) and the side-input style; TankTurn uses the body's facing) (move_world, move_to, play's points). CharacterSystem has no step-climbing
mcp_character_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_tag_provider, mcp_session_restorable):

    # Name used when the same toolset is placed more than once (when empty, "character" alone reaches it)
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    # "Motion generation" per player. Incremented by each new move / play / stop; older waits check it and stop
    var<private> Generation:[agent]int = map{}
    # Players being recorded
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
            McpTool("list", "Players driving a custom character. data: [\{player,pos,velocity,grounded\}]", array{})
            McpTool("state", "Body state (position, velocity cm/s, grounded, state, gravity scale, modifier scale, dashing, side-input style side_style / side_style_base, moving floor ground_velocity / inherited_velocity / riding, cling clinging / cling_surface / cling_normal / can_cling, action cells cells / cell_capacity / cell_actions)", array{McpArg("player", "player", "player index")})
            McpTool("move", "Sets the move input (same as walk's SetMoveInput; forward = ahead, left = left; length up to 1). With seconds, resets to 0 after that time (move_done at the end)", array{McpArg("player", "player", "player index"), McpArg("input", "json", "\{forward,left\} or [forward,left]"), McpOptArg("seconds", "float", "hold the input for this many seconds")})
            McpTool("move_world", "Walks in a world direction (cm direction; length ignored). Converted to input every frame according to walk's Space. Stops after seconds (default 1) (move_done)", array{McpArg("player", "player", "player index"), McpArg("dir", "vector3", "direction"), McpOptArg("seconds", "float", "seconds (default 1.0)"), McpOptArg("scale", "float", "input strength 0-1 (default 1)")})
            McpTool("move_to", "Walks to a world position (stops when the horizontal distance is at most tolerance; move_done on arrival. If the game moves the body elsewhere, reason = moved_away)", array{McpArg("player", "player", "player index"), McpArg("pos", "vector3", "destination (cm)"), McpOptArg("tolerance", "float", "distance in cm that counts as arrived (default 60)"), McpOptArg("timeout", "float", "seconds (default 15)")})
            McpTool("stop", "Zeroes the input and stops move / play (brake = true also zeroes horizontal velocity)", array{McpArg("player", "player", "player index"), McpOptArg("brake", "bool", "also zero the horizontal velocity")})
            McpTool("jump", "Jumps (failed if it cannot)", array{McpArg("player", "player", "player index")})
            McpTool("dash", "Dashes (failed if it cannot)", array{McpArg("player", "player", "player index")})
            McpTool("teleport", "Moves the feet to pos (no collision check). With keep_velocity false (default) the velocity is zeroed", array{McpArg("player", "player", "player index"), McpArg("pos", "vector3", "position (cm; the feet)"), McpOptArg("keep_velocity", "bool", "keep the velocity")})
            McpTool("set_velocity", "Sets the velocity (cm/s, world axes)", array{McpArg("player", "player", "player index"), McpArg("velocity", "vector3", "velocity")})
            McpTool("add_velocity", "Adds to the velocity (cm/s)", array{McpArg("player", "player", "player index"), McpArg("delta", "vector3", "velocity to add")})
            McpTool("set_gravity_scale", "Gravity scale (1 = default, 0 = weightless)", array{McpArg("player", "player", "player index"), McpArg("scale", "float", "scale")})
            McpTool("set_side_style", "Changes the side-input style (walk's base; same as SetSideStyle). turn = turn toward the movement direction, strafe = sidestep while facing forward, tank_turn = turn in place, toggle = same as the toggle button. While a buff decides the style, the buff wins. reply gives the current and base styles", array{McpArg("player", "player", "player index"), McpArg("style", "string", "turn / strafe / tank_turn / toggle")})
            McpTool("play", "Plays a motion JSON (play_done at the end). steps: [\{t,move,world,jump,dash,teleport,stop\}] (input at t seconds) / points: [\{pos,jump,dash,wait,teleport\}] (walks through them in order)", array{McpArg("player", "player", "player index"), McpArg("motion", "json", "\{steps:[...]\} or \{points:[...], tolerance, timeout\}")})
            McpTool("record_start", "Starts recording the motion (position, velocity and grounded every interval seconds, plus events such as jumps and dashes)", array{McpArg("player", "player", "player index"), McpOptArg("interval", "float", "seconds (default 0.1)")})
            McpTool("record_stop", "Stops recording and returns it. data: \{interval,samples:[\{t,pos,velocity,grounded\}],actions:[\{t,action\}],points:[\{pos\}]\} (points can be passed to play as is)", array{McpArg("player", "player", "player index")})

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

    # ---- Motion generation per player ----

    NextGeneration<private>(Agent:agent)<transacts>:int =
        Next := (if (G := Generation[Agent]) then G else 0) + 1
        if (set Generation[Agent] = Next) {}
        Next

    IsCurrent<private>(Agent:agent, Gen:int)<transacts><decides>:void =
        Generation[Agent] = Gen

    # ---- Waiting work (spawned) ----

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
            # Stop if the game moved the body elsewhere (respawn, results stage etc.)
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

    # Walks to Target. Returns "reached" / "timeout" / "replaced" (the input is left as is; the caller zeroes it)
    WalkTo<private>(Agent:agent, Gen:int, Motor:character_motor_component, Walk:character_walk_component, Target:vector3, Tolerance:float, Timeout:float)<suspends>:string =
        Start := GetSimulationElapsedTime()
        var Result:string = "timeout"
        var Previous:vector3 = Motor.Entity.GetGlobalTransform().Translation
        loop:
            if (not IsCurrent[Agent, Gen] or not Motor.IsSimulating[]):
                set Result = "replaced"
                break
            Pos := Motor.Entity.GetGlobalTransform().Translation
            # Stop if the game moved the body elsewhere (to the results stage on clear, respawn etc.)
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
            # Ease off when close (do not overshoot)
            Strength := Clamp(GapLength / 150.0, 0.35, 1.0)
            Walk.SetMoveInput(McpWorldToMoveInput(Walk, Motor, Gap) * Strength)
            Sleep(0.0)
        Result

    # Plays a motion JSON
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

    # Applies one step (move = input, world = world direction (converted once with the facing at that time), jump / dash, teleport = position, stop = zero input)
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

    # ---- State snapshot / restore (key "characters": position, velocity and gravity scale per player; players matched by index) ----

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

# Moving farther than this in one frame counts as the game having moved the body (teleport), so walking stops (cm)
JumpAwayCm<internal>:float = 800.0

# Squared horizontal distance
DistanceSquaredXY<internal>(A:vector3, B:vector3)<transacts>:float =
    DL := A.Left - B.Left
    DF := A.Forward - B.Forward
    DL * DL + DF * DF

# Body state as JSON
McpMotorStateJson<public>(Motor:character_motor_component)<transacts>:string =
    States := for (State : array{character_motor_state.Grounded, character_motor_state.Airborne, character_motor_state.Rising, character_motor_state.Falling, character_motor_state.Moving, character_motor_state.Still, character_motor_state.Clinging}, Motor.IsInState[State]):
        McpQuote(MotorStateName(State))
    Dashing := if (Dasher := Motor.Entity.GetComponent[character_dash_component], Dasher.IsDashing[]) then "true" else "false"
    # Side-input style (omitted without walk). side_style = current style (with buffs), side_style_base = walk's base
    SideFields:[]string = if (Walk := Motor.FindCharacterWalk[]) then array{McpField("side_style", McpQuote(SideStyleName(Walk.GetSideStyle()))), McpField("side_style_base", McpQuote(SideStyleName(Walk.GetBaseSideStyle())))} else array{}
    # Moving floor (riding is omitted without ride). ground_velocity = velocity of the floor being stood on, inherited_velocity = horizontal velocity inherited when leaving the floor (0 on landing)
    Riding := if (Ride := Motor.Entity.GetComponent[character_ride_component]) then (if (Ride.FindRidingEntity[]) then "true" else "false") else ""
    RideFields:[]string = if (Riding <> "") then array{McpField("riding", Riding)} else array{}
    # Cling (ClingKit). clinging = whether clinging, cling_surface = wall / ceiling ("" when not clinging), cling_normal = surface normal (the last surface when not clinging), can_cling = whether a modifier that grants cling (GrantsCling) is active
    ClingSurfaceName := if (Surface := Motor.GetClingSurface[]) then ClingSurfaceKey(Surface) else ""
    ClingFields:[]string = array{McpField("clinging", if (Motor.IsClinging[]) then "true" else "false"), McpField("cling_surface", McpQuote(ClingSurfaceName)),
        McpField("cling_normal", McpVector(Motor.GetClingNormal())), McpField("can_cling", if (Motor.CanCling[]) then "true" else "false")}
    # Action cells (CellKit; omitted when absent). cells = remaining, cell_capacity = maximum, cell_actions = available actions
    CellFields:[]string = if (Cells := Motor.Entity.GetComponent[character_action_cell_component]):
        Actions := for (Action : array{character_cell_action.AirJump, character_cell_action.Boost, character_cell_action.WallKick}, Cells.HasAction[Action]):
            McpQuote(CellActionKey(Action))
        array{McpField("cells", "{Cells.GetCells()}"), McpField("cell_capacity", "{Cells.GetCapacity()}"), McpField("cell_actions", McpArray(Actions))}
    else:
        array{}
    McpObject(array{McpField("pos", McpVector(Motor.Entity.GetGlobalTransform().Translation)), McpField("velocity", McpVector(Motor.GetVelocity())),
        McpField("grounded", if (Motor.IsGrounded[]) then "true" else "false"), McpField("states", McpArray(States)), McpField("gravity_scale", McpNumber(Motor.GetGravityScale())),
        McpField("speed_multiplier", McpNumber(Motor.GetSpeedMultiplier())), McpField("jump_multiplier", McpNumber(Motor.GetJumpMultiplier())),
        McpField("extra_air_jumps", "{Motor.GetExtraAirJumps()}"), McpField("dashing", Dashing),
        McpField("ground_velocity", McpVector(Motor.GetGroundVelocity())), McpField("inherited_velocity", McpVector(Motor.GetInheritedVelocity()))} + SideFields + RideFields + ClingFields + CellFields)

# Action cell action name (MCP string)
CellActionKey<internal>(Action:character_cell_action)<computes>:string =
    case (Action):
        character_cell_action.AirJump => "air_jump"
        character_cell_action.Boost => "boost"
        character_cell_action.WallKick => "wall_kick"

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
        character_motor_state.Clinging => "clinging"

# Name of the cling surface (used by MCP: wall / ceiling)
ClingSurfaceKey<internal>(Surface:character_cling_surface)<computes>:string =
    case (Surface):
        character_cling_surface.Wall => "wall"
        character_cling_surface.Ceiling => "ceiling"

# Side-input style name (used by MCP: turn / strafe / tank_turn)
SideStyleName<internal>(Style:character_side_style)<computes>:string =
    case (Style):
        character_side_style.Turn => "turn"
        character_side_style.Strafe => "strafe"
        character_side_style.TankTurn => "tank_turn"

# Side-input style from its name (turn / strafe / tank_turn; Turn / Strafe / TankTurn also accepted). Fails for anything else
ReadSideStyle<internal>(Name:string)<transacts><decides>:character_side_style =
    Found := for (Style : array{character_side_style.Turn, character_side_style.Strafe, character_side_style.TankTurn}, SideStyleName(Style) = Name or SideStyleTitle(Style) = Name):
        Style
    Found[0]

SideStyleTitle<internal>(Style:character_side_style)<computes>:string =
    case (Style):
        character_side_style.Turn => "Turn"
        character_side_style.Strafe => "Strafe"
        character_side_style.TankTurn => "TankTurn"

# Input ({"forward","left"} or [forward, left]). Shortened to length 1 at most
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

# Converts world direction Dir into move input (forward = ahead, left = left; length 1) in walk's current walk basis (GetWalkBasis: axes according to Space and the side-input style)
#   In SideView the forward axis is vector3{}, so only left remains. In TankTurn forward is the body's facing and left means "turn that way" (a destination to the side is reached by turning first, then moving)
#   Motor is kept for compatibility with the previous version (unused)
McpWorldToMoveInput<public>(Walk:character_walk_component, Motor:character_motor_component, Dir:vector3)<transacts>:vector3 =
    Horizontal := vector3{Forward := Dir.Forward, Left := Dir.Left}
    Length := Horizontal.Length()
    if (Length < 0.0001):
        return vector3{}
    Unit := Horizontal / Length
    Basis := Walk.GetWalkBasis()
    vector3{Forward := DotProduct(Unit, Basis(0)), Left := DotProduct(Unit, Basis(1))}

# Motion recording of one player (created by record_start, turned into JSON by record_stop)
mcp_character_recorder<internal> := class<internal>:
    Motor<internal>:character_motor_component
    IntervalSeconds<internal>:float
    # Maximum number of samples (about 5 minutes at 0.1 s)
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
        character_action.WallKicked => "wall_kicked"
        character_action.ClingStart => "cling_start"
        character_action.ClingEnd => "cling_end"
