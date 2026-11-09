using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/UI }
using { /Fortnite.com/UI }
using { SceneGraphSystem }
using { WidgetSystem }
using { WidgetSystem.TooltipKit }

# Request to change the text of the text HUD
# Direction: from your component to the text_hud_component's entity (SendDown, or SendDown from an ancestor)
# Sender: your component. Receiver: text_hud_component. Not consumed
hud_text_request_event<public> := class(scene_event):
    # Whose text to change. false means everyone (including people shown later)
    Agent<public>:?agent = false
    # Text to show
    Text<public>:message

# Role: HUD that shows one line of text at a fixed screen position (does not take input). Shows the same text for everyone (SetText) or per-person text (SetTextFor). Empty text is invisible
# Placement: in the editor, attach to an entity. Who sees it and when is set on player_widget_component (Audience, ActiveOnBegin, activation signals)
# Notifications received: changes the text via hud_text_request_event (to change from other parts without writing code)
# From outside: SetText / SetTextFor / ClearTextFor
text_hud_component<public> := class<final_super>(player_widget_component):

    # Text shown at first
    @editable:
        ToolTip := TextHudTextToolTip
        Categories := array{TextHudCategory}
    Text<public>:string = ""
    # Position (horizontal screen ratio 0.0-1.0). Default 0.5
    @editable_number(float):
        ToolTip := WidgetPositionXToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionXRatio<public>:float = 0.5
    # Position (vertical screen ratio 0.0-1.0). Default 0.15
    @editable_number(float):
        ToolTip := WidgetPositionYToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    PositionYRatio<public>:float = 0.15
    # Text color. Default white
    @editable:
        ToolTip := TextHudColorToolTip
        Categories := array{TextHudCategory}
    TextColor<public>:color = NamedColors.White
    # Text size (pixels at 1080p). 0 uses Fortnite's default size. Default 0
    @editable_number(float):
        ToolTip := TextHudSizeToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{400.0}
    TextSize<public>:float = 0.0
    # Opacity of the panel behind the text (0.0-1.0). 0 shows no panel. Default 0
    @editable_number(float):
        ToolTip := TextHudBackgroundOpacityToolTip
        Categories := array{TextHudCategory}
        MinValue := option{0.0}
        MaxValue := option{1.0}
    BackgroundOpacity<public>:float = 0.0
    # Color of the panel behind the text. Default black
    @editable:
        ToolTip := TextHudBackgroundColorToolTip
        Categories := array{TextHudCategory}
    BackgroundColor<public>:color = NamedColors.Black

    var<private> SharedText:?message = false
    var<private> AgentTexts:[agent]message = map{}
    var<private> Blocks:[agent]text_block = map{}

    # Set everyone's text to Value (per-person text is cleared). People shown later also get this text
    SetText<public>(Value:message):void =
        set SharedText = option{Value}
        set AgentTexts = map{}
        for (Agent -> Block : Blocks):
            Block.SetText(Value)

    # Set only Agent's text to Value (takes priority over everyone's text)
    SetTextFor<public>(Agent:agent, Value:message):void =
        if (set AgentTexts[Agent] = Value) {}
        if (Block := Blocks[Agent]):
            Block.SetText(Value)

    # Clear Agent's per-person text and go back to everyone's text
    ClearTextFor<public>(Agent:agent):void =
        set AgentTexts = AgentTexts.RemoveKey(Agent)
        if (Block := Blocks[Agent]):
            Block.SetText(CurrentTextFor(Agent))

    OnReceive<override>(SceneEvent:scene_event):logic =
        if (Request := hud_text_request_event[SceneEvent]):
            if (Agent := Request.Agent?):
                SetTextFor(Agent, Request.Text)
            else:
                SetText(Request.Text)
        (super:)OnReceive(SceneEvent)

    CreateWidget<override>(View:widget_view):widget =
        Block := MakeStyledText(CurrentTextFor(View.Player), widget_text_style{Color := TextColor, Size := TextSize})
        if (set Blocks[View.Player] = Block) {}
        spawn{ForgetWhenHidden(View)}
        MakeScreenCanvas(MakePanel(Block, BackgroundColor, BackgroundOpacity, 16.0), PositionXRatio, PositionYRatio)

    CurrentTextFor<private>(Agent:agent):message =
        if (Value := AgentTexts[Agent]) then Value
        else if (Value := SharedText?) then Value
        else StringToMessage(Text)

    ForgetWhenHidden<private>(View:widget_view)<suspends>:void =
        View.HiddenEvent.Await()
        set Blocks = Blocks.RemoveKey(View.Player)
