using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Playspaces }
using { SceneGraphSystem }

# 役割：InEntity がいる playspace の参加で OnAdded、退出で OnRemoved を呼ぶ（listener の interface を実装しなくてよい。メソッドをそのまま渡せる）。返り値を Cancel すると止まる（OnEndSimulation で Cancel する）
# 前提・注意：
#   - すでにいるプレイヤーには、この関数の中で（返る前に）1 人ずつ OnAdded を呼ぶ。呼ぶ側はその時点で受けられる状態にしておく
#   - InEntity の playspace が取れない（シーンに入っていない entity など）と false を返し、何も呼ばない
#   - 世界に 1 つの slot が欲しいだけなら、これを使わずに player_manager_component（PlayerAddedEvent / GetSlots / FindSlot）を使う
(InEntity:entity).SubscribePlayers<public>(OnAdded:type{_(:player):void}, OnRemoved:type{_(:player):void}):?cancelable =
    if (Playspace := InEntity.GetPlayspaceForEntity[]):
        # 引数の関数を Subscribe にそのまま渡すと UEFN では V3502 になるので、メソッドで包んで渡す
        AddedSubscription := Playspace.PlayerAddedEvent().Subscribe(player_callback_relay{Callback := OnAdded}.Invoke)
        RemovedSubscription := Playspace.PlayerRemovedEvent().Subscribe(player_callback_relay{Callback := OnRemoved}.Invoke)
        for (Player : Playspace.GetPlayers()):
            OnAdded(Player)
        option{cancelable_group{Cancelables := array{AddedSubscription, RemovedSubscription}}}
    else:
        false

# 関数を listenable の Subscribe に渡すための包み（引数で受け取った関数をそのまま渡すと UEFN のビルドで V3502 になる）
player_callback_relay<internal> := class<internal>:
    Callback<internal>:type{_(:player):void}

    Invoke<internal>(Player:player):void =
        Callback(Player)
