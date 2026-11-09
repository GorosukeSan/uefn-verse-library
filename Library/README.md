# Library — UEFN Scene Graph の部品集

Scene Graph（entity / component）で作る、組み合わせて使う部品。対象は UEFN v43.00 以降。

## フォルダとモジュール
- `<名前>System/` … 1 つの仕組み（例 `CountdownSystem`）。直下に中心の component とイベント。
- `<名前>System/<名前>Kit/` … その仕組みの差し替え部品（例 `ConditionKit`）。Kit は `<名前>SystemKits.verse` で `<public>` にする（フォルダのモジュールは既定で internal）。
- `<名前>System/TooltipKit/` … エディターに出す説明（`message`）。
- `<名前>System/README.md` … その System の使い方（概要 / 置き方 / 設定 / イベント / タグ / 公開 API / 前提・注意 / 確かめ方）。
- `_Test/<名前>SystemTest/` … 動作確認テスト（フォルダ名を System と同じにするとモジュール名がぶつかる）（`_Test/README.md`）。
- `<名前>ExperimentalKit/`（System の下でも `_Samples` の下でもよい）… `@experimental` の API を使うコードだけを置くフォルダ。名前が `ExperimentalKit` で終わるフォルダの外のコードは、実験的な API も、このフォルダの中の型も使わない。VerseShare は「実験的を含む」をオンにしたプロジェクトにだけ、このフォルダを配る（オフのプロジェクトでは、あっても無くても触らない）。
- 新しい System は `LibraryModules.verse` に `<名前>System<public> := module {}` を足す。

## System の一覧
| System | すること |
|---|---|
| SceneGraphSystem | 区画（`game_scope_component`）、区画で 1 つを探す・探して覚える（`ResolveScopedComponent` / `AwaitScopedComponent`）・送る、一番近い祖先から探す（`FindNearestAncestorComponent`）、cancelable、map の補助 |
| ActivationSystem | 起動・停止の合図（だれが起こしたかの分かる `activated_by_agent_event` も）、開始で起動、合図で有効・無効 |
| ConditionSystem | 条件の基底、all / any、届いた scene_event で満たす（EventKit の `event_received_condition_component`） |
| PlayerSystem | 参加者の slot、1 人ずつの view、タグ、持ち主（`FindOwningPlayer`）、体（`possessable_component`）、プレイヤーに付ける物、Fortnite キャラクターの動きへの反応（MotionKit）、人数・組の人数の条件（ConditionKit の `player_count_condition_component` / `player_group_count_condition_component`） |
| LoadoutSystem | プレイヤー 1 人分の部品（プレハブ）を人ごとに作って付ける。中の部品は持ち主だけに効く |
| PickupSystem | 拾える物（オーブ）と、拾った人に付く効果（効果のプレハブ＝土台 `pickup_effect_component` ＋起動の合図で動く部品の組み合わせ。寿命・重ねがけ・持ち主）、ステージへの合図（StageKit）、拾ったときの知らせと続いている効果の一覧を持ち主の画面に出す HUD（HudKit。見せ方は効果のプレハブの根の card_info_component） |
| CharacterSystem | 独自キャラクター（自前の物理・カプセルの掃引・input_action の操作）と、動き・反応・条件の部品、触れる面と動く足場に乗る部品（SurfaceKit）、バフ・能力の付与（BuffKit。体に倍率・空中ジャンプ・ダッシュの許可を重ねる `AddModifier`） |
| InputSystem | 入力の補助（`AwaitPlayerInput` など）、入力の部品、準備 OK |
| WidgetSystem | 1 人ずつの画面（HUD・メニュー）、文字・ゲージ・通知・選択メニュー、標準 HUD を隠す |
| VolumeSystem | プレイヤーが範囲に入った・出た、人数の条件、起動の部品 |
| InteractSystem | 押して使う物と、起動・条件をつなぐ |
| GameSequenceSystem / ModeSystem / CountdownSystem / ScheduleSystem | ゲームの流れ、モードの選択、カウントダウン、実時刻のスケジュール |
| AbilitySystem / EnergySystem / ItemSystem | 能力と付与の仕方、エネルギー、アイテム |
| HoverSystem / JetpackSystem / SwingSystem / GravitySystem / MovementSystem | Fortnite キャラクター向けの移動の能力と補助 |
| CheckpointSystem / SpawnSystem / GridSystem / MoverSystem | 足場（乗ったらエネルギーを満たす EnergyKit の `checkpoint_energy_refill_component` も）、自動で出す・消す（帯で出し続ける `spawner_component`・決めた場所に好きな数を出す PrefabKit の `spawn_prefab_component` と関数の `SpawnPrefab`）、グリッドの借用、動く物 |
| MCPSystem | MCP（エディターの外の Python）からライブ編集でセッション中のゲームに命令を送り、返事を受け取る（受け箱・ツールセットの interface・Core。ほかの System 用のツールセットは Kit。UI は画面ごとのオプトイン） |
| FNDeviceSystem | クリエイティブ デバイスに頼る処理（デバイスとの橋渡し、ゲーム終了・職業・スコア・シネマティック・音）。ほかの System はデバイスに依存しない |

## 設計の決まり

### 1. 継承に頼らず、component を付け外しして組み合わせる
- component は基本 `class<final_super>(component)` の具象。設定は `@editable`。
- 「何をするか」と「いつ・だれに・どの場面で」を別の component に分ける。例：能力（`AbilitySystem`）は `ability_component` の派生が中身だけを持ち、付与の仕方は同じ entity に置く `ability_grant_players` / `ability_grant_item` / `ability_grant_condition` で選ぶ。中身の component は付与の仕方を知らない。
- 継承を使ってよいのは「中身を 1 つだけ書かせる」とき（抽象基底 → 具象の 1 段）。抽象 → 抽象 → 具象のような段は作らない。基底に流れを書いて派生にいくつもの穴（protected のフック）を埋めさせる形は避け、イベントの購読や同じ entity の別 component で代える。
- interface を実装させて受け取る（listener）形は使わない。コールバック（関数）か `listenable` を渡す。
- 1 人ずつの処理は、component が `player_view_set`（PlayerSystem）を持ち、slot の下に普通の component の view を作る（基底を継承しない）。
- プレイヤーの slot の下（LoadoutSystem のロードアウトの中など）に置いた部品は「持ち主がいる」。`Entity.FindOwningPlayer[]` が成功する部品は、全員ではなく持ち主だけに効く（能力の付与・widget・付ける物・アイテム・標準 HUD・独自キャラクター）。新しく作る部品もこれにそろえる。

### 2. 公開イベントは Epic の標準 component と同じ形
- 状態の変化は `XxxEventInternal<private><final>:event(t)` ＋ `XxxEvent<public><final>:listenable(t) = MakeProxyListenable(XxxEventInternal)`。外から Signal できない。
- entity の木の中の配送には `scene_event` の派生も送る。名前は、起きたこと = 過去形（`*_reached_event`）、変化 = `*_changed_event`、依頼 = `*_request_event`。項目に送り元（component か entity）を持たせ、人は `Agent:agent` で持つ。型の上に「方向・送り手・受け手・消費するか」を書く。
- 送り元の項目名：送った component を、その役割名（型名から `_component` と System 名の接頭辞を除いた名詞。`player_group_component` → `Group`、`countdown_component` → `Countdown`）で、具体型のまま項目の先頭に置く。能力（`*_ability_component`）から送るものは `Ability`。役割名がほかの項目とぶつかるときは型名から `_component` を除いた全体（`player_ready_component` → `PlayerReady`。`Ready:logic` とぶつかるため）。送り手がいろいろな型になりうるとき（`component` / `entity` 型）だけ `Sender`（entity は component でない送り手のときだけ）。`Source` は使わない。人（`Agent:agent`、いないかもしれないなら `?agent`）は送り元の次。起動・停止の合図の系統、だれからでもよい依頼（`hud_*_request_event`）、作った側の view にだけ届く包み（`player_view_source_event`）は送り元を持たなくてよい。
- 「世界に 1 つ」を探すときは `FindScopedComponent`（区画 `game_scope_component` の中、無ければ世界）。全体へ送るときは `SendScoped`。
- 見つけたものを覚えるときは `set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)`（覚える場所は自分のフィールド。条件の `IsSatisfied` など `<decides>` の判定の中では探さずに `Manager?` を読む。止まるときに `false` に戻す）。見つかるまで待つなら `Entity.AwaitScopedComponent(...)`。自身か祖先の一番近いものは `Entity.FindNearestAncestorComponent[...]`（エンジンの `FindAncestorComponents` は並び順が決まっていない）。
- 起動の合図を送る部品は、だれが起こしたかが分かるなら `SendActivatedBy(Agent)`（`activated_by_agent_event`。`activated_event` の派生なので受け手はそのまま動く）を使う。人が要る受け手（デバイスの橋渡しなど）は `FindActivatingAgent[]` で読む。
- モジュールの `var` の `weak_map`（セッション・プレイヤーごとの記録）は使わない（数に上限がある）。人ごとの記録は component のフィールド（`[agent]t`）に持ち、slot の下の entity から探す。

### 3. プレイヤーの状態はタグで知らせる
- 「その人が今〜している」（ホバー中・スイング中・チェックポイントの上・準備 OK など）を持つ System は、そのあいだプレイヤー（`agent`。v43 では `agent` も entity なのでタグを持てる）に Verse のタグ（`tag` の派生）を付け、終わったら外す。キャラクターの entity ではなく agent に付けるので、スポーン前・倒れているあいだ・リスポーンのあとも消えない（⚠ 未検証：UEFN 実機での agent へのタグ付け。`_Test/PlayerSystemTest` で確かめる）。
- 付け外しは `player_tag_holder`（PlayerSystem/PlayerTags.verse）を通す。`AddTag` が返す `tag_key` を覚えて自分の分だけ `RemoveTag` するので、ほかの部品が付けた同じ型のタグは消さない。止まるとき（`OnEndSimulation`・能力の `defer`）に必ず外す。
- 確かめる側は `Agent.HasPlayerTag[タグの型]`（中は `ContainsTag`）。相手の component を探したり using したりしない。
- タグの型は状態を持つ System に置き、すべて `player_state_tag` の派生にする。動き（速度・位置）を操る状態は `controlled_movement_tag` の派生にし、ほかの力（引力・ホバー）はそれが付いた人に手を出さない。
- 今あるタグ：`pickup_effect_tag`（Pickup。効果を受けているあいだ）、`character_modified_tag` の派生（Character / BuffKit。速さ・ジャンプ・重力・空中ジャンプ・ダッシュ）、`hovering_tag`（Hover）、`swinging_tag`（Swing。controlled_movement。実際に付くのは派生の `swing_anchored_tag`（地面で待つ）/ `swing_pendulum_tag`（振っている）。`HasPlayerTag[swinging_tag]` はどちらでも成功する）、`jetpack_boosting_tag`（Jetpack。controlled_movement）、`on_checkpoint_tag`（Checkpoint）、`player_ready_tag`（Input / ReadyKit）、`in_volume_tag`（Volume）、`custom_character_tag`（Character。独自キャラクターを動かしているあいだ）。

### 4. 実時間の処理
- 1 フレーム待つのは `Sleep(0.0)` が一般的な書き方。前のフレームからの秒数が要るとき・毎フレームのコールバックにしたいときは、component の `TickEvents.PrePhysics.Await()`（戻り値が前のフレームからの秒数）か `TickEvents.PrePhysics.Subscribe`（OnBeginSimulation で購読、OnEndSimulation で Cancel）を使う。Library のコードは後者で書いている。
- component でない実行時のクラス（ランナー）は、持ち主の component から `listenable(float)`（`TickEvents.PrePhysics` を渡す）を受け取って待つ。
- 経過時間はフレーム数で数えず、DeltaTime の足し合わせか `GetSimulationElapsedTime()` の差で測る。
- 多数の物について同じ計算をするなら、1 つの component がまとめて決まった間隔（例 毎秒）で計算する。結果は「開始時刻からの経過時間で決まる値」にして、途中参加・一時停止・やり直しでもずれないようにする（物ごとのループを持たない）。
- 毎フレーム世界全体を探さない。見つけた相手は覚えておく。決まった間隔で問い合わせる（ポーリング）より、イベントを待つ。
- 位置を毎フレーム Verse で動かすより、`keyframed_movement_component` などエンジン側で動くものを使う。

- Fortnite のラウンド（`fort_round_manager`）に合わせるときは、部品に直接ラウンドの購読を書かない。合図で動く部品は `activate_on_round_component`（ラウンド開始で `round_started_event`、終了で `round_ended_event`。どちらも起動・停止の合図の派生）の配下に置き、ActiveOnBegin / StartOnBegin はオフにする。コードで要るときは `round_watcher`（ActivationSystem）をフィールドに持つ（`SubscribeRoundStarted` の処理はラウンドの終わりで止められる）。ラウンド単位の状態は、開始と終了の両方で片付ける。

- 人ごとの選び（メニューで選んだモード・ジャンル・役など）は `player_group_component`（PlayerSystem）に置き、その人にだけ効かせる。画面（widget）は、全員に出すものでなければ同じ entity に `widget_show_in_group_component` などの絞り込みを置く（だれが何を選んだかを各部品で覚えない）。

### 5. 名前と値
- 失敗するかもしれない問い合わせは `<decides>`（`Find*` / `Is*` / `Has*`）。`Get*` は失敗しない。副作用があって `<decides>` にできないものだけ `Try*` で `logic` を返し、理由をコメントに書く。
- 外から読むだけの状態は `var<private> X<public>`、読めなくてよいものは `<private>`。状態の問い合わせは `IsActive[]` などの関数にそろえる。
- 公開する数値には単位を名前に付ける：長さ `Cm`、時間 `Seconds`、角度 `Degrees`、速さ `CmPerSecond`。割合・倍率（`Ratio` / `Multiplier`）は単位なし。長さはエンジンと同じセンチメートル。
- 子の並び順に意味を持たせない。順番が要るなら `@editable Order:int`。
- 内部の補助は `<internal>`（Kit からも見える）。実行時にだけ作るクラスは `class<internal>` でコンストラクターを内部にする。
- System をまたいで使う共通の補助は関数で作る。型引数を持つクラス（`scoped_lookup(t)` のような入れ物）は、名前の順でそのモジュールより前のモジュールのフィールドに使うと V3502（Can't access a function from a preceding type）になる（standalone の型チェッカーで再現。SceneGraphSystem の `ScopedLookup.verse`）。

### 6. 説明
- 公開する型・関数・イベントには、すぐ上に 1〜2 行の説明（何をするか、失敗する条件、単位、前提）。
- component の先頭には `役割` / `置き方` / `親` / `子` / `同じ entity` / `いつ` / `知らせ` / `タグ` / `外から` / `前提` のうち当てはまるもの。
- 実機で確かめていない振る舞いには `⚠ 未検証：` を付ける（確かめたら外す）。`@experimental` の API は `…ExperimentalKit` フォルダの中だけで使い、README と component の `前提` に書く（使うと島を公開できない）。
- ログ（Print）は `[snake_case の component 名] 何が起きたか` の形にする。前提が欠けているときは黙って失敗せず Print する。
- `@editable` には `ToolTip`（TooltipKit の message）と `Categories`。

## 確かめ方
- 型チェック：verse-standalone（UE のソースから自分でビルドする Verse の型チェッカー。配布キット: https://github.com/GorosukeSan/verse-standalone-kit ）の `verse_check.py --profile fortnite --runtime runtime-uefn43`。listenable / event / TickEvents の `Await` に出る「internal」「Unknown member」と、それに続く `race` / `loop` のエラー（V3538 / V3579）はチェッカー側の既知の誤り（UEFN ではビルドが通る）。
- それ以外の V3512（effects not allowed）は本当のエラー。例：`<suspends>` の関数を `if` の条件の中で呼ぶ（`if (AwaitWithin(...)?)`）。先に変数で受けてから `if (X?)` にする。
- 動き：`_Test` のテストを UEFN で動かす。
- UEFN のビルドでだけ出るエラーがある（standalone の型チェッカーでは出ない）。例：引数で受けた関数を `Subscribe` にそのまま渡す（V3502）→ メソッドで包む小さなクラスを通す。配る前に UEFN でビルドする。
- 公開している型の種類を変える（クラス → enum など）と、開いているエディターが古い型を覚えていて 9002 が残ることがある。エディターを再起動すれば消える（エディターの中の型を Python などで書き換えて直そうとしない。クラッシュする）。
- 実験的な API を使っていないか：digest の `@experimental` の名前と、`ExperimentalKit` の外のコードを突き合わせる（使っていたら `…ExperimentalKit` へ移す）。
