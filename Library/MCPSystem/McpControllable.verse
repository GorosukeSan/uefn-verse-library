using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /Verse.org/SpatialMath }
using { /UnrealEngine.com/JSON }
using { MCPSystem.TooltipKit }

# 命令を受けられる部品の entity に付ける役割のタグ。受け箱（mcp_inbox_component）はこのタグの entity の component から mcp_controllable を集める
# 付けるのは mcp_controllable を実装した component 自身（OnBeginSimulation で付け、OnEndSimulation で外す。MCP はタグを書けないため）
mcp_controllable_tag<public> := class<concrete>(tag){}

# 命令の受け口（ツールセット）。component が実装し、自分の entity に mcp_controllable_tag を付ける
#   宛先 "to" は "ツールセット" か "ツールセット@インスタンス"（同じツールセットの部品が複数あるとき。インスタンスは McpId）
#   受け箱は、宣言にないツール（unknown_tool）と、省略できない引数が無いとき（bad_args）を、McpHandle を呼ぶ前に返す
mcp_controllable<public> := interface:
    # ツールセットの名前（"entity" / "widget" など。英小文字）
    McpToolset<public>()<transacts>:string
    # インスタンスの名前（空なら "ツールセット" だけで届く。"ツールセット@名前" でも届く）
    McpId<public>()<transacts>:string
    # 受けられるツールの説明（describe が集める）
    McpTools<public>()<transacts>:[]mcp_tool
    # ツールを実行して返事を返す。同じフレームで終わらないものは spawn してすぐ "accepted" を返し、終わったら Call.Notify で知らせる
    #   何度実行しても同じ結果になる形にする（受け箱が作り直されると、返事を見る前の命令がもう一度届くことがある）
    #   読んだ値を信用しない（失敗しうる変換は Call.Find*[] / if の中で。範囲を確かめる）
    McpHandle<public>(Call:mcp_call):mcp_reply

# ---- 名前（Verse は entity の名前を読めないので、MCP から名前で指す entity にはこれを付ける） ----

# mcp_name_component が自分の entity に付けるタグ
mcp_name_tag<public> := class<concrete>(tag){}

# 役割：entity に MCP から指せる名前を付ける（entity.find の name、引数の "entity":"<名前>"、widget の画面・session のキーなど）
# 置き方：名前で指したい entity に付ける。同じ名前が複数あってもよい（探すと全部返る。引数で 1 つを指すときは最初に見つけたもの）
mcp_name_component<public> := class<final_super>(component):
    # 名前（英数字を勧める。空なら付けていないのと同じ）
    @editable:
        ToolTip := McpNameToolTip
        Categories := array{McpCategory}
    McpName<public>:string = ""

    var<private> TagKey:?tag_key = false

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        set TagKey = option{Entity.AddTag(mcp_name_tag{})}

    OnEndSimulation<override>():void =
        if (Key := TagKey?, Entity.RemoveTag[Key]) {}
        set TagKey = false
        (super:)OnEndSimulation()

# InEntity に付いた mcp_name_component の名前。無ければ空
(InEntity:entity).GetMcpName<public>()<reads>:string =
    if (Named := InEntity.GetComponent[mcp_name_component]) then Named.McpName else ""

# ---- タグの名前（Verse のタグは型なので、文字列から探すには名前と型の表が要る） ----

# 名前を付けたタグの型。Concrete があれば付け外しにも使える（抽象のタグは探す・確かめるだけ）
mcp_tag_entry<public> := class<final>:
    Name<public>:string
    TagType<public>:castable_subtype(tag)
    Concrete<public>:?castable_concrete_subtype(tag) = false

# 探す・付け外しに使えるタグ（具体的な型）
McpTagEntry<public>(Name:string, TagType:castable_concrete_subtype(tag))<transacts>:mcp_tag_entry =
    mcp_tag_entry{Name := Name, TagType := TagType, Concrete := option{TagType}}

# 探す・確かめるだけのタグ（抽象の基底など）
McpFindOnlyTagEntry<public>(Name:string, TagType:castable_subtype(tag))<transacts>:mcp_tag_entry =
    mcp_tag_entry{Name := Name, TagType := TagType}

# タグの名前を MCP に知らせる部品が実装する（entity.find / player.has_tag などがタグの名前を型に直すときに集める）
#   実装した component の entity には mcp_controllable_tag を付ける（受け箱がそのタグで集める。mcp_controllable を実装しなくてよい）
mcp_tag_provider<public> := interface:
    McpTagEntries<public>()<transacts>:[]mcp_tag_entry

# Entry のタグの型から新しいタグを作る。抽象のタグ（Concrete が無い）なら失敗する
(Entry:mcp_tag_entry).MakeTag<public>()<transacts><decides>:tag =
    TagType:castable_concrete_subtype(tag) = Entry.Concrete?
    TagType{}

# ---- 状態の書き出し・復元（session_restorable の土台。SessionKit の session ツールセットが集める） ----

# 状態を書き出し・戻せる部品の entity に付ける役割のタグ（実装した component 自身が付ける）
mcp_session_restorable_tag<public> := class<concrete>(tag){}

# 状態を JSON に書き出し、JSON から戻せる部品が実装する（DESIGN の session_restorable）
#   キーはセッションをまたいで変わらないもの（"character"、名前・置いた位置から作る "countdown@race" など）
mcp_session_restorable<public> := interface:
    # 変わらないキー（同じキーが複数あると、後に集めたものが上書きする）
    McpSessionKey<public>()<transacts>:string
    # 今の状態を JSON の文字列（オブジェクトか配列）にする
    McpSessionSave<public>(Context:mcp_session_context):string
    # State（McpSessionSave が返した JSON を読み直したもの）に戻す。結果を短い文で返す（"ok" か、戻せなかった理由）
    McpSessionRestore<public>(Context:mcp_session_context, State:value):string

# 書き出し・復元のときに渡す情報。プレイヤーは「その回の番号」（core.players の並び）で当てる
#   保存した人数より今が少なければ余りは捨て、多ければ足りない人はそのまま（決めた規則。README）
#   復元する位置どうしが MinSeparationCm より近いときは、ClaimPosition が左（Left）へずらす（当たりの掃引はしない）
mcp_session_context<public> := class<internal>:
    # 今のプレイヤー（番号の順）
    Players<public>:[]player
    # 復元する位置どうしを離す距離（cm）
    MinSeparationCm<public>:float = 120.0

    var<private> Claimed:[]vector3 = array{}

    # Desired に置いてよい位置を返し、使った位置として覚える。もう覚えた位置と近ければ、左へ MinSeparationCm ずつ（最大 16 回）ずらす
    ClaimPosition<public>(Desired:vector3)<transacts>:vector3 =
        var Position:vector3 = Desired
        var Tries:int = 0
        loop:
            if (Tries >= 16 or not IsCrowded[Position]):
                break
            set Tries += 1
            set Position = Desired + vector3{Left := MinSeparationCm * (Tries * 1.0)}
        set Claimed += array{Position}
        Position

    IsCrowded<private>(Position:vector3)<transacts><decides>:void =
        Near := for (Other : Claimed, DistanceSquared(Other, Position) < MinSeparationCm * MinSeparationCm) { Other }
        Near.Length > 0

    # 番号 Index のプレイヤー。いなければ失敗する
    FindPlayer<public>(Index:int)<transacts><decides>:player =
        Players[Index]

# mcp_session_context を作る（SessionKit 以外から書き出し・復元を呼ぶとき・テスト）
MakeMcpSessionContext<public>(Players:[]player, MinSeparationCm:float)<transacts>:mcp_session_context =
    mcp_session_context{Players := Players, MinSeparationCm := MinSeparationCm}

# 置いた位置からキーを作る（"@left,up,forward" の cm を丸めた値）。名前の無い部品のキーに使う（置いた物は動かないかぎり同じキーになる）
McpPositionKey<public>(Position:vector3)<transacts>:string =
    "@{McpRoundText(Position.Left)},{McpRoundText(Position.Up)},{McpRoundText(Position.Forward)}"

# 名前があれば名前、無ければ置いた位置のキー
(InEntity:entity).GetMcpKey<public>()<transacts>:string =
    Name := InEntity.GetMcpName()
    if (Name <> "") then Name else McpPositionKey(InEntity.GetGlobalTransform().Translation)

# float を四捨五入した整数の文字（範囲外・有限でないなら "x"）
McpRoundText<public>(F:float)<transacts>:string =
    if (F.IsFinite[], F > -9.0e15, F < 9.0e15, R := Round[F]) then "{R}" else "x"

# 1 つの component が entity に付けたタグを覚えておき、止まるときに自分の付けた分だけ外す（ツールセットの component が mcp_controllable_tag を付けるときなどに使う）
# 使い方：RoleTags:mcp_role_tags = mcp_role_tags{} を持ち、OnBeginSimulation で RoleTags.Add(Entity, mcp_controllable_tag{})、OnEndSimulation で RoleTags.RemoveAll()
mcp_role_tags<public> := class:
    var<private> Keys:[]tuple(entity, tag_key, tag) = array{}

    # Target に Tag を付ける（Tag は呼ぶたびに作ったものを渡す）
    Add<public>(Target:entity, Tag:tag)<transacts>:void =
        set Keys += array{(Target, Target.AddTag(Tag), Tag)}

    # Target に付けたタグのうち、TagType の型（派生を含む）のものを外す。1 つでも外したら成功する
    Remove<public>(Target:entity, TagType:castable_subtype(tag))<transacts><decides>:void =
        var Kept:[]tuple(entity, tag_key, tag) = array{}
        var Removed:int = 0
        for (Item : Keys):
            if (Item(0) = Target, TagType[Item(2)]):
                if (Target.RemoveTag[Item(1)]) {}
                set Removed += 1
            else:
                set Kept += array{Item}
        set Keys = Kept
        Removed > 0

    # この holder で付けたタグをすべて外す
    RemoveAll<public>()<transacts>:void =
        for (Item : Keys):
            if (Item(0).RemoveTag[Item(1)]) {}
        set Keys = array{}

    # 付けている数
    GetCount<public>()<transacts>:int = Keys.Length
