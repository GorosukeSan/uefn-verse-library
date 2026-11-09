using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { PlayerSystem }

# ジェットパックでチャージしている・飛んでいる（速度を操っている）人（agent）に付くタグ。jetpack_ability_component が付け外しする。
# controlled_movement_tag の派生なので、引力やホバーはこの人の速度を書き換えない
jetpack_boosting_tag<public> := class(controlled_movement_tag):

# 方向：jetpack_ability_component の entity から上へ（SendUp）。同じものを、その人の slot の下へ player_event としても送る（同じ人の HUD などの view が受ける）
# 受け手：ブーストのゲージを出す HUD など。消費しない
# 送る時：ゲージの値が変わったときだけ（使える = 1、チャージ中は 0 から 1、飛んだあと着地するまで 0、剥奪で 0）
jetpack_boost_changed_event<public> := class(scene_event):
    # 送ったジェットパックの能力
    Ability<public>:jetpack_ability_component
    # ゲージが変わった人
    Agent<public>:agent
    # ゲージ（0.0〜1.0）
    Ratio<public>:float
