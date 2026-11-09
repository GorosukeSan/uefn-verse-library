using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }
using { /Fortnite.com/Characters }
using { MovementSystem }
using { PlayerSystem }
using { SceneGraphSystem }

# Role: runtime class that watches the checkpoints (checkpoint_component) of one zone together. Once per frame, queries the position of every player in the zone exactly once per player and compares it with every registered checkpoint
#   (querying everyone's position per checkpoint would mean checkpoints x players queries. The comparison itself is still checkpoints x players)
# Creation: not created directly. At simulation start, checkpoint_component looks for the tracker used by a checkpoint that started earlier in the same zone and registers with it (creating one when there is none)
# When: one of the registered checkpoints (the Driver) subscribes to its own TickEvents.PrePhysics and calls Tick every frame. When the Driver stops, one of the remaining checkpoints takes over; when none is left, it stops
# Requirements: one player_manager_component in the zone (game_scope_component; the world when there is none). The first one found is remembered (looked up every second until found)
# ⚠ Unverified: whether disabling the Driver checkpoint's entity stops its TickEvents and thereby every check (if so, remove checkpoints to be disabled from the zone)
checkpoint_tracker<internal> := class<internal>:

    LookupIntervalSeconds<private>:float = 1.0

    var Checkpoints<private>:[]checkpoint_component = array{}
    var Driver<private>:?checkpoint_component = false
    var Manager<private>:?player_manager_component = false
    var ManagerSubscription<private>:?cancelable = false
    var NextLookupSeconds<private>:float = 0.0

    # Adds Checkpoint to the watched set (does nothing when already in it). Makes Checkpoint the Driver when there is none
    Register<internal>(Checkpoint:checkpoint_component):void =
        if (not Checkpoints.Find[Checkpoint]):
            set Checkpoints += array{Checkpoint}
        if (not Driver?):
            SetDriver(option{Checkpoint})

    # Removes Checkpoint from the watched set. If it was the Driver, the first remaining one takes over. When none is left, also unsubscribes from player_manager_component
    Unregister<internal>(Checkpoint:checkpoint_component):void =
        set Checkpoints = for (Other : Checkpoints, Other <> Checkpoint):
            Other
        if (Current := Driver?, Current = Checkpoint):
            SetDriver(if (Next := Checkpoints[0]) then option{Next} else false)
        if (Checkpoints.Length = 0):
            ManagerSubscription.CancelIfSet()
            set ManagerSubscription = false
            set Manager = false
            set NextLookupSeconds = 0.0

    # One frame: reads each checkpoint's position once, reads each player's position once, and compares with every checkpoint
    Tick<internal>():void =
        MaybeManager := GetManager()
        if (Found := MaybeManager?):
            Targets := Checkpoints
            for (Checkpoint : Targets):
                Checkpoint.PrepareFrame()
            for (Slot : Found.GetSlots()):
                CheckPlayer(Slot.Player, Targets)

    CheckPlayer<private>(Agent:agent, Targets:[]checkpoint_component):void =
        if (FortCharacter := Agent.GetFortCharacter[], Start := FortCharacter.FindGlobalTranslation[]):
            var Position:vector3 = Start
            for (Checkpoint : Targets):
                Moved := Checkpoint.CheckAt(Agent, FortCharacter, Position)
                # After moving the player onto a top face, compare the remaining checkpoints with the moved position (same result as when each checkpoint read the position itself)
                if (Moved?, Lifted := FortCharacter.FindGlobalTranslation[]):
                    set Position = Lifted

    SetDriver<private>(NewDriver:?checkpoint_component):void =
        if (Old := Driver?):
            Old.StopDriving()
        set Driver = NewDriver
        if (Next := NewDriver?):
            Next.StartDriving()

    GetManager<private>():?player_manager_component =
        if (Found := Manager?):
            option{Found}
        else:
            Now := GetSimulationElapsedTime()
            if (Now >= NextLookupSeconds, Current := Driver?):
                set NextLookupSeconds = Now + LookupIntervalSeconds
                if (Found := Current.Entity.ResolveScopedComponent(Manager, player_manager_component)?):
                    set Manager = option{Found}
                    set ManagerSubscription = option{Found.PlayerRemovedEvent.Subscribe(OnPlayerRemoved)}
                    option{Found}
                else:
                    false
            else:
                false

    OnPlayerRemoved<private>(Player:player):void =
        for (Checkpoint : Checkpoints):
            Checkpoint.ForgetAgent(Player)
