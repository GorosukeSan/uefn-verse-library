using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Colors }
using { /Verse.org/Input }
using { /Verse.org/Input/UI }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Input }
using { /Fortnite.com/UI }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { ActivationSystem }
using { InputSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# Screen texts
InputSampleTitle<localizes>:message = "Input sample"
InputSampleStepMessage<localizes>(Index:int, Total:int, Action:string):message = "{Index} / {Total}   {Action}"
InputSampleMappingMessage<localizes>(Mapping:string):message = "Mapping: {Mapping}"
InputSampleKeyMessage<localizes>(Key:string):message = "Key: {Key} (default binding; differs if changed in the settings)"
InputSampleNoteMessage<localizes>(Note:string):message = "{Note}"
InputSampleWaiting<localizes>(Seconds:int):message = "Input: press this input (switches to the next every {Seconds} s)"
InputSampleDetected<localizes>:message = "Input: detected"
InputSampleNotDetectable<localizes>:message = "Input: this Mapping has no input action that Verse can detect"
InputSampleButtonMessage<localizes>(Mapping:string, Action:string):message = "{Mapping}\n{Action}"
InputSampleButtonWaiting<localizes>:message = "Button: waiting for a Click on the button at the left (no focus; TriggeringInputAction can press it)"
InputSampleButtonClicked<localizes>:message = "Button: Click detected"
InputSampleButtonNoAction<localizes>:message = "Button: this input cannot be assigned to a button (logic input_actions only)"

# Role: one input that input_sample_component checks in turn. Holds either LogicAction or VectorAction (display only when neither)
input_sample_step<public> := class:
    # Input action name shown on screen
    Label<public>:string
    # Mapping name shown on screen
    MappingLabel<public>:string
    # Name of the key to press (keyboard / gamepad). The current binding cannot be read from Verse, so the default key is written
    KeyName<public>:string = ""
    # Extra note
    Note<public>:string = ""
    # Mapping added during this step. Character-control Mappings are enabled by default, so they are not added
    Mapping<public>:?input_mapping = false
    # Whether to remove the Mapping when the step ends. A Mapping whose default state is unknown (InteractMapping) is not removed
    RemoveMappingAfter<public>:logic = false
    # Input detected by a press (logic; BeginDetectEvent = waits for the moment of the press)
    LogicAction<public>:?input_action(logic) = false
    # Input whose value is a vector3 (Move, PointerSelect, PointerZoom; waits for TriggerActivationEvent)
    VectorAction<public>:?input_action((/Verse.org/SpatialMath:)vector3) = false

    # Whether there is a detectable input
    IsDetectable<public>()<decides><transacts>:void =
        LogicAction? or VectorAction?

    # Wait until the input arrives. Never returns when there is no detectable input
    AwaitTrigger<public>(PlayerInput:player_input)<suspends>:void =
        if (Action := LogicAction?):
            PlayerInput.AwaitPressed(Action)
        else if (Action := VectorAction?):
            Triggered := PlayerInput.GetInputEvents(Action).TriggerActivationEvent.Await()
        else:
            Sleep(Inf)

# Role: one player's check screen (Verse UI without a Widget Blueprint). The input mode stays None (HUD), so it also checks whether button_loud's TriggeringInputAction works on a screen without focus
input_sample_widget<public> := class:

    StepText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    MappingText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    KeyText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    NoteText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    ResultText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    ButtonResultText<public>:text_block = text_block{DefaultTextColor := NamedColors.White}
    # The text is the Mapping and the input action. TriggeringInputAction is swapped per step
    ActionButton<public>:button_loud = button_loud{}

    Root<private>:canvas = canvas{}
    var<private> Built:logic = false

    # The widget shown on screen (returns the same one every time)
    GetWidget<public>():widget =
        if (not Built?):
            set Built = true
            Root.AddWidget(MakeInfoSlot())
            Root.AddWidget(MakeButtonSlot())
        Root

    MakeInfoSlot<private>():canvas_slot =
        InfoSlots:[]stack_box_slot = array:
            stack_box_slot:
                Widget := text_block{DefaultText := InputSampleTitle, DefaultTextColor := NamedColors.White}
                HorizontalAlignment := horizontal_alignment.Left
                Padding := margin{Bottom := 8.0}
            stack_box_slot{Widget := StepText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := MappingText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := KeyText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := NoteText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 8.0}}
            stack_box_slot{Widget := ResultText, HorizontalAlignment := horizontal_alignment.Left, Padding := margin{Bottom := 4.0}}
            stack_box_slot{Widget := ButtonResultText, HorizontalAlignment := horizontal_alignment.Left}
        canvas_slot:
            Anchors := anchors{Minimum := vector2{X := 0.5, Y := 0.2}, Maximum := vector2{X := 0.5, Y := 0.2}}
            Alignment := vector2{X := 0.5, Y := 0.5}
            SizeToContent := true
            Widget := overlay:
                Slots := array:
                    overlay_slot:
                        Widget := color_block{DefaultColor := NamedColors.Black, DefaultOpacity := 0.85}
                        HorizontalAlignment := horizontal_alignment.Fill
                        VerticalAlignment := vertical_alignment.Fill
                    overlay_slot:
                        Padding := margin{Left := 32.0, Top := 24.0, Right := 32.0, Bottom := 24.0}
                        Widget := stack_box{Orientation := orientation.Vertical, Slots := InfoSlots}

    MakeButtonSlot<private>():canvas_slot =
        canvas_slot:
            Anchors := anchors{Minimum := vector2{X := 0.05, Y := 0.5}, Maximum := vector2{X := 0.05, Y := 0.5}}
            Alignment := vector2{X := 0.0, Y := 0.5}
            SizeToContent := true
            Widget := ActionButton

# Role: sample that shows the standard input actions (all of /Fortnite.com/Input and /Verse.org/Input) on screen one at a time, every StepSeconds, and shows "detected" when pressed. logic inputs are detected at the moment of the press (BeginDetectEvent), vector3 inputs (Move, PointerSelect, PointerZoom) with TriggerActivationEvent. In the PointerSelect / PointerZoom steps, TouchMapping is added to show the Virtual Pointer. The button_loud at the left gets the same input as TriggeringInputAction, to check that a key causes a Click even on a screen without focus
# Placement: attach to an empty entity in the editor. Place one player_manager_component in the scope (or the world)
# Try it: when the session starts (StartOnBegin), the top of the screen shows "n / total   action name", "Mapping" and "Key". Pressing the listed key changes it to "detected" and also prints to the output log. Advances to the next input every StepSeconds, wrapping to the first after the last
# When: with StartOnBegin true, from the start of the simulation. With false, from the activate signal (activated_event) to the deactivate signal (deactivated_event)
# Requirements / notes: character-control Mappings are never removed (removing them makes the player unable to move). UI Mappings are added only for the step and then removed. The current key bindings cannot be read from Verse, so the key names on screen are the defaults
input_sample_component<public> := class<final_super>(component):

    # When on, starts from the start of the simulation. When off, waits for the activate signal
    @editable
    StartOnBegin<public>:logic = true

    # Interval between inputs (seconds)
    @editable
    StepSeconds<public>:float = 6.0

    Views<private>:player_view_set = player_view_set{}

    # The inputs checked in turn
    Steps<public>:[]input_sample_step = array:
        # --- /Fortnite.com/Input/Character (enabled by default; the Mapping is not touched) ---
        input_sample_step{Label := "Reload", KeyName := "R / X", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.Reload}}
        input_sample_step{Label := "WeaponPrimary", KeyName := "Left click / RT", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.WeaponPrimary}}
        input_sample_step{Label := "WeaponSecondary", KeyName := "Right click / LT", MappingLabel := "Character.RangedWeaponMapping", LogicAction := option{Character.WeaponSecondary}}
        input_sample_step{Label := "Crouch", KeyName := "Left Ctrl / Right stick press", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Crouch}}
        input_sample_step{Label := "Sprint", KeyName := "Left Shift / Left stick press", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Sprint}}
        input_sample_step{Label := "Jump", KeyName := "Space / A", MappingLabel := "Character.TraversalMapping", LogicAction := option{Character.Jump}}
        # @experimental. Unknown whether InteractMapping is enabled by default, so it is only added and not removed
        input_sample_step:
            Label := "Interact (experimental)"
            KeyName := "E / X"
            MappingLabel := "Character.InteractMapping (experimental)"
            Note := "This step adds InteractMapping (not removed)"
            Mapping := option{Character.InteractMapping}
            LogicAction := option{Character.Interact}
        # @experimental. The Mapping it belongs to is not exposed in the API
        input_sample_step{Label := "Move (experimental)", KeyName := "W A S D / Left stick", MappingLabel := "Character (owning Mapping not in the API)", VectorAction := option{Character.Move}}

        # --- /Verse.org/Input/Gameplay (no detectable action) ---
        input_sample_step{Label := "(no action)", MappingLabel := "Gameplay.HotbarMapping", KeyName := "(none)"}

        # --- /Verse.org/Input/UI (the Mapping is added only for this step and removed afterwards) ---
        input_sample_step{Label := "NextTab", KeyName := "E / RB", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{NextTab}}
        input_sample_step{Label := "PreviousTab", KeyName := "Q / LB", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{PreviousTab}}
        input_sample_step{Label := "NextPage", KeyName := "C / RT", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{NextPage}}
        input_sample_step{Label := "PreviousPage", KeyName := "Z / LT", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{PreviousPage}}
        input_sample_step{Label := "Back", KeyName := "Escape / Back", MappingLabel := "UI.MenuNavigationMapping", Mapping := option{MenuNavigationMapping}, RemoveMappingAfter := true, LogicAction := option{Back}, Note := "Esc may be taken by the Fortnite menu and never arrive"}
        input_sample_step{Label := "Use", KeyName := "F / Y", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Use}}
        input_sample_step{Label := "Inspect", KeyName := "I / X", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Inspect}}
        input_sample_step{Label := "Sort", KeyName := "V / Right stick press", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Sort}}
        input_sample_step{Label := "Drop", KeyName := "X / Left stick press", MappingLabel := "UI.InventoryMenuMapping", Mapping := option{InventoryMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Drop}}
        input_sample_step{Label := "Craft", KeyName := "F / Y", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Craft}}
        input_sample_step{Label := "Inspect", KeyName := "I / X", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Inspect}}
        input_sample_step{Label := "Favorite", KeyName := "V / Right stick press", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Favorite}}
        input_sample_step{Label := "Scrap", KeyName := "X / Left stick press", MappingLabel := "UI.CraftingMenuMapping", Mapping := option{CraftingMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Scrap}}
        input_sample_step{Label := "Track", KeyName := "F / Y", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Track}}
        input_sample_step{Label := "PlaceMarker", KeyName := "P / X", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{PlaceMarker}}
        input_sample_step{Label := "Reset", KeyName := "R / Left stick press", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{Reset}}
        input_sample_step{Label := "ToggleView", KeyName := "V / Right stick press", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ToggleView}}
        input_sample_step{Label := "ZoomIn", KeyName := "Z / LT", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ZoomIn}}
        input_sample_step{Label := "ZoomOut", KeyName := "X / RT", MappingLabel := "UI.MapMenuMapping", Mapping := option{MapMenuMapping}, RemoveMappingAfter := true, LogicAction := option{ZoomOut}}
        # Adding TouchMapping shows the Virtual Pointer (the on-screen cursor)
        input_sample_step:
            Label := "PointerSelect"
            KeyName := "Touch / Click"
            MappingLabel := "UI.TouchMapping"
            Note := "Adding TouchMapping shows a pointer on screen. The click position (screen coordinates, cm) arrives as the value"
            Mapping := option{TouchMapping}
            RemoveMappingAfter := true
            VectorAction := option{PointerSelect}
        # @experimental
        input_sample_step:
            Label := "PointerZoom (experimental)"
            KeyName := "Pinch / Wheel"
            MappingLabel := "UI.TouchMapping"
            Mapping := option{TouchMapping}
            RemoveMappingAfter := true
            VectorAction := option{PointerZoom}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        if (StartOnBegin?):
            Activate()

    OnReceive<override>(SceneEvent:scene_event):logic =
        Views.HandleActivation(SceneEvent, Entity, CreateView)
        false

    OnEndSimulation<override>():void =
        Views.Deactivate()
        (super:)OnEndSimulation()

    # Show the check screen to everyone (late joiners too) and start cycling. Does nothing when already started
    Activate<public>():void =
        Views.Activate(Entity, CreateView)

    # Remove everyone's check screen and stop cycling
    Deactivate<public>():void =
        Views.Deactivate()

    # Succeeds while running
    IsActive<public>()<decides><transacts>:void =
        Views.IsActive[]

    CreateView<private>(ViewEntity:entity, Slot:player_slot_component):component =
        input_sample_view_component{Entity := ViewEntity, Source := Self, Player := Slot.Player}

# Role: one player's cycle. Shows Source.Steps in order from the first, waiting for the input and for the button Click
# Placement: created at runtime by input_sample_component (never placed in the editor)
input_sample_view_component<public> := class<final_super>(component):

    Source<public>:input_sample_component
    Player<public>:player

    Widget<private>:input_sample_widget = input_sample_widget{}
    var<private> Shown:logic = false

    OnSimulate<override>()<suspends>:void =
        if (Source.Steps.Length = 0):
            return
        if (PlayerInput := GetPlayerInput[Player]):
            var Index:int = 0
            loop:
                if (Step := Source.Steps[Index]):
                    RunStep(PlayerInput, Step, Index)
                set Index = if (Index + 1 < Source.Steps.Length) then Index + 1 else 0
        else:
            Print("[input_sample] Cannot get this player's input (player_input)")

    OnEndSimulation<override>():void =
        Hide()
        (super:)OnEndSimulation()

    # Show one input for StepSeconds. Waits separately for the input and for a Click on the button at the left (which has the same input as TriggeringInputAction), switching whichever arrives to "detected"
    # Even when stopped midway (the view disappears), defer restores the Mapping
    RunStep<private>(PlayerInput:player_input, Step:input_sample_step, Index:int)<suspends>:void =
        Widget.StepText.SetText(InputSampleStepMessage(Index + 1, Source.Steps.Length, Step.Label))
        Widget.MappingText.SetText(InputSampleMappingMessage(Step.MappingLabel))
        Widget.KeyText.SetText(InputSampleKeyMessage(Step.KeyName))
        Widget.NoteText.SetText(InputSampleNoteMessage(Step.Note))
        Widget.ActionButton.SetText(InputSampleButtonMessage(Step.MappingLabel, Step.Label))
        set Widget.ActionButton.TriggeringInputAction = Step.LogicAction
        if (Step.IsDetectable[]):
            Widget.ResultText.SetText(InputSampleWaiting(if (Seconds := Round[Source.StepSeconds]) then Seconds else 0))
        else:
            Widget.ResultText.SetText(InputSampleNotDetectable)
        if (Step.LogicAction?):
            Widget.ButtonResultText.SetText(InputSampleButtonWaiting)
        else:
            Widget.ButtonResultText.SetText(InputSampleButtonNoAction)

        if (Mapping := Step.Mapping?):
            PlayerInput.AddInputMapping(Mapping)
        defer:
            if (Step.RemoveMappingAfter?, Mapping := Step.Mapping?):
                PlayerInput.RemoveInputMapping(Mapping)
        Show()

        race:
            Sleep(Source.StepSeconds)
            block:
                Step.AwaitTrigger(PlayerInput)
                Widget.ResultText.SetText(InputSampleDetected)
                Print("[input_sample] Input detected: {Step.MappingLabel} > {Step.Label}")
                Sleep(Inf)
            block:
                Clicked := Widget.ActionButton.OnClick().Await()
                Widget.ButtonResultText.SetText(InputSampleButtonClicked)
                Print("[input_sample] Button Click detected: {Step.MappingLabel} > {Step.Label}")
                Sleep(Inf)

    Show<private>():void =
        if (not Shown?, PlayerUI := GetPlayerUI[Player]):
            set Shown = true
            PlayerUI.AddWidget(Widget.GetWidget(), player_ui_slot{InputMode := ui_input_mode.None})

    Hide<private>():void =
        if (Shown?, PlayerUI := GetPlayerUI[Player]):
            set Shown = false
            PlayerUI.RemoveWidget(Widget.GetWidget())
