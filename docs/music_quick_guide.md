# 音乐系统速查（给 Kisa 这边和 AI 助手看）

2026-11-15，音效这边（EiZi233）把叠轨音乐系统合进了这个分支。出问题先看这一页。

## 我们做了什么

1. **把 develop_framework 合并进来了**（正常的 git merge，没有冲突）。带来了：`Music` 自动加载、打中喵、曲库、
   全部音乐素材（`assets/audio/`）。
2. **Kisa 的四个大关（现在是 level_2 迪斯科、level_3 飞船、level_4 电视墙、level_8_abduction 吸猫）的音乐换成了我们的叠轨音乐**，跟着积累条一层层加。迪斯科关保持 120 BPM；另外三关是 160（比原来快）。
3. **打中会喵**；连击到 10、20、50……会响一声转圈喵。
4. 对原有文件只改了两处：`stages/disco/disco_music.gd` 加了 4 行（我们的音乐开着时它不去动音轨），`scripts/main.gd` 加了几行接音乐和喵。
   关卡场景、谱面、演出都没动。

## 怎么关掉 / 退回原来的音乐

每个大关一个配置文件：`levels/music/<大关文件名>.json`（比如 `level_2.json`）。
把里面的 `"use_in_game": true` 改成 `false`，这一关就**完全回到原来的音乐和速度**。删掉这个文件效果一样。

- 不想要打中喵 / 转圈喵：`main.tscn` 里选 HitMeow 节点，取消 `enabled`（或调 `volume_db`、清空 `spin_sounds`）。

## 怎么听、怎么改

- **改音乐**：运行游戏后按 **Tab** 调出编辑面板，"音乐"页里每条轨道点一段 = 从当前进度起换成它；最上面的 Gauge 条就是积累条。改完点 Save。
  加轨道、加片段直接改 `levels/music/` 里的 json（原来的 Music Director 面板已经被这个面板取代）。
- **写猫鼓 / 鬼畜猫旋律**：Tab 面板最上面一排点 **Meow**（或打开 `scenes/tools/meow_studio.tscn` 按 F6），进全屏的喵谱子工作室。
  选一个大关当伴奏，PLAY，点格子写谱子，Listen 边改边听，Save 存成 `levels/music/patterns/` 里的 json；
  Add to lane 把它作为新片段加进那一关的轨道（马上写进那一关的音乐配置），回游戏后在 Music 页选它。不替换原来的片段。
  有 MIDI 的话：`python tools/music_gen/midi_to_pattern.py 曲子.mid --name 名字`。
- **只想听**：编辑面板最上面一排点 **Jukebox**，或者在 Godot 里打开 `scenes/tools/jukebox.tscn` 按 F6。
  点一首就放，下面的按钮开关每条音轨，最下面是所有音效。不改任何东西；Esc 回主菜单。
- 配置格式和设计见 `docs/music_manager.md`，素材清单见 `assets/audio/README.md`。

## 它是怎么接进游戏的（排查用）

- `scripts/main.gd` 的 `_ready`：如果这一关的配置开了 `use_in_game`，就用 `Music.build(...)` 建的同步音轨代替谱面的 `stream`，
  速度用配置里的 `bpm`；进小关时调 `Music.set_section(i)`，积累条变化时调 `Music.set_progress(值 / 满条值)`。
- 轨道在小节线上切换（进度变了要等到下一个小节线才换）。
- 迪斯科关：分数线还是 `disco.tscn` 里那 9 条，音乐配置里的切换点就是按这 9 条线写的。改了分数线，音乐不会自动跟着变，
  要到面板里挪切换点（或改 `tools/music_gen/make_music_sets.py` 里的 `E` 再重新生成）。

## 常见问题

| 现象 | 原因 / 办法 |
|---|---|
| 某一关变快了 | 它的音乐配置是 160。把 `use_in_game` 关掉，或者以后给它做 120 的素材 |
| 迪斯科关没有声音或层不对 | 看 `levels/music/level_2.json` 在不在、`use_in_game` 是不是 true；关掉就回到原来的 11 条分轨 |
| 打开项目报找不到音频 | 重新导入一次（关掉 Godot 再开，或 项目 → 重新加载当前项目）；素材在 `assets/audio/music/` |
| 主菜单转盘只有 5 格 | 原来就是这样（转盘没跟着加格子）。用顶部"关卡"页选大关点"试玩"，或在转盘上往右拨到第 6–9 关（没有格子亮） |
| 导入时报几个模型贴图找不到 | 和音乐无关，是飞碟模型原有的 |
| 想换一关的曲子 | 面板"编辑"页里给轨道"+ 片段"选别的 WAV；同一关里要用同一个速度、同一套和声的素材（`scene1` 一套、每首经典曲各一套、`scene1_120` 是 120 的） |
