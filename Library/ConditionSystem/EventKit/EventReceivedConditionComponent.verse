using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { ConditionSystem.TooltipKit }

# event_received_condition_component の EventType の既定。どこからも送られない scene_event なので、EventType を選ぶまで条件を満たさない
no_scene_event<public> := class(scene_event):

# 役割：起動してから（起動の合図 activated_event を受けてから。合図が来なければ開始から）、EventType の scene_event（その派生も）がこの entity に届いたら満たす。起動の合図か Reset で満たさない状態に戻る
#   「カードが出されたら」「敵が倒されたら」など、ゲーム側の知らせで次へ進むときに、条件の派生を書かずに使う
# 置き方：エディターで entity に付け、EventType で型を選ぶ。コードからなら event_received_condition_component{Entity := E, EventType := my_event} で作る
# 親：game_transition_component か condition_all / condition_any の entity の直下
# いつ：この entity に届く scene_event だけを見る（祖先からの SendDown・区画全体への SendScoped・世界全体への SendGlobal・子孫からの SendUp）。ほかの枝で SendUp されたものは届かない
# 知らせ：満たしたとき・戻ったとき condition_changed_event を上へ送る（NotifyChanged）。受けた scene_event は消費しない
# 外から：Reset（満たさない状態に戻す）、FindReceivedEvent（満たしたときに受けた scene_event。中の Agent などを読む）
# ⚠ 未検証：subtype(scene_event) の @editable が UEFN のエディターで型を選べるか（scene_event は interface。subtype(component) は選べることを確かめ済み）と、型の値での絞り込み（EventType[SceneEvent]）が UEFN で動くか（standalone の型チェックと新しい VM の実行では動く）
event_received_condition_component<public> := class<final_super>(condition_component):

    # 待つ scene_event の型（その派生も合う）。既定の no_scene_event のままなら満たさない
    @editable:
        ToolTip := EventTypeToolTip
        Categories := array{EventConditionCategory}
    EventType<public>:subtype(scene_event) = no_scene_event

    var<private> Received:?scene_event = false

    IsSatisfied<override>()<decides><transacts>:void =
        Received?

    OnReceive<override>(SceneEvent:scene_event):logic =
        # 起動の合図で戻してから型を見る（EventType が activated_event なら、起動でそのまま満たす）
        if (activated_event[SceneEvent]):
            Reset()
        if (EventType[SceneEvent], not Received?):
            set Received = option{SceneEvent}
            NotifyChanged()
        false

    OnEndSimulation<override>():void =
        set Received = false
        (super:)OnEndSimulation()

    # 満たさない状態（まだ受けていない）に戻す。満たしていなければ何もしない
    Reset<public>():void =
        if (Received?):
            set Received = false
            NotifyChanged()

    # 満たしたときに受けた scene_event（起動してから最初に受けた合うもの）。まだ受けていなければ失敗する
    FindReceivedEvent<public>()<decides><transacts>:scene_event =
        Received?
