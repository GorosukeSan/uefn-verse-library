using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# 役割：同じ区画のチェックポイント（checkpoint_component）をまとめて見る実行時のクラス。1 フレームに 1 回、区画の全プレイヤーの位置を 1 人 1 回だけ問い合わせ、登録されたチェックポイントすべてと比べる
#   （チェックポイントごとに全員の位置を問い合わせると、数 × 人数ぶんの問い合わせになるため。比べる計算は数 × 人数のまま）
# 作り方：作らない。checkpoint_component がシミュレーション開始時に、同じ区画で先に始まったチェックポイントが使っているものを探して登録する（無ければ自分で作る）
# いつ：登録されたチェックポイントの 1 つ（Driver）が自分の TickEvents.PrePhysics を購読し、毎フレーム Tick を呼ぶ。Driver が止まったら残りの 1 つに引き継ぎ、1 つも無くなったら止まる
# 前提：区画（game_scope_component。無ければ世界）に player_manager_component が 1 つ。最初に見つけたものを覚えておく（見つかるまでは 1 秒ごとに探す）
# ⚠ 未検証：Driver のチェックポイントの entity を無効（disabled）にしたとき、その TickEvents が止まって全部の確認が止まるか（止まるなら、無効にするチェックポイントは区画から外す）
checkpoint_tracker<internal> := class<internal>:

    LookupIntervalSeconds<private>:float = 1.0

    var Checkpoints<private>:[]checkpoint_component = array{}
    var Driver<private>:?checkpoint_component = false
    var Manager<private>:?player_manager_component = false
    var ManagerSubscription<private>:?cancelable = false
    var NextLookupSeconds<private>:float = 0.0

    # Checkpoint を見る対象に加える（もう入っていれば何もしない）。Driver がいなければ Checkpoint を Driver にする
    Register<internal>(Checkpoint:checkpoint_component):void =
        if (not Checkpoints.Find[Checkpoint]):
            set Checkpoints += array{Checkpoint}
        if (not Driver?):
            SetDriver(option{Checkpoint})

    # Checkpoint を見る対象から外す。Driver だったら残りの最初の 1 つに引き継ぐ。1 つも無くなったら player_manager_component の購読もやめる
    Unregister<internal>(Checkpoint:checkpoint_component):void =
        set Checkpoints = for (Other : Checkpoints, Other <> Checkpoint):
            Other
        if (Current := Driver?, Current = Checkpoint):
            SetDriver(if (Next := Checkpoints[0]) then option{Next} else false)
        if (Checkpoints.Length = 0):
            ManagerSubscription.CancelIfSet()
            set ManagerSubscription = false
            set Manager = false
            set NextLookupSeconds = 0.0

    # 1 フレーム分：チェックポイントの位置を 1 回ずつ読み、プレイヤーごとに位置を 1 回読んで、すべてのチェックポイントと比べる
    Tick<internal>():void =
        MaybeManager := GetManager()
        if (Found := MaybeManager?):
            Targets := Checkpoints
            for (Checkpoint : Targets):
                Checkpoint.PrepareFrame()
            for (Slot : Found.GetSlots()):
                CheckPlayer(Slot.Player, Targets)

    CheckPlayer<private>(Agent:agent, Targets:[]checkpoint_component):void =
        if (FortCharacter := Agent.GetFortCharacter[], Start := FortCharacter.FindGlobalTranslation[]):
            var Position:vector3 = Start
            for (Checkpoint : Targets):
                Moved := Checkpoint.CheckAt(Agent, FortCharacter, Position)
                # 上面へ移したら、残りのチェックポイントは移したあとの位置と比べる（チェックポイントごとに位置を読んでいたときと同じ結果にする）
                if (Moved?, Lifted := FortCharacter.FindGlobalTranslation[]):
                    set Position = Lifted

    SetDriver<private>(NewDriver:?checkpoint_component):void =
        if (Old := Driver?):
            Old.StopDriving()
        set Driver = NewDriver
        if (Next := NewDriver?):
            Next.StartDriving()

    GetManager<private>():?player_manager_component =
        if (Found := Manager?):
            option{Found}
        else:
            Now := GetSimulationElapsedTime()
            if (Now >= NextLookupSeconds, Current := Driver?):
                set NextLookupSeconds = Now + LookupIntervalSeconds
                if (Found := Current.Entity.ResolveScopedComponent(Manager, player_manager_component)?):
                    set Manager = option{Found}
                    set ManagerSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
                    option{Found}
                else:
                    false
            else:
                false

    OnPlayerRemoved<private>(Player:player):void =
        for (Checkpoint : Checkpoints):
            Checkpoint.ForgetAgent(Player)
