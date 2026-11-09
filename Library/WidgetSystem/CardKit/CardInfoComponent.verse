using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Role: holds the info used to show this entity as a card (name, description, badge, image, color, sort order). Card screens (card_menu_component, or a game's selection screen) take this component and build the card with GetCard
#   This component is the only owner of the name and sort order (do not keep the same values on other components). It does not hold per-person text (records, etc.); add that with WithSubtitle / WithBadge when showing
# Placement: in the editor, attach to the entity to be chosen as a card (a map root, a mode, an item, etc.)
# From outside: GetCard(Id) / GetTitle() / GetCardId(). To sort, SortCards (ascending Order)
card_info_component<public> := class<final_super>(component):

    # ID used when pressing from code (the button ID in card_menu_component; also used by MCPSystem's widget.press). Empty means Title; if that is also empty, an index the menu decides
    #   Set it here when a presser (tests, MCP) uses it, so the ID does not change when the name is renamed or translated
    @editable:
        ToolTip := CardIdToolTip
        Categories := array{CardInfoCategory}
    CardId<public>:string = ""

    # Name (if empty, GetTitle returns Fallback)
    @editable:
        ToolTip := CardTitleToolTip
        Categories := array{CardInfoCategory}
    Title<public>:string = ""
    # One line under the name (not shown if empty)
    @editable:
        ToolTip := CardSubtitleToolTip
        Categories := array{CardInfoCategory}
    Subtitle<public>:string = ""
    # Description (shown wrapped. Not shown if empty)
    @editable:
        ToolTip := CardDescriptionToolTip
        Categories := array{CardInfoCategory}
    Description<public>:string = ""
    # Small badge at the top right (difficulty, new, etc. Not shown if empty)
    @editable:
        ToolTip := CardBadgeToolTip
        Categories := array{CardInfoCategory}
    Badge<public>:string = ""
    # Image at the top (an AccentColor band if none)
    @editable:
        ToolTip := CardThumbnailToolTip
        Categories := array{CardInfoCategory}
    Thumbnail<public>:?texture = false
    # Card color (the band when there is no image, and the badge background)
    @editable:
        ToolTip := CardAccentColorToolTip
        Categories := array{CardInfoCategory}
    AccentColor<public>:color = NamedColors.SkyBlue
    # Sort order (smaller comes first). The order among equal values is undefined
    @editable_number(int):
        ToolTip := CardOrderToolTip
        Categories := array{CardInfoCategory}
        MinValue := option{-100000}
        MaxValue := option{100000}
    Order<public>:int = 0

    # Name. Fallback if empty
    GetTitle<public>(?Fallback:string = "")<transacts>:string =
        if (Title = "") then Fallback else Title

    # ID used when pressing from code. CardId, or Title if empty, or Fallback if that is also empty
    GetCardId<public>(?Fallback:string = "")<transacts>:string =
        if (CardId <> "") then CardId else GetTitle(?Fallback := Fallback)

    # Data for one card (Id is the ID used when pressing from code. If the name is empty, Id becomes the name)
    GetCard<public>(Id:string)<transacts>:widget_card =
        widget_card:
            Id := Id
            Title := GetTitle(?Fallback := Id)
            Subtitle := Subtitle
            Description := Description
            Badge := Badge
            Image := Thumbnail
            AccentColor := AccentColor

# Sort Infos by ascending Order (insertion sort. Equal Order keeps the order found. Up to a few dozen)
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
