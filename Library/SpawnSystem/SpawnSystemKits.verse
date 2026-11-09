# SpawnSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
OriginKit<public> := module {}
# prefab を出す部品（spawner の factory の prefab_spawn_factory_component、起動や関数で好きな場所・数を出す spawn_prefab_component と出す場所の spawn_point_component）
PrefabKit<public> := module {}
# エディターに出す説明（message）
TooltipKit<public> := module {}
