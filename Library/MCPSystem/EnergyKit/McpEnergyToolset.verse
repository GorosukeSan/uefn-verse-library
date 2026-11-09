using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Verse.org/Simulation/Tags }
using { /UnrealEngine.com/JSON }
using { PlayerSystem }
using { EnergySystem }
using { MCPSystem }
using { MCPSystem.TooltipKit }

# Role: Energy toolset (destination "energy"). Lists energies (EnergySystem's energy_component); set, add, use, fill, set the maximum
#   The target is addressed by "energy" (entity id or name) or "player" (index; that player's energy = FindEnergyFor)
# Placement: best attached to the same entity as the inbox
# Tags: mcp_controllable_tag and mcp_session_restorable_tag on its own entity (key "energies": amount and max; owned ones are keyed "p<index>")
mcp_energy_toolset_component<public> := class<final_super>(component, mcp_controllable, mcp_session_restorable):

    # Name used when the same toolset is placed more than once (when empty, "energy" alone reaches it)
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
            McpTool("list", "List of energies. data: [\{id,name,owner,amount,max,ratio\}] (owner is the owning player's index, -1 if none)", array{})
            McpTool("get", "Amount (either energy or player)", array{McpOptArg("energy", "entity", "an entity with energy_component"), McpOptArg("player", "player", "that player's energy")})
            McpTool("set", "Sets the amount (clamped to 0-max)", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target"), McpArg("amount", "float", "amount")})
            McpTool("restore", "Adds (the part above max is discarded)", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target"), McpArg("amount", "float", "amount")})
            McpTool("consume", "Uses (stops at 0 even if short)", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target"), McpArg("amount", "float", "amount")})
            McpTool("spend", "Uses only if enough (otherwise failed and nothing changes)", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target"), McpArg("amount", "float", "amount")})
            McpTool("fill", "Fills to max", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target")})
            McpTool("set_max", "Sets the maximum", array{McpOptArg("energy", "entity", "target"), McpOptArg("player", "player", "target"), McpArg("max", "float", "maximum")})

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
            McpFail("no_entity", "energy or player (energy_component)")

    # energy (entity) or player (that player's energy). Fails when neither is given
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

    # State key: "p<index>" when owned, otherwise the name or the placed position
    EnergyKey<private>(Energy:energy_component)<transacts>:string =
        if (Owner := Energy.Entity.FindOwningPlayer[]):
            "p{Entity.McpGetPlayerIndex(Owner)}"
        else:
            Energy.Entity.GetMcpKey()

    # ---- State (key "energies": {"<key>":{"amount","max"}}) ----

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
