using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Abilities }
using { /UnrealEngine.com/Abilities }

# Uses the ItemEquippedAbilities of the fort_item_ability_component on InEntity (the item's entity) on Agent's character (plays the effects). Returns the ones that could be used, so pass them to EndItemAbilities when stopping
# Does nothing and returns an empty array when there is no fort_item_ability_component or no character
(InEntity:entity).BeginItemAbilities<public>(Agent:agent):[]ability_effect =
    var Effects:[]ability_effect = array{}
    if:
        Abilities := InEntity.GetComponent[fort_item_ability_component]
        Parent := Agent.GetFortCharacter[].GetEntity[]
    then:
        for (MaybeAbility : Abilities.ItemEquippedAbilities):
            if (Ability := MaybeAbility?):
                Context := ability_context{Instigator := option{Agent}}
                Result := Ability.Use(Parent, Context)
                if (Effect := Result?):
                    set Effects += array{Effect}
    Effects

# Stops the effects returned by BeginItemAbilities (removes the ones that cannot be canceled)
EndItemAbilities<public>(Effects:[]ability_effect):void =
    for (Effect : Effects):
        Canceled := logic{Effect.AbilityComponent.Cancel[ability_ended{}]}
        if (not Canceled?):
            Effect.RemoveFromParent()
