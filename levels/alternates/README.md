# 保留的 DISCO 配置

`level_2.tres` 合并冲突中的 DISCO 版本保存在 `disco.tres`，它对应的新叠轨配置保存在 `disco_music.json`。文件内容完整保留。

主菜单第 2 关继续使用 ORBIT CAT；原 DISCO 的两段叠轨覆盖已关闭，猫猫三段关卡使用 `level_2.tres` 中的 120 BPM 伴奏。

`Levels.paths()` 只扫描 `levels/` 目录里的 `.tres`，不会把此子目录中的保留版本加入菜单，也不会改变现有菜单顺序。
