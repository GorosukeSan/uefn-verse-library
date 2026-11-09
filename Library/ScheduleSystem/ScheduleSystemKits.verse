# ScheduleSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ConditionKit<public> := module {}
# 残り時間を文字・数字のメッシュで出す component（schedule_text_component / schedule_digit_display_component）
DisplayKit<public> := module {}
# 開始前のカウントダウンを画面に出す component（schedule_countdown_hud_component）
HudKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
