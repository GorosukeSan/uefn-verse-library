using { /Verse.org/SceneGraph }
using { /Verse.org/Simulation }
using { ModeSystem.TooltipKit }

# 役割：ゲームのモードを 1 つ表す。Title は画面に出す名前、Order は候補の順番
# 置き方：エディターで entity に付ける。mode_select_component の entity の直下に、モードの数だけ 1 つずつ（並び順は関係ない。順番は Order で決める）
game_mode_component<public> := class<final_super>(component):

    # 画面に出すモードの名前。既定 "Mode"
    @editable:
        ToolTip := ModeTitleToolTip
        Categories := array{ModeCategory}
    Title<public>:string = "Mode"

    # 候補の順番（小さいほど先）。mode_select_component.GetModes の並びと、投票が同数のときの勝ち（小さいほうが勝つ）に使う。同じ値どうしの順番は決まらない
    @editable_number(int):
        ToolTip := ModeOrderToolTip
        Categories := array{ModeCategory}
        MinValue := option{0}
        MaxValue := option{1000}
    Order<public>:int = 0
