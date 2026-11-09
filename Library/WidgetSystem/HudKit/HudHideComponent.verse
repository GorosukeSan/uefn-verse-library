using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/UI }
using { ActivationSystem }
using { PlayerSystem }
using { SceneGraphSystem }
using { WidgetSystem.TooltipKit }

# 役割：起動しているあいだ、Fortnite 標準の HUD の一部（チェックを入れたもの）を、区画の全員について人ごとに隠す。止まると、自分が隠した人の分だけ元に戻す（島全体の設定には触らない）
# 置き方：エディターで entity に付ける
# いつ：ActiveOnBegin なら開始から。起動の合図で隠し、停止の合図で戻す。途中参加の人にも隠す
# 外から：Activate / Deactivate / IsActive
# 前提：区画（または世界）に player_manager_component が 1 つ
hud_hide_component<public> := class<final_super>(component):

    # オンならゲームの開始から隠す。既定オフ
    @editable:
        ToolTip := HudHideActiveOnBeginToolTip
        Categories := array{HudHideCategory}
    ActiveOnBegin<public>:logic = false
    # ミニマップ
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideMinimap<public>:logic = true
    # 建築メニューと素材
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideBuild<public>:logic = true
    # チーム情報・人数・撃破数
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideTeamInfo<public>:logic = true
    # ラウンド・ストームの情報
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideRoundInfo<public>:logic = true
    # 経験値
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideExperience<public>:logic = true
    # 体力とシールド
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideHealth<public>:logic = false
    # 手持ちのアイテム欄
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideInventory<public>:logic = false
    # インタラクトの案内
    @editable:
        ToolTip := HudHideElementToolTip
        Categories := array{HudHideCategory}
    HideInteractionPrompts<public>:logic = false

    var<private> Active:logic = false
    var<private> Hidden:[]player = array{}
    var<private> AddedSubscription:?cancelable = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (ActiveOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (activated_event[SceneEvent]):
            Activate()
        else if (deactivated_event[SceneEvent]):
            Deactivate()
        false

    OnEndSimulation<override>():void =
        Deactivate()
        (super:)OnEndSimulation()

    # 隠し始める（今いる全員と、これから参加する人）。もう隠していれば何もしない
    Activate<public>():void =
        if (Active?):
            return
        set Active = true
        if (OwningPlayer := Entity.FindOwningPlayer[]):
            # 持ち主のいる entity（キャラクターの中など）なら、持ち主の分だけ隠す
            HideFor(OwningPlayer)
        else if (Manager := Entity.FindScopedComponent[player_manager_component]):
            set AddedSubscription = option{Manager.PlayerAddedEvent.Subscribe(HideFor)}
            for (Slot : Manager.GetSlots()):
                HideFor(Slot.Player)

    # 自分が隠した人の分を元に戻す。隠していなければ何もしない
    Deactivate<public>():void =
        if (not Active?):
            return
        set Active = false
        AddedSubscription.CancelIfSet()
        set AddedSubscription = false
        if (Playspace := Entity.GetPlayspaceForEntity[]):
            Controller := Playspace.GetHUDController()
            for (Player : Hidden, Player.IsActive[]):
                Controller.ResetElementsForPlayer(Player, GetElements())
        set Hidden = array{}

    # 隠しているあいだ成功する
    IsActive<public>()<decides><transacts>:void =
        Active?

    HideFor<private>(Player:player):void =
        if (Playspace := Entity.GetPlayspaceForEntity[]):
            Playspace.GetHUDController().HideElementsForPlayer(Player, GetElements())
            set Hidden += array{Player}

    GetElements<private>()<transacts>:[]hud_element_identifier =
        var Elements:[]hud_element_identifier = array{}
        if (HideMinimap?):
            set Elements += array{creative_hud_identifier_minimap{}}
        if (HideBuild?):
            set Elements += array{creative_hud_identifier_build_menu{}, creative_hud_identifier_crafting_resources{}}
        if (HideTeamInfo?):
            set Elements += array{creative_hud_identifier_team_info{}, creative_hud_identifier_player_count{}, creative_hud_identifier_elimination_counter{}}
        if (HideRoundInfo?):
            set Elements += array{creative_hud_identifier_round_info{}, creative_hud_identifier_round_timer{}, creative_hud_identifier_storm_timer{}, creative_hud_identifier_storm_notifications{}}
        if (HideExperience?):
            set Elements += array{creative_hud_identifier_experience_level{}, creative_hud_identifier_experience_ui{}, creative_hud_identifier_experience_supercharged{}}
        if (HideHealth?):
            set Elements += array{creative_hud_identifier_health{}, creative_hud_identifier_health_numbers{}, creative_hud_identifier_shields{}, creative_hud_identifier_shield_numbers{}}
        if (HideInventory?):
            set Elements += array{creative_hud_identifier_player_inventory{}, creative_hud_identifier_equipped_item{}}
        if (HideInteractionPrompts?):
            set Elements += array{creative_hud_identifier_interaction_prompts{}}
        Elements
