using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }
using { /UnrealEngine.com/Itemization }
using { AbilitySystem }
using { ItemSystem }
using { InputSystem }
using { EnergySystem }
using { EnergySystem.TooltipKit }

# 方向：energy_restore_ability_component の entity から上へ（SendUp）
# 受け手：祖先（アイテムなら持ち主のプレイヤーまで）。HUD で「回復するものが無い」と出すなど。消費しない
energy_restore_failed_event<public> := class(scene_event):
    # 送った能力
    Ability<public>:energy_restore_ability_component
    # 使おうとした人
    Agent<public>:agent

# 役割：エネルギーを回復する能力。付与された人が RestoreAction（既定は射撃）を押すと、その人のエネルギー（FindRestoreTarget）を RestoreAmount 回復する。
#   回復できたとき、この entity がアイテム（item_component がある）で ConsumeItemOnUse なら、アイテムを 1 つ減らす（最後の 1 つなら消え、能力も剥奪される）。回復するものが無ければ、何も減らさずに energy_restore_failed_event を上へ送る
# 付与の仕方は同じ entity に置く component で選ぶ：
#   - アイテムとして（装備しているあいだ。使うと 1 つ減る） → アイテムの entity に item_component・item_holder_component・ability_grant_item_component と一緒に置く。重ねて持つなら basic_stackable_component
#   - 全員に最初から（回数無制限） → ability_grant_players_component。連打を防ぐなら CooldownSeconds を決める
#   - 条件を満たしているあいだ → ability_grant_condition_component（子に条件）
#   - コードから → Grant / Revoke
# 知らせ：回復したら RestoredEvent、回復するものが無ければ FailedEvent と energy_restore_failed_event
energy_restore_ability_component<public> := class<final_super>(ability_component):

    # 使ったときに回復する量。持ち物のうち一番減っているもの（無ければプレイヤーのエネルギー）を回復する（既定 100.0）
    @editable_number(float):
        ToolTip := EnergyRestoreAmountToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
        MinValue := option{0.0}
        MaxValue := option{10000.0}
    RestoreAmount<public>:float = 100.0
    # 回復してから次に使えるまでの秒数。0.0 ならすぐ使える（既定 0.0）
    @editable_number(float):
        ToolTip := EnergyRestoreCooldownToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
        MinValue := option{0.0}
        MaxValue := option{600.0}
    CooldownSeconds<public>:float = 0.0
    # true なら、アイテムに置いたとき回復するたびにアイテムを 1 つ減らす。アイテムでなければ使わない（既定 true）
    @editable:
        ToolTip := EnergyRestoreConsumeItemToolTip
        Categories := array{EnergyCategory, EnergyRestoreCategory}
    ConsumeItemOnUse<public>:logic = true
    # 押すと回復する操作（既定 WeaponPrimary = 攻撃のボタン）
    @editable:
        ToolTip := EnergyRestoreActionToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RestoreAction<public>:input_action(logic) = Character.WeaponPrimary
    # 付与しているあいだ足すキー割り当て。RestoreAction を含むものを選ぶ（既定 RangedWeaponMapping）
    @editable:
        ToolTip := EnergyRestoreMappingToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RestoreMapping<public>:input_mapping = Character.RangedWeaponMapping
    # true なら剥奪したときに RestoreMapping を外す。この能力専用の割り当てのときだけ true にする（既定 false）
    @editable:
        ToolTip := EnergyRemoveMappingToolTip
        Categories := array{EnergyCategory, EnergyInputCategory}
    RemoveMappingOnRevoke<public>:logic = false

    RestoredEventInternal<private><final>:event(tuple(agent, energy_component)) = event(tuple(agent, energy_component)){}
    FailedEventInternal<private><final>:event(agent) = event(agent){}

    # 回復したときに、（使った人, 回復した energy_component）で届く（Await / Subscribe する。外から Signal はできない）
    RestoredEvent<public><final>:listenable(tuple(agent, energy_component)) = MakeProxyListenable(RestoredEventInternal)

    # 使ったが回復するもの（FindRestoreTarget）が無かったときに、使った人で届く
    FailedEvent<public><final>:listenable(agent) = MakeProxyListenable(FailedEventInternal)

    RunFor<override>(Agent:agent)<suspends>:void =
        MaybeInput := Agent.AwaitPlayerInput()
        if (PlayerInput := MaybeInput?):
            race:
                PlayerInput.HoldInputMapping(RestoreMapping, RemoveMappingOnRevoke)
                loop:
                    PlayerInput.AwaitPressed(RestoreAction)
                    Restored := TryRestoreFor(Agent)
                    if (Restored?, CooldownSeconds > 0.0):
                        Sleep(CooldownSeconds)
        else if (not player[Agent]):
            Print("[energy_restore_ability_component] プレイヤーでない agent に付与されました。入力が取れないので動きません")

    # Agent のエネルギーを RestoreAmount 回復する（押したときと同じ処理。入力を通さずに使わせたいときに呼ぶ）。回復できたら true。
    # 回復できたときは、アイテムなら 1 つ減らす（ConsumeItemOnUse）。回復するものが無ければ何も減らさず、知らせて false
    # 知らせる処理（SendUp・Signal）とアイテムを減らす処理は巻き戻せないので <decides> にはできない。回復できるかだけを確かめるなら FindRestoreTarget[] を使う
    TryRestoreFor<public>(Agent:agent):logic =
        if (Target := FindRestoreTarget[Agent]):
            Target.Restore(RestoreAmount)
            RestoredEventInternal.Signal((Agent, Target))
            if (ConsumeItemOnUse?, Entity.GetComponent[item_component]):
                Entity.ConsumeOne()
            true
        else:
            Entity.SendUp(energy_restore_failed_event{Ability := Self, Agent := Agent})
            FailedEventInternal.Signal(Agent)
            false

    # Agent について回復する先を探す。順に：Agent の持ち物（この entity 以外のアイテム）の energy_component のうち満タンでなく、割合が一番低いもの → Agent 自身に付いた energy_component（満タンでなければ）
    # どれも無い・すべて満タンなら失敗する
    FindRestoreTarget<public>(Agent:agent)<decides><transacts>:energy_component =
        var Best:?energy_component = false
        for (Item : Agent.GetAgentItems(), Item <> Entity, Energy := Item.FindEnergy[], not Energy.IsFull[]):
            if (Current := Best?):
                if (Energy.GetRatio() < Current.GetRatio()):
                    set Best = option{Energy}
            else:
                set Best = option{Energy}
        if (Found := Best?):
            Found
        else:
            Own := Agent.GetComponent[energy_component]
            not Own.IsFull[]
            Own
