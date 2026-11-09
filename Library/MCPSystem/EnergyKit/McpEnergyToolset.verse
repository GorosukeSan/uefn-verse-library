using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { PlayerSystem }
using { EnergySystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# 役割：Energy ツールセット（宛先 "energy"）。エネルギー（EnergySystem の energy_component）の一覧・量を決める・足す・使う・満たす・最大を決める
#   対象は "energy"（entity の番号か名前）か "player"（番号。その人のエネルギー＝ FindEnergyFor）で指す
# 置き方：受け箱と同じ entity に付けるとよい
# タグ：自分の entity に mcp_controllable_tag と mcp_session_restorable_tag（キー "energies"：量と最大。持ち主のいるものは "p<番号>"）
mcp_energy_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_session_restorable):

    # 同じツールセットを複数置くときの名前（空なら "energy" だけで届く）
    @editable:
        ToolTip := McpToolsetIdToolTip
        Categories := array{McpCategory}
    InstanceId<public>:string = ""

    RoleTags<private>:mcp_role_tags = mcp_role_tags{}

    OnBeginSimulation<override>():void =
        (super:)OnBeginSimulation()
        RoleTags.Add(Entity, mcp_controllable_tag{})
        RoleTags.Add(Entity, mcp_session_restorable_tag{})

    OnEndSimulation<override>():void =
        RoleTags.RemoveAll()
        (super:)OnEndSimulation()

    McpToolset<override>()<transacts>:string = "energy"

    McpId<override>()<transacts>:string = InstanceId

    McpTools<override>()<transacts>:[]mcp_tool =
        array:
            McpTool("list", "エネルギーの一覧。data に [\{id,name,owner,amount,max,ratio\}]（owner は持ち主のプレイヤーの番号、いなければ -1）", array{})
            McpTool("get", "量（energy か player のどちらか）", array{McpOptArg("energy", "entity", "energy_component の entity"), McpOptArg("player", "player", "その人のエネルギー")})
            McpTool("set", "量を決める（0〜最大に丸める）", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象"), McpArg("amount", "float", "量")})
            McpTool("restore", "足す（最大を超える分は捨てる）", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象"), McpArg("amount", "float", "量")})
            McpTool("consume", "使う（足りなくても 0 で止まる）", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象"), McpArg("amount", "float", "量")})
            McpTool("spend", "足りれば使う（足りなければ failed で何も変えない）", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象"), McpArg("amount", "float", "量")})
            McpTool("fill", "満たす", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象")})
            McpTool("set_max", "最大を決める", array{McpOptArg("energy", "entity", "対象"), McpOptArg("player", "player", "対象"), McpArg("max", "float", "最大")})

    McpHandle<override>(Call:mcp_call):mcp_reply =
        Tool := Call.Tool
        Inbox := Call.Inbox
        if (Tool = "list"):
            Items := for (Energy : FindEnergies()) { EnergyJson(Inbox, Energy) }
            McpOkData("{Items.Length} energies", McpArray(Items))
        else if (Energy := FindTarget[Call]):
            if (Tool = "get"):
                McpOkData("{Energy.CurrentAmount}/{Energy.GetMax()}", EnergyJson(Inbox, Energy))
            else if (Tool = "fill"):
                Energy.Fill()
                McpOk("amount={Energy.CurrentAmount}")
            else if (Tool = "set_max"):
                if (NewMax := Call.FindFloat["max"]):
                    Energy.SetMax(NewMax)
                    McpOk("max={Energy.GetMax()}")
                else:
                    McpBadArg("max")
            else if (Amount := Call.FindFloat["amount"]):
                if (Tool = "set"):
                    Energy.SetAmount(Amount)
                    McpOk("amount={Energy.CurrentAmount}")
                else if (Tool = "restore"):
                    Energy.Restore(Amount)
                    McpOk("amount={Energy.CurrentAmount}")
                else if (Tool = "consume"):
                    Energy.Consume(Amount)
                    McpOk("amount={Energy.CurrentAmount}")
                else if (Tool = "spend"):
                    if (Energy.Spend[Amount]) then McpOk("amount={Energy.CurrentAmount}") else McpFail("failed", "not enough")
                else:
                    McpFail("unknown_tool", Tool)
            else:
                McpBadArg("amount")
        else:
            McpFail("no_entity", "energy か player（energy_component）")

    # energy（entity）か player（その人のエネルギー）。どちらも無ければ失敗する
    FindTarget<private>(Call:mcp_call)<transacts><decides>:energy_component =
        if (Call.HasArg["energy"]):
            Call.FindEntity["energy"].GetComponent[energy_component]
        else:
            Player := Call.FindPlayer["player"]
            Entity.FindEnergyFor[Player]

    FindEnergies<private>()<transacts>:[]energy_component =
        if (World := Entity.GetSimulationEntity[]):
            for (Energy : World.FindDescendantComponents(energy_component)) { Energy }
        else:
            array{}

    # 状態のキー：持ち主がいれば "p<番号>"、いなければ名前か置いた位置
    EnergyKey<private>(Energy:energy_component)<transacts>:string =
        if (Owner := Energy.Entity.FindOwningPlayer[]):
            "p{Entity.McpGetPlayerIndex(Owner)}"
        else:
            Energy.Entity.GetMcpKey()

    # ---- 状態（キー "energies"：{"<キー>":{"amount","max"}}） ----

    McpSessionKey<override>()<transacts>:string = "energies"

    McpSessionSave<override>(Context:mcp_session_context):string =
        Fields := for (Energy : FindEnergies()):
            McpField(EnergyKey(Energy), McpObject(array{McpField("amount", McpNumber(Energy.CurrentAmount)), McpField("max", McpNumber(Energy.GetMax()))}))
        McpObject(Fields)

    McpSessionRestore<override>(Context:mcp_session_context, State:value):string =
        if (O := State.AsObject[]):
            Pairs := for (Energy : FindEnergies(), V := O[EnergyKey(Energy)], Item := V.AsObject[]) { (Energy, Item) }
            for (Pair : Pairs):
                if (X := Pair(1)["max"], NewMax := McpValueToFloat[X]):
                    Pair(0).SetMax(NewMax)
                if (X := Pair(1)["amount"], Amount := McpValueToFloat[X]):
                    Pair(0).SetAmount(Amount)
            "ok restored={Pairs.Length}"
        else:
            "bad_state"

EnergyJson<internal>(Inbox:mcp_inbox_component, Energy:energy_component)<transacts>:string =
    Owner := if (P := Energy.Entity.FindOwningPlayer[]) then Inbox.Entity.McpGetPlayerIndex(P) else -1
    McpObject(array{McpField("id", "{Inbox.GetHandle(Energy.Entity)}"), McpField("name", McpQuote(Energy.Entity.GetMcpName())), McpField("owner", "{Owner}"),
        McpField("amount", McpNumber(Energy.CurrentAmount)), McpField("max", McpNumber(Energy.GetMax())), McpField("ratio", McpNumber(Energy.GetRatio()))})
