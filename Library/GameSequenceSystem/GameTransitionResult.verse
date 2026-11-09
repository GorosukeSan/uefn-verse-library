using { /Verse.org/SceneGraph }

# Base of the reasons the sequence could not advance (becomes game_sequence_state.Failed)
game_node_error<public> := class<computes>:

# The transition target entity has no game_node_component
game_node_not_found_error<public> := class<computes>(game_node_error):
    # The target entity that did not carry game_node_component
    Target<public>:entity

# There is no first node (no node among the children)
game_node_empty_error<public> := class<computes>(game_node_error):
