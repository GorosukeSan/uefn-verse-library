using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { /Fortnite.com/Characters }

# プレイヤーとその体（キャラクターの entity）を行き来する。
# entity → agent は Epic の標準の形で、entity に付いた possessable_component の Agent（その entity を今操っている agent）を読む。

# Agent の体の entity（fort_character の entity）。キャラクターがいない（スポーン前・退出後など）と失敗する
(Agent:agent).FindPlayerEntity<public>()<decides><transacts>:entity =
    Agent.GetFortCharacter[].GetEntity[]

# Body を今操っている agent（Body に付いた possessable_component の Agent）。possessable_component が無い・だれも操っていないと失敗する。
# プレイヤーのキャラクターの entity なら、そのプレイヤー。NPC など、プレイヤー以外が操っていることもある
(Body:entity).FindPossessingAgent<public>()<decides><transacts>:agent =
    Body.GetComponent[possessable_component].Agent?

# Body を今操っているプレイヤー。プレイヤー以外（NPC など）が操っている・だれも操っていないと失敗する
(Body:entity).FindPlayer<public>()<decides><transacts>:player =
    player[Body.FindPossessingAgent[]]

# Body を今操っている agent のキャラクター（fort_character）。だれも操っていない・キャラクターがいないと失敗する
(Body:entity).FindFortCharacter<public>()<decides><transacts>:fort_character =
    Body.FindPossessingAgent[].GetFortCharacter[]
