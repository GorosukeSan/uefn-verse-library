using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { SceneGraphSystem }

# プレイヤーの状態をタグで表す。
# 状態を持つ System は、そのあいだプレイヤー（agent。v43 では agent も entity なのでタグを持てる）にタグを付け、終わったら外す。
# キャラクターの entity ではなく agent に付けるので、スポーン前・倒れているあいだ・リスポーンのあとも消えない。
# ほかの System はその System を知らなくても、Agent.HasPlayerTag[タグの型] で状態を確かめられる（例：ホバーは「動きを操られている」なら浮かない）。
# 付けるのは player_tag_holder を通す（自分が付けた分だけを外し、ほかの部品が付けた同じ型のタグは残す）。
# ⚠ 未検証：agent に付けたタグの付け外し・ContainsTag が UEFN 43.00 の実機で動くか（digest では agent は entity の派生で、entity は has_tags）。_Test の PlayerSystemTest で確かめる

# プレイヤーの状態を表すタグの基底。状態ごとにこの派生を作る。
# 派生で付けたタグは基底の型でも見つかる（Agent.HasPlayerTag[player_state_tag] は「何かの状態にある」）
player_state_tag<public> := class<abstract>(tag):

# 能力などがプレイヤーの動き（速度・位置）を直接操っているあいだ付くタグ。
# ほかの力（引力・ホバーなど）は、これが付いている人の速度を書き換えない。
# 例：スイング中（SwingSystem の swinging_tag はこの派生）。自分で動きを操る能力を作るときもこの派生を付ける
controlled_movement_tag<public> := class(player_state_tag):

# Agent に TagType（またはその派生）のタグが付いていれば成功する
(Agent:agent).HasPlayerTag<public>(TagType:castable_subtype(tag))<decides><reads>:void =
    Agent.ContainsTag[TagType]

# 1 つの部品がプレイヤーに付けたタグを人ごとに覚えておき、あとで自分の付けた分だけを外す。
# 同じ人に同じ型のタグをほかの部品も付けていても、そちらは消さない。
# 使い方：Tags:player_tag_holder = player_tag_holder{} を持ち、状態に入ったら Tags.Add(Agent, hovering_tag{})、
#   抜けたら Tags.Remove(Agent)、止まるとき（OnEndSimulation・能力の defer）に Tags.RemoveAll()
player_tag_holder<public> := class:
    var<private> Keys:[agent]tag_key = map{}

    # Agent に Tag を付ける。このholderで付けたタグがもうあれば何もしない。Tag は呼ぶたびに作ったもの（hovering_tag{} など）を渡す
    Add<public>(Agent:agent, Tag:tag)<transacts>:void =
        if (not Keys[Agent]):
            if (set Keys[Agent] = Agent.AddTag(Tag)) {}

    # このholderで Agent に付けたタグを外す（付けていなければ何もしない）
    Remove<public>(Agent:agent)<transacts>:void =
        if (Key := Keys[Agent]):
            if (Agent.RemoveTag[Key]) {}
            set Keys = Keys.RemoveKey(Agent)

    # On なら Add、そうでなければ Remove
    Set<public>(Agent:agent, On:logic, Tag:tag)<transacts>:void =
        if (On?):
            Add(Agent, Tag)
        else:
            Remove(Agent)

    # このholderで Agent にタグを付けていれば成功する
    Has<public>(Agent:agent)<decides><reads>:void =
        Keys[Agent]

    # このholderで付けたタグをすべて外す
    RemoveAll<public>()<transacts>:void =
        for (Agent -> Key : Keys):
            if (Agent.RemoveTag[Key]) {}
        set Keys = map{}
