# LevelKit：音游关卡工具骨架

Godot 4.7。一份关卡就是一个 JSON 文件，里面有两样东西：谱面（音符）和世界（摆在场景里的东西）。

工具里可以手摆、录制、程序生成、试玩，游戏里一行代码把关卡加载出来。

## 打开

- 在 Godot 里打开 `levelkit/level_editor.tscn`，按 **F6**（运行当前场景）。主场景还是原来的 `node_2d.tscn`，没有动。
- 命令行（`G` 是 Godot 可执行文件的路径）：

```bash
"$G" --path . res://levelkit/level_editor.tscn
```

## 编辑器操作

**顶栏**：关卡名、New / Save / Open、Undo / Redo、Song…、BPM、Offset、Beats、播放、Rec、Metro、Hits、吸附精度、Seed、Diff、from song、Gen chart、Gen world、PLAYTEST。

| 位置 | 操作 |
|---|---|
| 谱面（下） | 左键空白处加音符，向右拖成长按；左键拖音符可以移动；右键删除；点顶部刻度条跳转播放头；滚轮滚动时间，Ctrl/Cmd+滚轮缩放 |
| 世界（中） | 左侧选一个类型后点击放置（吸附到拍子网格，按住 Shift 不吸附）；左键拖动物体；右键删除；滚轮缩放；中键或空白处拖动平移 |
| 左栏 | 物体调色板，以及选中物体的属性面板（根据 Registry 自动生成） |

**快捷键**

| 键 | 作用 |
|---|---|
| Space | 播放 / 暂停 |
| Home | 回到开头 |
| Tab | 从播放头开始试玩（Esc 返回） |
| D F J K | 试听轨道音；开着 **Rec** 时直接写进谱面，按住超过半拍会变成长按 |
| R / M / H | 录音 / 节拍器 / 打击音 |
| Ctrl/Cmd + S | 保存 |
| Ctrl/Cmd + Z / Shift+Z / Y | 撤销 / 重做 |
| Ctrl/Cmd + D | 复制选中的物体 |
| Delete | 删除选中的物体 |
| Esc | 回到选择工具 |

**存档位置**：从 Godot 里运行时存到 `res://levels/`（跟着仓库一起提交）；导出版存到 `user://levels/`。

## 做一关的流程

1. 把歌放进 `songs/`，跑一次分析（只需要 numpy；ogg/mp3 还要装 soundfile）：

   ```bash
   pip install numpy soundfile
   ```

   ```bash
   python3 tools/analyze_song.py songs/my_song.ogg
   ```

   已经知道 BPM 的话，加上 `--bpm 128`，这样只搜 offset。
2. 在编辑器里点 **Song…** 选这首歌（也可以直接把文件拖进窗口）。BPM 和 Offset 会从 `.analysis.json` 自动填好。
3. 打开 **Metro** 播放，用耳朵校准 Offset，让节拍器的咔哒声落在鼓点上。任何节拍检测都可能差半拍。
4. 出谱面，三种办法可以混着用：
   - **Gen chart**：程序生成。勾上 from song 就按歌的 onset 生成，不勾就按节奏型库生成。Seed 和 Diff 控制结果。
   - **Rec**：边听边按 D F J K 录进去。
   - 在谱面上手修。
5. **Gen world** 按谱面铺出世界。这只是个跑酷示例，换成你们自己的规则。之后可以手动调。
6. 按 **Tab** 试玩，看准确率和偏差的毫秒数。
7. 按 Ctrl+S 保存。

## 在游戏里用

```gdscript
var level := LevelData.load_file("res://levels/stage1.json")
LevelBuilder.build(level, $World)        # 按 Registry 生成每个物体

var clock := SongClock.new(level)        # 歌曲时钟：用音频播放位置校正，不会漂移
add_child(clock)
clock.load_song()
clock.play()
clock.note_passed.connect(func(n): ...)  # 每个音符到达时触发
clock.beat                               # 当前拍子（float）
clock.hits(lane)                         # x = 已经过的次数，y = 距上一次多少拍

var judge := Judge.new(level)            # 判定：press(lane, clock.time) / expire(clock.time)
```

世界坐标和时间是绑定的：`x = beat * meta.px_per_beat`。所以按拍子摆的东西在游戏里天然就踩在节拍上。

## 比赛中要改的地方

| 想做的事 | 改哪里 |
|---|---|
| 加一种物体 | `core/registry.gd` 里加一行 `add("enemy", {label, color, size, scene = "res://...tscn", props = [...]})`。调色板、属性面板、存档、LevelBuilder 都会自动跟上 |
| 物体的参数 | `props` 里用 `param()` / `choice()` / `flag()`。游戏里会按属性名赋值给节点，如果节点有 `setup(props)` 方法也会调用 |
| 改轨道数、名字、按键、音色 | `Registry.LANES` |
| 换生成规则 | `core/chart_gen.gd`：`PATTERNS` 节奏型库（越多越不重复）、`_assign_lanes` 轨道规则、`place_runner` 世界规则 |
| 判定窗口 | `core/judge.gd` 顶部的三个常量 |
| 真正的玩法 | 自己写一个场景，用上面的 `SongClock` + `Judge` + `LevelBuilder`。`play/playtest.gd` 是一个可以参考的最小例子 |

## 结构

```
levelkit/
  level_editor.tscn       编辑器入口
  core/                   数据和规则，不碰界面（游戏也用这些）
    level_data.gd         一关 = meta + chart + entities；存读 JSON
    registry.gd           (autoload) 物体类型和轨道 ← 比赛时主要改这个
    song_clock.gd         歌曲时钟、音符事件、hits()
    judge.gd              时间判定
    chart_gen.gd          谱面 / 世界生成
    level_builder.gd      关卡 → 游戏节点
    level_doc.gd          撤销/重做、关卡文件夹
    sfx.gd                (autoload) 合成的占位音效
  editor/                 chart_view（谱面）、stage_view（世界）、side_panel、level_editor
  play/playtest.gd        通用四轨试玩
  dev/dev_tools.gd        命令行工具和自测
  ui/ui_kit.gd            主题和控件构造（来自 gnjam）
tools/analyze_song.py     歌曲分析：BPM、offset、onset
levels/                   关卡 JSON
songs/                    歌和它的 .analysis.json
```

## 开发命令

都写在 `--` 后面：

- 自测：把所有系统跑一遍，包括模拟鼠标编辑谱面和世界、录音、试玩的开关。

  ```bash
  "$G" --headless --path . res://levelkit/level_editor.tscn -- --selftest
  ```

- 批量生成关卡：

  ```bash
  "$G" --headless --path . res://levelkit/level_editor.tscn -- --gen=stage2 --seed=3 --diff=0.7 --bars=32 --bpm=140 --world
  ```

- 其他参数：
  - `--level=名字`：打开指定关卡。
  - `--song=文件 [--gen-from-song]`：导入歌曲，可选直接按 onset 生成谱面。
  - `--shot=x.png [--play|--playtest] [--at=秒]`：截图后退出。

## 已知限制

- 输入延迟没有单独校准，只有歌曲的 Offset。蓝牙耳机要另外加一个全局输入偏移。
- 编辑器里的物体只画占位方块，不实例化真实场景。真实场景要在游戏里看。
- 没有框选和批量操作，也没有变速歌（BPM 是单一值）。
- 用歌曲 onset 生成的谱面需要人工过一遍。
