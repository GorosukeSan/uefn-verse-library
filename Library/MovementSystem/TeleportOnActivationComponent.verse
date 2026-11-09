using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { ActivationSystem }
using { SceneGraphSystem }
using { MovementSystem.TooltipKit }

# 役割：だれが起こしたかの分かる起動の合図（activated_by_agent_event。ボタン・選択メニュー・ボリュームの入り口など）を受けたら、その人のキャラクターをこの entity の位置（＋OffsetCm）へ移す（ワープ・選んだ場所へ行く）
#   移すのはキャラクターの entity の位置（当たり判定は見ない）。だれが起こしたか分からない合図では何もしない
# 置き方：エディターで、行き先の entity に付ける。選択メニューの Targets・インタラクトの Targets などにこの entity を入れる
# 外から：TeleportAgent(Agent) で直接移す
# ⚠ 未検証：キャラクターの entity の位置を書き換えたときに、移動の状態（落下中など）がそのまま続くか
teleport_on_activation_component<public> := class<final_super>(component):

    # この entity の位置からのずらし（cm。キャラクターの原点は体の真ん中なので、床の上なら上に 100 くらい）。既定は上に 100
    @editable:
        ToolTip := TeleportOffsetToolTip
        Categories := array{TeleportCategory}
    OffsetCm<public>:vector3 = vector3{Up := 100.0}

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent], Agent := SceneEvent.FindActivatingAgent[]):
            TeleportAgent(Agent)
        false

    # Agent のキャラクターを、この entity の位置（＋OffsetCm）へ移す。キャラクターがいなければ何もしない
    TeleportAgent<public>(Agent:agent):void =
        if (Character := Agent.GetFortCharacter[], Body := Character.GetEntity[]):
            Target := Entity.GetGlobalTransform().Translation + OffsetCm
            Body.SetGlobalTransform(Body.GetGlobalTransform().WithTranslation(Target))
