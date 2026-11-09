# FNDeviceSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# スケジュール（ScheduleSystem）の期間中にシネマティック シーケンス デバイスを再生する component（schedule_sequence_component）
ScheduleKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
