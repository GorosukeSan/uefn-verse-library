# Make the CheckpointSystem Kits public so they can be used from outside the library (your code).
# Modules created from folders are internal by default; without this declaration they cannot be imported with using.
PresenceKit<public> := module {}
# Kit that refills energy (EnergySystem) when a checkpoint is reached (checkpoint_energy_refill_component)
EnergyKit<public> := module {}
# Kit that spawns checkpoints through a spawner (checkpoint_factory_component)
SpawnKit<public> := module {}
# Kit holding the descriptions (message) shown in the editor
TooltipKit<public> := module {}
