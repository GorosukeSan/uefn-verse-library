# CheckpointSystem の Kit をライブラリの外（利用者のコード）から使えるように public にする。
# フォルダから作られるモジュールは既定で internal なので、宣言しないと外から using できない。
PresenceKit<public> := module {}
# チェックポイントに乗ったらエネルギー（EnergySystem）を満たす Kit（checkpoint_energy_refill_component）
EnergyKit<public> := module {}
# チェックポイントを spawner で出す Kit（checkpoint_factory_component）
SpawnKit<public> := module {}
# エディターに出す説明（message）を置く Kit
TooltipKit<public> := module {}
