# ConditionSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
GroupKit<public> := module {}
# 届いた scene_event で満たす条件（event_received_condition_component）
EventKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
