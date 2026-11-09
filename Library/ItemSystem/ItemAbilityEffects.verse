using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }
using { /Fortnite.com/Abilities }
using { /UnrealEngine.com/Abilities }

# InEntity（アイテムの entity）に付いた fort_item_ability_component の ItemEquippedAbilities を、Agent のキャラクターに使う（演出を出す）。使えたものを返すので、止めるときに EndItemAbilities に渡す
# fort_item_ability_component が無い・キャラクターがいないときは何もせず空を返す
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

# BeginItemAbilities が返した演出を止める（止められないものは取り除く）
EndItemAbilities<public>(Effects:[]ability_effect):void =
    for (Effect : Effects):
        Canceled := logic{Effect.AbilityComponent.Cancel[ability_ended{}]}
        if (not Canceled?):
            Effect.RemoveFromParent()
