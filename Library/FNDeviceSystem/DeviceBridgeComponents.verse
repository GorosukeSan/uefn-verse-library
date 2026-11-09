using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Devices }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { FNDeviceSystem.TooltipKit }

# FNDeviceSystem：Fortnite のクリエイティブ デバイス（creative_device）に頼る処理をまとめる System。
# Scene Graph の部品（起動・停止の合図、だれが起こしたか）と、デバイスでしかできないこと（ゲームの終了・職業とチーム・スコア・シネマティック・音など）をつなぐ。
# デバイスはレベルに置いたものを @editable で選ぶ。ほかの System はデバイスに依存しない（デバイスを使うときはこの System の部品を置く）。

# 役割：起動の合図を受けたら、Trigger のトリガー デバイスを鳴らす。停止の合図を受けたら StopTrigger を鳴らす
#   合図がだれが起こしたかの分かるもの（activated_by_agent_event）なら、その人で Trigger(Agent) する（デバイス側で「起こした人」に効く設定がそのまま使える）
#   トリガー デバイスはエディターでほとんどのデバイスの操作につなげられるので、Scene Graph からデバイスを動かす万能の出口になる
# 置き方：エディターで entity に付ける（合図が届く場所。インタラクト・ボリューム・メニューの Targets など）
# 外から：Fire / FireFor（コードから鳴らす）
# 前提・注意：デバイスは 1 つずつ選ぶ（デバイスの配列は MCP で書けないため）。複数のデバイスを使うときは、子の entity にこの部品を 1 つずつ置く
device_trigger_component<public> := class<final_super>(component):

    # 起動の合図で鳴らすトリガー デバイス
    @editable:
        ToolTip := DeviceTriggersToolTip
        Categories := array{FNDeviceCategory}
    Trigger<public>:?trigger_device = false
    # 停止の合図で鳴らすトリガー デバイス
    @editable:
        ToolTip := DeviceStopTriggersToolTip
        Categories := array{FNDeviceCategory}
    StopTrigger<public>:?trigger_device = false

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            if (Agent := SceneEvent.FindActivatingAgent[]):
                FireFor(Agent)
            else:
                Fire()
        else if (deactivated_event[SceneEvent], Device := StopTrigger?):
            Device.Trigger()
        false

    # Trigger をだれでもなく鳴らす
    Fire<public>():void =
        if (Device := Trigger?):
            Device.Trigger()

    # Trigger を Agent が起こしたものとして鳴らす
    FireFor<public>(Agent:agent):void =
        if (Device := Trigger?):
            Device.Trigger(Agent)

# 役割：Trigger のトリガー デバイスが鳴るたびに、Targets の entity へ起動の合図を送る（鳴らした人が分かれば activated_by_agent_event）。デバイス側の出来事（ボタン・タイマー・倒した数など）を、トリガー デバイスを通して Scene Graph の部品につなぐ入口
# 置き方：エディターで entity に付ける。Targets が空なら、この entity とその子孫へ送る
# 知らせ：TriggeredEvent（鳴らした人。分からなければ false）
# 前提・注意：デバイスは 1 つずつ選ぶ（デバイスの配列は MCP で書けないため）。複数のデバイスを使うときは、子の entity にこの部品を 1 つずつ置く
device_event_component<public> := class<final_super>(component):

    # 鳴ったら合図を送るトリガー デバイス
    @editable:
        ToolTip := DeviceEventTriggersToolTip
        Categories := array{FNDeviceCategory}
    Trigger<public>:?trigger_device = false
    # 起動の合図を送る entity。空なら、この entity とその子孫
    @editable:
        ToolTip := DeviceEventTargetsToolTip
        Categories := array{FNDeviceCategory}
    Targets<public>:[]entity = array{}

    TriggeredEventInternal<private><final>:event(?agent) = event(?agent){}

    # Trigger が鳴るたびに、鳴らした人（分からなければ false）で届く（Await / Subscribe する。外から Signal はできない）
    TriggeredEvent<public><final>:listenable(?agent) = MakeProxyListenable(TriggeredEventInternal)

    var<private> Subscriptions:[]cancelable = array{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Device := Trigger?):
            set Subscriptions = array{Device.TriggeredEvent.Subscribe(OnTriggered)}

    OnEndSimulation<override>():void =
        for (Subscription : Subscriptions):
            Subscription.Cancel()
        set Subscriptions = array{}
        (super:)OnEndSimulation()

    OnTriggered<private>(MaybeAgent:?agent):void =
        TriggeredEventInternal.Signal(MaybeAgent)
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            if (Agent := MaybeAgent?):
                Receiver.SendActivatedBy(Agent)
            else:
                Receiver.SendActivated()

# 起動の合図を受けたときに、デバイスへ渡す相手
device_target_agents<public> := enum:
    # 合図を起こした人（activated_by_agent_event の Agent）。分からなければ何もしない
    Activator
    # 持ち主（ロードアウトの中など、slot の下に置いたとき）。いなければ合図を起こした人
    Owner
    # 区画の全員
    Everyone

# 役割：部品が使う、合図からデバイスへ渡す相手を決める補助
GetDeviceTargets<internal>(InEntity:entity, SceneEvent:scene_event, Targets:device_target_agents)<transacts>:[]agent =
    case (Targets):
        device_target_agents.Everyone =>
            if (Manager := InEntity.FindScopedComponent[player_manager_component]):
                Everyone:[]agent = for (Slot : Manager.GetSlots()):
                    Slot.Player
                Everyone
            else:
                array{}
        device_target_agents.Owner =>
            if (Owner := InEntity.FindOwningPlayer[]):
                Owners:[]agent = array{Owner}
                Owners
            else if (Agent := SceneEvent.FindActivatingAgent[]):
                array{Agent}
            else:
                array{}
        device_target_agents.Activator =>
            if (Agent := SceneEvent.FindActivatingAgent[]) then array{Agent} else array{}
