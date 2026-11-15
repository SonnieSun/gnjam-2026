# 保留的关卡配置（不在主菜单上）

`Levels.paths()` 只扫描 `levels/` 目录里的 `.tres`，这个子目录里的不会出现在菜单上，也不会改变菜单顺序。想用哪个，挪回 `levels/` 并按文件名排好序就行（主菜单转盘的格子数也要跟着改）。

- `disco.tres` + `disco_music.json`：远端合并时保存的旧 DISCO 版本。现在用的 DISCO 是 `levels/level_1_disco.tres`。
- `orbit_cat.tres`：moumou 的 ORBIT CAT（拍地球猫三段），原来是第 3 格，没有单独的音乐配置。它的猫、地球、星系美术现在用在第 2 格电视机关卡钻进屏幕之后的拍地球小关里。

- `abduction.tres` + `abduction_music.json`：单独的吸猫关（原来的第 4 格）。吸猫仍接在第 1 关 DISCO 的结尾。
- `pizza_cat_level_5.tres` + `pizza_cat_level_5_music.json`：PIZZA CAT（原来的第 5 格）。

现在主菜单只有三格（2026-11-15 按 Kisa 的要求）：1 DISCO / 2 TV WALL（洗衣机开场 + 拍地球）/ 3 SPACESHIP（星球 + 万花筒）。
