using { /Verse.org/Simulation }
using { /Verse.org/Assets }
using { /Verse.org/Input }
using { /Fortnite.com/Input }

# 役割：入力を待つための小さな部品（能力の RunFor や、1 人分の view から呼ぶ）。基底クラスを継承しなくてよい
# 使い方の例（押しているあいだだけ何かする）：
#   MaybeInput := Agent.AwaitPlayerInput()   # <suspends> は if の条件で呼べない（V3512）ので先に受ける
#   if (PlayerInput := MaybeInput?):
#       race:
#           PlayerInput.HoldInputMapping(Mapping, RemoveMappingOnRevoke)
#           loop:
#               PlayerInput.AwaitPressed(Action)
#               race:
#                   PlayerInput.AwaitReleased(Action)
#                   DoWhileHeld()

# Agent がプレイヤーなら、その人の入力（player_input）を返す。プレイヤーでない・入力が取れないと失敗する
(Agent:agent).FindPlayerInput<public>()<decides><transacts>:player_input =
    GetPlayerInput[player[Agent]]

# Agent の入力（player_input）が取れるまで、1 フレームずつ待って取り直す（シミュレーション開始直後や参加した直後は、まだ取れないことがある）。
# 取れたらそれを返す。プレイヤーでない・取れる前に退出したら false。能力の RunFor の頭で使う（FindPlayerInput で 1 回だけ試すと、取れなかった人には能力が動かないまま「付与中」になる）
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

# Action が押される（検出が始まる = BeginDetectEvent）まで待つ。Action を含む input_mapping がその人に足されていないと届かない
(PlayerInput:player_input).AwaitPressed<public>(Action:input_action(logic))<suspends>:void =
    PlayerInput.GetInputEvents(Action).BeginDetectEvent.Await()

# Action が離される（検出が終わる = EndDetectEvent）まで待つ。押していないときに呼ぶと、次に押して離すまで戻らない
(PlayerInput:player_input).AwaitReleased<public>(Action:input_action(logic))<suspends>:void =
    PlayerInput.GetInputEvents(Action).EndDetectEvent.Await()

# Mapping をその人に足し、止められる（race で負ける・キャンセルされる）まで戻らない。RemoveOnEnd が true なら、止められたときに Mapping を外す
# race の 1 本の枝として使い、能力が止まると同時に後片付けされるようにする
# 前提・注意：RemoveOnEnd は、その能力専用の割り当てを選んだときだけ true にする。RangedWeaponMapping / TraversalMapping など、武器や移動も使う割り当てを外すと、撃てない・動けなくなる。
#   外すときは数えずに外すので、同じ割り当てをほかの機能（別の能力・player_input_component など）が使っているときも true にしない
(PlayerInput:player_input).HoldInputMapping<public>(Mapping:input_mapping, RemoveOnEnd:logic)<suspends>:void =
    PlayerInput.AddInputMapping(Mapping)
    defer:
        if (RemoveOnEnd?):
            PlayerInput.RemoveInputMapping(Mapping)
    Sleep(Inf)
