using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Game }
using { ActivationSystem.TooltipKit }

# ラウンドが始まった合図（activated_event の派生なので、起動を待つ部品はこれで動き出す）
# 方向：activate_on_round_component の Targets（空ならその entity）から下へ（SendDown）
# 送り手：activate_on_round_component。受け手：起動を待つ部品（ラウンド番号が要るものはこの型で受ける）。消費しない
round_started_event<public> := class(activated_event):
    # 始まったラウンドの番号（1 から）
    RoundNumber<public>:int

# ラウンドが終わった合図（deactivated_event の派生なので、起動を待つ部品はこれで止まって片付ける）
# 方向・送り手・受け手は round_started_event と同じ
round_ended_event<public> := class(deactivated_event):
    # 終わったラウンドの番号（1 から）
    RoundNumber<public>:int

# 役割：Fortnite のラウンド（fort_round_manager）の開始・終了を受け取る補助（実行時のクラス）。component がフィールドに 1 つ持ち、OnBeginSimulation で Start、OnEndSimulation で Stop を呼ぶ（継承しない）
#   OnStarted はラウンドが始まるたびに動き、ラウンドが終わると止められる（ラウンドのあいだだけ続く処理をそのまま書ける）。もうラウンドの途中なら、Start の中ですぐ動く
#   OnEnded はラウンドが終わるたびに呼ばれる
# 前提・注意：fort_round_manager が無い（シミュレーションの entity から取れない）と Start は false を返し、何も呼ばない
round_watcher<public> := class<unique>:

    var<private> Manager:?fort_round_manager = false
    var<private> Subscriptions:[]cancelable = array{}
    var<private> InRound:logic = false
    # 最後に終わったラウンドの番号（このラウンドが終わったかを、購読の順番に頼らずに判断するため）
    var<private> EndedRound:int = 0

    # Owner のシミュレーションの round manager を購読する。取れなければ false
    Start<public>(Owner:entity, OnStarted:type{_()<suspends>:void}, OnEnded:type{_():void}):logic =
        Stop()
        if (Found := Owner.GetFortRoundManager[]):
            set Manager = option{Found}
            # 引数の関数を Subscribe にそのまま渡すと UEFN では V3502 になるので、メソッドで包んで渡す
            Relay := round_callback_relay{Watcher := Self, Started := OnStarted, Ended := OnEnded}
            set Subscriptions = array:
                Found.SubscribeRoundStarted(Relay.InvokeStarted)
                Found.SubscribeRoundEnded(Relay.InvokeEnded)
            true
        else:
            false

    # 購読をやめる
    Stop<public>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        set Manager = false
        set InRound = false
        set EndedRound = 0

    # ラウンドの途中（始まってから終わるまで）なら成功する。
    #   同じラウンドの始まりを購読しているほかの部品のコールバックが先に呼ばれても成功するよう、round manager の RoundNumber（始まりのコールバックより前に増える）でも判断する
    IsInRound<public>()<decides><transacts>:void =
        if (InRound?):
        else:
            Found := Manager?
            Found.RoundNumber > 0
            Found.RoundNumber > EndedRound

    # 今の（最後に始まった）ラウンドの番号。始まる前は 0、ゲームが終わると 0 に戻る。round manager が無ければ 0
    GetRoundNumber<public>()<transacts>:int =
        if (Found := Manager?) then Found.RoundNumber else 0

    SetInRound<internal>(Value:logic):void =
        set InRound = Value
        if (not Value?, Found := Manager?):
            set EndedRound = Found.RoundNumber

# round_watcher が使う、渡された関数を listenable に渡すための包み
round_callback_relay<internal> := class<internal>:
    Watcher<internal>:round_watcher
    Started<internal>:type{_()<suspends>:void}
    Ended<internal>:type{_():void}

    InvokeStarted<internal>()<suspends>:void =
        Watcher.SetInRound(true)
        Started()

    InvokeEnded<internal>():void =
        Watcher.SetInRound(false)
        Ended()

# 役割：Fortnite のラウンドが始まったら Targets へ起動の合図（round_started_event）、終わったら停止の合図（round_ended_event）を送る。合図で動く部品（カウントダウン・スポナー・画面・メニュー・ボリューム・ロードアウトなど）を、ラウンドのあいだだけ動かし、ラウンドごとにやり直させる
#   FirstRound / LastRound で、送るラウンドを絞れる（0 なら絞らない）。シミュレーションの開始ではなく「ゲーム（ラウンド）の開始」で動かしたいときに使う（その部品の ActiveOnBegin / StartOnBegin はオフにする）
# 置き方：エディターで entity に付ける。Targets が空なら、この entity とその子孫へ送る
# 知らせ：round_started_event / round_ended_event（RoundNumber 付き）、RoundStartedEvent / RoundEndedEvent（ラウンドの番号）
# 外から：IsInRound / GetRoundNumber
# 前提・注意：fort_round_manager が無いと何もしない（出力ログに出る）
activate_on_round_component<public> := class<final_super>(component):

    # 合図を送る entity（その entity と子孫に届く）。空なら、この entity とその子孫へ送る
    @editable:
        ToolTip := RoundTargetsToolTip
        Categories := array{ActivationCategory}
    Targets<public>:[]entity = array{}
    # このラウンド番号から送る（1 から。0 なら最初から）。既定 0
    @editable_number(int):
        ToolTip := RoundFirstToolTip
        Categories := array{ActivationCategory}
        MinValue := option{0}
        MaxValue := option{100}
    FirstRound<public>:int = 0
    # このラウンド番号まで送る（0 なら最後まで）。既定 0
    @editable_number(int):
        ToolTip := RoundLastToolTip
        Categories := array{ActivationCategory}
        MinValue := option{0}
        MaxValue := option{100}
    LastRound<public>:int = 0

    RoundStartedEventInternal<private><final>:event(int) = event(int){}
    RoundEndedEventInternal<private><final>:event(int) = event(int){}

    # 送るラウンドが始まるたびに、ラウンドの番号で届く（Await / Subscribe する。外から Signal はできない）
    RoundStartedEvent<public><final>:listenable(int) = MakeProxyListenable(RoundStartedEventInternal)

    # 送るラウンドが終わるたびに、ラウンドの番号で届く
    RoundEndedEvent<public><final>:listenable(int) = MakeProxyListenable(RoundEndedEventInternal)

    Watcher<private>:round_watcher = round_watcher{}
    var<private> SentRound:int = 0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Started := Watcher.Start(Entity, OnRoundStarted, OnRoundEnded)
        if (not Started?):
            Print("[activate_on_round_component] fort_round_manager が見つかりません（ラウンドの合図を送れません）")

    OnEndSimulation<override>():void =
        Watcher.Stop()
        (super:)OnEndSimulation()

    # ラウンドの途中なら成功する
    IsInRound<public>()<decides><transacts>:void =
        Watcher.IsInRound[]

    # 今の（最後に始まった）ラウンドの番号（始まる前は 0）
    GetRoundNumber<public>()<transacts>:int =
        Watcher.GetRoundNumber()

    OnRoundStarted<private>()<suspends>:void =
        Number := Watcher.GetRoundNumber()
        if (IsTargetRound[Number]):
            set SentRound = Number
            for (Receiver : GetReceivers()):
                Receiver.SendDown(round_started_event{RoundNumber := Number})
            RoundStartedEventInternal.Signal(Number)

    OnRoundEnded<private>():void =
        # 送ったラウンドが終わったときだけ止める（送っていないラウンドの終わりでは何もしない）
        if (SentRound > 0):
            Number := SentRound
            set SentRound = 0
            for (Receiver : GetReceivers()):
                Receiver.SendDown(round_ended_event{RoundNumber := Number})
            RoundEndedEventInternal.Signal(Number)

    IsTargetRound<private>(Number:int)<decides><transacts>:void =
        FirstRound <= 0 or Number >= FirstRound
        LastRound <= 0 or Number <= LastRound

    GetReceivers<private>()<transacts>:[]entity =
        if (Targets.Length > 0) then Targets else array{Entity}
