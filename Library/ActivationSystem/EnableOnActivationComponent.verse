using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem.TooltipKit }

# 役割：起動の合図（activated_event）で有効に、停止の合図（deactivated_event）で無効にする（Invert なら逆）。切り替えるのは、有効・無効を持つ component（enableable：メッシュ・ライト・インタラクト・パーティクルなど）すべて
#   「ノードに入ったら扉を出す」「ボタンを押したら明かりを点ける」のように、起動の合図を見た目や操作につなぐ
# 置き方：エディターで entity に付ける。合図が届く場所（起動したい部品の entity か、その子孫）に置く
# 同じ entity：切り替えるメッシュなど（Targets が空のとき）
# いつ：ApplyOnBegin なら、開始時に「停止しているとき」の状態にする。そのあとは合図のたび
# 外から：SetEnabled で直接切り替える。IsOn で今の状態（起動の合図を受けた状態か）を読む
# 前提・注意：この component 自身は切り替えない。Targets の entity は子孫まで見ず、その entity に付いた component だけを切り替える
enable_on_activation_component<public> := class<final_super>(component):

    # 有効・無効を切り替える entity。空なら、この entity に付いている component（有効・無効を持つもの）を切り替える。既定 空
    @editable:
        ToolTip := EnableTargetsToolTip
        Categories := array{ActivationCategory}
    Targets<public>:[]entity = array{}

    # true なら逆にする（起動の合図で無効、停止の合図で有効）。既定 false
    @editable:
        ToolTip := EnableInvertToolTip
        Categories := array{ActivationCategory}
    Invert<public>:logic = false

    # true なら、シミュレーション開始で「停止しているとき」の状態にする（起動されるまで隠すなど）。既定 true
    @editable:
        ToolTip := EnableApplyOnBeginToolTip
        Categories := array{ActivationCategory}
    ApplyOnBegin<public>:logic = true

    var<private> On:logic = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ApplyOnBegin?):
            Apply(false)

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Apply(true)
        else if (deactivated_event[SceneEvent]):
            Apply(false)
        false

    # 起動の合図を受けた状態（Active = true）か、停止した状態（false）にする。Invert なら、有効・無効は逆になる
    Apply<public>(Active:logic):void =
        set On = Active
        Enabled := if (Invert?) then (if (Active?) then false else true) else Active
        SetEnabled(Enabled)

    # Targets（空ならこの entity）の component を、Enabled なら有効、そうでなければ無効にする（この component の状態 IsOn は変えない）
    SetEnabled<public>(Enabled:logic):void =
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers, Component : Receiver.GetComponents(), Component <> Self, Target := enableable[Component]):
            if (Enabled?):
                Target.Enable()
            else:
                Target.Disable()

    # 最後に起動の合図を受けた（Apply(true)）なら成功する
    IsOn<public>()<decides><transacts>:void =
        On?
