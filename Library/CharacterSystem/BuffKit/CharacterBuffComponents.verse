using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 体に変更（バフ・能力の付与）が重なっているあいだ、持ち主（agent）に付くタグの基底。派生で何が変わっているかが分かる
#   付けるのは BuffKit の部品（character_buff_component / character_move_grant_component）。同じ型のタグが 2 つ以上付くこともある（重ねがけ）
character_modified_tag<public> := class<abstract>(player_state_tag):
# 速さの倍率が 1 でない変更が重なっている
character_speed_modified_tag<public> := class(character_modified_tag):
# ジャンプの倍率が 1 でない変更が重なっている
character_jump_modified_tag<public> := class(character_modified_tag):
# 重力の倍率が 1 でない変更が重なっている
character_gravity_modified_tag<public> := class(character_modified_tag):
# 空中ジャンプの回数が増えている
character_air_jumps_added_tag<public> := class(character_modified_tag):
# ダッシュが許されている（dash の RequiresGrant がオンでも出せる）
character_dash_granted_tag<public> := class(character_modified_tag):
# 左右の入力のしかた（walk の SideStyle）が変更で決められている
character_side_style_modified_tag<public> := class(character_modified_tag):

# 役割：起動の合図（activated_event）から停止の合図（deactivated_event）まで、独自キャラクターの体に倍率（速さ・ジャンプ・重力）を重ねる。止まると必ず外す
#   OverrideSideStyle なら、そのあいだ walk の左右の入力のしかたを SideStyle にする（回転・カニ歩き・その場で回る を拾って切り替える）
#   重ねがけ：いくつ置いても（効果を何回拾っても）倍率は掛け合わせ。外すと、その分だけ元に戻る（ほかの部品の分は残る）。左右の入力のしかたは最後に重ねたものが勝ち、全部外れると walk の基本に戻る
#   どの体に効かせるか：(1) この entity か祖先の体（ロードアウトの体の中に置いたとき）、(2) 持ち主（プレイヤーの slot の下。PickupSystem の効果のプレハブ・ロードアウト）の体、(3) だれが起こしたかの分かる起動の合図（activated_by_agent_event）の人の体
# 置き方：エディターで entity に付ける。PickupSystem の効果のプレハブの根（pickup_effect_component と同じ entity）か子、ロードアウトの中、起動の合図が届く場所
# いつ：起動の合図から停止の合図まで。ActiveOnBegin なら開始から
# タグ：重ねているあいだ、体の持ち主に character_speed_modified_tag / character_jump_modified_tag / character_gravity_modified_tag（倍率が 1 でないものだけ）/ character_side_style_modified_tag（OverrideSideStyle のとき）
# 外から：Apply / Remove / IsApplied
# 前提・注意：独自キャラクター（character_motor_component）の体だけ。速さは walk の MaxSpeedCmPerSecond（走るときも）、ジャンプは jump の JumpSpeedCmPerSecond に掛かる。見つからなければ出力ログに出す
character_buff_component<public> := class<final_super>(component):

    # 歩く・走る速さの上限に掛ける倍率。既定 1（変えない）
    @editable_number(float):
        ToolTip := BuffSpeedToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    SpeedMultiplier<public>:float = 1.0
    # 跳ぶ瞬間の上向きの速さに掛ける倍率（高さはおよそ 2 乗で変わる）。既定 1
    @editable_number(float):
        ToolTip := BuffJumpToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    JumpMultiplier<public>:float = 1.0
    # 重力に掛ける倍率（0.5 でふんわり落ちる、0 で落ちない）。既定 1
    @editable_number(float):
        ToolTip := BuffGravityToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0.0}
        MaxValue := option{10.0}
    GravityMultiplier<public>:float = 1.0
    # オンなら、重ねているあいだ walk の左右の入力のしかたを SideStyle にする。既定オフ（変えない）
    @editable:
        ToolTip := BuffOverrideSideStyleToolTip
        Categories := array{CharacterBuffCategory}
    OverrideSideStyle<public>:logic = false
    # OverrideSideStyle のとき、重ねているあいだの左右の入力のしかた（Turn / Strafe / TankTurn）。既定 Strafe
    @editable:
        ToolTip := BuffSideStyleToolTip
        Categories := array{CharacterBuffCategory}
    SideStyle<public>:character_side_style = character_side_style.Strafe
    # オンなら、起動の合図を待たずに開始から重ねる。既定オフ
    @editable:
        ToolTip := BuffActiveOnBeginToolTip
        Categories := array{CharacterBuffCategory}
    ActiveOnBegin<public>:logic = false

    Applier<private>:character_modifier_applier = character_modifier_applier{Label := "character_buff_component"}

    OnSimulate<override>()<suspends>:void =
        if (ActiveOnBegin?):
            # 体（同じプレハブの部品）がそろってから
            Sleep(0.0)
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Remove()
        false

    OnEndSimulation<override>():void =
        Remove()
        (super:)OnEndSimulation()

    # 体に倍率を重ねる（もう重ねていれば何もしない）。Activator は体を探す手がかり（だれが起こしたか。無ければ false）
    Apply<public>(Activator:?agent):void =
        var AddedTags:[]tag = array{}
        if (SpeedMultiplier <> 1.0):
            set AddedTags += array{character_speed_modified_tag{}}
        if (JumpMultiplier <> 1.0):
            set AddedTags += array{character_jump_modified_tag{}}
        if (GravityMultiplier <> 1.0):
            set AddedTags += array{character_gravity_modified_tag{}}
        if (OverrideSideStyle?):
            set AddedTags += array{character_side_style_modified_tag{}}
        Side:?character_side_style = if (OverrideSideStyle?) then option{SideStyle} else false
        Applier.Apply(Entity, Activator, character_modifier{SpeedMultiplier := SpeedMultiplier, JumpMultiplier := JumpMultiplier, GravityMultiplier := GravityMultiplier, SideStyle := Side}, AddedTags)

    # 重ねた倍率を外す（重ねていなければ何もしない）
    Remove<public>():void =
        Applier.Remove()

    # 今重ねていれば成功する
    IsApplied<public>()<decides><transacts>:void =
        Applier.IsApplied[]

# 役割：起動の合図から停止の合図まで、独自キャラクターの体に能力を足す（空中ジャンプの回数を増やす・ダッシュを許す）。止まると必ず外す
#   空中ジャンプ：jump の AirJumps に ExtraAirJumps を足す（空中で拾ったら、増えた分をすぐ使える）。重ねると足し合わせ
#   ダッシュ：GrantDash なら、dash の RequiresGrant がオンの体でもダッシュできる（dash の部品と、その DashAction の入力は体に置いておく）
#   どの体に効かせるかは character_buff_component と同じ
# 置き方：エディターで entity に付ける。PickupSystem の効果のプレハブ、ロードアウトの中、起動の合図が届く場所
# いつ：起動の合図から停止の合図まで。ActiveOnBegin なら開始から
# タグ：足しているあいだ、体の持ち主に character_air_jumps_added_tag（ExtraAirJumps が 0 でないとき）/ character_dash_granted_tag（GrantDash のとき）
# 外から：Apply / Remove / IsApplied
character_move_grant_component<public> := class<final_super>(component):

    # 空中ジャンプの回数に足す数（2 段ジャンプにするなら 1）。既定 1
    @editable_number(int):
        ToolTip := MoveGrantAirJumpsToolTip
        Categories := array{CharacterBuffCategory}
        MinValue := option{0}
        MaxValue := option{10}
    ExtraAirJumps<public>:int = 1
    # オンなら、dash の RequiresGrant がオンの体でもダッシュできるようにする。既定オフ
    @editable:
        ToolTip := MoveGrantDashToolTip
        Categories := array{CharacterBuffCategory}
    GrantDash<public>:logic = false
    # オンなら、起動の合図を待たずに開始から足す。既定オフ
    @editable:
        ToolTip := BuffActiveOnBeginToolTip
        Categories := array{CharacterBuffCategory}
    ActiveOnBegin<public>:logic = false

    Applier<private>:character_modifier_applier = character_modifier_applier{Label := "character_move_grant_component"}

    OnSimulate<override>()<suspends>:void =
        if (ActiveOnBegin?):
            Sleep(0.0)
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(if (Agent := SceneEvent.FindActivatingAgent[]) then option{Agent} else false)
        else if (deactivated_event[SceneEvent]):
            Remove()
        false

    OnEndSimulation<override>():void =
        Remove()
        (super:)OnEndSimulation()

    # 体に能力を足す（もう足していれば何もしない）。Activator は体を探す手がかり
    Apply<public>(Activator:?agent):void =
        var AddedTags:[]tag = array{}
        if (ExtraAirJumps <> 0):
            set AddedTags += array{character_air_jumps_added_tag{}}
        if (GrantDash?):
            set AddedTags += array{character_dash_granted_tag{}}
        Applier.Apply(Entity, Activator, character_modifier{ExtraAirJumps := ExtraAirJumps, GrantsDash := GrantDash}, AddedTags)

    # 足した能力を外す（足していなければ何もしない）
    Remove<public>():void =
        Applier.Remove()

    # 今足していれば成功する
    IsApplied<public>()<decides><transacts>:void =
        Applier.IsApplied[]

# 役割：BuffKit の部品が共通で使う、体を探して変更を重ね・外す手伝い（実行時だけ）。重ねた変更と、持ち主に付けたタグを覚えておき、Remove で自分の分だけ外す
character_modifier_applier<internal> := class<internal>:
    # 出力ログに出す部品の名前
    Label<internal>:string

    var<private> Handle:?cancelable = false
    var<private> Holders:[]player_tag_holder = array{}

    # Context から体を探し（祖先の体 → 持ち主の体 → Activator の体）、Modifier を重ね、体の持ち主に OwnerTags を付ける。もう重ねていれば何もしない
    Apply<internal>(Context:entity, Activator:?agent, Modifier:character_modifier, OwnerTags:[]tag):void =
        if (Handle?):
            return
        if (Motor := FindTargetMotor[Context, Activator]):
            set Handle = option{Motor.AddModifier(Modifier)}
            if (Owner := Motor.FindOwner[]):
                set Holders = for (Tag : OwnerTags):
                    Holder := player_tag_holder{}
                    Holder.Add(Owner, Tag)
                    Holder
        else:
            Print("[{Label}] 効かせる独自キャラクターの体（character_motor_component）が見つかりません（体の中・持ち主のいる場所に置くか、だれが起こしたかの分かる起動の合図で動かしてください）")

    # 重ねた変更と付けたタグを外す
    Remove<internal>():void =
        Handle.CancelIfSet()
        set Handle = false
        for (Holder : Holders):
            Holder.RemoveAll()
        set Holders = array{}

    IsApplied<internal>()<decides><transacts>:void =
        Handle?

    FindTargetMotor<private>(Context:entity, Activator:?agent)<decides><transacts>:character_motor_component =
        if (Above := Context.FindCharacterMotorAbove[]):
            Above
        else if (Owner := Context.FindOwningPlayer[], Motor := Context.FindCharacterMotorFor[Owner]):
            Motor
        else:
            Context.FindCharacterMotorFor[Activator?]
