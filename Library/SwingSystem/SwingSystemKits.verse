# SwingSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ModifierKit<public> := module {}
# TargetKit：つかまれる物の振る舞い（swing_life_component・swing_lift_component）
TargetKit<public> := module {}
# TooltipKit：ToolTip・Categories の文言（message）
TooltipKit<public> := module {}
