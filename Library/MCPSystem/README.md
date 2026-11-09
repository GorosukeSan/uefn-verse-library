# MCPSystem

MCP（エディターの外の Python）から、**セッション中のゲーム**に命令を送り、返事を受け取る System です。UEFN の **ライブ編集**（エディターで `@editable` を書き換えると、セッション中のゲームに約 0.1 秒で届く）を使います。画面操作（マウス・キーボードの入力）は使いません。

- 送り手（Python）が受け箱の component の文字列の `@editable` に **命令の列（JSON）** を書く → 受け箱が宛先の **ツールセット** に渡す → 返事を `Print` → 送り手が MCP の `GetVerseOutput` で読む。
- 命令は「ツールセット.ツール」（UEFN の MCP のツールセットと同じ考え方）。entity・プレイヤー・独自キャラクター・画面（UI）・ゲームの流れ・スポーン・拾える物・動く物・カウントダウン・エネルギー・状態の書き出し / 復元・デバッグのツールセットがあります（13 個・112 ツール）。ゲームの部品も interface（`mcp_controllable`）を実装すれば、自分のツールセットを足せます。
- UI は **画面ごとのオプトイン**：`mcp_widget_control_component` を置いた画面だけが MCP から見え、押せます。押すと本物のクリックと同じく `AwaitClick` / `AwaitChoice` に届きます（作り手のコードは変わらない）。

確認バージョン：**UEFN v43.00**（2026-11-08）。MCPSystem の版：**1.0.0**（`MCPSystemVersion`。送り手との約束の形が変わったら上げる）。

## フォルダと依存
| 場所 | 中身 | 依存 |
|---|---|---|
| 直下 | 受け箱 `mcp_inbox_component`（Core ツールセット）、interface `mcp_controllable` とタグ `mcp_controllable_tag`、命令の呼び出し `mcp_call`、返事 `mcp_reply`、ツールの説明 `mcp_tool` / `mcp_arg`、JSON の小道具、名前 `mcp_name_component`、タグの名前の表 `mcp_tag_entry` / `mcp_tag_provider`、状態の書き出し・復元の土台 `mcp_session_restorable`、`mcp_role_tags` | Verse・UnrealEngine・Fortnite の標準だけ（**ほかの System に依存しない**） |
| `EntityKit` | `mcp_entity_toolset_component`（"entity"）、`mcp_restore_transform_component` | ActivationSystem |
| `PlayerKit` | `mcp_player_toolset_component`（"player"） | PlayerSystem |
| `CharacterKit` | `mcp_character_toolset_component`（"character"） | CharacterSystem・PlayerSystem・MovementSystem |
| `WidgetKit` | `mcp_widget_toolset_component`（"widget"）、オプトイン `mcp_widget_control_component` | WidgetSystem |
| `GameSequenceKit` | `mcp_flow_toolset_component`（"flow"） | GameSequenceSystem |
| `SpawnKit` | `mcp_spawn_toolset_component`（"spawn"） | SpawnSystem |
| `PickupKit` | `mcp_pickup_toolset_component`（"pickup"） | PickupSystem |
| `MoverKit` | `mcp_mover_toolset_component`（"mover"） | MoverSystem |
| `CountdownKit` | `mcp_countdown_toolset_component`（"countdown"） | CountdownSystem |
| `EnergyKit` | `mcp_energy_toolset_component`（"energy"） | EnergySystem・PlayerSystem |
| `SessionKit` | `mcp_session_toolset_component`（"session"） | 直下だけ |
| `DebugKit` | `mcp_debug_toolset_component`（"debug"） | 直下だけ |
| `TooltipKit` | エディターに出す説明 | — |

- 依存は「Kit → 直下」「Kit → 対象の System」の向きだけです。対象の System から MCPSystem へは依存しません（MCPSystem を使わないプロジェクトでも各 System は動きます）。使う System の Kit だけを取り込めます（直下だけでも Core ツールセットと自作の受け口は動きます）。
- Python の送り手（`mcp.py`・`mcpsystem\`）は、Library の外に別のパッケージ（MCPSystem パッケージ）として置いています。Library を UEFN の Content に配るとき .verse 以外のファイルが入らないように分けています（Content の中に .verse 以外があると `VerseToolset.Delete` がフォルダを消すのを拒む）。

## 導入（置き方）
1. 最上位の entity を 1 つ作り（例 `MCP_Inbox`）、`mcp_inbox_component` を付ける。ライブ編集で書くのはこの component の `Inbox` だけなので、Lore のロック・保存はこの entity のパッケージだけで済みます（設定「エンティティを外部ファイルとして保存」がオンのとき）。
2. 使うツールセットの component を同じ entity に付ける（どこに置いてもタグで集めるので、同じ entity でなくてもよい）。
3. MCP から UI を操作したい画面（`player_widget_component` の派生）の entity に `mcp_widget_control_component` を付け、`ScreenId` を決める（例 `map_select`）。
4. Verse で entity の名前は読めないので、MCP から名前で指したい entity には `mcp_name_component`（`McpName`）を付ける。
5. ゲーム固有のタグを MCP の名前で使うなら、ゲームの component に `mcp_tag_provider` を実装する（下の「ゲームのツールセットを足す」）。
6. セッションを始める（**component を足したら、実行中のセッションには届かない**。`PushChanges(bVerseOnly=false)`（約 90 秒）か `StartSession` のやり直しが要る）。

```
MCP_Inbox（最上位）
  mcp_inbox_component
  mcp_entity_toolset_component, mcp_player_toolset_component, mcp_character_toolset_component, mcp_widget_toolset_component,
  mcp_flow_toolset_component, mcp_spawn_toolset_component, mcp_pickup_toolset_component, mcp_mover_toolset_component,
  mcp_countdown_toolset_component, mcp_energy_toolset_component, mcp_session_toolset_component, mcp_debug_toolset_component
CD_Lobby（ロビーの画面の entity）
  cd_map_select_component（player_widget_component の派生）
  mcp_widget_control_component（ScreenId = map_select）  ← オプトイン
```

## 設定（@editable）
- `mcp_inbox_component.Inbox : string = ""` — MCP が書く命令の JSON。エディターでは空にしておく。
- `mcp_inbox_component.RunInboxAtStart : logic = false` — オンなら、受け箱の起動時（ラウンドの開始・リセット・Verse の入れ直し）に入っている命令を実行する（セッション開始前に書いておいた命令で始める）。オフなら起動時の中身は実行しない（作り直しのあと、前に実行した命令を繰り返さないため）。
- `mcp_inbox_component.MaxPerFrame : int = 50`（1〜1000）— 1 フレームに実行する命令の数。
- `mcp_inbox_component.MaxLineChars : int = 12000`（2000〜15000）— 返事 1 行の文字数（`GetVerseOutput` は 1 行 16384 文字で切る）。
- `mcp_inbox_component.Quiet : logic = false` — オンなら返事を Print しない（公開版）。
- `mcp_inbox_component.LogLevel : int = 1`（0〜3）— 受け箱のログの詳しさの初期値（`debug.set_level` で変えられる）。
- `mcp_inbox_component.ScreenSeconds : float = 0.0` — 返事の行をクライアントの画面にも出す秒数。**0 ならログだけ**（`Print` は既定で 2 秒画面に出て、プレイの邪魔になる。v43.00 実機で確認）。
- 各ツールセットの `InstanceId : string = ""` — 同じツールセットを複数置くときの名前（"mover@door_a" の door_a）。
- `mcp_widget_control_component.ScreenId : string = ""`（空なら "screen"）、`AllowPress : logic = true`、`AllowShowHide : logic = true`。
- `mcp_name_component.McpName : string = ""`。
- `mcp_session_toolset_component.RestoreOnRoundStart : string = ""`（ラウンドが始まるたびに戻す状態。空なら何もしない）、`RestoreDelaySeconds : float = 1.5`、`MinSeparationCm : float = 120.0`。
- `mcp_restore_transform_component.Key : string = ""`。

## 命令と返事の形（送り手と受け手の約束）
**受け箱に書くもの**（`Inbox`）
```json
{"n": 17, "cmds": [
  {"seq": 1794137895018, "to": "widget", "tool": "press", "args": {"player": 0, "screen": "map_select", "button": "m01"}},
  {"seq": 1794137895019, "to": "mover@door_a", "tool": "play", "args": [12]}
]}
```
- `cmds` は **返事をまだ見ていない命令だけ**。送り手は返事を見たら外して書き直す（1 フレームの間に何度書いても、前の命令が上書きで消えない）。`n` は書くたびに変える（同じ中身を送り直すときも文字列を変える）。
- `seq` は増やすだけ。送り手はミリ秒の時刻から始める（前の実行と重ならない）。受け箱は処理済みの seq 以下は実行せず、覚えている返事（直近 256 件）を出し直す（出してから 1 秒たってから、1 秒に 1 回まで）。
- `to` は "ツールセット" か "ツールセット@インスタンス"。`"*"` はすべての受け口（宣言にないツールは unknown_tool）。`"core"`（`"inbox"` でもよい）は受け箱そのもの。
- `tool` は `cmd` でもよい（検証版との互換）。`args` は名前つき（オブジェクト）か並び（配列。ツールの説明の引数の順）。省略してよい。
- 引数の型：int / float は JSON の数か数の文字列、bool は **"true" / "false" / 1 / 0**（v43.00 の Verse の JSON には `AsBool` が無く、true / false を読めない。Python の送り手は自動で文字にする）、vector3 は `{"left","up","forward"}` か `{"x","y","z"}`（UE の軸。x = forward、y = right = −left、z = up）か `[left, up, forward]`、entity は番号（`entity.find` などが返す `id`。このセッションの中で変わらない）か `mcp_name_component` の名前、player は `core.players` の番号（0 から。playspace の `GetPlayers` の順。出入りで変わる）。
- 受け箱は宣言にないツール（`unknown_tool`）と省略できない引数が無いとき（`bad_args missing <名前>`）を、ツールセットに渡す前に返す。どのツールセットにも `help`（そのツールセットの説明）がある。

**返事**（`GetVerseOutput` の行。行頭の目印 `[MCPC]`）
```
[MCPC] {"seq":1794137895018,"ok":true,"to":"widget","tool":"press","hits":1,"reply":"pressed m01","f":224,"t":3433.15}
[MCPC] [{"seq":..,"ok":true,...},{"seq":..,"ok":false,"error":"no_button","reply":"no_button zzz",...}]
[MCPC] ~5:0:6:{"seq":1794138365,"ok":true,"to":"debug","tool":"payload",...
[MCPC] {"event":"move_done","seq":1794137956928,"data":{"ok":true,"reason":"reached",...},"f":2659,"t":3515.6}
[MCPC] {"seq":0,"hello":true,"v":"1.0.0","boot":138243801,"skipped_len":18,"f":0,"t":3777.93}
```
- `ok` / `reply`（人が読む文）/ `error`（ok=false のときのエラーの種類＝ reply の最初の語）/ `data`（構造のある返事。JSON の値）/ `hits`（受けた受け口の数。2 以上なら `results` に受け口ごとの結果）/ `f`（受け箱のフレーム）/ `t`（シミュレーションの秒）。
- エラーの種類：`no_target`（宛先が無い）/ `unknown_tool` / `bad_args` / `no_entity` / `no_player` / `not_shown` / `no_button` / `disabled` / `not_waiting` / `not_in_round` / `failed` / `bad_json` / `bad_command` / `too_large`。
- 1 フレームの返事は 1 行の配列にまとめる（`GetVerseOutput` は 1 秒に約 100 行で間引くため）。1 行 `MaxLineChars` まで。残りは次のフレーム。
- 1 つの返事が 1 行に入らないときは `~<chunk_id>:<part>:<parts>:<JSON の一部をそのまま>` の行に分ける（逃がさない。返事の JSON に改行は無い）。送り手が `part` の順につないで `json.loads`。UTF-8 の文字の途中では切らない（ASCII の文字の前で切る）。60 万文字を超える返事は `too_large`。
- 長くかかるツール（`character.move` の seconds・`move_world`・`move_to`・`play`・`debug.frames`・`debug.wait`）はすぐ `reply:"accepted"` を返し、終わったら `event` の行を出す。
- 受け箱が起動したら `hello`（`boot` は起動ごとに変わる）。送り手は見たら未完了の命令を書き直す（作り直しで処理済みの seq を忘れるので、返事を見る前の命令はもう一度実行されうる → **ツールは何度実行しても同じ結果になる形にする**）。
- Python は `json.loads(行, strict=False)`（制御文字は `"` `\` 改行・タブ・復帰だけを逃がしている）。

## ツールセットとツールの一覧
自動生成（Verse のソースから。セッション無しで動く）：
```
python -I <MCPSystem パッケージ>\tools\gen_tool_docs.py <Library>\MCPSystem --readme <Library>\MCPSystem\README.md --python <MCPSystem パッケージ>\mcpsystem\toolsets_table.py
```
セッション中の受け箱から（ゲームのツールセットも入る）：`python -I mcp.py describe --markdown`（MCPSystem パッケージのフォルダで）。ツールの宣言は `McpTool("名前", "説明", array{McpArg(...), McpOptArg(...)})` を 1 行に書く（自動生成が読むため）。

<!-- tools:begin -->
| ツールセット（宛先） | ツール | 引数 | すること |
|---|---|---|---|
| `core` | `ping` | — | 受け箱が動いているか（pong を返す） |
| `core` | `echo` | text:string? | 引数をそのまま返す（text か、並びの引数を空白でつないだもの） |
| `core` | `describe` | toolset:string? | ツールセットとツールの一覧（引数の説明つき）。data に JSON |
| `core` | `list` | — | 受け口（ツールセット）の一覧。data に [{toolset,id,tools}] |
| `core` | `status` | — | 受け箱の状態（処理済みの seq・待ち・フレーム・受け口の数・ログの詳しさ） |
| `core` | `time` | — | シミュレーションの秒・UTC の Unix 時刻・フレーム |
| `core` | `round` | — | ラウンドの途中か・番号 |
| `core` | `players` | — | プレイヤーの一覧（番号・キャラクターの有無・位置 cm）。ほかのツールの player はこの番号 |
| `core` | `tags` | — | 名前を付けたタグの一覧（entity.find / player.has_tag などで使える名前） |
| `core` | `batch` | cmds:json | 命令の配列を同じフレームで順に実行する。data に返事の配列 |
| `character` | `list` | — | 独自キャラクターを動かしている人の一覧。data に [{player,pos,velocity,grounded}] |
| `character` | `state` | player:player | 体の状態（位置・速度 cm/s・接地・状態・重力の倍率・変更の倍率・ダッシュ中か・左右の入力のしかた `side_style`（バフ込み）/ `side_style_base`（walk の基本）。walk が無ければ side_style は出ない）・動く床 `ground_velocity`（乗っている床の速度）/ `inherited_velocity`（床から離れたときに受け継いだ水平の速度。着地で 0）/ `riding`（体に `character_ride_component` があるときだけ。乗って運ばれていれば true） |
| `character` | `move` | player:player, input:json, seconds:float? | 移動の入力を入れる（walk の SetMoveInput と同じ。forward = 前、left = 左。長さ 1 まで）。seconds を渡すとその秒数のあと 0 に戻す（終わりに move_done） |
| `character` | `move_world` | player:player, dir:vector3, seconds:float?, scale:float? | 世界の向き（cm の向き。長さは使わない）へ歩かせる。walk の Space に合わせて毎フレーム入力に直す。seconds（既定 1）のあと止める（move_done） |
| `character` | `move_to` | player:player, pos:vector3, tolerance:float?, timeout:float? | 世界の位置へ歩かせる（水平の距離が tolerance 以下で止まる。着いたら move_done。ゲームが体を別の場所へ移したら reason = moved_away） |
| `character` | `stop` | player:player, brake:bool? | 入力を 0 にし、move / play を止める（brake = true なら水平の速度も 0） |
| `character` | `jump` | player:player | ジャンプさせる（跳べなければ failed） |
| `character` | `dash` | player:player | ダッシュさせる（出せなければ failed） |
| `character` | `teleport` | player:player, pos:vector3, keep_velocity:bool? | 足元を pos へ（当たりを見ない）。keep_velocity が false（既定）なら速度を 0 に |
| `character` | `set_velocity` | player:player, velocity:vector3 | 速度を決める（cm/s。世界の向き） |
| `character` | `add_velocity` | player:player, delta:vector3 | 速度を足す（cm/s） |
| `character` | `set_gravity_scale` | player:player, scale:float | 重力の倍率（1 で既定、0 で無重力） |
| `character` | `set_side_style` | player:player, style:string | 左右の入力のしかた（walk の基本。`SetSideStyle` と同じ）を変える。`turn` = 動く向きへ回る、`strafe` = 前を向いたまま横へ（カニ歩き）、`tank_turn` = その場で回る、`toggle` = 切り替えのボタンと同じ（`SwitchSideStyle`）。バフ（`character_modifier.SideStyle`）が決めているあいだはそちらが優先。reply に今のしかたと基本 |
| `character` | `play` | player:player, motion:json | 動きの JSON を再生する（終わりに play_done）。steps：[{t,move,world,jump,dash,teleport,stop}]（t 秒に入力）／points：[{pos,jump,dash,wait,teleport}]（順に歩いて通る） |
| `character` | `record_start` | player:player, interval:float? | 動きの記録を始める（interval 秒ごとの位置・速度・接地と、ジャンプ・ダッシュなどの出来事） |
| `character` | `record_stop` | player:player | 記録を止めて返す。data に {interval,samples:[{t,pos,velocity,grounded}],actions:[{t,action}],points:[{pos}]}（points はそのまま play に渡せる） |
| `countdown` | `list` | — | カウントダウンの一覧。data に [{id,name,running,paused,remaining,duration}] |
| `countdown` | `state` | countdown:entity | カウントダウン 1 つの状態 |
| `countdown` | `start` | countdown:entity | 数えていなければ始める |
| `countdown` | `restart` | countdown:entity, seconds:float? | 最初から数え直す（seconds で今回だけの長さ） |
| `countdown` | `stop` | countdown:entity | やめる（数え終わりは知らせない） |
| `countdown` | `pause` | countdown:entity | 一時停止 |
| `countdown` | `resume` | countdown:entity | 続ける |
| `countdown` | `add_seconds` | countdown:entity, seconds:float | 残りを増やす（マイナスで減らす） |
| `debug` | `log` | text:string | ログに「[MCP] text」を書く（ゲームのログと同じ時系列で見る目印に） |
| `debug` | `get_level` | — | 受け箱のログの詳しさ（0〜3） |
| `debug` | `set_level` | level:int | 受け箱のログの詳しさを変える（0 = 返事だけ、1 = 起動・壊れた命令、2 = 命令ごと、3 = 詳しく） |
| `debug` | `dump` | toolset:string? | 引数の要らない "state" ツールを持つ受け口をまとめて呼ぶ。data に [{to,ok,reply,data}] |
| `debug` | `counts` | — | 世界の entity の数・受け口の数・名前を付けた entity の数 |
| `debug` | `frames` | seconds:float? | seconds 秒のフレームの数と 1 フレームの秒（平均・最大）を測る（終わりに frames） |
| `debug` | `wait` | seconds:float | seconds 秒待ってから知らせる（長くかかるツールの見本。終わりに waited） |
| `debug` | `payload` | chars:int | chars 文字の文字列を data で返す（大きい返事を分けて出す仕組みの確かめ） |
| `energy` | `list` | — | エネルギーの一覧。data に [{id,name,owner,amount,max,ratio}]（owner は持ち主のプレイヤーの番号、いなければ -1） |
| `energy` | `get` | energy:entity?, player:player? | 量（energy か player のどちらか） |
| `energy` | `set` | energy:entity?, player:player?, amount:float | 量を決める（0〜最大に丸める） |
| `energy` | `restore` | energy:entity?, player:player?, amount:float | 足す（最大を超える分は捨てる） |
| `energy` | `consume` | energy:entity?, player:player?, amount:float | 使う（足りなくても 0 で止まる） |
| `energy` | `spend` | energy:entity?, player:player?, amount:float | 足りれば使う（足りなければ failed で何も変えない） |
| `energy` | `fill` | energy:entity?, player:player? | 満たす |
| `energy` | `set_max` | energy:entity?, player:player?, max:float | 最大を決める |
| `entity` | `find` | tag:string?, name:string?, root:entity?, limit:int? | entity を探す（tag・name・root のどれか。root だけなら子孫すべて）。data に [{id,name,pos}] |
| `entity` | `info` | entity:entity | entity の情報（親・子の数・component の数・付いている名前つきタグ・位置） |
| `entity` | `children` | entity:entity | 直下の子。data に [{id,name}] |
| `entity` | `parent` | entity:entity | 親（最上位なら simulation entity の番号） |
| `entity` | `get_transform` | entity:entity, space:string? | 位置（cm）・回転（度）・大きさ |
| `entity` | `set_transform` | entity:entity, pos:vector3?, rot:json?, scale:vector3?, space:string? | 位置・回転・大きさを変える（渡したものだけ） |
| `entity` | `move_by` | entity:entity, delta:vector3 | 位置をずらす（世界の向き、cm） |
| `entity` | `enable` | entity:entity, recursive:bool? | entity の component（enableable なもの。mesh など）を有効にする |
| `entity` | `disable` | entity:entity, recursive:bool? | entity の component（enableable なもの）を無効にする |
| `entity` | `has_tag` | entity:entity, tag:string | タグが付いているか（reply が true / false） |
| `entity` | `add_tag` | entity:entity, tag:string | タグを付ける（<concrete> のタグだけ。このツールセットが止まると外れる） |
| `entity` | `remove_tag` | entity:entity, tag:string, all:bool? | MCP から付けたタグを外す（all = true なら、その型のタグを全部外す） |
| `entity` | `activate` | entity:entity, player:player? | 起動の合図（activated_event。player を渡すと activated_by_agent_event）を entity とその子孫へ送る |
| `entity` | `deactivate` | entity:entity | 停止の合図（deactivated_event）を entity とその子孫へ送る |
| `entity` | `components` | entity:entity | component の一覧（型の名前は読めないので、番号・有効か・MCP の受け口なら名前） |
| `entity` | `state` | — | このツールセットの状態（MCP から付けたタグの数・番号の数） |
| `flow` | `list` | — | 流れの一覧。data に [{id,name,state,current,nodes:[{id,name,order,active}]}] |
| `flow` | `state` | sequence:entity? | 流れの状態（list と同じ。sequence を渡すとその流れだけ） |
| `flow` | `start` | sequence:entity? | 最初のノードから始める（進めていれば何もしない） |
| `flow` | `stop` | sequence:entity? | 止める |
| `flow` | `restart` | sequence:entity? | 最初のノードからやり直す |
| `flow` | `jump` | sequence:entity?, node:entity?, order:int? | ノードへ移る（node か order のどちらか） |
| `mover` | `list` | — | 動く物の一覧。data に [{id,name,moving,finished,speed,pos,target}] |
| `mover` | `state` | mover:entity | 動く物 1 つの状態 |
| `mover` | `play` | mover:entity | 動き出す・止まった位置から続ける |
| `mover` | `pause` | mover:entity | その場で一時停止 |
| `mover` | `restart` | mover:entity, return_to_start:bool? | 道のりの最初からやり直す |
| `mover` | `set_speed` | mover:entity, speed:float | 速さ（cm/s。1 未満は 1） |
| `pickup` | `list` | — | 拾える物の一覧。data に [{id,name,display_name,available,pos}] |
| `pickup` | `pick` | pickup:entity, player:player | 拾わせる（拾ったときと同じ。効果を与えて隠す） |
| `pickup` | `grant` | pickup:entity, player:player | 拾える物の効果だけを与える（拾える物はそのまま） |
| `pickup` | `restore` | pickup:entity | 戻す（また拾えるようにする） |
| `pickup` | `hide` | pickup:entity | 隠す（拾えなくする） |
| `pickup` | `effects` | player:player | プレイヤーが受けている効果。data に [{id,effect_id,remaining}] |
| `pickup` | `end_effects` | player:player | プレイヤーの効果をすべて終える |
| `player` | `list` | — | プレイヤーの一覧。data に [{index,has_character,pos,tags,groups}]（tags は名前つきタグのうち付いているもの、groups は入っている組の id） |
| `player` | `get_position` | player:player | Fortnite のキャラクターの位置（cm）・向き・速度（cm/s） |
| `player` | `teleport` | player:player, pos:vector3, yaw:float? | Fortnite のキャラクターを移す（体の entity の transform を書く） |
| `player` | `has_tag` | player:player, tag:string | agent にタグが付いているか（reply が true / false） |
| `player` | `add_tag` | player:player, tag:string | agent にタグを付ける（<concrete> のタグだけ。このツールセットが止まると外れる） |
| `player` | `remove_tag` | player:player, tag:string, all:bool? | MCP から付けたタグを外す（all = true ならその型を全部） |
| `player` | `groups` | — | 組（player_group_component）の一覧。data に [{id,name,members}] |
| `player` | `join_group` | player:player, group:entity | 組に入れる（player_group_component.Join。兄弟の組から出す設定ならそれも） |
| `player` | `leave_group` | player:player, group:entity | 組から出す |
| `player` | `state` | — | プレイヤーの数・MCP から付けたタグの数 |
| `session` | `keys` | — | 状態を書き出せる部品のキーの一覧 |
| `session` | `snapshot` | keys:string[]? | 状態を書き出す。data に {v,t,players,items:{キー:JSON}} |
| `session` | `restore` | state:json, keys:string[]? | 状態を戻す（snapshot の data をそのまま渡す）。reply にキーごとの結果 |
| `spawn` | `list` | — | 出し手の一覧。data に [{id,name,kind,count,max,running,pos}]（kind は prefab か spawner） |
| `spawn` | `spawn` | spawner:entity, count:int? | spawn_prefab_component の決めた場所に count 個出す。data に出した entity の [{id}] |
| `spawn` | `spawn_at` | spawner:entity, pos:vector3, yaw:float? | spawn_prefab_component で好きな位置に 1 つ出す |
| `spawn` | `despawn` | spawner:entity, entity:entity | 出し手が出したもの 1 つを消す |
| `spawn` | `despawn_all` | spawner:entity | 出し手が出したものを全部消す |
| `spawn` | `start` | spawner:entity | spawner_component を動かす |
| `spawn` | `stop` | spawner:entity | spawner_component を止める（出したものは消える） |
| `spawn` | `refill` | spawner:entity | spawner_component を今すぐ 1 回分補充する |
| `spawn` | `spawned` | spawner:entity | 出し手が出しているもの。data に [{id,pos}] |
| `widget` | `list` | — | オプトインした画面の一覧（出しているかに関係なく）。data に [{screen,entity,widgets:[{widget,mode,audience,shown_to}]}] |
| `widget` | `screens` | player:player? | 今出ている画面と、待っているボタン。data に [{player,screen,widget,mode,buttons:[{id,index,label,enabled}]}] |
| `widget` | `press` | player:player, screen:string, button:string, widget:int? | ボタンを押す（ID・文字・番号のどれか。本物のクリックと同じく AwaitClick / AwaitChoice に届く） |
| `widget` | `show` | player:player, screen:string, widget:int? | 画面を出す（ShowFor） |
| `widget` | `close` | player:player, screen:string, widget:int? | 画面を閉じる（HideFor） |
| `widget` | `state` | — | オプトインした画面の数・今出ている数 |
<!-- tools:end -->

## Python の送り手（Library の外の MCPSystem パッケージ）
```python
import sys; sys.path.insert(0, r"<MCPSystem パッケージのフォルダ>")
from mcpsystem import connect
mcp = connect()                                            # 受け箱（最上位の MCP_Inbox の mcp_inbox_component）を探す
mcp.core.ping()                                            # "pong"
screens = mcp.widget.screens()                             # [{"player":0,"screen":"map_select","buttons":[{"id":"m01","label":"Stage 1",...}]}]
mcp.widget.press(0, "map_select", "Stage 1")                # ID・文字・番号のどれでも
goal = mcp.entity.find(tag="goal_tag")[0]["pos"]
mcp.character.move_to(player=0, pos=goal, wait=True)      # 終わりの知らせ（move_done）まで待つ
snap = mcp.session.snapshot(); mcp.session.restore(state=snap)
replies = mcp.channel.batch([("debug", "log", {"text": str(i)}) for i in range(300)])   # まとめ送り
```
CLI：`python -I mcp.py core.ping`、`python -I mcp.py widget.press "[0,\"map_select\",\"m01\"]"`、`python -I mcp.py character.move_to "{\"player\":0,\"pos\":[0,100,500]}" --wait`、`python -I mcp.py describe --markdown`、`python -I mcp.py tools`（セッション無しで一覧）。テスト：`python -I tests\test_channel.py`（偽の受け箱。UEFN は要らない）。詳しくは MCPSystem パッケージの README。

## 活用例
- **自動テスト**：セッションを始めて、画面のボタンを押し（`widget.press`）、独自キャラクターを動かし（`character.play` / `move_to`）、ゲームのログ（`[my_game] cleared` など）を待って判定する。作者のゲームでは、ロビー → マップ選択 → クリア → リザルト → ロビーを通すスクリプトをこの形で書いています。
- **状態から始める**：`session.snapshot` で作業中の状態を JSON にして保存し、次のセッションの開始前に `mcp_session_toolset_component.RestoreOnRoundStart` に書いておく（同じ条件で何度も試す）。セッション中なら `session.restore` を送るだけ（PushChanges もリセットも要らない）。
- **値を詰める**：`entity.set_transform` / `mover.set_speed` / `countdown.add_seconds` などで、セッションを止めずに試す。
- **動きの記録と再生**：`character.record_start` → 人が遊ぶ → `record_stop` の `points` をそのまま `character.play` に渡す。
- **ログの目印**：`debug.log` で「[MCP] ここから計測」のような目印をゲームのログと同じ時系列に入れる。
- **ゲームのツールセットを足す**：ゲームの component に `mcp_controllable` を実装し、`OnBeginSimulation` で自分の entity に `mcp_controllable_tag` を付ける（`mcp_role_tags` を使うと外し忘れない）。
```verse
my_game_mcp_component := class<final_super>(component, mcp_controllable, mcp_tag_provider):
    RoleTags<private>:mcp_role_tags = mcp_role_tags{}
    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()
    McpToolset<override>()<transacts>:string = "mygame"
    McpId<override>()<transacts>:string = ""
    McpTagEntries<override>()<transacts>:[]mcp_tag_entry = array{McpFindOnlyTagEntry("my_goal_tag", my_goal_tag)}
    McpTools<override>()<transacts>:[]mcp_tool =
        array{McpTool("restart", "やり直す", array{McpOptArg("player", "player", "番号")})}
    McpHandle<override>(Call:mcp_call):mcp_reply =
        if (Call.Tool = "restart"):
            # 読み取りは Call.FindPlayer[] / FindInt[] などの <decides>（範囲外・壊れた値で失敗する。実行時エラーにしない）
            McpOk("restarted")
        else:
            McpFail("unknown_tool", Call.Tool)
```
作者のゲームでは、ゲーム固有のツールセット（state / maps、ゲームのタグの名前）をこの形で 1 つ置いています。

## イベント・タグ
- タグ：`mcp_controllable_tag`（受け口・タグの名前を知らせる部品の entity）、`mcp_name_tag`（`mcp_name_component`）、`mcp_session_restorable_tag`（状態を書き出せる部品）、`mcp_widget_control_tag`（画面のオプトイン）。どれも部品が自分で付け外しする（MCP はタグを書けない）。どれも `<concrete>`（MCP から `entity.add_tag` で付けられる）。
- scene_event・listenable は持ちません（命令はライブ編集の文字列、返事は Print）。

## 公開 API（直下。Kit の component は上の一覧と各ファイルの先頭のコメント）
```verse
MCPSystemVersion<public>:string = "1.0.0"
mcp_controllable_tag<public> := class<concrete>(tag)
mcp_controllable<public> := interface:
    McpToolset<public>()<transacts>:string
    McpId<public>()<transacts>:string
    McpTools<public>()<transacts>:[]mcp_tool
    McpHandle<public>(Call:mcp_call):mcp_reply
mcp_arg<public> := struct{Name, Type, Doc:string; Required:logic}
mcp_tool<public> := struct{Name, Doc:string; Args:[]mcp_arg}
McpArg / McpOptArg(Name, Type, Doc)<transacts>:mcp_arg ; McpTool(Name, Doc, Args)<transacts>:mcp_tool ; (Tool:mcp_tool).ToJson()
FindMcpTool<public>(Tools:[]mcp_tool, Name:string)<transacts><decides>:mcp_tool
mcp_reply<public> := struct{Ok:logic; Text:string; Data:string}
McpOk(Text) / McpOkData(Text, Data) / McpFail(Code, Detail) / McpBadArg(Name)
mcp_call<public> := class<internal>:                       # 受け箱が作る
    Seq, Toolset, Id, Tool, Inbox
    FindArg / HasArg / FindString / FindInt / FindFloat / FindLogic / FindVector / FindObject / FindArray / FindEntity / FindPlayer / FindAgent  # <decides>
    GetStringOr / GetIntOr / GetFloatOr / GetLogicOr
    Notify(EventName:string, Data:string)                  # 長くかかるツールの終わりの知らせ
mcp_inbox_component<public> := class<final_super>(component):
    Inbox, RunInboxAtStart, MaxPerFrame, MaxLineChars, Quiet, LogLevel, ScreenSeconds
    ExecuteJson(CommandJson:string):string                 # 命令 1 つをその場で実行して返事の JSON（Print しない。ゲームのコード・テストから）
    GetHandle(Target:entity):int ; FindHandleEntity(Handle:int)<decides>:entity ; FindNamed(Name:string):[]entity ; ResolveEntity(V:value)<decides>:entity
    GetTagEntries():[]mcp_tag_entry ; FindTagEntry(Name:string)<decides>:mcp_tag_entry ; GetControllables():[]mcp_controllable
    Notify(EventName, Seq, Data) ; Log(Level, Text) ; GetLogLevel() / SetLogLevel(Level) ; IsInRound()<decides> ; GetRoundNumber() ; GetFrame()
mcp_name_component<public> := class<final_super>(component): McpName:string
(InEntity:entity).GetMcpName()<reads>:string ; (InEntity:entity).GetMcpKey()<transacts>:string ; McpPositionKey(Position:vector3):string
mcp_tag_entry<public> := class<final>{Name:string; TagType:castable_subtype(tag); Concrete:?castable_concrete_subtype(tag)}
McpTagEntry(Name, TagType:castable_concrete_subtype(tag)) ; McpFindOnlyTagEntry(Name, TagType:castable_subtype(tag)) ; (Entry:mcp_tag_entry).MakeTag()<decides>:tag
mcp_tag_provider<public> := interface: McpTagEntries()<transacts>:[]mcp_tag_entry
mcp_session_restorable_tag<public> := class<concrete>(tag)
mcp_session_restorable<public> := interface:
    McpSessionKey()<transacts>:string ; McpSessionSave(Context:mcp_session_context):string ; McpSessionRestore(Context:mcp_session_context, State:value):string
mcp_session_context<public> := class<internal>: Players:[]player ; MinSeparationCm:float ; ClaimPosition(Desired:vector3):vector3 ; FindPlayer(Index:int)<decides>:player
MakeMcpSessionContext(Players:[]player, MinSeparationCm:float):mcp_session_context
mcp_role_tags<public> := class: Add(Target, Tag) ; Remove(Target, TagType)<decides> ; RemoveAll() ; GetCount()
# JSON の小道具
McpEscape / McpQuote / McpNumber（有限でなければ null）/ McpInteger / McpLogic / McpVector / McpRotation / McpField / McpObject / McpArray / McpStringArray / McpJoin / McpJoinTree
McpParseInt / McpParseFloat / McpDigit / McpFloatToInt（±9.0e15 まで）/ McpFindChar / McpSlice           # 失敗しうるものは <decides>
McpValueToString / McpValueToInt / McpValueToFloat / McpValueToLogic / McpValueToVector                      # JSON の value から。<decides>
(InEntity:entity).McpGetPlayers():[]player ; (InEntity:entity).McpGetPlayerIndex(Agent:agent):int
McpReadCommand(V:value)<decides>:mcp_command ; McpToolsetJson(Controllable):string
```

## 前提・注意・制限
- **ライブ編集の無い環境（公開した島）では何もしない**：`Inbox` はクック時の値のまま変わらない。公開版では `Quiet` をオンにする（ログを汚さない）。
- 実行中のセッションに **component・entity を足しても届かない**（`PushChanges(bVerseOnly=false)` 約 90 秒、か StartSession が要る）。`@editable` の書き換え・`SetEntityTransform`・既存の component を外す、は届く（LIVE_EDIT.md）。
- **受け手は実行時エラーで止まらない書き方**：失敗しうる変換はすべて `<decides>`（`McpFloatToInt` は ±9.0e15、ベクトル・小数は ±1.0e15、`McpParseInt` は 18 桁まで）。大きな float を `Floor[]` / `Int[]` するとエラーではなく実行時エラー（`ErrRuntime_IntegerBoundsExceeded`）になり `OnSimulate` ごと止まるので、ツールの中でも範囲を確かめる。
- **作り直し**：ラウンドの開始・`PushChanges` で受け箱が作り直されると、処理済みの seq を忘れる。返事を見る前に作り直しが起きた命令は 2 回実行されうる（ツールは何度実行しても同じ結果になる形に）。`entity` の番号（`id`）も作り直しで変わる。
- 1 つの受け箱に命令を書く送り手は 1 つにする（2 つの送り手が同時に書くと、上書きで相手の命令が消える）。
- 文字列を 1 文字ずつ `+=` でつなぐと長い文字列で O(n²) になる（10 万文字で数秒）。標準の `Concatenate` は中で再帰していて、10 万個の断片で **実行時エラー（`ErrRuntime_InfiniteLoop`）** になり受け箱が止まる（v43.00 実機）。返事を組み立てるときは `McpJoin` / `McpJoinTree`（2 つずつ足す）を使う。1 フレームの計算が長すぎても同じ実行時エラーになるので、1 つの返事は 60 万文字まで（超えると `too_large`）、`debug.payload` は 30 万文字まで。
- Verse の実行時エラーが出ると、エディターに「An unrecoverable Verse runtime error occurred!」のダイアログが出て、閉じるまで MCP が応答しない（タイムアウトになる）。受け箱の `OnSimulate` も止まるので、直して `PushChanges` で入れ直す。
- Verse から entity の名前・component の型の名前は読めない（v43.00 時点）。`entity.components` は番号・有効か・MCP の受け口かだけを返す。名前は `mcp_name_component` で付ける。
- タグの名前は表（`mcp_tag_provider`）で知らせたものだけ使える。付け外し（`add_tag`）は `<concrete>` のタグだけ（具体的な型でないと Verse でタグを作れない）。ゲームのタグは `McpFindOnlyTagEntry`（探す・確かめるだけ）で知らせればよい。
- 画面はラウンドの中でだけ出る（WidgetSystem の決まり）。ラウンドの外では `widget.screens` は空、`press` は `not_shown`、`show` は `not_in_round`。
- `character` の `move_world` / `move_to` / `play` は walk の今の歩く向き（`GetWalkBasis`：`Space` と左右の入力のしかた）に合わせて世界の向きを入力に直す（`View` は Fortnite のキャラクターの視線。`TankTurn` は体の向きが前で、横の行き先へは回ってから進む）。ゲームが体を別の場所へ移したら（1 フレームで 800 cm 以上）歩かせるのをやめる（`moved_away`）。段差を登る処理は CharacterSystem に無い。
- 状態の書き出し・復元のマルチプレイ：プレイヤーは「その回の番号」で当てる（保存した人数より今が少なければ余りは捨て、多ければ足りない人はそのまま）。復元する位置どうしが `MinSeparationCm` より近ければ左へずらす（当たりの掃引はしない）。動く物（MoverSystem）は途中の位置へ戻す API が無いので入れていない。実行時に作ったもの（スポーンしたプレハブ）は入れていない。
- ⚠ 未検証：マルチプレイ（2 人以上）での番号・`widget` の人ごとの押下・状態の復元の重なり（`ClaimPosition` はテストで確かめただけ）。実機で通していないツール：`spawn` の出す・消す、`flow` の移る、`countdown` / `energy` の書き換え（確かめたゲームに部品が無い）、`pickup.pick` / `grant`、`entity.enable` / `disable` / `add_tag` / `remove_tag` / `activate` / `deactivate`、`player.teleport` / `join_group` / `leave_group` / `add_tag`。実機で通したもの：読み取り（list / state / find / info / get_transform / components / has_tag / screens など）、`widget.press` / `close` / `show`、`character.teleport` / `move_world` / `move_to` / `jump` / `play`（points）/ `record_start` / `record_stop`、`session.snapshot` / `restore`、`entity.move_by` / `set_transform`、`mover.pause` / `play` / `set_speed`、`pickup.hide` / `restore`、`debug` 全部。`mcp_role_tags.Remove` の型でのキャスト（`TagType[Tag]`）はテストで通した。
- 以前の記録では「`@editable` の値は届かない」だったことがある（v43.00 の 2026-11-01 頃）。届かない条件は未確認。

## 実測（UEFN v43.00、2026-11-08、検証用プロジェクト・1 人・Epic のサーバーのセッション）
| 項目 | 結果 |
|---|---|
| 1 件ずつ（`core.ping`、往復） | 平均 0.111〜0.118 秒（0.084〜0.153）、約 8〜9 件/秒 |
| まとめ送り（`core.echo`、`batch`） | 30 件 0.20 秒、100 件 0.38 秒、300 件 1.08 秒、1000 件 4.2 秒（誤り 0）。検証版（30 件 0.2・300 件 0.55・1000 件 2.8 秒）より遅いのは、返事 1 件が長い（to / tool / hits / f / t）・ツールの説明で引数を確かめるため（推測） |
| 大きい返事（`debug.payload`。行に入らない分は `~` の行に分かれる） | 1 万文字 0.18 秒、3 万文字 0.77 秒、10 万文字 3.7 秒（1 文字ずつ `+=` の版は 10 万文字 9.0 秒、`Concatenate` の版は 10 万文字で実行時エラー） |
| `core.describe`（14 ツールセット・114 ツール、約 2.1 万文字） | 0.8〜3.3 秒 |
| `widget.press`（ボタン）→ ゲームのログに開始の行が出るまで | 0.16〜0.17 秒（3 回） |
| ほかのツール（entity / player / character / widget / pickup / mover / session / debug の読み取り） | 0.11〜0.16 秒 |
| サーバーのフレーム（`debug.frames`） | 1 秒に 30 フレーム（1 フレーム 0.0334 秒） |
| `session.snapshot` / `restore`（characters・pickups・countdowns・energies） | 0.13 秒 / 0.11 秒。独自キャラクターの位置が書き出した値に戻った |
| `PushChanges(bVerseOnly=false)`（Verse・component の変更を実行中のセッションへ） | 91〜109 秒 |

## 確かめ方
- 型チェック：verse-standalone の `verse_check.py <Library> --profile fortnite --runtime runtime-uefn43`（既知の誤検出以外 0）。
- テスト：`_Test/MCPSystemTest/` の `mcp_system_test_component` を entity に 1 つ置いて始める（プレイヤー不要、1 秒）。JSON の小道具（逃がし・数の読み取り・範囲の確認）、`ExecuteJson` での振り分け（Core・宛先・インスタンス・複数・ツールの有無・省略できない引数・並びの引数・data の確かめ・batch・help・describe）、タグの名前の表、`mcp_role_tags`、`ClaimPosition` を確かめる。結果は `[TEST] MCPSystem`（v43.00 実機で 44 passed, 0 failed）。
- ライブ編集の経路：セッション中に `python -I mcp.py core.ping`。Python のテスト：`python -I tests\test_channel.py`（偽の受け箱。UEFN は要らない。どちらも MCPSystem パッケージのフォルダで）。

## 移行が要るもの（2026-11-08）
- 新しい System（既存の利用者に変更は要らない）。
- WidgetSystem に足したもの（互換あり）：`widget_view.AwaitClick(OnClick, ?ButtonId:string = "", ?Label:string = "")`、`AwaitChoice(Buttons, ?ButtonIds:[]string = array{})`、`GetWaitingButtons():[]widget_button_info`、`PressButton(Key:string):widget_press_result`、`widget_press_result`、`widget_button_info`（WidgetSystem の README の「移行」）。
- 検証版（Library に入れる前の試作）から：`McpName()` → `McpToolset()` / `McpId()`、`McpHandle(Cmd:string, Args:[]string)` → `McpHandle(Call:mcp_call)`（引数は `Call.Find*`）、`McpDescribe():string` → `McpTools():[]mcp_tool`、返事 `mcp_reply{Ok, Text}` に `Data` を足した、命令の `cmd` は `tool`（`cmd` も読む）、宛先 `inbox` は `core`（`inbox` も読む）。
