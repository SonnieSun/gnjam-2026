# 保留的关卡配置（不在主菜单上）

`Levels.paths()` 只扫描 `levels/` 目录里的 `.tres`，这个子目录里的不会出现在菜单上，也不会改变菜单顺序。想用哪个，挪回 `levels/` 并按文件名排好序就行（主菜单转盘的格子数也要跟着改）。

- `disco.tres` + `disco_music.json`：远端合并时保存的旧 DISCO 版本。现在用的 DISCO 是 `levels/level_1_disco.tres`。
- `abduction.tres` + `abduction_music.json`：原来的第 3 关 ABDUCTION（吸猫小关）。现在吸猫已经接在第 1 关 DISCO 的结尾，第 3 关换成了 ORBIT CAT（`levels/level_3_orbit_cat.tres`）。

现在主菜单的顺序：1 DISCO / 2 SPACESHIP / 3 ORBIT CAT / 4 TV WALL / 5 LEVEL 5。
