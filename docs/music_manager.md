> **注意（后来的改动）**：Music Director 面板和它的编辑器插件已经删掉了。按进度切换片段现在在游戏里按 Tab 调出的面板上编辑（`scripts/tools/game_editor.gd`）；加轨道、加片段直接改 `levels/music/` 里的 json。下文里关于 Music Director 的部分只作历史记录。

# 叠轨音乐播放管理（设计）

> **已经做了的（2026-11-15）**：`Music` autoload（`scripts/music/music.gd`）和 Music Director 面板
> （`scenes/tools/music_director.tscn`，F6 运行）。每个大关的配置在 `levels/music/<大关文件名>.json`（如 `level_1.json`）。
> 下面"运行时"一节写的四个旋钮，第一版统一成了更简单的东西：**几条轨道，每条放几段 loop，同一时刻
> 只响一段；每个小关里写"积累条进度到哪儿换成哪段"**。详见文末"Music Director"。

目标：一关的音乐由几层 loop 叠起来，玩法推进时在小节线上加层、换层、换风格，节拍时钟不受影响。
素材见 `assets/audio/README.md`。下面是第一版要做的东西，先简单能用。

## 核心做法：一个同步流 + 只改音量

- 一关用到的**所有** loop（每层的每个版本）放进一个 `AudioStreamSynchronized`，从第 0 秒一起播放，
  永远不停、不跳。要"开一层"就是把它的音量从 −80 dB 拉到 0，要"换风格"就是 A 的音量降、B 的音量升。
- 这样所有层天然对齐（同一个混音循环里推进），不会有"后开的层慢几毫秒"的问题；loop 长度不同
  （4 / 8 / 16 小节）也没关系，因为都是整数小节，各自循环，永远对得上。
- **Conductor 不用改时钟逻辑**：它本来就是放一个 stream、读 `get_playback_position()` 算 `song_beat`。
  只要把它放的 stream 换成这个同步流。

已经在 Godot 4.7.2 里验证过（headless）：

- 打包时写进 WAV 的 `smpl` 循环点会被导入器读到，导入后 `loop_mode = LOOP_FORWARD`，循环整个文件；
- 三个不同长度的 loop 放进 `AudioStreamSynchronized` 一起播放，`get_playback_position()` 按真实时间
  往前走（7 秒时报 6.97 s），`get_length()` 是最长那条的长度（这里 24 s），可以直接给 Conductor 当一遍的长度；
- `set_sync_stream_volume(i, db)` 可以单独控制每条的音量。

限制：一个 `AudioStreamSynchronized` 最多 32 条。所以每关只放这关会用到的版本（第 1 关全部风格加猫化加
节奏型大约 30 条，正好装得下；爵士是另一套骨架，单独一关）。

## 数据：每关一个 MusicSet

`MusicSet`（Resource，存成 `.tres`，放 `levels/` 或 `assets/audio/music/<关>/`）：

| 字段 | 说明 |
| --- | --- |
| `bpm` | 160 |
| `layers` | 一组 `MusicLayer`：`slot`（槽位名）、`variant`（版本名）、`stream`（WAV） |
| `start_phase` / `start_style` | 开局状态 |

槽位（slot）就是"同一时刻只响一个版本"的位置：

| 槽位 | 第 1 关的版本 |
| --- | --- |
| `bed`（L0） | `futurebass` · `eurobeat` · `chip` · `disco` · `cat`（C_stabs） |
| `groove`（L1） | `four` · `half` · `break` · `club` |
| `bass`（L2） | `four` · `half` · `break` · `club` · `cat`（C_bass） |
| `hook`（L3） | `futurebass` · `eurobeat` · `chip` · `disco` · `cat`（C_lead） |
| `peak`（L4） | `futurebass` · `eurobeat` · `chip` · `disco` |
| `meowdrums` | `on`（C_drums，叠加层，没有别的版本） |
| `event_meow` / `event_seal` / `event_vox` | 事件层（X_meow、X_seal、X_vox） |

经典曲一关：`bed` = `fb_L0_keys` / `cat`（C_stabs）；`hook` = `pluck` / `cat_flow` / `cat` / `cat_pool`；
`bass` = `L2_bass` / `cat`（C_bass）；`peak` = `fb_L4_peak`；`meowdrums`；`groove` 用第 1 关的。

## 运行时：Music（autoload）

状态只有四个"旋钮"，每个旋钮的变化都**排队到下一个边界**才生效：

| 旋钮 | 值 | 生效时机 | 作用 |
| --- | --- | --- | --- |
| `phase` | 0–4 | 下一小节 | 开哪些槽：0 = bed+groove，1 = +bass，2 = +hook，3 = +peak，4 = 全开 |
| `style` | 风格名 | 下一个 4 小节边界 | bed / hook / peak 换成这个风格的版本 |
| `catness` | 0–4 | 下一小节 | 1 = +meowdrums，2 = bed→cat，3 = hook→cat，4 = bass→cat |
| `rhythm` | four / half / break / club | 下一个 4 小节边界 | groove + bass 换版本；谱面要同时换 |

接口（草案）：

```gdscript
Music.load_set(set: MusicSet)        # 建同步流交给 Conductor，按开局状态设音量
Music.set_phase(n: int)
Music.set_style(style: StringName)
Music.set_catness(level: int)
Music.set_rhythm(rhythm: StringName)
Music.trigger_event(slot: StringName, bars := 4)   # 事件层开 N 小节后自己关
Music.miss()                          # hook / peak 降 9 dB，一小节后回来
```

每个槽位当前应该响哪个版本，由四个旋钮算出来（`_target_variant(slot)`）。到边界时对每条子流比较
"该不该响"，该响的 10 ms 淡入，不该响的淡出 1 拍。

### 边界和淡入淡出

- 在 `_process` 里看 `Conductor.song_beat`：一越过排队的边界（小节 = 4 拍，4 小节 = 16 拍）就应用。
  为了不晚，提前 `AudioServer.get_output_latency()` 应用（和 Conductor 算时间的方式一致）。
- 淡入淡出自己在 `_process` 里按幅度线性插值，每帧调 `set_sync_stream_volume()`；−80 dB 当静音。
- 晚一帧（约 16 ms）开层，最多吃掉这一小节第一下的开头，听得出但不严重；第一版先这样，不行再改成
  提前一帧排程。

### 总线

| 总线 | 内容 | 效果 |
| --- | --- | --- |
| `Music` | 同步流 | 压缩器，`sidechain = "Kick"`：玩家打中时音乐让一下 |
| `Kick` | 玩家底鼓、拍手（DrumKit / Sfx） | — |
| `Sfx` | 猫叫单发、转场音效 | — |

同步流只能进一条总线，所以 MISS 的"变闷"第一版改成 hook / peak 降音量；真要低通，把 hook 和 peak
拆进第二个同步流放 `MusicTop` 总线，和第一个同一帧 `play()`（要实测两者对不对得齐）。

## 转场（和 Conductor 的小节信号配合）

| 时机 | 做法 | 素材 |
| --- | --- | --- |
| 第 20 小节（一关的最后一小节） | 除 groove、bass 外全部淡出；放上升音效 | `sfx/riser_1b.wav` |
| 下一小节首拍 | 镲；载入下一关的 MusicSet，从头播放 | `sfx/crash.wav` |
| 风格切换 | 切换前一小节第 4 拍放提示音 | `sfx/glitch_meow.wav`、`laser_zap.wav` |
| 猫化 +1 / −1 | 生效那一小节首拍 | `sfx/catness_up.wav` / `catness_down.wav` |
| 失败 | 音乐 `pitch_scale` 0.5 秒内降到接近 0（卡带停转），然后停 | `sfx/catness_down.wav` |
| 重来 | 倒带音效 1 小节，再从这一关第 1 小节开始 | `sfx/rewind_1b.wav` |
| 过关 | 第 20 小节后首拍用过关音效替代镲 | `sfx/level_clear.wav` |

单发音效对齐到拍子：在 `Conductor.beat` / `bar` 信号里放，或者算好下一拍的时间提前排。

## 第一版要做的

1. `MusicSet`、`MusicLayer` 两个 Resource，加第 1 关和一首经典曲（康康舞曲）的 `.tres`。
2. `Music` autoload：`load_set` 建同步流交给 Conductor，四个旋钮，边界排队，淡入淡出。
3. Conductor 加一个 `load_stream(stream)`（不用谱面里的 stream 时用），时钟逻辑不动。
4. 调试面板：按键切 phase / style / catness / rhythm，屏幕上显示当前小节和每条子流的音量。
5. 总线布局 + Music 总线上的侧链压缩。
6. 实测：长时间播放会不会漂（开 10 分钟看 `song_beat` 和各层是否还对齐）。

还没定的：猫化由什么驱动（连击，还是关卡进度）；六个 MV 场景各用哪个风格、哪首经典曲。

## Music Director（已做）

编辑器顶部工具栏点"音乐"按钮（或打开 `scenes/tools/music_director.tscn` 按 F6）。面板有两页：

- **曲库**：只是听。列出现在所有做好的曲子（四种风格、全猫乐队、Jazz、三种节奏、Entertainer、五首经典曲和它们的猫版、鬼畜版），
  点一首就循环放，下面的按钮开关它的每条音轨；最下面是所有一次性音效（喵、打中喵、SFX），点一下听一声。
  加了新曲子在 `scripts/music/jukebox.gd` 的 `_songs()` 里加一行。
- **编辑**：给每个大关配音乐，下面说的都是这一页。

一关的音乐是几条**轨道**（默认按乐器分：节奏、低音、和声、旋律、高潮、猫鼓、事件），每条轨道里放几段
**片段**（loop），同一时刻每条轨道只响一段。

- **点一段** = 从当前进度起，这条轨道换成它；再点正在响的那段 = 从这里起这条轨道静音。正在响的那段是粉色的。
- **PROGRESS** 就是积累条有多满：先拖到某个进度再点，就是"进度到这里时换成它"。
  SNAP 开着时等到下一个小节线才换（和游戏里一样）；AUTO 让进度随音乐在 N 小节里从 0 走到 100%。
- 每条轨道下的**细条**：颜色是每段进度里响的片段，白色小竖条是切换点，粉线是积累条事件线。
  拖切换点改位置（吸附 5% 和事件线），右键删掉。
- **+ 片段** 往轨道里放 WAV（从 `assets/audio/music` 里选），右键一段 = 拿掉；**+ 轨道** 加一条，`×` 删一条；
  轨道名字可以直接改；M 静音（只在面板里）；dB 是这条轨道的音量。一大关最多 32 段。
- 上面：选大关、选小关（名字和积累条事件线取自谱面）、PLAY、当前小节、USE IN GAME、SAVE、
  **EXPORT MIX**（录一遍 AUTO，也就是这个小关从 0% 到 100%，存成 `levels/music/exports/level_<n>_<小关>.wav`，不进 git）。
- 快捷键：Space 播放 / 停止，← → 进度 ±5%，↑ ↓ 换小关，Ctrl+S 保存。

配置和大关文件同名：`levels/level_1.tres` 的音乐是 `levels/music/level_1.json`，以此类推。
新加一个大关，面板里打开它就会新建一份空配置。第 3、4 关都是 MV：`level_3.json` 是 future bass 版，`level_4.json` 是 eurobeat 版。

配置格式：

```json
{
  "title": "LEVEL 1", "bpm": 160, "use_in_game": false, "quantize_beats": 4,
  "lanes": [{"id": "bed", "name": "和声", "gain_db": 0,
             "clips": [{"id": "fb_keys", "file": "res://assets/audio/music/scene1/style_futurebass/s1_fb_L0_keys_4b.wav"},
                       {"id": "cat_stabs", "file": "res://assets/audio/music/scene1/cat_band/s1_C_stabs_4b.wav"}]}],
  "sections": [{"title": "DISCO", "cues": {"bed": [[0, "fb_keys"], [0.5, "cat_stabs"]]}}]
}
```

`cues` 里每条轨道是一串 `[进度, 片段]`：进度到这里换成这段（`""` = 静音）；当前进度之前最后一个切换点说了算，
一个切换点都没到 = 静音。初始配置由 `tools/music_gen/make_music_sets.py` 生成（第 1 关：future bass 越来越猫；
第 2 关：16 个小关轮流换风格，第二轮加猫；第 3、4 关：六个 MV 小关一关比一关猫；第 5 关：康康舞曲）。之后都在面板里改。

游戏里（`scripts/main.gd`）：配置开了 `use_in_game` 的大关，谱面的伴奏换成这套同步流、BPM 换成配置的；
进小关时（`section_entered`）`Music.set_section(i)`，积累条变化时（`gauge.changed`）`Music.set_progress(值 / 满条值)`。
没开的大关用谱面自己的伴奏和 BPM。谱面默认是 160；Kisa 的四关（迪斯科、飞船、电视墙、吸猫）原来是按 120 做的，它们的 `.tres` 里写着 `bpm = 120`。

## 速度（BPM）

每个大关的速度写在它的音乐配置里（`levels/music/level_N.json` 的 `"bpm"`），游戏开了 USE IN GAME 就按它走，所以不同大关可以是不同速度。
现在所有素材都是 160。有些曲子（目前是致爱丽丝）更适合 120：还没渲染，只留了占位（`compose_classics.py` 的 `TEMPO`）；
要做的时候需要一套 120 的鼓和低音，再把那个大关的 `"bpm"` 改成 120。同一个大关里中途变速现在不支持。

## 以后：运行时猫旋律（第一版已经做了，见文末"喵谱子"）

想法：鬼畜版猫旋律不预渲染，旋律存成音符数据，游戏里按拍触发喵（每只猫一个采样，`pitch_scale` 变速变调，到点停掉 = 硬切，
共鸣提前烤进采样）。好处是变速不用重渲染、可以做成"打中才唱出这个音"。做好后和预渲染的 `L3_cat_kichiku` 对比，一样好再替换它。
普通猫版（拉长的 Miiiiao、互相叠）运行时做不了，继续用预渲染的音轨。

## Kisa 的四关（现在是 level_2、3、4 和 level_8_abduction）

这四关也用这套音乐系统（配置在 `levels/music/level_2.json` 等，都开了 USE IN GAME；关掉就回到关卡原来的音乐和 120 的速度）。
最早它们是 level_6 到 level_9，后来 Kisa 重排成了第 2、3、4 关，配置跟着改了名。

- **level_2 迪斯科（120 BPM）**：保持它原来的速度，用我们第 1 关素材的 120 版（`assets/audio/music/scene1_120/`）。
  和它原来的配乐一样，积累条每过一条事件线加一层：星星灯 = 和声，灯球 = 旋律，跳舞猫 = 猫鼓，漂移 = 高潮；
  拆房子上路时鼓和低音换成 club 节奏、和声旋律换成 future bass；舞池 = 猫旋律，网格 = 高潮回来，圆台 = 猫和声 + 猫低音，飞碟 = 喵事件轨。
  吸猫小关是全猫乐队配半拍节奏。关卡自己的分轨控制（`DiscoMusic`）在我们的音乐开着时让开，只改了它一处。
- **level_3 飞船 / level_4 电视墙 / level_8_abduction 吸猫（160 BPM）**：分别放 Eurobeat、山魔王（后段鬼畜猫）、Chip。注意它们原来是 120，开着我们的音乐整关会变快；
  嫌快就在配置里把 `use_in_game` 关掉。
- 连击到里程碑（10、20、50……）会响一声转圈喵（"oiia"），在 main.tscn 的 HitMeow 节点上调或关。

初始配置都由 `tools/music_gen/make_music_sets.py` 生成；120 的素材是 `CAT_BPM=120 python -I compose_disc.py` 渲染的。

## 音乐的档次（设计，2026-11-15）

一关的音乐按"有多猫、有多满"分档，积累条越满档越高。常态是**音乐 + 猫鼓 + 猫主旋律**；别的猫声部是点缀。

| 档 | 什么时候 | 响什么 |
|---|---|---|
| 0 开场 | 刚进小关 | 鼓 + 低音（可以带和声） |
| 1 音乐 | 积累条刚起来 | + 和声、乐器旋律 |
| 2 猫鼓 | 约三分之一 | + 猫鼓（先于猫旋律进） |
| 3 猫旋律（常态） | 约一半 | 乐器旋律换成猫主旋律（喵放完、互相叠的那版） |
| 4 高潮 | 约四分之三 | + 高潮层 |
| 5 KIAI | 最后 5%–15%，或特别的时刻 | 鬼畜猫旋律**叠在**猫主旋律上面。克制地用，短，一关一两次 |

- **猫和声、猫低音**少见：只在某一关的最后一段当"全猫"的颜色用，不是常态。
- **一关里换不换音轨**：小关之内，轨道跟着积累条换片段（上表）。小关之间可以换风格或换节奏型（比如迪斯科关拆房子时鼓换成 club、
  和声旋律换成 future bass），但同一大关用同一个调、同一个速度的素材，这样随时能切。每个小关会从头重新叠；后面的小关可以从 1、2 档起步，不必回到 0。
- **速度**：一个大关一个速度（配置里的 `bpm`）。现在 160 是主力，迪斯科关是 120。

### KIAI 现在怎么做的

每条轨道同一时刻只响一段，所以要"叠"就得放在不同轨道：配置里多了一条 **KIAI 鬼畜** 轨道，里面只有鬼畜猫旋律，
切换点放在很靠后的进度；旋律轨道上的猫主旋律照常响，两条就叠在一起了。KIAI 轨道音量 -2 dB。
现在用上的：迪斯科关的飞碟结尾（最后 5%）和吸猫小关的最后 15%；第 7、9 关最后 10%；第 8 关山魔王最后 10%。

### 以后再做（现在没做）

- KIAI 由别的东西触发，而不是只看进度：连击到里程碑、积累条刚满的那一小节、关卡脚本主动喊一声（`Music` 加一个"开 N 小节 KIAI"的接口）。
- KIAI 时把乐器旋律和高潮层压低一点（让猫更突出），结束后放回来。
- 小关之间的过门：切小关前一小节放 riser / 倒放，切过去第一拍放 crash 和一声长喵。
- 掉血时的反应：连续 Miss 时退一档，而不只是跟着积累条慢慢掉。
- 运行时猫旋律（见上一节）做好之后，KIAI 的鬼畜层可以换成玩家打出来的。

## 喵谱子：在游戏里写猫鼓和鬼畜猫旋律（2026-11-15）

除了预渲染的 WAV 片段，轨道里还可以放**谱子片段**：不渲染，游戏里跟着节拍一格一格（16 分音符）触发喵采样。
它们**不替换**原来预渲染的猫鼓和猫旋律，只是多出来可以选的片段。

- **在哪写**：**曲库**是总入口（游戏里按 Tab 点 **Jukebox**，或打开 `scenes/tools/jukebox.tscn` 按 F6）。
  曲库里多了一排"喵谱子"：存好的谱子都列在这里，点名字 = 跟着现在放的曲子一起放，点 ✎ = 在**喵谱子工作室**
  （`scenes/tools/meow_studio.tscn`，全屏）里打开编辑；"+ 新猫鼓 / + 新旋律"也在这一排。
  工作室是独立的：PLAY 默认只放谱子本身，按上面的 BPM 自己走，不放曲子，可以勾节拍器。
  想配着别的音轨听，就在"伴奏"里选曲库里的任意一首，下面一排是它的每条音轨，点亮哪条就加哪条进试听。
  Tab 面板上还有一个 **Meow** 按钮直接进工作室。
  - **New drums**：猫鼓，每行一种喵（低喵、高喵、只用开头一下的"mi"），点格子 = 响 / 不响。
  - **New melody**：鬼畜猫旋律，小钢琴卷帘（A3 到 E6）。点 = 放一个音，往右拖 = 拉长，右键 = 删掉；同一时刻只有一个音。
    Cat 选哪只猫唱，auto = 每 4 小节挑原本音高离这一句最近的那只。
  - **PLAY** 之后谱子一直循环，边改边听。**Save** 存成 `levels/music/patterns/<名字>.json`，存了就出现在曲库里。
  - **MIDI 键盘**：插着的话，按键就试听那个音；PLAY 的时候按，音符直接录进旋律（对齐到 16 分音符，松手决定长度，
    弹得太高太低会挪八度放进猫的音区）。猫鼓谱子里，从中央 C 起一个键对应一行。
- **怎么用进关卡**：工作室只管写和存。回到游戏按 Tab，**Music** 页每条轨道右边有一个 **+ meow**，
  从里面选一个存好的谱子，它就成了这条轨道的一个新片段，和别的片段一样点它来按进度切换；点右上角 Save 写进这一关的配置。
- **从 MIDI 来**：`python tools/music_gen/midi_to_pattern.py 曲子.mid --name 名字`，旋律就出现在工作室的谱子列表里。
  它只要 Python，不要采样，谁都能跑：取音符最多的那一轨、每个时刻留最高的音、对齐到 16 分音符、整体挪八度放进猫的音区。
- **想要高质量的预渲染版**（拉长的 Miiiiao、互相叠）：在有采样的电脑上
  `python -I render_pattern_leads.py <谱子.json> <loops 目录>`，出"喵放完 / 切到音符 / 鬼畜"三条 WAV。
- **怎么发声的**（`scripts/music/meow_player.gd`，`Music.meow`）：每只猫一个采样（`assets/audio/meows/runtime/`，
  共鸣已经烤进去，由 `make_runtime_meows.py` 生成），用 `pitch_scale` 变速变调到要的音高，音符结束就停掉。
  所以换速度不用重渲染。触发提前了一个输出延迟，尽量落在格子上，但精度是一帧左右（10–20 毫秒），比预渲染的松一点。
- **配置里的样子**：片段写成 `{"id": "名字", "pattern": "res://levels/music/patterns/名字.json"}`（普通片段是 `"file"`）。
  谱子片段不占同步流的 32 条名额。
- 自带两个起步的：`meow_drums_basic`（猫鼓）和 `kichiku_riff`（第 1 关那条旋律）。
