# FNDeviceSystem

Fortnite のクリエイティブ デバイス（`creative_device`）に頼る処理をまとめた System です。起動・停止の合図（ActivationSystem）と、デバイスでしかできないこと（トリガー・ゲーム終了・職業とチーム・スコア・シネマティック シーケンス・音）をつなぎます。Library の中でデバイスに依存するのはこの System だけです。ほかの System でデバイスを使いたいときは、この System の部品を置きます。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `device_trigger_component` | 合図が届く entity（ノード、インタラクト・ボリューム・メニューの `Targets` など） | 起動の合図で `Trigger` のトリガー デバイスを鳴らす（起こした人が分かればその人で）。停止の合図で `StopTrigger` を鳴らす |
| `device_event_component` | どこでもよい。`Targets` が空なら、この entity と子孫が送り先 | `Trigger` のトリガー デバイスが鳴るたびに、`Targets` へ起動の合図を送る（鳴らした人が分かれば `activated_by_agent_event`） |
| `device_end_game_component` | 合図が届く entity（ゴールのボリューム、流れの最後のノードなど） | 起動の合図で、ゲーム終了デバイスを `Recipients` に `Activate` する |
| `device_class_component` | 合図が届く entity。ロードアウト（LoadoutSystem）の中に置いてもよい | 起動の合図で、職業とチームの選択デバイスで `Recipients` の職業・チームを変える |
| `device_score_component` | 合図が届く entity（コイン・ゴールなど） | 起動の合図で、スコア マネージャー デバイスを `Recipients` に使う |
| `device_sequence_component` | 合図が届く entity | 起動の合図でシネマティック シーケンス デバイスを再生し、停止の合図で止める |
| `device_audio_component` | 合図が届く entity | 起動の合図でオーディオ プレイヤー デバイスを鳴らし、停止の合図で止める |
| `schedule_sequence_component`（ScheduleKit） | `schedule_component`（ScheduleSystem）の entity かその子孫 | スケジュールが Active のあいだシネマティック シーケンス デバイスを再生し、期間の途中なら経過時間に合わせる |

デバイスはレベルに置いたものを `@editable` で選びます。1 つの部品で選べるデバイスは 1 つです（デバイスの配列は MCP で書けないため）。複数のデバイスを使うときは、子の entity に部品を 1 つずつ置きます。

例：「ゴールのボリュームに入った人を勝ちにして、スコアも足す」
```
ゴール（player_volume_component + volume_activation_component）
├ 終了（device_end_game_component、EndGame = ゲーム終了デバイス、Recipients = Activator）
└ 加点（device_score_component、ScoreManager = スコア マネージャー デバイス、Change = Award）
```
`volume_activation_component` は最初の 1 人が入ったとき、その人の分かる起動の合図（`activated_by_agent_event`）を子の entity へ送ります。子の部品はその人に対してデバイスを使います。

## 設定（@editable）
- `device_trigger_component.Trigger : ?trigger_device = false` — 起動の合図で鳴らすトリガー デバイス。
- `device_trigger_component.StopTrigger : ?trigger_device = false` — 停止の合図で鳴らすトリガー デバイス（だれでもなく鳴らす）。
- `device_event_component.Trigger : ?trigger_device = false` — 鳴ったら合図を送るトリガー デバイス。
- `device_event_component.Targets : []entity = array{}` — 起動の合図を送る entity。空なら、この entity とその子孫。
- `device_end_game_component.EndGame : ?end_game_device = false` — 終わらせるゲーム終了デバイス（勝ち負けの設定はデバイス側）。
- `device_end_game_component.Recipients : device_target_agents = Activator` — だれに対して終えるか。
- `device_class_component.Selector : ?class_and_team_selector_device = false` — 使う職業とチームの選択デバイス（どの職業・チームにするかはデバイス側）。
- `device_class_component.Change : device_class_change = Class` — 何を変えるか（`Class` / `Team` / `TeamAndClass`）。
- `device_class_component.Recipients : device_target_agents = Owner` — だれを変えるか。
- `device_score_component.ScoreManager : ?score_manager_device = false` — 使うスコア マネージャー デバイス（点数はデバイス側）。
- `device_score_component.Change : device_score_change = Award` — `Award` はデバイスの設定どおりに加点（`Activate`）、`Increment` / `Decrement` は 1 段上げ下げ。
- `device_score_component.Recipients : device_target_agents = Activator` — だれのスコアを変えるか。
- `device_sequence_component.Sequence : ?cinematic_sequence_device = false` — 再生するシネマティック シーケンス デバイス。
- `device_audio_component.AudioPlayer : ?audio_player_device = false` — 鳴らすオーディオ プレイヤー デバイス。
- `device_sequence_component` / `device_audio_component` の `Scope : device_play_scope = Everyone` — `Everyone` は全員に（デバイスの Visibility の設定に従う）、`Activator` は合図を起こした人にだけ（`Play(Agent)`。デバイスの Visibility を Instigator にしておく。起こした人が分からなければ全員に）。
- `device_sequence_component` / `device_audio_component` の `StopOnDeactivate : logic = true` — オンなら停止の合図で止める。
- `schedule_sequence_component.Sequence : ?cinematic_sequence_device = false` — 期間中に再生するデバイス（Visibility = Everyone のもの）。
- `schedule_sequence_component.MaxLateStartSeconds : float = 0.0` — 期間に入った時点で開始からこの秒数より経っていたら再生しない（0 以上。0 なら制限なし）。
- `schedule_sequence_component.ResyncOnPlayerJoin : logic = true` — オンなら期間中にプレイヤーが参加するたびに、Play し直して経過時間に合わせる。

`Recipients`（`device_target_agents`）の意味：
- `Activator` — 合図を起こした人（`activated_by_agent_event` の `Agent`）。分からなければ何もしない。
- `Owner` — 持ち主（slot の下に置いたとき）。いなければ合図を起こした人。どちらも無ければ何もしない。
- `Everyone` — 区画（または世界）の `player_manager_component` の slot にいる全員。見つからなければ何もしない。

## イベント
この System は scene_event の型を作りません。送る・受けるのは ActivationSystem の起動・停止の合図です。
- `device_event_component.TriggeredEvent : listenable(?agent)` — `Trigger` が鳴るたびに、鳴らした人（分からなければ false）で届く。
- 送るもの: `device_event_component` は、鳴るたびに `Targets`（空なら自分の entity）から下へ `activated_by_agent_event`（鳴らした人が分かるとき。`SendActivatedBy`）か `activated_event`（`SendActivated`）を送る。停止の合図は送らない。
- 受けるもの: `device_trigger_component` / `device_sequence_component` / `device_audio_component` は `activated_event` と `deactivated_event`。`device_end_game_component` / `device_class_component` / `device_score_component` は `activated_event` だけ。どれも `FindActivatingAgent[]` で起こした人を読む。どれも消費しない。
- `schedule_sequence_component` は合図を受けません。一番近い `schedule_component` の状態の変化（`StateChangedEvent`）を `schedule_follower` で受けます。

## 持ち主
- `device_target_agents.Owner` を選んだ部品（`device_class_component` の既定）は、プレイヤーの slot の下（LoadoutSystem のロードアウトの中など）に置くと持ち主（`FindOwningPlayer`）に対して使います。slot の下に無ければ合図を起こした人に使います。
- ロードアウトは作った次のフレームに配下へ起動の合図を送るので、ロードアウトの中の `device_class_component` は、ロードアウトを付けたときに持ち主の職業を変えます。
- `Activator` / `Everyone` を選んだ部品と、`device_trigger_component` / `device_event_component` / `device_sequence_component` / `device_audio_component` / `schedule_sequence_component` は、持ち主がいても動きを変えません。

## 公開 API
```verse
device_trigger_component<public> := class<final_super>(component):
    Trigger<public>:?trigger_device
    StopTrigger<public>:?trigger_device
    Fire<public>():void                                     # Trigger をだれでもなく鳴らす
    FireFor<public>(Agent:agent):void                       # Trigger を Agent が起こしたものとして鳴らす

device_event_component<public> := class<final_super>(component):
    Trigger<public>:?trigger_device
    Targets<public>:[]entity
    TriggeredEvent<public><final>:listenable(?agent)

device_target_agents<public> := enum:
    Activator
    Owner
    Everyone

device_end_game_component<public> := class<final_super>(component):
    EndGame<public>:?end_game_device
    Recipients<public>:device_target_agents

device_class_change<public> := enum:
    Class
    Team
    TeamAndClass

device_class_component<public> := class<final_super>(component):
    Selector<public>:?class_and_team_selector_device
    Change<public>:device_class_change
    Recipients<public>:device_target_agents

device_score_change<public> := enum:
    Award
    Increment
    Decrement

device_score_component<public> := class<final_super>(component):
    ScoreManager<public>:?score_manager_device
    Change<public>:device_score_change
    Recipients<public>:device_target_agents

device_play_scope<public> := enum:
    Everyone
    Activator

device_sequence_component<public> := class<final_super>(component):
    Sequence<public>:?cinematic_sequence_device
    Scope<public>:device_play_scope
    StopOnDeactivate<public>:logic
    Play<public>():void                                     # （全員に）再生する
    Stop<public>():void                                     # 止める

device_audio_component<public> := class<final_super>(component):
    AudioPlayer<public>:?audio_player_device
    Scope<public>:device_play_scope
    StopOnDeactivate<public>:logic
    Play<public>():void                                     # （全員に）鳴らす
    Stop<public>():void                                     # 止める

# ScheduleKit
schedule_sequence_component<public> := class<final_super>(component):
    Sequence<public>:?cinematic_sequence_device
    MaxLateStartSeconds<public>:float
    ResyncOnPlayerJoin<public>:logic
    IsPlaying<public>()<decides><transacts>:void            # 再生しているあいだ成功する
    Resync<public>():void                                   # 再生中なら今の経過時間に合わせ直す。再生していなければ何もしない
```

## 前提・注意
- デバイスはレベルに置き、component の `@editable` で選びます。デバイス側の設定（勝ち負け・職業・点数・Visibility など）はデバイスで決めます。
- デバイスの `@editable` はどれも 1 つずつ（`?デバイスの型`）です。デバイスの配列は MCP で書けないためです。複数のデバイスを使うときは、子の entity に部品を 1 つずつ置きます（例：トリガー デバイスを 3 つ鳴らすなら、合図が届く entity の子に `device_trigger_component` を 3 つ、それぞれ別の entity に置く）。
- MCP でレベルを組むとき：Fortnite 標準の `input_action` / `input_mapping`（`Character.Jump`・`TraversalMapping` など）は、MCP の `SetComponentProperty` で参照として設定できません。コードの既定値として使うのはかまいません。別のものにしたいときはエディターで選びます。文字列の配列（`choice_menu_component.Options` など）は、MCP では長さと中身を同時に変えられないので、いったん空にしてから入れ直します。
- `device_trigger_component` の停止の合図（`StopTrigger`）と `Fire` は、だれでもなく鳴らします。起こした人が要るデバイスの設定には `FireFor` か、起こした人の分かる合図を使います。
- `device_event_component` は起動の合図だけを送ります。停止させたいときは別の部品から停止の合図を送ります。
- `device_end_game_component` などの `Recipients = Activator` は、起こした人の分からない合図（`activated_event` だけ。ゲームの流れのノードに入ったときなど）では何もしません。だれにでも効かせたいときは `Everyone` にします。`Everyone` には区画（または世界）に `player_manager_component` が要ります。
- `device_sequence_component` / `device_audio_component` の `Play` / `Stop`（コードから呼ぶもの）は、`Scope` に関係なく全員に対して呼びます。
- デバイスを選んでいない（`false` のまま）部品は、合図を受けても何もしません（Print もしません）。
- `schedule_sequence_component`（`FNDeviceSystem/ScheduleKit/ScheduleSequenceComponent.verse`）は ScheduleSystem から移ってきました。ScheduleSystem の `schedule_follower` で、自分の entity か一番近い祖先の `schedule_component` を見ます。見つからなければ Print して何もしません。ツールチップとカテゴリは ScheduleSystem の TooltipKit（`ScheduleCategory` など）を使います。
- `schedule_sequence_component` は実機で確かめていない点があります（コードの `前提・注意（実機で確認すること）`）：
  - 途中参加の人に映像が合うかはデバイス側の仕様に依ります。`ResyncOnPlayerJoin` がオンなら参加のたびに Play ＋ `SetPlaybackTime` をやり直すので、全員の再生が一瞬跳ねるかもしれません。合わないなら、人ごとのデバイス（Visibility = Instigator）を人数分用意して `Play(Agent)` する作りに変えます。
  - `SetPlaybackTime` は Play の直後に呼びます。経過が 0.5 秒未満なら呼びません。
  - シーケンスが Active の長さより短いと、終わったあとは止まったままです（ループは設定しません）。
  - `ResyncOnPlayerJoin` には区画（または世界）に `player_manager_component` が要ります（無いと参加で合わせ直しません）。
- この System は `@experimental` の API を使っていません。

## 確かめ方
- `_Test/FNDeviceSystemTest/` はありません（デバイスはレベルに置いたものを選ぶので、テストが実行時に作れません）。この System の component を使うテストも `_Test` にはありません。`_Samples/` にも見本はありません。
- 確かめるときは、UEFN でデバイスをレベルに置き、合図の送り手（`interact_trigger_component`・`volume_activation_component`・ゲームの流れのノードなど）の配下にこの System の component を置いて動かします。
- 関係するもの：`schedule_sequence_component` が見るスケジュールの側は `_Test/ScheduleSystemTest/`、`Everyone` などが使う区画での探し方（`FindScopedComponent[player_manager_component]`）は `_Samples/ScopeSample/` で確かめられます。起こした人の分かる合図（`activated_by_agent_event` / `FindActivatingAgent`）を確かめるテストは今のところありません。
