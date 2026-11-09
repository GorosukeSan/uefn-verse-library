using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# 役割：mover の行き先 1 つ。Position は世界の位置（センチメートル）。Index は、mover_path_route_component なら地点の番号（並べた順で 0 から。往復でも同じ地点は同じ番号）、ランダムな道のりなら選んだ回数（0 から）
mover_target<public> := struct<computes>:
    # 行き先の世界の位置（センチメートル）
    Position<public>:vector3 = vector3{}
    # 決まった地点の道のりなら地点の番号、ランダムの道のりなら選んだ回数（どちらも 0 から）
    Index<public>:int = 0

# 方向：mover の entity から SendDown（自分と子孫）
# 送り手：mover_component（Mover）。次の行き先を決めて向かい始めたとき
# 受け手：行き先の目印などの見た目。消費しない
mover_target_changed_event<public> := class(scene_event):
    # 送った mover_component
    Mover<public>:mover_component
    # 決めた行き先
    Target<public>:mover_target

# 方向：mover の entity から SendDown（自分と子孫）
# 送り手：mover_component（Mover）。行き先に着いたとき（TargetReachedEvent と同じタイミング）
# 受け手：着いたときの演出など。消費しない
mover_target_reached_event<public> := class(scene_event):
    # 送った mover_component
    Mover<public>:mover_component
    # 着いた行き先
    Target<public>:mover_target

# 方向：mover の entity から SendDown（自分と子孫）
# 送り手：mover_component（Mover）。道のりの終わり（mover_path_mode.Once の最後の地点に着いた・道のりの component が無い）で止まったとき（FinishedEvent と同じタイミング）
# 受け手：止まったときの演出など。消費しない
mover_finished_event<public> := class(scene_event):
    # 止まった mover_component
    Mover<public>:mover_component
