# 音频素材

全部 **160 BPM、4/4、44.1 kHz 16-bit 立体声 WAV**。一小节 = 1.5 秒 = 66150 采样。

- **音乐 loop**（`music/`）都是整数小节（文件名里 `_4b`、`_8b`、`_16b` 就是几小节），首尾无缝。
  文件里写了 `smpl` 循环点，Godot 导入（默认 Loop Mode = Detect From WAV）后自己就会循环。
- 同一层的不同版本按 RMS 对齐响度，可以在小节线上直接互换，新的一层只要 10 ms 淡入。
- 玩家的底鼓（"咚"）和拍手**不在**音乐里，是 `sfx/kick.wav`、`sfx/clap.wav`，打中时由判定系统放，
  并压一下音乐总线（侧链）。
- 怎么叠、怎么切见 `docs/music_manager.md`。

## `music/scene1/`：第 1 关

和弦 Ebmaj7 | F7 | Dm7 | Gm7（一小节一个），4 小节 loop。

| 文件夹 | 层 | 内容 |
| --- | --- | --- |
| `skeleton` | L1 律动、L2 bass | 反拍镲 + 铃鼓；八度 bass。所有直拍风格共用 |
| `style_futurebass` | L0 / L3 / L4 | **主力风格**。每拍抽吸的宽锯齿和弦；拨弦主旋律；门控和弦 + 扫频 |
| `style_eurobeat` | L0 / L3 / L4 | 反拍和弦短打；干净方波主旋律；合成铜管、铃声、orch hit |
| `style_chip` | L0 / L3 / L4 | 8-bit 琶音；脉冲波主旋律；方波和声 + 卡顿 |
| `style_disco` | L0 / L3 / L4 | 钢琴短打；铜管 riff；放克吉他 |
| `style_jazz` | L0–L4 全套 | 摇摆骨架（不和直拍风格共用律动）：钢琴、叮叮镲、行走 bass、萨克斯、铜管 |
| `cat_band` | 猫化 1–4 | **主力风格**。`C_drums` 喵鼓（叠加）；`C_stabs` 猫和声（换 L0）；`C_lead` 猫唱主旋律（换 L3）；`C_bass` 猫 bass（换 L2） |
| `events` | 事件层 | `X_meow` 猫合唱、`X_seal` 海豹、`X_vox` 人声切片，由 beat manager 触发 |
| `rhythm_variants` | 换 L1 + L2 | `Rhalf` 半速、`Rbreak` 2-step、`Rclub` jersey club；玩家底鼓位置跟着变 |
| `entertainer_leads` | 16 小节 L3 | Entertainer 旋律：拨弦 / 猫，用第 1 关的和弦 |

## `music/scene1_120/`：第 1 关素材的 120 BPM 版

给 Kisa 的迪斯科关（它是 120 BPM）用的 17 条音轨，`s120_*`，每条 4 小节 = 8 秒，内容和 `scene1/` 里同名的一样：
骨架鼓和低音、disco 和 future bass 两种风格、club 和半拍节奏、全猫乐队、喵和海豹事件轨。

## `music/classics/<曲名>/`：经典曲

只借旋律，每首自己的调和和弦，是独立的一关，不和第 1 关互切。每首都有：`fb_L0_keys` 铺底、`L2_bass`、
`fb_L4_peak` 高潮层、`C_drums` / `C_stabs` / `C_bass` 猫化层，主旋律有 `L3_pluck`（拨弦）和三种猫版本：
`L3_cat_flow`（每声喵叠着放完）、`L3_cat`（压到音符长度，更鬼畜）、`L3_cat_pool`（长音组轮流）。
这三条都带一点点音高共鸣和咬字（让旋律听得出来），乐句结尾的"MIAO"按原音高唱、是全句最响的音，下面叠一声低八度。
`L3_cat_kichiku` 是鬼畜版：每 4 小节固定一只猫（原本音高离这句最近的），每个音从喵的开头重新触发、变速变调、到音符结束硬切，共鸣全量。
所有曲子现在都是 160 BPM；致爱丽丝更适合 120，以后单独渲染（`tools/music_gen/compose_classics.py` 里的 `TEMPO` 是占位，还没用上）。
律动用第 1 关的 `skeleton/s1_L1_groove_4b.wav`。

| 曲子 | 调 | loop | 速度 |
| --- | --- | --- | --- |
| `can_can` 天国与地狱（Offenbach 1858） | G | 8 小节 | 原速 |
| `turkish_march` 土耳其进行曲（Mozart 1783） | A 小调 | 16 小节 | 半速 |
| `ode_to_joy` 欢乐颂（Beethoven 1824） | C | 8 小节 | 原速 |
| `mountain_king` 山魔王的宫殿（Grieg 1875） | A 小调 | 4 小节 | 原速 |
| `fur_elise` 致爱丽丝（Beethoven 1810） | A 小调 | 4 小节 | 原速 |

## `sfx/`：单发音效

| 文件 | 用途 |
| --- | --- |
| `kick`、`clap` | 玩家打击声 |
| `spin_meow_a` / `_b` | 转圈猫（OIIA 风格，用我们自己的猫叫拼的）：道具、彩蛋、FRENZY |
| `catness_up` / `catness_down` | 猫化层换进来 / 退出去 |
| `miss_meow` | MISS |
| `glitch_meow` | 卡顿喵：风格切换、FRENZY 开始 |
| `meow_long_NN_<音>` / `meow_short_NN_<音>` | 调在第 1 关和弦音（G、Bb、D、F）上的长喵 / 短喵，事件触发时按当前和弦挑。每只猫在自己的音区唱（八度跟着猫走，文件名里写着），不会被硬拉低到不像喵 |
| `hit_meow_perfect_a/b/c` / `hit_meow_good_a/b/c` | 打中反馈喵，队员自己录的三声喵（a、b = 第一段录音，c = 第二段），都是原音高。Perfect 0.24 秒；Good 0.16 秒、轻一点。由 main.tscn 的 HitMeow 节点播放：每次随机挑一个（不连着重复），音高轻微随机 ±3%、音量 ±1 dB（检查器里可调） |
| `meow_natural_NN` | 长音组猫的原声 |
| `kitten_mi`、`seal_bark`、`orch_hit_Bb`、`laser_zap` | 点缀 |
| `riser_1b`、`crash` | 第 20 小节上升、下一小节首拍的镲 |
| `rewind_1b` | 重来时的倒带 |
| `level_clear` | 过关 |

原版 OIIA 音频不在这里（不是我们的素材）；确认能用的话放成 `sfx/oiia_original.wav`。

## `meows/`：在用的猫

按分工和喵选秀编号命名：`miao_long_NN`（长音组）、`miao_accent_NN`（E5 以下的长音、句尾喊）、
`miao_short_NN`（短音、喵鼓、猫和声）。13、14、15 是团队自己录的（13、14 来自第一段录音，15 来自第二段）。现在的阵容：长音 1、6、10、13、14、15；重音 6、13；短音 8、11、14、15（#12 效果不好，不用了）。

## 署名（游戏里必须写）

- "Weibliche Britisch Kurzhaar will Futter C1277 MIAUEN"，作者 PantheraLeo1359531，Wikimedia Commons，CC BY 4.0（1 号猫）
- "Arctocephalusgazellavocal"，作者 Aubin T、Jouventin P、Charrier I，Wikimedia Commons，CC BY 4.0（海豹）

其余：BigSoundBank（CC0）、Wikimedia Commons CC0 猫叫、99Sounds x Monosounds 免版税采样包，或合成；
经典曲旋律为公有领域，Entertainer 和土耳其进行曲的音符取自 Mutopia Project 公有领域乐谱。

## 重新生成

生成脚本在 `tools/music_gen/`（Python + numpy）。采样包和原始录音不在仓库里，见那边的 README。
