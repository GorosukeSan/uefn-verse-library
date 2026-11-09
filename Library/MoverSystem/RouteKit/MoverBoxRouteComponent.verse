using { /Verse.org/SceneGraph }
using { /Verse.org/SpatialMath }
using { /Verse.org/Random }
using { MoverSystem }

# 役割：BoxMinCm〜BoxMaxCm（世界の位置、センチメートル）の直方体の中のランダムな点を、次々に行き先にする道のり（終わらない）。MarginCm だけ内側を使う（自分の大きさの半分を入れると、はみ出さない）。行き先は今の位置から MinStepCm 以上先を選ぶ（何回か選んでもだめならそのまま）
# 置き方：実行時に作る（グリッドの範囲を借りた spawner などが、借りた範囲を BoxMinCm / BoxMaxCm に入れて付ける）
# 同じ entity：mover_component（ぶつかって跳ね返したいなら Motion = Physics）
mover_box_route_component<public> := class<final_super>(mover_route_component):

    # 直方体の小さい側の角（世界の位置、センチメートル）
    BoxMinCm<public>:vector3 = vector3{}
    # 直方体の大きい側の角（世界の位置、センチメートル）
    BoxMaxCm<public>:vector3 = vector3{}
    # 各面から内側へ空ける幅（センチメートル）。軸の長さより大きいと、その軸は真ん中だけを使う
    MarginCm<public>:float = 0.0
    # 次の行き先を、今の位置から少なくともこれだけ先にする（センチメートル）
    MinStepCm<public>:float = 100.0

    MaxAttempts<private>:int = 8

    var Picked<private>:int = 0

    # 選んだ回数（mover_target.Index）を 0 に戻す（mover_component の Restart が呼ぶ）
    Reset<override>():void =
        set Picked = 0

    NextTarget<override>(Home:vector3, Position:vector3):?mover_target =
        var Candidate:vector3 = MakeRandomPoint()
        var Attempt:int = 1
        loop:
            if (Attempt >= MaxAttempts or Distance(Candidate, Position) >= MinStepCm):
                break
            set Candidate = MakeRandomPoint()
            set Attempt += 1
        Index := Picked
        set Picked += 1
        option{mover_target{Position := Candidate, Index := Index}}

    MakeRandomPoint<private>()<transacts>:vector3 =
        vector3:
            Forward := PickBetween(BoxMinCm.Forward, BoxMaxCm.Forward)
            Left := PickBetween(BoxMinCm.Left, BoxMaxCm.Left)
            Up := PickBetween(BoxMinCm.Up, BoxMaxCm.Up)

    PickBetween<private>(Low:float, High:float)<transacts>:float =
        Inner := Low + MarginCm
        Outer := High - MarginCm
        if (Inner < Outer):
            GetRandomFloat(Inner, Outer)
        else:
            (Low + High) / 2.0
