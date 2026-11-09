using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }

# Role: represents one participating player. Views of features hung on the player are created as children of this entity
# Placement: created at runtime by player_manager_component (not placed in the editor)
player_slot_component<public> := class<final_super>(component):

    # The player this slot represents
    Player<public>:player
