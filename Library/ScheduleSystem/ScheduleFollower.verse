using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }

# 役割：component が「自分の entity か祖先の schedule_component」を見つけて、状態の変化（と、要るなら毎秒）を受け取るための補助。継承せず、フィールドに 1 つ持つ（ScheduleSystem の Kit・FNDeviceSystem・利用者の component）
# 使い方：OnBeginSimulation で Attach(Entity, OnChanged, OnSecond)、OnEndSimulation で Detach。スケジュールがもう評価されていれば Attach の中で OnChanged が 1 回呼ばれる（実行時に足した Kit も今の状態から始まる）
# 前提：スケジュールは 1 つだけ見る（入れ子なら一番近いもの）。OnSecond を渡すと毎秒呼ばれる（表示にだけ使う）
schedule_follower<public> := class<unique>:

    var<private> Schedule:?schedule_component = false
    var<private> Subscriptions:[]cancelable = array{}

    # 見つけたスケジュール。Attach より前・見つからなかったときは失敗する
    FindSchedule<public>()<decides><transacts>:schedule_component =
        Schedule?

    # Owner の entity、無ければ祖先から schedule_component を探して購読する。見つからなければ何もしない（false を返す）
    Attach<public>(Owner:entity, OnChanged:type{_(:schedule_snapshot):void}, OnSecond:?type{_(:schedule_snapshot):void}):logic =
        Detach()
        # 自身か、一番近い祖先のスケジュール（エンジンの FindAncestorComponents は順が決まっていないので使わない）
        if (Found := Owner.FindNearestAncestorComponent[schedule_component]):
            set Schedule = option{Found}
            # 引数の関数を Subscribe にそのまま渡すと UEFN では V3502 になるので、メソッドで包んで渡す
            set Subscriptions = array{Found.StateChangedEvent.Subscribe(schedule_callback_relay{Callback := OnChanged}.Invoke)}
            if (Second := OnSecond?):
                set Subscriptions += array{Found.SecondEvent.Subscribe(schedule_callback_relay{Callback := Second}.Invoke)}
            if (Snapshot := Found.FindLastSnapshot[]):
                OnChanged(Snapshot)
            true
        else:
            false

    # 購読をやめる
    Detach<public>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Schedule = false

# 関数を listenable の Subscribe に渡すための包み（引数で受け取った関数をそのまま渡すと UEFN のビルドで V3502 になる）
schedule_callback_relay<internal> := class<internal>:
    Callback<internal>:type{_(:schedule_snapshot):void}

    Invoke<internal>(Snapshot:schedule_snapshot):void =
        Callback(Snapshot)
