using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ActivationSystem }
using { CharacterSystem }
using { CharacterSystem.TooltipKit }

# 独自キャラクターに起きたことの知らせ
# 方向：character_action_trigger_component の entity から根へ（SendUp）
# 送り手：character_action_trigger_component（Trigger）。受け手：祖先の component。消費しない
character_action_event<public> := class(scene_event):
    # 送った部品
    Trigger<public>:character_action_trigger_component
    # 起きたこと
    Action<public>:character_action

# 役割：独自キャラクターに Action（着地・ジャンプ・ダッシュ・動き始め・壁に当たったなど）が起きるたびに、Targets へ起動の合図（activated_event）を送り、character_action_event を上へ送る
#   反応（音・パーティクル・通知・有効化・アイテム）は、Targets の entity に置いた起動を待つ部品が受け持つ（コードを書かずに組み合わせる）
#   CooldownSeconds のあいだは次を無視する（続けて何度も起きることの重複を防ぐ）
# 置き方：エディターで、独自キャラクターの entity（character_motor_component と同じ entity）か、その子孫に付ける
# 知らせ：character_action_event を上へ、TriggeredEvent に届ける
character_action_trigger_component<public> := class<final_super>(component):

    # 見張ること。既定 Landed
    @editable:
        ToolTip := ActionTriggerActionToolTip
        Categories := array{CharacterEventCategory}
    Action<public>:character_action = character_action.Landed
    # 起動の合図を送る entity（その entity と子孫に届く）。空なら、この entity とその子孫へ送る
    @editable:
        ToolTip := ActionTriggerTargetsToolTip
        Categories := array{CharacterEventCategory}
    Targets<public>:[]entity = array{}
    # 次を無視する時間（秒）。0 なら無視しない。既定 0
    @editable_number(float):
        ToolTip := ActionTriggerCooldownToolTip
        Categories := array{CharacterEventCategory}
        MinValue := option{0.0}
        MaxValue := option{60.0}
    CooldownSeconds<public>:float = 0.0

    TriggeredEventInternal<private><final>:event(character_action) = event(character_action){}

    # Action が起きるたびに届く（Await / Subscribe する。外から Signal はできない）
    TriggeredEvent<public><final>:listenable(character_action) = MakeProxyListenable(TriggeredEventInternal)

    var<private> Subscription:?cancelable = false
    var<private> LastSeconds:float = -1000.0

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (Motor := Entity.FindCharacterMotorAbove[]):
            set Subscription = option{Motor.ActionEvent.Subscribe(OnAction)}
        else:
            Print("[character_action_trigger_component] character_motor_component が見つかりません（独自キャラクターの entity か子孫に置いてください）")

    OnEndSimulation<override>():void =
        if (Current := Subscription?):
            Current.Cancel()
        set Subscription = false
        (super:)OnEndSimulation()

    OnAction<private>(Happened:character_action):void =
        if (Happened <> Action):
            return
        Now := GetSimulationElapsedTime()
        if (CooldownSeconds > 0.0 and Now - LastSeconds < CooldownSeconds):
            return
        set LastSeconds = Now
        Entity.SendUp(character_action_event{Trigger := Self, Action := Happened})
        TriggeredEventInternal.Signal(Happened)
        Receivers := if (Targets.Length > 0) then Targets else array{Entity}
        for (Receiver : Receivers):
            if (Motor := Entity.FindCharacterMotorAbove[], Owner := Motor.FindOwner[]):
                Receiver.SendActivatedBy(Owner)
            else:
                Receiver.SendActivated()
