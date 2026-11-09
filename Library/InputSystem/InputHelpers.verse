using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }

# Role: small helpers for awaiting input (called from an ability's RunFor or from a per-player view). No base class to inherit from
# Usage example (do something only while the key is held):
#   MaybeInput := Agent.AwaitPlayerInput()   # <suspends> cannot be called in an if condition (V3512), so take the result first
#   if (PlayerInput := MaybeInput?):
#       race:
#           PlayerInput.HoldInputMapping(Mapping, RemoveMappingOnRevoke)
#           loop:
#               PlayerInput.AwaitPressed(Action)
#               race:
#                   PlayerInput.AwaitReleased(Action)
#                   DoWhileHeld()

# Returns the input (player_input) of Agent when it is a player. Fails when it is not a player or the input is unavailable
(Agent:agent).FindPlayerInput<public>()<decides><transacts>:player_input =
    GetPlayerInput[player[Agent]]

# Retries every frame until Agent's input (player_input) is available (right after the simulation starts or right after joining it may not be yet).
# Returns it once available. false when Agent is not a player or left before it became available. Use at the top of an ability's RunFor (trying only once with FindPlayerInput leaves the ability "granted" but not running for players whose input was unavailable)
(Agent:agent).AwaitPlayerInput<public>()<suspends>:?player_input =
    loop:
        if (Player := player[Agent]):
            if (not Player.IsActive[]):
                return false
            if (PlayerInput := GetPlayerInput[Player]):
                return option{PlayerInput}
        else:
            return false
        Sleep(0.0)

# Waits until Action is pressed (detection begins = BeginDetectEvent). Does not arrive unless an input_mapping containing Action has been added to the player
(PlayerInput:player_input).AwaitPressed<public>(Action:input_action(logic))<suspends>:void =
    PlayerInput.GetInputEvents(Action).BeginDetectEvent.Await()

# Waits until Action is released (detection ends = EndDetectEvent). Called while not pressed, it does not return until the next press and release
(PlayerInput:player_input).AwaitReleased<public>(Action:input_action(logic))<suspends>:void =
    PlayerInput.GetInputEvents(Action).EndDetectEvent.Await()

# Adds Mapping to the player and does not return until stopped (loses a race / is canceled). When RemoveOnEnd is true, removes Mapping when stopped
# Use as one branch of a race so the cleanup happens as soon as the ability stops
# ⚠ There is a case where the defer inside a branch stopped by losing a race did not run (v43.00 in UEFN; see the note in InputMappingLease). For mappings where a leftover is a problem, add outside the race and remove after it
# Requirements: set RemoveOnEnd to true only for a mapping dedicated to that ability. Removing a mapping that weapons or movement also use (RangedWeaponMapping / TraversalMapping, ...) makes the player unable to shoot or move.
#   Removal is not counted, so do not set it to true either when another feature (another ability, player_input_component, ...) uses the same mapping
(PlayerInput:player_input).HoldInputMapping<public>(Mapping:input_mapping, RemoveOnEnd:logic)<suspends>:void =
    PlayerInput.AddInputMapping(Mapping)
    defer:
        if (RemoveOnEnd?):
            PlayerInput.RemoveInputMapping(Mapping)
    Sleep(Inf)
