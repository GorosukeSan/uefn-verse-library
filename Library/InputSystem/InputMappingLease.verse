using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }

# Role: "leases" an input mapping (input_mapping). Lease it when entering a scene, return it when leaving. When several scenes lease the same mapping, it is not removed until the last one returns it
#   input_mapping cannot be compared (there is no way to tell whether two are the same), so the caller gives each mapping a name (Key, e.g. "touch", "ranged_weapon") and the lease count is tracked per name
#   AddInputMapping only when the count goes 0 -> 1, RemoveInputMapping only when it goes 1 -> 0 (do not pass different mappings under the same name)
# Usage:
#   if (Lease := Player.LeaseInputMapping("touch", TouchMapping)?):  # enter the scene (false when the input is unavailable)
#       defer:
#           Lease.Release()                                          # leave the scene (calling it more than once is fine)
#   ⚠ Return it from a scope that exits normally (outside the race / after the race ends). The defer inside a branch stopped by losing a race did not run (v43.00 in UEFN), so
#     leasing inside a race branch and returning in a defer leaves the mapping in place (a leftover TouchMapping makes the camera impossible to turn)
# Requirements:
#   - Only mappings leased through this mechanism are counted. If another part calls AddInputMapping / RemoveInputMapping on the same mapping without it, the lessee's input also stops when that part removes it
#   - The per-player counts live in a per-session table (weak_map(session, ...))

# Names of commonly used mappings (every part leasing the same mapping uses the same name)
# Virtual Pointer (TouchMapping of /Verse.org/Input/UI; PointerSelect, etc.)
TouchMappingLeaseKey<public>:string = "touch"
# Weapon mapping (RangedWeaponMapping of /Fortnite.com/Input/Character; WeaponPrimary / WeaponSecondary, etc.)
RangedWeaponMappingLeaseKey<public>:string = "ranged_weapon"

# One player's lease counts per name
input_mapping_lease_counts<internal> := class<internal>:
    var Counts<internal>:[string]int = map{}

# Lease counts per player (per session. weak_map(player, ...) would count as save data, so the session is the key and players are held inside)
var InputMappingLeaseTable<internal>:weak_map(session, [player]input_mapping_lease_counts) = map{}

# The per-player lease counts of the current session
GetLeaseTable<internal>()<transacts>:[player]input_mapping_lease_counts =
    if (Found := InputMappingLeaseTable[GetSession()]) then Found else map{}

# Player's lease counts (created and stored if missing)
GetLeaseCounts<internal>(Player:player)<transacts>:input_mapping_lease_counts =
    Table := GetLeaseTable()
    if (Found := Table[Player]):
        Found
    else:
        Made := input_mapping_lease_counts{}
        if (set InputMappingLeaseTable[GetSession()] = ConcatenateMaps(Table, map{Player => Made})) {}
        Made

# The handle returned by LeaseInputMapping, used to return the lease (Release does nothing from the second call on)
input_mapping_lease<public> := class<internal>:
    Player<internal>:player
    PlayerInput<internal>:player_input
    Key<internal>:string
    Mapping<internal>:input_mapping
    var Returned<internal>:logic = false

    # Returns the lease (decrements the count by 1 and removes the mapping when it reaches 0)
    Release<public>():void =
        if (not Returned?):
            set Returned = true
            ReleaseLeasedMapping(Player, PlayerInput, Key, Mapping)

    # Succeeds while not yet returned
    IsHeld<public>()<decides><transacts>:void =
        not Returned?

# Leases Mapping to Player under the name Key (adds it to the player when the count for that name is 0). Return it with Release on the returned handle. false when the input is unavailable
(Player:player).LeaseInputMapping<public>(Key:string, Mapping:input_mapping):?input_mapping_lease =
    if (PlayerInput := GetPlayerInput[Player]):
        Table := GetLeaseCounts(Player)
        Current := if (Count := Table.Counts[Key]) then Count else 0
        if (set Table.Counts[Key] = Current + 1) {}
        if (Current = 0):
            PlayerInput.AddInputMapping(Mapping)
        option{input_mapping_lease{Player := Player, PlayerInput := PlayerInput, Key := Key, Mapping := Mapping}}
    else:
        false

# How many leases Player currently holds under the name Key (0 means this mechanism has not added it)
(Player:player).GetInputMappingLeaseCount<public>(Key:string)<transacts>:int =
    if (Table := GetLeaseTable()[Player], Count := Table.Counts[Key]) then Count else 0

ReleaseLeasedMapping<internal>(Player:player, PlayerInput:player_input, Key:string, Mapping:input_mapping):void =
    if (Table := GetLeaseTable()[Player], Count := Table.Counts[Key]):
        if (Count <= 1):
            if (set Table.Counts[Key] = 0) {}
            PlayerInput.RemoveInputMapping(Mapping)
        else:
            if (set Table.Counts[Key] = Count - 1) {}
