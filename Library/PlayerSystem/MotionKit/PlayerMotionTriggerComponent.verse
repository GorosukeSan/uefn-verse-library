using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { SceneGraphSystem }
using { PlayerSystem.TooltipKit }

# 役割：キャラクターの一瞬の動き（Motion：ジャンプ・着地・しゃがみ・スプリント・倒された・ダメージなど）が起きるたびに、Targets へ起動の合図（activated_event）を送り、player_motion_event を上へ送る
#   反応（通知・アイテムを配る・付ける物・有効化など）は、Targets の entity に置いた起動を待つ部品が受け持つ（コードを書かずに組み合わせる）
#   CooldownSeconds のあいだは、同じ人の次の動きを無視する（続けて何度も起きる動きの重複を防ぐ）
# 置き方：エディターで entity に付ける。ロードアウトのプレハブ（loadout_component の Prefab）の中に置くと持ち主だけを見る。持ち主のいない場所に置くと区画の全員を見る
# 知らせ：player_motion_event を上へ、MotionEvent に（その人, 動き）
# 前提：持ち主がいないときは、区画（または世界）に player_manager_component が 1 つ
player_motion_trigger_component<public> := class<final_super>(component):

    # 見張る動き。既定 Jumped
    @editable:
        ToolTip := PlayerMotionToolTip
        Categories := array{PlayerMotionCategory}
    Motion<public>:player_motion = player_motion.Jumped
    # 起動の合図を送る entity（その entity と子孫に届く）。空なら、この entity とその子孫へ送る
    @editable:
        ToolTip := PlayerMotionTargetsToolTip
        Categories := array{PlayerMotionCategory}
    Targets<public>:[]entity = array{}
    # 同じ人の次の動きを無視する時間（秒）。0 なら無視しない。既定 0
    @editable_number(float):
        ToolTip := PlayerMotionCooldownToolTip
        Categories := array{PlayerMotionCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.0

    MotionEventInternal<private><final>:event(tuple(agent, player_motion)) = event(tuple(agent, player_motion)){}

    # Motion が起きるたびに、（その人, 動き）で届く（Await / Subscribe する。外から Signal はできない）
    MotionEvent<public><final>:listenable(tuple(agent, player_motion)) = MakeProxyListenable(MotionEventInternal)

    Watchers<private>:player_motion_watcher_set = player_motion_watcher_set{}
    var<private> LastSeconds:[agent]float = map{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        Watchers.Start(Entity, OnMotion, TickEvents.PrePhysics)

    OnEndSimulation<override>():void =
        Watchers.Stop()
        (super:)OnEndSimulation()

    OnMotion<private>(Agent:agent, Happened:player_motion):void =
        if (Happened <> Motion):
            return
        Now := GetSimulationElapsedTime()
        if (CooldownSeconds > 0.0, Previous := LastSeconds[Agent], Now - Previous < CooldownSeconds):
            return
        if (set LastSeconds[Agent] = Now) {}
        Entity.SendUp(player_motion_event{Trigger := Self, Agent := Agent, Motion := Happened})
        MotionEventInternal.Signal((Agent, Happened))
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            Receiver.SendActivatedBy(Agent)
