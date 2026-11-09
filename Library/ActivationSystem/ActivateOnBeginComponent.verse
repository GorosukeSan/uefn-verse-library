using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：シミュレーションが始まったら、この entity とその子孫へ起動の合図（activated_event）を 1 回送る。ゲームの流れ（GameSequenceSystem）を使わずに、起動を待つ部品（カウントダウン・入力・画面など）を最初から動かす
# 置き方：エディターで、起動したい部品の entity（かその祖先）に付ける
# 知らせ：開始の次のフレームで activated_event を下へ送る（同じ木の component がみな OnBeginSimulation を終えてから届くように 1 フレーム待つ）
# 前提・注意：停止の合図は送らない（止めたいときは SendDeactivated か、各部品の Stop / Deactivate を呼ぶ）
activate_on_begin_component<public> := class<final_super>(component):

    OnSimulate<override>()<suspends>:void =
        TickEvents.PrePhysics.Await()
        Entity.SendActivated()
