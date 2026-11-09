using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# 役割：この entity をカードで見せるときの情報（名前・説明・札・画像・色・並び順）を持つ。カードの画面（card_menu_component や、ゲームの選択画面）は、この component を取って GetCard でカードを作る
#   名前や並び順の持ち主はこの component だけにする（ほかの component に同じ値を持たせない）。人ごとに変わる文字（記録など）は持たない（出すときに WithSubtitle / WithBadge で足す）
# 置き方：エディターで、カードで選ばせたい entity（マップの根・モード・品物など）に付ける
# 外から：GetCard(Id) / GetTitle()。並べるときは SortCards（Order の小さい順）
card_info_component<public> := class<final_super>(component):

    # 名前（空なら、GetTitle は Fallback を返す）
    @editable:
        ToolTip := CardTitleToolTip
        Categories := array{CardInfoCategory}
    Title<public>:string = ""
    # 名前の下の 1 行（空なら出さない）
    @editable:
        ToolTip := CardSubtitleToolTip
        Categories := array{CardInfoCategory}
    Subtitle<public>:string = ""
    # 説明（折り返して出す。空なら出さない）
    @editable:
        ToolTip := CardDescriptionToolTip
        Categories := array{CardInfoCategory}
    Description<public>:string = ""
    # 右上の小さい札（難しさ・新着など。空なら出さない）
    @editable:
        ToolTip := CardBadgeToolTip
        Categories := array{CardInfoCategory}
    Badge<public>:string = ""
    # 上の画像（無ければ AccentColor の帯）
    @editable:
        ToolTip := CardThumbnailToolTip
        Categories := array{CardInfoCategory}
    Thumbnail<public>:?texture = false
    # カードの色（画像が無いときの帯・札の地）
    @editable:
        ToolTip := CardAccentColorToolTip
        Categories := array{CardInfoCategory}
    AccentColor<public>:color = NamedColors.SkyBlue
    # 並び順（小さいほど先）。同じ値どうしの順は決まらない
    @editable_number(int):
        ToolTip := CardOrderToolTip
        Categories := array{CardInfoCategory}
        MinValue := option{-100000}
        MaxValue := option{100000}
    Order<public>:int = 0

    # 名前。空なら Fallback
    GetTitle<public>(?Fallback:string = "")<transacts>:string =
        if (Title = "") then Fallback else Title

    # カード 1 枚分のデータ（Id はコードから押すときの ID。名前が空なら Id を名前にする）
    GetCard<public>(Id:string)<transacts>:widget_card =
        widget_card:
            Id := Id
            Title := GetTitle(?Fallback := Id)
            Subtitle := Subtitle
            Description := Description
            Badge := Badge
            Image := Thumbnail
            AccentColor := AccentColor

# Infos を Order の小さい順に並べる（挿入ソート。同じ Order は先に見つけた順。数十まで）
SortCards<public>(Infos:[]card_info_component)<transacts>:[]card_info_component =
    var Sorted:[]card_info_component = array{}
    for (Info : Infos):
        var Inserted:[]card_info_component = array{}
        var Placed:logic = false
        for (Other : Sorted):
            if (not Placed?, Info.Order < Other.Order):
                set Inserted += array{Info}
                set Placed = true
            set Inserted += array{Other}
        if (not Placed?):
            set Inserted += array{Info}
        set Sorted = Inserted
    Sorted
