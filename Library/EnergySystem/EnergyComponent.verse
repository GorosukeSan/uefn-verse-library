using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { SceneGraphSystem }
using { EnergySystem.TooltipKit }

# エネルギーの量が変わった知らせ
# 方向：energy_component の entity から上へ（SendUp）。前に知らせた量から変わったときだけ送る（Spend[] で減らしたときは、同じフレームの物理のあと（TickEvents.PostPhysics）に送る）
# 受け手：祖先（アイテムなら持ち主のプレイヤーまで）。消費しない
energy_changed_event<public> := class(scene_event):
    # 送った energy_component（割合は Energy.GetRatio()、最大は Energy.GetMax()）
    Energy<public>:energy_component
    # 変わったあとの量（0〜最大）
    Amount<public>:float
    # 前に知らせた量からの差。増えたらプラス、減ったらマイナス
    Delta<public>:float

# 役割：エネルギーの量を持つ。StartFull なら満タンで、そうでなければ 0 で始まる。量が変わると energy_changed_event を上へ知らせる
# 置き方：エディターで entity に付ける（エネルギーを使う能力・アイテムの entity か、その子）。プレイヤーごとに持たせるなら、実行時にプレイヤー（agent の entity）に付ける（能力は FindEnergyFor で探す）
# 外から：Consume / Restore / SetAmount / Fill / SetMax で量を変える（変わったらすぐ energy_changed_event と ChangedEvent）。足りるときだけ減らすなら if (Energy.Spend[10.0]) と書く（足りなければ失敗して何も変えない。知らせは同じフレームの物理のあと）
#   量は 0〜最大（GetMax）に丸める。MaxEnergy はエディターで決める最初の最大で、SetMax で変えた後の最大は GetMax で読む
# いつ：TickEvents.PostPhysics を購読し、Spend[] で減らした分の知らせを送る（Spend[] を呼ばなかったフレームは何もしない）
# ⚠ 未検証：PrePhysics や OnSimulate の中で Spend[] したとき、その同じフレームの PostPhysics で知らせが届くか（UEFN 実機。遅れても次のフレーム）
energy_component<public> := class<final_super>(component):

    # エディターで決める最初の最大量（既定 100.0）。SetMax で変えたあとの最大は GetMax で読む
    @editable_number(float):
        ToolTip := MaxEnergyToolTip
        Categories := array{EnergyCategory, EnergyAmountCategory}
        MinValue := option{1.0}
        MaxValue := option{10000.0}
    MaxEnergy<public>:float = 100.0
    # true（既定）なら満タンで始める。false なら 0 で始める（チェックポイントや回復で満たしてから使う）
    @editable:
        ToolTip := EnergyStartFullToolTip
        Categories := array{EnergyCategory, EnergyAmountCategory}
    StartFull<public>:logic = true

    # 今の量（0〜最大）。シミュレーション開始前に量を変える関数を呼んでいなければ 0.0
    var<private> CurrentAmount<public>:float = 0.0

    ChangedEventInternal<private><final>:event(float) = event(float){}

    # 量が変わるたびに、変わったあとの量で届く（energy_changed_event と同じタイミング）（Await / Subscribe する。外から Signal はできない）
    ChangedEvent<public><final>:listenable(float) = MakeProxyListenable(ChangedEventInternal)

    var Initialized<private>:logic = false
    var MaxOverride<private>:?float = false
    var NotifiedAmount<private>:float = 0.0
    var NotifyPending<private>:logic = false
    var FlushSubscription<private>:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        EnsureInitialized()
        set FlushSubscription = option{TickEvents.PostPhysics.Subscribe(OnPostPhysics)}

    OnEndSimulation<override>():void =
        FlushSubscription.CancelIfSet()
        set FlushSubscription = false
        (super:)OnEndSimulation()

    # 今の最大。SetMax を呼ぶまでは MaxEnergy と同じ
    GetMax<public>()<reads>:float =
        if (Override := MaxOverride?) then Override else MaxEnergy

    # 量が 0 以下なら成功する
    IsEmpty<public>()<decides><reads>:void =
        CurrentAmount <= 0.0

    # 量が最大（GetMax）以上なら成功する
    IsFull<public>()<decides><reads>:void =
        CurrentAmount >= GetMax()

    # 量が Amount 以上あれば成功する（Spend[] が成功するかを、量を変えずに確かめる）。Amount がマイナスなら失敗する
    HasEnough<public>(Amount:float)<decides><reads>:void =
        Amount >= 0.0
        CurrentAmount >= Amount

    # 量 ÷ 最大（0.0〜1.0）。最大が 0 なら 0.0
    GetRatio<public>()<reads>:float =
        CurrentMax := GetMax()
        if (CurrentMax > 0.0):
            CurrentAmount / CurrentMax
        else:
            0.0

    # 量が Amount 以上あれば Amount 減らす。足りない（または Amount がマイナス）なら失敗し、何も変えない。if の条件に書ける（例 if (Energy.Spend[10.0]):）
    # 量（CurrentAmount）はすぐ変わる。知らせる処理（SendUp・Signal）は巻き戻せないので、energy_changed_event と ChangedEvent は同じフレームの物理のあと（TickEvents.PostPhysics）に送る（それより前に Consume などで量を変えたときは、そのときにまとめて送る）
    Spend<public>(Amount:float)<decides><transacts>:void =
        EnsureInitialized()
        HasEnough[Amount]
        set CurrentAmount = CurrentAmount - Amount
        set NotifyPending = true

    # Amount 減らす。足りなくても失敗せず、0 で止まる（ホバー中に毎フレーム減らすときなど）。量が変わったらすぐ energy_changed_event を上へ知らせる
    Consume<public>(Amount:float):void =
        EnsureInitialized()
        SetEnergy(CurrentAmount - Amount)

    # Amount 戻す。最大を超える分は捨てる。量が変わったらすぐ energy_changed_event を上へ知らせる
    Restore<public>(Amount:float):void =
        EnsureInitialized()
        SetEnergy(CurrentAmount + Amount)

    # 量を Value にする（0〜最大に丸める）。量が変わったらすぐ energy_changed_event を上へ知らせる。シミュレーション開始前に呼んだときは、開始時に StartFull で上書きしない
    SetAmount<public>(Value:float):void =
        EnsureInitialized()
        SetEnergy(Value)

    # 満タン（最大）にする。量が変わったらすぐ energy_changed_event を上へ知らせる
    Fill<public>():void =
        EnsureInitialized()
        SetEnergy(GetMax())

    # 最大を NewMax に変える（マイナスは 0 にする）。今の量が新しい最大を超えていれば最大に丸め、energy_changed_event を上へ知らせる
    # 量を変える前（シミュレーション開始前）に呼んだときは知らせず、開始時に新しい最大で始める（StartFull なら満タン）
    SetMax<public>(NewMax:float):void =
        set MaxOverride = option{Max(NewMax, 0.0)}
        if (Initialized?):
            SetEnergy(CurrentAmount)

    # 最初の量を決める（StartFull なら最大、そうでなければ 0）。一度だけ
    EnsureInitialized<private>()<transacts>:void =
        if (not Initialized?):
            set Initialized = true
            set CurrentAmount = if (StartFull?) then GetMax() else 0.0
            set NotifiedAmount = CurrentAmount

    SetEnergy<private>(Value:float):void =
        set CurrentAmount = Clamp(Value, 0.0, GetMax())
        Notify()

    OnPostPhysics<private>(DeltaTime:float):void =
        if (NotifyPending?):
            Notify()

    # 前に知らせた量から変わっていれば、energy_changed_event を上へ送り、ChangedEvent に届ける
    Notify<private>():void =
        set NotifyPending = false
        if (CurrentAmount <> NotifiedAmount):
            Delta := CurrentAmount - NotifiedAmount
            set NotifiedAmount = CurrentAmount
            Entity.SendUp(energy_changed_event{Energy := Self, Amount := CurrentAmount, Delta := Delta})
            ChangedEventInternal.Signal(CurrentAmount)

# InEntity 自身に付いた energy_component、無ければ子孫で最初に見つかったもの。子孫に複数あると、どれが返るかは決まらない（1 つだけ置く前提）。無ければ失敗する
(InEntity:entity).FindEnergy<public>()<decides><transacts>:energy_component =
    if (Energy := InEntity.GetComponent[energy_component]):
        Energy
    else:
        first (Energy : InEntity.FindDescendantComponents(energy_component)):
            Energy

# 能力（InEntity に付いた ability_component の派生など）が Agent について使うエネルギーを探す。順に：
#   1. InEntity 自身か子孫の energy_component（FindEnergy）。アイテムの entity に置けば、そのアイテムのエネルギー。付与された全員が同じ量を分け合う
#   2. Agent（プレイヤーの entity）自身に付いた energy_component。プレイヤーごとのエネルギー（持ち物の中は探さない）
# どちらも無ければ失敗する（能力はエネルギーを使わずに動く）
(InEntity:entity).FindEnergyFor<public>(Agent:agent)<decides><transacts>:energy_component =
    if (Energy := InEntity.FindEnergy[]):
        Energy
    else:
        Agent.GetComponent[energy_component]

# InEntity 自身か子孫の energy_component（FindEnergy）、無ければ祖先に付いた energy_component（近い順）。どれも無ければ失敗する
# ロードアウト・独自キャラクターの根に energy_component を 1 つ置くと、その中の部品がみな同じエネルギーを使う
(InEntity:entity).FindEnergyAbove<public>()<decides><transacts>:energy_component =
    if (Energy := InEntity.FindEnergy[]):
        Energy
    else:
        var Current:?entity = if (Parent := InEntity.GetParent[]) then option{Parent} else false
        var Found:?energy_component = false
        loop:
            if (Found?):
                break
            if (Candidate := Current?):
                if (Energy := Candidate.GetComponent[energy_component]):
                    set Found = option{Energy}
                set Current = if (Parent := Candidate.GetParent[]) then option{Parent} else false
            else:
                break
        Found?
