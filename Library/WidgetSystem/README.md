# WidgetSystem

プレイヤーの画面に widget（HUD・メニュー）を 1 人ずつ出す System です。基底 `player_widget_component` の派生が `CreateWidget` で 1 人分の widget を作るだけで、だれに出すか（`Audience`）・重ね順（`ZOrder`）・メニューの重なり（`MenuConflict`）・途中参加・後片付けは基底が受け持ちます。すぐ使える文字・ゲージ・通知の HUD、選択メニュー、標準 HUD を隠す部品もあります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `player_widget_component` の派生 | 起動の合図が届く場所（ゲームの流れなら、ノードの entity かその子孫）。直接は置かない（派生を置く）。1 entity に何個置いてもよい | 起動しているあいだ、`Audience` で決めた人の画面に widget を出す。停止で全員から消す |
| `text_hud_component`（HudKit） | 同上 | 画面の決まった位置に文字を 1 行出す（全員に同じ文字か、人ごとの文字） |
| `gauge_hud_component`（HudKit） | 同上 | 割合（0.0〜1.0）を横棒で出す（全員に同じ値か、人ごとの値） |
| `notification_hud_component`（HudKit） | 同上（既定で開始から全員に出す） | 数秒で消える通知を縦に積んで出す |
| `hud_hide_component`（HudKit） | 起動の合図が届く場所 | 起動しているあいだ、Fortnite 標準の HUD のうちチェックを入れたものを人ごとに隠す。止まると自分が隠した分だけ戻す |
| `card_menu_component`（MenuKit） | 起動の合図が届く場所。子 entity にカードごとの `card_info_component` を置く | 子 entity の `card_info_component` をカードにして Order の順に並べ、押されたカードの entity へ起動の合図を送る。マウスが乗る・フォーカスが来たカードは枠の色が変わり、Virtual Pointer で押したカードは奥へ沈む |
| `card_info_component`（CardKit） | カードで選ばせたい entity（マップの根・モード・品物など） | カードに出す情報（Title・Subtitle・Description・Badge・Thumbnail・AccentColor・Order）を持つ。名前・並び順の持ち主はこの component だけにする。カードの画面のほか、PickupSystem の HudKit（拾った効果の HUD）も効果のプレハブの根のこれを読む（依存は PickupSystem → WidgetSystem の向きだけ） |
| `choice_menu_component`（MenuKit） | 起動の合図が届く場所（インタラクトで開くなら、`interact_trigger_component` の `Targets` に入れる entity） | 見出しの下に項目のボタンを並べ、押された項目を知らせ、`Targets[番号]` へ起動の合図を送る |
| `widget_show_in_group_component`（ShowKit） | widget と同じ entity | プレイヤーの組（PlayerSystem の `player_group_component`）に入っている人にだけ、同じ entity の widget を出す。入ったら出し、出たら消す。「メニューで選んだ人にだけ、そのモード・ジャンルの HUD を出す」 |
| `widget_show_item_holder_component`（ShowKit） | アイテムの entity（`item_component`・`item_holder_component` と同じ entity） | アイテムの持ち手が付いているあいだ、同じ entity の `player_widget_component`（すべて）をその人に出し、外れたら消す |
| `player_widget_view_component` | 実行時に `player_widget_component` がプレイヤーの slot の下に作る（エディターでは置かない） | 1 人の画面に widget を足し、消えるときに外す |

例：ノードにいるあいだ全員に文字を出し、標準 HUD のミニマップなどを隠す
```
ノード（game_node_component）
├ 案内（text_hud_component、Text = "ゴールを目指せ"）
└ HUD を隠す（hud_hide_component）
```
ゲームの流れを使わずに最初から出すなら、`ActiveOnBegin` をオンにします。だれに出すかを場所やアイテムで決めるなら、`Audience = Chosen` にして、同じ entity に `widget_show_item_holder_component`（ShowKit）か `widget_show_in_volume_component`（VolumeSystem の WidgetKit）を置きます。

## 設定（@editable）
- ラウンド（設定なし。オフにできない）— 必ず fort_round_manager を挟む。出すのはラウンドの途中（OnRoundStarted から OnRoundEnded まで）だけで、ラウンドの外では Activate / ShowFor も受け付けない。ActiveOnBegin の画面は OnRoundStarted で出し（ラウンドの途中に置かれたときも購読の直後に呼ばれる）、OnRoundEnded で全員から消す。UEFN の編集中に画面が残らない。round manager が無いとき（テストなど）は開始時に出し、いつでも出せる。`IsOutsideRound[]` で問い合わせられる。
すべての `player_widget_component` の派生にあるもの：
- `Mode : player_widget_mode = player_widget_mode.Hud` — `Hud` は操作を奪わない表示（表示中も移動・カメラの操作はそのまま）。`Menu` は操作を受け取る画面で、表示した瞬間にフォーカスを移す。
- `Audience : player_widget_audience = player_widget_audience.Everyone` — `Everyone` は起動したら区画の全員に出す（途中参加の人にも）。`Chosen` は `ShowFor` で決めた人だけに出す。
- `ZOrder : int = 0` — 画面に重ねる順（0〜100000）。大きいほど手前。目安は HUD 0〜100、メニュー 1000、通知 10000。
- `MenuConflict : player_widget_menu_conflict = player_widget_menu_conflict.CloseOther` — 同じ人にもう別のメニューが出ているとき、前を閉じてこちらを出す（`CloseOther`）か、前を残してこちらを出さない（`KeepOther`）か。`Mode = Menu` のときだけ使う。
- `ActiveOnBegin : logic = false` — オンならゲームの開始から出す（`Chosen` なら `ShowFor` を受け付け始める）。オフなら起動の合図から。
- `ForwardReceivedEvents : logic = false` — オンなら、この entity に届いた知らせ（起動・停止の合図以外の scene_event）を、出している全員の `widget_view.ReceivedEvent` へ渡す。

HudKit / MenuKit：
- `text_hud_component.Text : string = ""` — 最初に出す文字。空なら見えない。
- `text_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.15` — 置く位置（画面の割合 0.0〜1.0。左上が 0, 0。その点を真ん中にして置く）。
- `gauge_hud_component.WidthPx : float = 300.0`（10〜2000）/ `HeightPx : float = 16.0`（2〜500） — 棒の幅と高さ（画面のピクセル）。
- `gauge_hud_component.FillColor : color = NamedColors.White` / `BackColor : color = NamedColors.Black` — 中身と背景の色。
- `gauge_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.9` — 置く位置。
- `gauge_hud_component.InitialRatio : float = 1.0` — 最初の割合（0.0〜1.0）。
- `notification_hud_component.DisplaySeconds : float = 3.0` — 1 つの通知を出しておく秒数（0.5〜60）。
- `notification_hud_component.MaxLines : int = 4` — 同時に出す通知の数（1〜20）。超えたら古いものから消す。
- `notification_hud_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.3` — 置く位置。
- `notification_hud_component` は既定を `ActiveOnBegin = true`、`ZOrder = 10000` にしている。
- `choice_menu_component.Title : string = ""` — 見出し。空なら出さない。
- `choice_menu_component.Options : []string = array{"OK"}` — 並べる項目（上から番号 0, 1, 2 ...）。
- `choice_menu_component.Targets : []entity = array{}` — 項目ごとに起動の合図を送る entity（`Options` と同じ並び。足りない番号は送らない）。
- `choice_menu_component.CloseOnChoice : logic = true` — オンなら、選んだらその人のメニューを閉じる。
- `widget_show_in_group_component.Group : ?entity = false` — 組（`player_group_component` を付けた entity）。空なら、この entity かその祖先の組。どちらも無ければだれにも出さない。
- `choice_menu_component.ShowCloseButton : logic = true` / `CloseText : string = "Close"` — 最後に何も選ばずに閉じるボタンを足すか、その文字。
- `choice_menu_component.PositionXRatio : float = 0.5` / `PositionYRatio : float = 0.5` — 置く位置。
- `choice_menu_component` は既定を `Mode = Menu`、`ZOrder = 1000` にしている。
- `hud_hide_component.ActiveOnBegin : logic = false` — オンならゲームの開始から隠す。オフなら起動の合図から。
- `hud_hide_component` の隠すもの（オンにしたものを隠す）：`HideMinimap = true`（ミニマップ）、`HideBuild = true`（建築メニューと素材）、`HideTeamInfo = true`（チーム情報・人数・撃破数）、`HideRoundInfo = true`（ラウンド・ストームの情報）、`HideExperience = true`（経験値）、`HideHealth = false`（体力とシールド）、`HideInventory = false`（手持ちのアイテム欄）、`HideInteractionPrompts = false`（インタラクトの案内）。

CardKit / MenuKit（カード）：
- `card_info_component.Title / Subtitle / Description / Badge : string`、`Thumbnail : ?texture`（無ければ AccentColor の帯）、`AccentColor : color`、`Order : int`（小さいほど先）。
- `card_menu_component.Title : string`、`Columns : int = 4`、`CloseOnChoice`・`ShowCloseButton`・`CloseText`（choice_menu と同じ）、`PositionXRatio / PositionYRatio`、`PointerFieldOfViewDegrees : float = 90`（Virtual Pointer の押した位置を画面の割合に直すときのカメラの水平の画角）。見た目は `var Style : widget_card_style`（コードで差し替える）。
- `text_hud_component.TextColor : color = 白`、`TextSize : float = 0`（0 は既定の大きさ）、`BackgroundOpacity : float = 0`（0 なら板なし）、`BackgroundColor : color = 黒`。

## イベント
- `widget_choice_event`（scene_event、SendUp）: `Menu : choice_menu_component`、`Agent : agent`、`Index : int`（`Options` の番号。0 から）。`choice_menu_component` で項目が押されたとき、その entity から根へ送る。受け手は祖先の component（条件・ゲームの流れ・利用者の component）。消費しない。
- `hud_text_request_event`（scene_event、SendDown）: `Agent : ?agent`（`false` なら全員。これから出す人も）、`Text : message`。利用者の component が `text_hud_component` の entity へ（またはその祖先から SendDown で）送り、文字を変える。消費しない。
- `hud_notification_request_event`（scene_event、SendDown）: `Agent : ?agent`（`false` なら出している全員）、`Text : message`。利用者の component が `notification_hud_component` の entity へ（またはその祖先から SendDown で）送り、通知を出す。消費しない。
- listenable（外から Signal はできない）
  - `choice_menu_component.ChoiceEvent : listenable(tuple(agent, int))` — だれかが項目を選ぶたびに、（その人, 項目の番号）で届く。
  - `widget_view.HiddenEvent : listenable(tuple())` — その人の画面から消えたときに 1 回届く（`Close`・`HideFor`・`Deactivate`・退出・メニューの入れ替え・停止）。
  - `widget_view.ReceivedEvent : listenable(scene_event)` — `SendToWidgets` / `SendToWidgetFor`（と `ForwardReceivedEvents`）で渡した知らせと、同じ人のほかの view から `SendToPlayer`（PlayerSystem）で送られた `player_event` の中身が届く。
- 送るもの: `choice_menu_component` は項目を選ばれると `Targets[番号]` の entity へ `SendActivatedBy(Agent)`（`activated_by_agent_event`）。
- 受けるもの
  - `player_widget_component`（派生すべて）は `activated_event`（出し始める）/ `deactivated_event`（全員から消す）。`ForwardReceivedEvents` がオンなら、それ以外の知らせを全員の表示へ渡す。
  - `text_hud_component` は `hud_text_request_event`、`notification_hud_component` は `hud_notification_request_event`。
  - `hud_hide_component` は `activated_event`（隠す）/ `deactivated_event`（戻す）。
  - `player_widget_view_component` は `player_view_source_event`（作った component から）と `player_event`（同じ人のほかの view から）を受け、中身を `widget_view.ReceivedEvent` に渡す。

## 持ち主
プレイヤーの slot の下（LoadoutSystem のロードアウトの中、CharacterSystem のキャラクターの中など。`Entity.FindOwningPlayer[]` が成功する場所）に置くと、全員ではなく持ち主に効きます。
- `player_widget_component`（派生すべて）：`Audience = Everyone` は「持ち主だけに出す」になる（ほかの人・途中参加の人には出さない）。`Chosen` なら、これまでどおり `ShowFor` で決めた人に出す。
- `hud_hide_component`：持ち主の分だけ標準 HUD を隠す（区画の全員と途中参加の人は見ない）。

## 公開 API
```verse
player_widget_mode<public> := enum:
    Hud
    Menu

(Mode:player_widget_mode).ToInputMode<public>()<computes>:ui_input_mode     # Hud → None、Menu → All

player_widget_audience<public> := enum:
    Everyone
    Chosen

widget_zorder<public> := type{_X:int where 0 <= _X, _X <= 2147483647}
MakePlayerUISlot<public>(ZOrder:int, InputMode:ui_input_mode)<transacts>:player_ui_slot   # 範囲外の ZOrder は丸める

player_widget_menu_conflict<public> := enum:
    CloseOther
    KeepOther

player_widget_component<public> := class<abstract><final_super>(component):
    Mode<public>:player_widget_mode
    Audience<public>:player_widget_audience
    ZOrder<public>:int
    MenuConflict<public>:player_widget_menu_conflict
    ActiveOnBegin<public>:logic
    ForwardReceivedEvents<public>:logic
    CreateWidget<protected>(View:widget_view):widget        # 派生が実装する。出すたびに 1 回呼ばれる（いちばん外側の widget を返す）
    Activate<public>():void                                 # 出し始める（Everyone は全員、Chosen は ShowFor を受け付け始める）
    Deactivate<public>():void                               # 全員から消す
    ShowFor<public>(Agent:agent):void                       # もう出ていれば何もしない。Chosen で起動していなければ起動してから出す
    HideFor<public>(Agent:agent):void
    IsShownFor<public>(Agent:agent)<decides><transacts>:void
    CanShowTo<public>(Agent:agent)<decides><transacts>:void    # 同じ entity の widget_audience_filter_component がすべて許すなら成功
    IsShown<public>()<decides><transacts>:void              # 起動しているあいだ成功
    FindView<public>(Agent:agent)<decides><transacts>:widget_view
    SendToWidgets<public>(SceneEvent:scene_event):void      # 出している全員の ReceivedEvent へ
    SendToWidgetFor<public>(Agent:agent, SceneEvent:scene_event):void

(InEntity:entity).GetPlayerWidgets<public>()<reads>:[]player_widget_component   # InEntity に付いた派生すべて

widget_view<public> := class<internal>:                     # 1 人分の窓口。利用者は作らない
    Player<public>:player
    Owner<public>:player_widget_component
    HiddenEvent<public><final>:listenable(tuple())
    ReceivedEvent<public><final>:listenable(scene_event)
    IsShown<public>()<decides><transacts>:void
    Close<public>():void                                    # Owner.HideFor(Player) と同じ
    Focus<public>(Target:widget):void
    SetDefaultFocus<public>(Target:widget):void             # CreateWidget の中で呼ぶ。出した次のフレームで Focus する
    AwaitClick<public>(OnClick:listenable(widget_message), ?ButtonId:string = "", ?Label:string = "")<suspends>:logic   # この人が押したら true（PressButton でも）、先に閉じたら false
    AwaitChoice<public>(Buttons:[]text_button_base, ?ButtonIds:[]string = array{})<suspends>:?int            # 押されたボタンの番号（PressButton でも同じ番号）。先に閉じたら false
    AwaitButtonGroupChoice<public>(Groups:[][]button, ?ButtonIds, ?Labels)<suspends>:?int     # 1 つの選択肢が複数の button でできているとき（どれかで選ばれる）
    AwaitButtonChoice<public>(Buttons:[]button, ?ButtonIds:[]string = array{}, ?Labels:[]string = array{})<suspends>:?int   # 中身を自由に入れられる button（カードなど）版。Labels は一覧に出す文字
    GetWaitingButtons<public>():[]widget_button_info        # 今 AwaitClick / AwaitChoice で待っているボタン（ID・番号・文字・有効か）
    PressButton<public>(Key:string):widget_press_result     # コードから押す（ID・ボタンの文字・番号の文字）。本物のクリックと同じく待ちに届く

widget_press_result<public> := enum:                       # Pressed / NotShown / NotWaiting / NoButton / Disabled
widget_button_info<public> := struct:
    Id<public>:string
    Index<public>:int
    Label<public>:string
    Enabled<public>:logic

player_widget_view_component<public> := class<final_super><internal>(component):   # 実行時に作られる
    View<public>:widget_view
    Root<public>:widget
    Slot<public>:player_ui_slot

# 配置と文字の補助（位置は画面の割合 0.0〜1.0、左上が 0, 0）
MakeScreenSlot<public>(Widget:widget, XRatio:float, YRatio:float)<transacts>:canvas_slot
MakeFullScreenSlot<public>(Widget:widget)<transacts>:canvas_slot
MakeScreenCanvas<public>(Widget:widget, XRatio:float, YRatio:float):canvas
MakeStack<public>(Widgets:[]widget, Orientation:orientation, PaddingPx:float):stack_box
widget_text_style<public> := struct { Color, Size（0 なら既定）, Justification }
MakeStyledText<public>(Text:message, Style:widget_text_style):text_block
MakePanel<public>(Widget:widget, BackColor:color, Opacity:float, PaddingPx:float):widget     # 後ろに板を敷く（Opacity 0 ならそのまま）
ToOpacity<public>(Value:float)<transacts>:widget_opacity                                       # 0.0〜1.0 に収める

# CardKit
widget_card<public> := struct { Id, Title, Subtitle, Description, Badge, Image:?texture, AccentColor, Enabled }   # WithSubtitle / WithBadge / WithEnabled で 1 か所だけ変えた写し
widget_card_style<public> := struct { WidthPx, HeightPx, ImageHeightPx, PaddingPx, BorderPx, BorderColor, BorderOpacity, HighlightColor, HighlightBackgroundOpacity, PressDepthPx, PressShadeOpacity, 色・文字の大きさ … }
MakeCardView<public>(Card, Style, ?Skin:?widget_card_skin = false):widget_card_button   # 押せるカード 1 枚（Button・SetHighlighted・SetPressed・ClearPressed・TrackHighlight(View)）
MakeCardButton<public>(Card, Style):button                                              # button だけ（選択・押し込みの表示が要らないとき）
PlayCardChosen<public>(Cards, Chosen, ShineSeconds, ?DimAmount, ?StepsPerSecond)<suspends>   # 選ばれた演出：ほかを暗く、選んだカードに光（擬似ライト）が斜めに走り傾きが追う
PlayCardZoom<public>(Root:canvas, Card, Style, Rect, Seconds, TargetScale, ?Skin, ?StepsPerSecond)<suspends>   # 写しを画面の真ん中へ拡大しながら消す（いちばん手前）
MakeCardContent<public>(Card, Style):widget                                             # 押せない見た目だけ
MakeCardGrid<public>(Buttons:[]widget, Columns:int, GapPx:float):widget
CardGridRect<public>(Index, Count, Columns, GapPx, Style, CenterX, CenterY):widget_screen_rect   # その並びで Index 枚目が占める範囲（画面の割合。1080p・16:9 基準）
widget_card_skin<public> / widget_card_skin_view<public> := interface                  # 地の見た目の差し替え（マテリアルなど。GetWidget・SetHighlight・SetPress・SetTilt・SetLight・SetFade）
MakeScreenSlot(Widget, X, Y, ?ZOrder)                                                    # ZOrder：同じ canvas の中で手前に出す
card_info_component.GetCard(Id)、GetTitle(?Fallback)、SortCards(Infos)

# PointerKit（Virtual Pointer。実験的）
(Player:player).PointerToScreenRatio<public>(ViewportPosition:vector3, FieldOfViewDegrees:float)<decides><transacts>:tuple(float, float)
RunCardPointerPress<public>(View:widget_view, Cards:[]widget_card_button, Rects:[]widget_screen_rect, FieldOfViewDegrees:float)<suspends>:void   # 押したカードを沈める（spawn で呼ぶ）
IntToMessage<public><localizes>(Value:int):message
PercentToMessage<public><localizes>(Value:int):message      # 75 → "75%"
StringToMessage<public><localizes>(Text:string):message

# HudKit
hud_text_request_event<public> := class(scene_event):
    Agent<public>:?agent
    Text<public>:message

text_hud_component<public> := class<final_super>(player_widget_component):
    Text<public>:string
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    SetText<public>(Value:message):void                     # 全員の文字（人ごとの文字は消す）
    SetTextFor<public>(Agent:agent, Value:message):void     # その人だけ（全員の文字より優先）
    ClearTextFor<public>(Agent:agent):void                  # 全員の文字に戻す

gauge_hud_component<public> := class<final_super>(player_widget_component):
    WidthPx<public>:float
    HeightPx<public>:float
    FillColor<public>:color
    BackColor<public>:color
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    InitialRatio<public>:float
    SetRatio<public>(Ratio:float):void                      # 全員（0.0〜1.0 に丸める。人ごとの値は消す）
    SetRatioFor<public>(Agent:agent, Ratio:float):void
    GetRatioFor<public>(Agent:agent)<transacts>:float

hud_notification_request_event<public> := class(scene_event):
    Agent<public>:?agent
    Text<public>:message

notification_hud_component<public> := class<final_super>(player_widget_component):
    DisplaySeconds<public>:float
    MaxLines<public>:int
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    Notify<public>(Agent:agent, Text:message):void          # その人に出していなければ何もしない
    NotifyAll<public>(Text:message):void

hud_hide_component<public> := class<final_super>(component):
    ActiveOnBegin<public>:logic
    HideMinimap<public>:logic
    HideBuild<public>:logic
    HideTeamInfo<public>:logic
    HideRoundInfo<public>:logic
    HideExperience<public>:logic
    HideHealth<public>:logic
    HideInventory<public>:logic
    HideInteractionPrompts<public>:logic
    Activate<public>():void
    Deactivate<public>():void                               # 自分が隠した人の分だけ戻す
    IsActive<public>()<decides><transacts>:void

# MenuKit
widget_choice_event<public> := class(scene_event):
    Menu<public>:choice_menu_component
    Agent<public>:agent
    Index<public>:int

choice_menu_component<public> := class<final_super>(player_widget_component):
    Title<public>:string
    Options<public>:[]string
    Targets<public>:[]entity
    CloseOnChoice<public>:logic
    ShowCloseButton<public>:logic
    CloseText<public>:string
    PositionXRatio<public>:float
    PositionYRatio<public>:float
    ChoiceEvent<public><final>:listenable(tuple(agent, int))
    OpenFor<public>(Agent:agent):void                       # ShowFor と同じ

# だれに出してよいかを絞る基底（同じ entity の widget はすべて、これが許す人にだけ出す。全員に出すときも ShowFor でも）
widget_audience_filter_component<public> := class<abstract><final_super>(component):
    AllowsWidgetFor<public>(Agent:agent)<decides><transacts>:void

# ShowKit
widget_show_in_group_component<public> := class<final_super>(widget_audience_filter_component):
    Group<public>:?entity

widget_show_item_holder_component<public> := class<final_super>(component):
```

## 前提・注意
- 絞り込み（`widget_audience_filter_component` の派生。`widget_show_in_group_component` など）は、ほかの出し方と重ねられる：`Audience = Everyone` なら起動で「組の人全員」に、`Chosen` ならボリューム・アイテムなどが `ShowFor` した人のうち「組の人」にだけ出る。許されない人には `ShowFor` しても出ない。組に入ったときに出し直すのは `Audience = Everyone` で起動しているときだけ（`Chosen` は、組に入ったあとでボリュームなどに入り直すと出る）。
- `player_widget_component` と `hud_hide_component` は、区画（または世界）に `player_manager_component`（PlayerSystem）が 1 つ要る。
- 同じ人には、同じ component から 1 枚しか出さない（`ShowFor` を何度呼んでも 1 枚）。
- `Mode = Menu` は 1 人に同時に 1 枚。ほかのメニューは同じ slot の下の view から探し、`MenuConflict` で前を閉じるか、こちらを出さないかを決める。
- コードからボタンを押す：`View.PressButton(Key)`（`AwaitClick` / `AwaitChoice` で待っているあいだだけ。本物のクリックと同じく、`AwaitChoice` なら同じ番号が返り、`widget_choice_handler` の合図と同じ道を通る）。待っているボタンの一覧は `View.GetWaitingButtons()`。ID は `AwaitClick(?ButtonId := "close")` / `AwaitChoice(Buttons, ?ButtonIds := array{"m01", "m02"})` で付ける（付けなければ番号の文字 "0"・"1" …）。MCP から押すのは MCPSystem の WidgetKit（画面ごとにオプトイン：同じ entity に `mcp_widget_control_component`）。
- `CreateWidget` は出すたびに呼ばれる。ボタンを待つなら `spawn{...}` の中で `View.AwaitClick` / `View.AwaitChoice` を使う（閉じると false が返って終わるので、待ちが残らない）。表示を変える知らせは `View.ReceivedEvent` を購読する。
- `Audience = Everyone` の人を `HideFor` で消したあと、`ShowFor` で戻せる。
- `hud_hide_component` は島全体の設定には触らず、人ごとに隠す（止まると、自分が隠した人の分だけ元に戻す）。途中参加の人にも隠す。
- `gauge_hud_component` は値の出どころを知らない。`energy_component.ChangedEvent`（EnergySystem）などを購読して `SetRatioFor` を呼ぶのは利用者側。
- `widget_show_item_holder_component` を使うときは、同じ entity の widget を `Audience = Chosen` にする。アイテムの entity に届いた知らせを表示に渡すなら、widget 側の `ForwardReceivedEvents` をオンにする。
- `choice_menu_component` では、パッドのときいちばん上のボタン（無ければ閉じるボタン）にフォーカスが移る。
- MCP でレベルを組むとき：文字列の配列（`choice_menu_component.Options`）は、MCP では長さと中身を同時に変えられない。いったん空にしてから入れ直す。Fortnite 標準の `input_action` / `input_mapping` は MCP の `SetComponentProperty` で参照として設定できない（コードの既定値として使うのはよい。別のものはエディターで選ぶ）。

- カード：マウスが乗る・パッドのフォーカスが来ると button の HighlightEvent が届き、`TrackHighlight` が枠の色（`HighlightColor`）と地の濃さを変える。自作の UI はこれをしないと、どれが選ばれているか分からない。
- Virtual Pointer（PointerKit、実験的）：ポインターの位置が届くのは `PointerSelect` を押しているあいだ（BeginDetect → DetectionOngoing → EndDetect）だけ。画面の大きさを取る API が無いので、`DeprojectViewportToWorld` の光線と視点の向きの差から画面の割合に直す（カメラの水平の画角と 16:9 が前提）。押しているあいだは、選ばれている表示より押し込みを優先する。⚠ 未確認：メニューを出しているあいだに PointerSelect が届くか。
- カードの高さは `HeightPx` にそろえる（中身が短くても同じ高さ）。`CardGridRect` で当たりの範囲を計算するため。

## 確かめ方
- テスト：`_Test/WidgetSystemTest/` の `widget_system_test_component`。`player_manager_component` を付けた entity を 1 つと、この component を付けた entity を 1 つ置き、プレイヤー 1 人以上で始める（参加を最大 10 秒待つ。画面表示の component はテストが実行時に作る）。起動の合図で全員に出ること・`SendToWidgets` が `ReceivedEvent` に届くこと・停止で消えて `HiddenEvent` が 1 回届くこと、`Audience = Chosen` の `ShowFor` / `HideFor`（2 回呼んでも 1 枚）と `FindView`、メニューの 1 人 1 枚（`CloseOther`）、HudKit / MenuKit の 4 つが出ることを確かめます。途中で文字・ゲージ・通知・メニューが一瞬出ます。数秒で終わります。結果は出力ログの `[TEST] WidgetSystem`。
- 見本：`_Samples/WidgetSample/`。HUD（`widget_sample_component`。1 秒ごとに `SendToWidgets` で経過時間を更新）、メニュー（`menu_sample_component`。`Mode = Menu`・`Audience = Chosen`、閉じるボタンを `View.AwaitClick` で待つ）、メニューを開く入力（`widget_sample_opener_component`。C / RT で開き、`SendToPlayer` で同じ人の HUD に知らせる）。

## 移行が要るもの（2026-11-08）
- `player_widget_component` は必ずラウンドを挟む（設定なし・オフにできない）：ラウンドの外では画面を出さず、ラウンドの終わり（OnRoundEnded）で閉じる
- `widget_view` にコードからボタンを押す入口を足した（互換あり。変えなくてよい）：`AwaitClick(OnClick, ?ButtonId, ?Label)`、`AwaitChoice(Buttons, ?ButtonIds)`、`GetWaitingButtons()`、`PressButton(Key)`、`widget_press_result`、`widget_button_info`。MCPSystem の WidgetKit が使う（MCP からの押下が本物のクリックと同じく `AwaitClick` / `AwaitChoice` に届く）

## 移行が要るもの（2026-11-09）
- 足したもの（互換あり）：CardKit（`card_info_component`・`widget_card`・`widget_card_style`・`MakeCardView` / `MakeCardButton` / `MakeCardContent` / `MakeCardGrid` / `CardGridRect`・スキンの interface）、MenuKit の `card_menu_component`、PointerKit、`widget_view.AwaitButtonChoice`、`widget_text_style` / `MakeStyledText` / `MakePanel` / `ToOpacity`、`text_hud_component` の文字の色・大きさ・板。
- `widget_wait`（internal）に押せるかを見る `Widgets` を足した。`AwaitChoice` の動きは変わらない。
