# LoadoutSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
# エディターに出す説明（message）
TooltipKit<public> := module {}
