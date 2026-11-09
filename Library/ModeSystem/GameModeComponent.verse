using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ModeSystem.TooltipKit }

# Role: represents one game mode. Title is the name shown on screen, Order is the position among the candidates
# Placement: attach to an entity in the editor. Directly under the mode_select_component entity, one per mode (child order does not matter; the position is decided by Order)
game_mode_component<public> := class<final_super>(component):

    # The mode name shown on screen. Default "Mode"
    @editable:
        ToolTip := ModeTitleToolTip
        Categories := array{ModeCategory}
    Title<public>:string = "Mode"

    # Position among the candidates (smaller comes first). Used for the order of mode_select_component.GetModes and to break a tied vote (the smaller wins). The order among equal values is unspecified
    @editable_number(int):
        ToolTip := ModeOrderToolTip
        Categories := array{ModeCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0
