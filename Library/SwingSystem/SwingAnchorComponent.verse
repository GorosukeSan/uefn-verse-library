using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：スイングでつかんだ点の entity に付く目印。つかまれた物が壊れるときに Break を呼ぶと、その点をつかんでいるスイングが途切れる
# 置き方：実行時に swing_runner（swing_ability_component が動かす）が、つかんだ点の entity に付ける（エディターでは置かない）。swing_target_component.Shatter が呼ぶ
swing_anchor_component<public> := class<final_super>(component):

    # Break されたら true（外からは読むだけ）
    var<private> Broken<public>:logic = false

    BrokenEventInternal<private><final>:event() = event(){}

    # Break されたときに届く（Await / Subscribe する。外から Signal はできない）
    BrokenEvent<public><final>:listenable(tuple()) = MakeProxyListenable(BrokenEventInternal)

    # この点をつかんでいるスイングを途切れさせる（Broken を true にし、BrokenEvent を送る）。2 回目以降は何もしない（BrokenEvent は 1 回だけ届く）
    Break<public>():void =
        if (Broken?):
            return
        set Broken = true
        BrokenEventInternal.Signal()
