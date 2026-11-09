# InteractSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ConditionKit<public> := module {}
# 押せる・押せないを切り替える部品（interact_gate_component）
GateKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
