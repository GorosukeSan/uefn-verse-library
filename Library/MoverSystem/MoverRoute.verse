using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# 役割：mover が 1 つの行き先へ向かう道筋。mover_component は、今の位置から Via の点を順に通って行き先へ、一定の速さ（SpeedCmPerSecond）で進む。曲線の道のり（RouteKit の mover_spline_route_component）が返す
mover_leg<public> := struct<computes>:
    # 行き先までに通る途中の点（世界の位置、センチメートル。行き先そのものは含めない）。空なら行き先へまっすぐ
    Via<public>:[]vector3 = array{}
    # true なら、進む向きに entity の向き（ヨー。entity の前 = Forward 軸）を合わせる。傾き（ピッチ・ロール）は変えない
    FaceTravelDirection<public>:logic = false

# 役割：mover_component が向かう行き先を、1 つずつ決める基底（道のり）。派生は NextTarget を書く（回り方の状態を持つなら Reset も、まっすぐでない道筋なら GetLeg も）
# 置き方：直接は置かない（RouteKit の派生を置く）。派生は 1 entity に 1 つまで
# 同じ entity：mover_component
mover_route_component<public> := class<abstract><final_super>(component):

    # 次の行き先を返す。mover_component が、動き出したとき・行き先に着いたとき（ぶつかって諦めたときも）に呼ぶ。Home は mover が動き出したときの位置、Position は今の位置（どちらも世界の位置、センチメートル）。もう行き先が無い（1 回だけの道のりの終わり）なら false を返す（mover は止まって FinishedEvent を出す）
    NextTarget<public>(Home:vector3, Position:vector3):?mover_target

    # 回り方の状態を最初に戻す（次の NextTarget が最初の行き先を返すようにする）。mover_component が Restart したときに呼ぶ。既定は何もしない（状態を持たない道のり）
    Reset<public>():void = {}

    # NextTarget が返した行き先 Target へ向かう道筋（途中の点・向きを合わせるか）。mover_component が NextTarget のすぐあとに 1 回呼ぶ。From は今の位置（世界の位置、センチメートル）。既定はまっすぐ（途中の点なし・向きは変えない）
    GetLeg<public>(From:vector3, Target:mover_target):mover_leg = mover_leg{}
