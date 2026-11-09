using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Game }

# キャラクターに起きた一瞬の動き（player_motion_trigger_component が知らせる）
player_motion<public> := enum:
    # ジャンプした
    Jumped
    # 地面に降りた（空中から地面へ）
    Landed
    # 地面から離れた（ジャンプ・落下・打ち上げ）
    LeftGround
    # しゃがみ始めた
    CrouchStarted
    # しゃがむのをやめた
    CrouchEnded
    # 走り始めた（スプリント）
    SprintStarted
    # 走るのをやめた
    SprintEnded
    # 倒された
    Eliminated
    # ダメージを受けた
    Damaged

# キャラクターの続いている状態（player_state_trigger_component / player_state_condition_component が見る）
player_motion_state<public> := enum:
    # 地面にいる
    OnGround
    # 空中にいる
    InAir
    # 落ちている
    Falling
    # しゃがんでいる
    Crouching
    # 走っている（スプリント）
    Sprinting
    # グライダーで飛んでいる
    Gliding
    # 水の中にいる
    InWater
    # 飛んでいる（飛行の状態）
    Flying
    # ダウンしている（倒れているが脱落していない）
    Down

# 動きのあった知らせ
# 方向：player_motion_trigger_component の entity から根へ（SendUp）
# 送り手：player_motion_trigger_component（Trigger）。受け手：祖先の component（キャラクターの中の部品、利用者の component）。消費しない
player_motion_event<public> := class(scene_event):
    # 送った部品
    Trigger<public>:player_motion_trigger_component
    # 動いた人
    Agent<public>:agent
    # 起きた動き
    Motion<public>:player_motion

# 役割：1 人のキャラクターを見張る実行時のクラス（MotionKit / ConditionKit の部品が使う）。毎フレーム Update を呼ぶと、キャラクターが変わったら（リスポーン）購読し直し、地面との出入りを調べ、動きを Notify に渡す
player_motion_watcher<internal> := class<internal>:
    Agent<internal>:agent
    Notify<internal>:type{_(:agent, :player_motion):void}

    var<private> Character:?fort_character = false
    var<private> Subscriptions:[]cancelable = array{}
    var<private> Sprinting:logic = false
    var<private> WasOnGround:logic = true

    # キャラクターの変化と、地面との出入りを調べる（TickEvents から毎フレーム呼ぶ）
    Update<internal>():void =
        if (C := Agent.GetFortCharacter[]):
            if (not IsWatching[C]):
                Watch(C)
            OnGround := logic{C.IsOnGround[]}
            if (WasOnGround? and not OnGround?):
                Notify(Agent, player_motion.LeftGround)
            else if (not WasOnGround? and OnGround?):
                Notify(Agent, player_motion.Landed)
            set WasOnGround = OnGround
        else if (Character?):
            Unwatch()

    IsWatching<private>(C:fort_character)<decides><transacts>:void =
        Known := Character?
        Known = C

    # Agent の今のキャラクターが State なら成功する。キャラクターがいなければ失敗する
    IsInState<internal>(State:player_motion_state)<decides><transacts>:void =
        C := Agent.GetFortCharacter[]
        case (State):
            player_motion_state.OnGround => C.IsOnGround[]
            player_motion_state.InAir => C.IsInAir[]
            player_motion_state.Falling => C.IsFalling[]
            player_motion_state.Crouching => C.IsCrouching[]
            player_motion_state.Sprinting => Sprinting?
            player_motion_state.Gliding => C.IsGliding[]
            player_motion_state.InWater => C.IsInWater[]
            player_motion_state.Flying => C.IsFlying[]
            player_motion_state.Down => C.IsDownButNotOut[]

    Stop<internal>():void =
        Unwatch()

    Watch<private>(C:fort_character):void =
        Unwatch()
        set Character = option{C}
        set Sprinting = false
        set WasOnGround = logic{C.IsOnGround[]}
        set Subscriptions = array:
            C.JumpedEvent().Subscribe(OnJumped)
            C.CrouchedEvent().Subscribe(OnCrouched)
            C.SprintedEvent().Subscribe(OnSprinted)
            C.EliminatedEvent().Subscribe(OnEliminated)
            C.DamagedEvent().Subscribe(OnDamaged)

    Unwatch<private>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Character = false
        set Sprinting = false

    OnJumped<private>(C:fort_character):void =
        Notify(Agent, player_motion.Jumped)

    OnCrouched<private>(Changed:tuple(fort_character, logic)):void =
        Notify(Agent, if (Changed(1)?) then player_motion.CrouchStarted else player_motion.CrouchEnded)

    OnSprinted<private>(Changed:tuple(fort_character, logic)):void =
        set Sprinting = Changed(1)
        Notify(Agent, if (Changed(1)?) then player_motion.SprintStarted else player_motion.SprintEnded)

    OnEliminated<private>(Result:elimination_result):void =
        Notify(Agent, player_motion.Eliminated)

    OnDamaged<private>(Result:damage_result):void =
        Notify(Agent, player_motion.Damaged)
