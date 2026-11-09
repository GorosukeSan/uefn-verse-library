# Makes the MCPSystem Kits public so that code outside the library (your code) can use them.
# Modules created from folders are internal by default, so without these declarations they cannot be imported with using from outside.
# The top level (inbox, command shape, interface, tags, Core toolset) depends on no other System. Toolsets that use other Systems are split into Kits (take only the Kits for the Systems you use)
# Finding entities, transform, enable / disable, tags, activation signals, components (SceneGraphSystem, ActivationSystem)
EntityKit<public> := module {}
# Player list, position, teleport, agent tags, groups (PlayerSystem)
PlayerKit<public> := module {}
# Custom character input, jump, dash, teleport, velocity, motion playback / recording (CharacterSystem, PlayerSystem)
CharacterKit<public> := module {}
# Screen list, pressing buttons, show / close. Opt-in per screen (WidgetSystem, PlayerSystem)
WidgetKit<public> := module {}
# Jumping to a node of the game flow (GameSequence), stopping it (GameSequenceSystem, SceneGraphSystem)
GameSequenceKit<public> := module {}
# Spawning and despawning prefabs (SpawnSystem)
SpawnKit<public> := module {}
# Pickups and effects (PickupSystem, PlayerSystem)
PickupKit<public> := module {}
# Movers (MoverSystem)
MoverKit<public> := module {}
# Countdowns (CountdownSystem)
CountdownKit<public> := module {}
# Energy (EnergySystem, PlayerSystem)
EnergyKit<public> := module {}
# State snapshot / restore (collects the top-level mcp_session_restorable)
SessionKit<public> := module {}
# Log verbosity, state dump, sample long-running tools (top level only)
DebugKit<public> := module {}
# Descriptions shown in the editor (message)
TooltipKit<public> := module {}
