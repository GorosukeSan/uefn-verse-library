# VolumeSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ActivationKit<public> := module {}
# ボリュームの中の人数の条件（player_in_volume_condition_component）
ConditionKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
# ボリュームの中の人にだけ widget を出す部品
WidgetKit<public> := module {}
