# 迪斯科关卡 · 分层循环配乐 v3

- 120 BPM，4/4 拍，**每条分轨 8 小节 = 16 秒 = 705600 采样（44.1kHz）**，第 0 秒就是第 1 拍
- 所有分轨同长度、同起点，可以放进 AudioStreamSynchronized 一起循环。混响尾巴已经折回开头，首尾无缝。
- 音量已经统一配好：一套里所有轨同时开到 0 dB 正好不削波，不用再单独调平衡。
- 机器可读版本：`layers.json`

## 两套循环
房间段（摇摆爵士）和上路以后（Piano House）的和声不一样，叠不到同一个循环上，所以分成两套，**在拆房子那一下从 room 切到 road**。两套的 00_base 各自不同。

### room（房间里）
| 文件 | 对应元素 | 内容 |
|---|---|---|
| loops/room_00_base.ogg | 固定背景节拍，一直放 | 摇摆鼓 + walking bass |
| loops/room_01_stars.ogg | 星星灯 | Charleston 节奏钢琴 |
| loops/room_02_ball.ogg | 灯球 | 铜管和弦短奏 |
| loops/room_03_dancers.ogg | 2D 跳舞猫 | 单簧管主旋律 + 喵喵合唱 |
| loops/room_04_drift.ogg | 猫漂移 | pad + 高音琶音 |

### road（拆房子上路以后）
| 文件 | 对应元素 | 内容 |
|---|---|---|
| loops/road_00_base.ogg | 固定背景节拍，一直放 | house 鼓 + 失真贝斯 / sub（带侧链） |
| loops/road_05_road.ogg | 拆房子上路 | 反拍 house 钢琴 |
| loops/road_06_dance_floor.ogg | 舞池地板 | 单簧管 + 铜管齐奏副歌 |
| loops/road_07_grid.ogg | 霓虹网格 | 方波琶音 + 合成器 pad |
| loops/road_08_plaza.ogg | 圆台 | 合成器主音（副歌高八度）+ 喵 |
| loops/road_09_ufo.ogg | 飞碟吸猫（可选） | 特雷门琴长音 |

## 音效（spin_sfx/）
- `kick.wav` / `snare.wav` / `hat.wav`：按键鼓采样，和分轨里的鼓同音色
- 旋转时可选的音效：`spin_scratch`（黑胶搓碟）、`spin_cowbell`（牛铃）、`spin_zap`（电子“咻”）、`spin_meow`（短喵）、`spin_swoosh_clap`（风声 + 拍手）。这几个都是不带音高或很短的声音，放在哪一拍都不会和和弦打架。

## 试听
`preview/preview_room.ogg`、`preview/preview_road.ogg`：每隔几秒加一层，最后一遍所有层全开。

## 重新生成
`python3 compose_layers.py <输出目录>`，大约 40 秒。改编曲看 `set_room()` 和 `set_road()`。
