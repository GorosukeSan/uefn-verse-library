# SceneGraphSystem

ほかの System が共通で使う、Scene Graph（entity / component）の小さな補助をまとめた System です。区画（`game_scope_component`）の中から「世界に 1 つ」の component を探す・探して覚える・見つかるまで待つ、区画全体へ知らせる、直下の子・一番近い祖先の component を探す、位置の計算、cancelable をまとめる、map から 1 件除く、などがあります。

## 置き方

| component | 置く場所 | すること |
|---|---|---|
| `game_scope_component` | 区画（1 つのゲームや部屋）の根にする entity | 区画の目印。この entity の配下で使う「世界に 1 つ」の仕組み（`player_manager_component`・`mode_select_component` など）は、区画の中だけで探される。付けなければ世界全体から探す |

ほかは component ではなく、関数とクラス（`cancelable_group`）です。

例：同じゲームを 2 つ並べる
```
世界
├ 部屋 A（game_scope_component）
│ ├ player_manager_component
│ └ ゲームの流れ …
└ 部屋 B（game_scope_component）
  ├ player_manager_component
  └ ゲームの流れ …
```
部屋 A の中の部品が `FindScopedComponent[player_manager_component]` で探すと、部屋 A のものが見つかります。部屋 A の中の部品が `SendScoped` で送った知らせは、部屋 B には届きません。

## 設定（@editable）
- 設定はありません。

## イベント
- この System の scene_event や listenable はありません。区画や世界へ送る関数（`SendScoped` / `SendGlobal`）を持ちます。

## 区画で 1 つを探して覚える
「区画の `player_manager_component` を探して、見つけたら覚える」処理は、覚える場所（`var<private> X:?型 = false`）を自分の component に持ち、`ResolveScopedComponent` で埋めます。
```verse
var<private> Manager:?player_manager_component = false

OnBeginSimulation<override>():void =
    (super:)OnBeginSimulation()
    # 覚えていればそのまま、無ければ区画（無ければ世界）から探す
    set Manager = Entity.ResolveScopedComponent(Manager, player_manager_component)

IsSatisfied<override>()<decides><transacts>:void =
    # <decides> の判定の中では探さない（失敗すると覚えたことも巻き戻る）
    Manager?.GetPlayerCount() >= 2

# 初めて見つけたときだけ購読・登録する
if (not Manager?, Found := Entity.ResolveScopedComponent(Manager, player_manager_component)?):
    set Manager = option{Found}
    Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)

# 見つかるまで待つ（1 秒ごとに探す）
OnSimulate<override>()<suspends>:void =
    Found := Entity.AwaitScopedComponent(player_manager_component)
```
止まるとき（`OnEndSimulation`）は `set Manager = false` で忘れます。

型引数を持つ入れ物のクラス（`scoped_lookup(t)` など）にしなかったのは、モジュールの名前の順で SceneGraphSystem より前のモジュール（ConditionSystem・PlayerSystem など）のフィールドに使うと、型チェックで V3502「Can't access a function from a preceding type」になるためです（関数は起きない）。ほかの System に型引数を持つクラスを足すときも同じことに気を付けます。

## 公開 API
```verse
# ScopeComponent
game_scope_component<public> := class<final_super>(component):
(InEntity:entity).FindScopeEntity<public>()<decides><transacts>:entity        # 自身か一番近い祖先の区画。無ければ失敗
(InEntity:entity).FindScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t   # 区画の配下。区画が無ければ世界
(InEntity:entity).SendScoped<public>(SceneEvent:scene_event):logic           # 区画の根から下へ。区画が無ければ SendGlobal

# ScopedLookup
(InEntity:entity).ResolveScopedComponent<public>(Known:?t, ComponentType:castable_subtype(t) where t:subtype(component))<transacts>:?t   # Known があればそれ、無ければ FindScopedComponent。見つからなければ false
(InEntity:entity).AwaitScopedComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<suspends>:t                 # 見つかるまで 1 秒ごとに FindScopedComponent

# AncestorComponent
(InEntity:entity).FindNearestAncestorComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t   # 自身か一番近い祖先。無ければ失敗

# WorldComponent
(InEntity:entity).FindWorldComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><transacts>:t    # simulation entity の配下
(InEntity:entity).SendGlobal<public>(SceneEvent:scene_event):logic           # simulation entity から下へ。まだ世界に入っていなければ false

# ChildComponent
(InEntity:entity).FindChildComponent<public>(ComponentType:castable_subtype(t) where t:subtype(component))<decides><reads>:t   # 直下の子だけ。最初の 1 つ
(InEntity:entity).GetChildComponents<public>(ComponentType:castable_subtype(t) where t:subtype(component))<reads>:[]t          # 直下の子だけ。無ければ空

# EntityTransform
MakeTranslationTransform<public>(Translation:vector3)<computes>:transform     # 回転なし、大きさ 1
(Transform:transform).WithTranslation<public>(Translation:vector3)<computes>:transform   # 回転と大きさはそのまま
(InEntity:entity).GetGlobalTranslation<public>()<transacts>:vector3           # 世界での位置（cm）
(InEntity:entity).ToLocalPosition<public>(WorldPosition:vector3)<transacts>:vector3   # 大きさが 0 の軸は 0

# Cancelable
cancelable_group<public> := class(cancelable):
    Cancelables<public>:[]cancelable = array{}
    Add<public>(Cancelable:cancelable)<transacts>:void     # Cancel 済みなら、足したものをその場で Cancel
    Cancel<override>()<transacts>:void                     # 2 回目以降は何もしない
(Subscription:?cancelable).CancelIfSet<public>()<transacts>:void   # 中身があれば Cancel

# MapHelpers
(Map:[k]v).RemoveKey<public>(Key:k where k:subtype(comparable), v:type)<transacts>:[k]v   # Key を除いた map を返す
```

## 前提・注意
- 区画は入れ子にできます（一番近い祖先の区画が使われる）。
- `FindScopedComponent` は、区画があれば区画の配下だけを探します。区画の中に無ければ、世界に置いてあっても見つからず失敗します（区画が無いときだけ世界全体を探す）。
- `FindScopedComponent` / `FindWorldComponent` は 1 つだけ置く前提で、複数あるとどれが返るかは決まりません。無いとき・`InEntity` がまだ世界に入っていないときは失敗します。区画や世界全体を探すので、毎フレーム呼ぶなら結果を覚えておきます。
- `SendScoped` / `SendGlobal` は、受け手のどれかが受け取った（`OnReceive` が true を返した）なら true を返します。`SendGlobal` は `InEntity` がまだ世界に入っていないと何も送らず、知らせもなく false を返します。
- `ResolveScopedComponent` は状態を持ちません（覚えるのは呼ぶ側のフィールド）。覚えた component が消されても気付きません。`AwaitScopedComponent` は見つかるまで 1 秒ごとに区画（または世界）を探します。
- `FindNearestAncestorComponent` は自身から親へ 1 つずつたどり、最初に見つかったものを返します。エンジンの `FindAncestorComponents` は並び順が決まっていないので、「一番近いもの」が要るときはこちらを使います。`FindScopeEntity`（PlayerSystem の `FindOwningSlot`・`FindAncestorGroup` も）はこれで探します。
- `FindChildComponent` / `GetChildComponents` は直下の子だけを見ます（孫は見ない）。子の並び順で返しますが、ライブラリの決まりでは並び順に意味を持たせません。
- `RemoveKey` は Verse の map に 1 件を消す操作が無いので、残りを詰め直した新しい map を返します。
- 実験的な API は使っていません。

## 確かめ方
- テスト：`_Test/SceneGraphSystemTest/` の `scene_graph_system_test_component`。entity A（`game_scope_component`）の下に `scope_test_marker_component`（`Label = "A"`）の entity と、テストの `ScopedChild` に入れる entity を置きます。entity B（`game_scope_component`）の下に `scope_test_marker_component`（`Label = "B"`）の entity を置きます。テストの component はどの区画にも入らない場所に置きます。`FindScopeEntity`（区画の中では見つかり、外では失敗する）、`FindScopedComponent`（区画 A の中では A の目印、区画の外では世界から見つかる）、`GetChildComponents`（直下だけを見る）、`FindNearestAncestorComponent`（実行時に作った入れ子で一番近いもの・自身を含む・無ければ失敗）、`ResolveScopedComponent`（区画 A で見つける・覚えたものはそのまま返す・無ければ false）を確かめます。開始の次のフレームで終わります。結果は出力ログの `[TEST] SceneGraphSystem`。
- 見本：`_Samples/ScopeSample/` の `scope_sample_component`。区画の中と外に置いて、自分の区画（`FindScopeEntity`）と、`FindScopedComponent[player_manager_component]` が区画の中・世界・無しのどれになるかを Print します。`OtherEntity` を入れると、その entity から探した結果が同じ `player_manager_component` かどうかも出します。`RepeatSeconds` を 0 より大きくすると繰り返し出します。出力ログの `[scope_sample]` を見ます。
