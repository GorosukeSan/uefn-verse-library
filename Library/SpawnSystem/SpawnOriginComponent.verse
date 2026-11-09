using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }

# spawn_origin_component が 1 回の補充ごとに返す基準の点（どれも世界での位置、センチメートル）
spawn_origins<public> := struct:
    # 帯を作って出す基準の点。空なら spawner はその回は何もしない
    SpawnPoints<public>:[]vector3 = array{}
    # 消すかどうかを決める帯の基準の点。空なら SpawnPoints を使う
    DespawnPoints<public>:[]vector3 = array{}
    # ここから近い（spawner の KeepNearCells 以内の）ものは消さない点
    KeepPoints<public>:[]vector3 = array{}

# 役割：spawner が「だれ（どこ）のまわりに」出すかを決める基底。派生は UpdateOrigins だけを書く。spawner は点ごとに帯（上限と下限）を作り、近いものをまとめる
# 置き方：直接は置かない（OriginKit の players_origin_component などの派生を置く）。派生は 1 entity に 1 つまで。置かなければ、spawner は自分の entity の位置を基準にする（決まった 1 点）
# 同じ entity：spawner_component
spawn_origin_component<public> := class<abstract><final_super>(component):

    # 派生が実装する。今の基準の点を返す。spawner が補充のたびに 1 回呼ぶ（派生はここで自分の状態を更新してよい）
    UpdateOrigins<public>()<transacts>:spawn_origins
