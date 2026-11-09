using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# 役割：参加中のプレイヤー 1 人を表す。ぶら下げる機能の view はこの entity の子に作られる
# 置き方：実行時に player_manager_component が作る（エディターでは置かない）
player_slot_component<public> := class<final_super>(component):

    # この slot が表す人
    Player<public>:player
