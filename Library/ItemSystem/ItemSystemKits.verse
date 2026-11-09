# ItemSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
ExclusiveKit<public> := module {}
# アイテムを配る Kit（item_grant_component / item_grant_entry_component）
GrantKit<public> := module {}
# アイテムの扱いの決まりを足す Kit（item_equip_lock_component）
RuleKit<public> := module {}
# エディターに出す説明（message）を置く Kit
TooltipKit<public> := module {}
