using { /Verse.org/SceneGraph }

# 流れが進められなかった理由の基底（game_sequence_state.Failed になる）
game_node_error<public> := class<computes>:

# 遷移先の entity に game_node_component が無い
game_node_not_found_error<public> := class<computes>(game_node_error):
    # game_node_component が付いていなかった遷移先の entity
    Target<public>:entity

# 最初のノードが無い（子にノードが 1 つも無い）
game_node_empty_error<public> := class<computes>(game_node_error):
