using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：spawner_component が「何を出すか」を決める基底。派生は CreateSpawned（entity を作る）だけを書く。
#   1 つ分が使うマス数・置き方（範囲いっぱいに伸ばすか）・高さの選び方は、spawner_component の設定（FootprintX/Y/Z、FitToArea、LevelIntervalCells）で決める
# 置き方：直接は置かない（PrefabKit の prefab_spawn_factory_component や、CheckpointSystem の checkpoint_factory_component などの派生を置く）。派生は 1 entity に 1 つまで
# 同じ entity：spawner_component
spawn_factory_component<public> := class<abstract><final_super>(component):

    # 出す entity を作る（世界にはまだ入れない）。Area は借りた範囲。spawner はこのあと自分の子にして、spawned_component を付け、自分の設定で置く
    CreateSpawned<public>(Area:spawn_area):entity
