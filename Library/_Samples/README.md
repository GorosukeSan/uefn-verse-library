# _Samples — Library の「置いてすぐ試す」見本

Library の仕組みを、レベルに置いてすぐ手で触って確かめるための component 置き場。画面や出力ログに日本語で手順を出し、プレイヤーの操作に反応する。公開 API だけで書いているので、使い方の見本も兼ねる。

## _Test との違い
- `_Test` は自動で進む動作確認。期待どおりかを `[PASS]` / `[FAIL]` でログに出し、人は結果を読むだけ。
- `_Samples` は人が操作して見る見本。合否は出さず、「今こうなっている」を画面と `Print` で出す。遊びながら仕組みを知る・自分のコードの土台にするためのもの。
- どちらも配布物に含めるが、利用者のレベルに置くのは確かめるときだけ。

## 使い方
1. レベル（または区画）に `player_manager_component` を付けた entity を 1 つ置く（ほとんどの見本が前提にする）。
2. 見たい見本の component を entity に付ける（置き方は各ファイルの先頭のコメント）。
3. セッションを始める。画面の文字と出力ログ（`[input_sample]` などの頭）を見ながら操作する。

## 見本の一覧

| フォルダ | component | 見せるもの | 置き方 |
|---|---|---|---|
| `InputSampleExperimentalKit/` | `input_sample_component` | 標準の入力アクション／Mapping（`/Fortnite.com/Input` と `/Verse.org/Input` の全部）を `StepSeconds` ごとに 1 つずつ画面に出し、押すと「検知しました」。logic の入力は押した瞬間（`BeginDetectEvent`）、vector3 の入力（Move・PointerSelect・PointerZoom）は `TriggerActivationEvent`。PointerSelect / PointerZoom の番では `TouchMapping` で Virtual Pointer が出る。左の `button_loud` に同じ入力を `TriggeringInputAction` に入れ、フォーカス無しでも Click が起きることを確かめる | 空の entity に付ける。`StartOnBegin` オフなら起動の合図（`activated_event`）で始まる |
| `VirtualPointerSampleExperimentalKit/` | `virtual_pointer_sample_component` | Virtual Pointer：`TouchMapping` + `PointerSelect` → `DeprojectViewportToWorld` で光線 → `FindSweepHits` で当たった場所を Print（LUF cm）。`TeleportOnClick` でそこへ移動、`UseOverheadCamera` で真上の `perspective_camera_component` を `camera_director_component.AddCamera` で足す。`ClickedEvent`（人, 世界座標）をほかの component が購読できる | 空の entity に付ける。カメラは @experimental なので既定はオフ |
| `Platformer2DSampleExperimentalKit/` | `platformer_2d_sample_component` | 横スクロールの 2D の見本（移動・ジャンプ・ゴール）。参加した人ごとに slot の下へ独自キャラクター（CharacterSystem の `character_motor_component`（`AxisLock = Left`）・walk・jump・body_link・カメラ）を作る。左右に動き、ジャンプ（2 段ジャンプ・短く押すと低い）で跳ぶ。ゴールの箱（`GoalOffsetCm` の先、`GoalSizeCm`）に入ると Print してスタートへ戻す。移動の入力 `Character.Move` と正射影のカメラ（CameraExperimentalKit）は @experimental | 床の上の空の entity に付ける（そこがスタート）。前（Forward）に床・足場を並べ、ゴールの先に着地できる場所を作る。区画（または世界）に `player_manager_component` が要る |
| `AbilitySample/` | `ability_sample_component` | 同じ entity の能力（`ability_component` の派生）と付与の component を開始時に一覧し、`GrantedEvent` / `RevokedEvent` を Print。`ToggleAction`（既定 E / RB、`MenuNavigationMapping`）で自分への Grant / Revoke を切り替える | 能力の component（swing / jetpack / hover / gravity_point）を付けた entity に付ける。付与の component は任意 |
| `WidgetSample/` | `widget_sample_component`（Hud）、`menu_sample_component`（Menu・Chosen）、`widget_sample_opener_component` | `player_widget_component` の派生の書き方（`CreateWidget(View)` だけを書く）。HUD は名前・経過時間（1 秒ごとに `SendToWidgets`）・最後に受けた `player_event` を出し、`View.ReceivedEvent` を購読して表示を変える。メニューは `Mode = Menu`・`Audience = Chosen`（開いた人にだけ出る）で、`View.AwaitClick` で `button_loud` を待ち `View.Close` で閉じる。opener は C（RT）で押した人にだけ `ShowFor` し、同じ人の HUD へ `SendToPlayer` で知らせる | HUD の entity に `widget_sample_component` + `activate_on_begin_component`。別の entity に `menu_sample_component`。opener は任意の entity に付け、`MenuEntity` にメニューの entity を入れる |
| `ScopeSample/` | `scope_sample_component` | 区画（`game_scope_component`）：自分がどの区画に属するか、`FindScopedComponent[player_manager_component]` が区画の中・世界・無しのどれになるかを Print。`OtherEntity` から探した結果が同じ manager かも出す | 区画の中と外に置いて比べる |

## 書き方（見本を足すとき）
- `@experimental` の API を使う見本は、フォルダ名の最後を `ExperimentalKit` にする（例 `InputSampleExperimentalKit`）。VerseShare は、このフォルダを「実験的を含む」をオンにしたプロジェクトにだけ配る。使うと島を公開できない。
- 1 見本 1 フォルダ。`_Samples/<名前>Sample/<名前>Sample.verse` に `<名前>_sample_component` を置く（フォルダを本体の System と同じ名前にすると `using` が曖昧になる）。
- 先頭のコメントに `役割` / `置き方` / `試し方` を書く。プレイヤーに見せる文字は日本語。
- 1 人ずつの処理は `player_view_set`（PlayerSystem）か `player_widget_component`（WidgetSystem）を使う（基底を継承しない）。
- 開始の仕方は `@editable StartOnBegin`（既定オン）か、起動の合図（`activated_event`）にそろえる。`player_widget_component` の派生は起動の合図だけなので `activate_on_begin_component` を一緒に置く。
- 止まるとき（`OnEndSimulation`・停止の合図）は、足した Mapping・画面・カメラ・購読を必ず外す。キャラクター操作の Mapping は外さない。
- `<suspends>` の呼び出し（`X.Await()` など）を `if (...)` の条件に書かない（先に束縛する）。変数名に `Log` を使わない。
- 公開 API（`<public>`）だけを使う。内部が要るなら Library 側に公開 API を足す。
