using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { ModeSystem.TooltipKit }

# 選ばれているモードが変わった知らせ（決まった・変わった・取り消された）
# 方向：区画全体（SendScoped。区画が無ければ世界全体）
# 送り手：mode_select_component。受け手：mode_selected_condition_component・モードを出す画面など。消費しない
mode_changed_event<public> := class(scene_event):
    # 送った mode_select_component
    Selector<public>:mode_select_component
    # 新しく選ばれたモード。取り消されたときは false
    Mode<public>:?game_mode_component

# 役割：選べるモード（子の game_mode_component）を持ち、受け付けているあいだに TrySelect で決まったモードを覚える。決まる・変わる・取り消されると mode_changed_event を区画全体へ送る。受け付けをやめると選びは消える
# 置き方：エディターで entity に付ける。区画（または世界）に 1 つ（条件と画面から FindScopedComponent で探される）
# 子：game_mode_component を付けた entity を、直下に 1 つずつ（候補の順番は各モードの Order）
# いつ受け付けるか：起動の合図（activated_event）から停止の合図（deactivated_event）まで。ActiveOnBegin が true ならシミュレーション開始から。コードから Activate / Deactivate を呼んでもよい
# 決め方：AllowReselect が false なら、最初に決まったモードのまま（取り消すまで次の TrySelect は効かない）。true なら、あとの TrySelect で選び直せる。多数決で決めるなら、同じ entity に mode_vote_component を置く（VoteKit）
# 知らせ：mode_changed_event を区画全体へ送り、SelectedEvent に届ける
# 外から：TrySelect / Clear / Activate / Deactivate。IsActive / FindSelected / IsSelected / GetModes で今の状態を問い合わせる
mode_select_component<public> := class<final_super>(component):

    # true ならシミュレーション開始から受け付ける。false なら起動の合図から。既定 false
    @editable:
        ToolTip := ModeActiveOnBeginToolTip
        Categories := array{ModeCategory}
    ActiveOnBegin<public>:logic = false

    # true なら、決まったあとも TrySelect で選び直せる。false なら最初に決まったモードのまま。既定 false
    @editable:
        ToolTip := ModeAllowReselectToolTip
        Categories := array{ModeCategory}
    AllowReselect<public>:logic = false

    # 選ばれているモード。決まっていなければ false
    var<private> Selected<public>:?game_mode_component = false
    var<private> Active:logic = false

    SelectedEventInternal<private><final>:event(?game_mode_component) = event(?game_mode_component){}

    # モードが決まった・変わったとき（option{Mode}）と、選びが消えたとき（false）に届く（Await / Subscribe する。外から Signal はできない）
    SelectedEvent<public><final>:listenable(?game_mode_component) = MakeProxyListenable(SelectedEventInternal)

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        set Active = false
        Clear()
        (super:)OnEndSimulation()

    # 受け付けを始める（TrySelect が効くようになる）。もう受け付けていれば何もしない
    Activate<public>():void =
        set Active = true

    # 受け付けをやめ、選びを消す（決まっていれば mode_changed_event{Mode := false} を送る）
    Deactivate<public>():void =
        set Active = false
        Clear()

    # 受け付けているあいだ（Activate から Deactivate まで）成功する
    IsActive<public>()<decides><transacts>:void =
        Active?

    # 選ばれているモード。決まっていなければ失敗する
    FindSelected<public>()<decides><transacts>:game_mode_component =
        Selected?

    # Mode が選ばれていれば成功する
    IsSelected<public>(Mode:game_mode_component)<decides><transacts>:void =
        Selected? = Mode

    # 選べるモードの一覧。直下の子の game_mode_component を Order の小さい順で返す（孫は見ない。同じ Order どうしの順番は決まらない）
    GetModes<public>()<transacts>:[]game_mode_component =
        SortModesByOrder(Entity.GetChildComponents(game_mode_component))

    # 受け付けているあいだに Mode に決め、mode_changed_event{Mode := option{Mode}} を区画全体へ送る。効いたら true。受け付けていない・もう決まっていて AllowReselect が false・もう Mode に決まっているときは何もせず false
    TrySelect<public>(Mode:game_mode_component):logic =
        if (not Active?):
            return false
        if (Current := Selected?):
            if (Current = Mode or not AllowReselect?):
                return false
        set Selected = option{Mode}
        Entity.SendScoped(mode_changed_event{Selector := Self, Mode := Selected})
        SelectedEventInternal.Signal(Selected)
        true

    # 選びを取り消す（決まっていなければ何もしない）。取り消すと mode_changed_event{Mode := false} を区画全体へ送る。受け付けているあいだなら、そのあと TrySelect でまた決められる
    Clear<public>():void =
        if (Selected?):
            set Selected = false
            Entity.SendScoped(mode_changed_event{Selector := Self, Mode := false})
            SelectedEventInternal.Signal(false)

# Modes を Order の小さい順に並べ替える（同じ Order どうしの順番は保つ）
SortModesByOrder<internal>(Modes:[]game_mode_component)<transacts>:[]game_mode_component =
    var Sorted:[]game_mode_component = array{}
    for (Mode : Modes):
        var Inserted:logic = false
        var Next:[]game_mode_component = array{}
        for (Existing : Sorted):
            if (not Inserted?, Mode.Order < Existing.Order):
                set Next += array{Mode}
                set Inserted = true
            set Next += array{Existing}
        if (not Inserted?):
            set Next += array{Mode}
        set Sorted = Next
    Sorted
