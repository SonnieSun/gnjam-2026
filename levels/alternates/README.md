# 保留的关卡配置（不在主菜单上）

`Levels.paths()` 只扫描 `levels/` 目录里的 `.tres`，这个子目录里的不会出现在菜单上，也不会改变菜单顺序。想用哪个，挪回 `levels/` 并按文件名排好序就行（主菜单转盘的格子会自动跟着变）。

- `disco.tres` + `disco_music.json`：远端合并时保存的旧 DISCO 版本。现在用的 DISCO 是 `levels/level_1_disco.tres`。
- `orbit_cat.tres`：moumou 的 ORBIT CAT（拍地球猫三段），原来是第 3 格，没有单独的音乐配置。它的猫、地球、星系美术现在用在第 2 格电视机关卡钻进屏幕之后的拍地球小关里。

- （吸猫关 `abduction.tres` 后来变成天空关的占位，接在第 1 关后面当插曲关；2026-11-17 起天空关是第 2 大关 `levels/level_2_sky.tres`。）
- `pizza_cat_level_5.tres` + `pizza_cat_level_5_music.json`：PIZZA CAT（原来的第 5 格）。

现在主菜单四格（2026-11-17 按 Kisa 的要求）：1 DISCO / 2 SKY（飞船吸猫）/ 3 TV WALL（洗衣机开场 + 拍地球）/ 4 SPACESHIP（星球 + 万花筒）。
