using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ConditionSystem }
using { SceneGraphSystem }
using { GameSequenceSystem.TooltipKit }

# Role: advances to the Target node when the conditions are satisfied (ends the sequence when Target is empty)
# Placement: attach to an entity in the editor
# Parent: directly under the entity of game_node_component
# Children: entities with conditions (condition_component subclasses), directly under it. With several, advances "when all are satisfied" (group them with condition_any when any one is enough). Without any, advances immediately
game_transition_component<public> := class<final_super>(component):

    # The node (entity with game_node_component) to advance to when the conditions are satisfied. Empty ends the sequence here. Default empty
    @editable:
        ToolTip := TransitionTargetToolTip
        Categories := array{TransitionCategory, TransitionTargetCategory}
    Target<public>:?entity = false
    # When several transitions of the same node can advance at once, the larger value wins (0-100). Default 0
    @editable_number(int):
        ToolTip := TransitionPriorityToolTip
        Categories := array{TransitionCategory, TransitionPriorityCategory}
        MinValue := option{0}
        MaxValue := option{100}
    Priority<public>:int = 0

    # Succeeds when it can advance. Succeeds when every condition (condition_component) of the direct children is satisfied; always succeeds without conditions
    IsReady<public>()<decides><transacts>:void =
        Entity.AreChildConditionsSatisfied[]

    # Succeeds when Target is empty (this transition ends the sequence). Whether Target lacks a node is checked by game_sequence_component when advancing
    IsFinish<public>()<decides><transacts>:void =
        not Target?
