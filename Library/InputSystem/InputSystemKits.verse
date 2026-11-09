# InputSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
InputKit<public> := module {}
# 「準備 OK」の部品（player_ready_component・all_players_ready_condition_component）
ReadyKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
