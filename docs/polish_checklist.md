# 打磨 Checklist（2026-11-17 起）

按板块列出发布前要做的事。做完一项就把 `[ ]` 改成 `[x]`，并在后面写上日期和提交号。
标着「待定」的项，具体做法还没讨论。

---

## 0. 谱面和音乐对接（已结束）

- [x] 游戏里所有地方都是 160 BPM。四个大关的 `levels/music/*.json` 都是 `use_in_game: true`、`bpm: 160`，`main.gd` 进关时用 `Music.bpm()` 覆盖谱面的 BPM；四个 `levels/level_*.tres` 里的 `bpm` 也改成了 160。（2026-11-17）
- [x] `docs/music_chart_handoff.md` 第 4 节列的问题都已解决：吃水果的谱面改到鼓上、BPM、洗衣机长按。（2026-11-17）

## 1. 第 2 关 SKY（单独开 session 做）

- [ ] 在单独的 session 里做，范围见那个 session 的任务说明：补阶段和演出、镜头、谱面、音乐层次，以及和第 1、3 关的衔接。
- [ ] 做完后在这里补上提交号。

## 2. 整体视觉：画面风格、滤镜、特效

- [ ] 定下每一关默认用哪种画面风格（原样 / 漫画 / Y2K），四关放在一起看要像同一个游戏。现在各关是混着用的。
- [ ] 命中特效统一：Y2K 命中特效只有第 1 关挂了，其他关用的是框架的星星。
- [ ] fever 的画面反馈统一：现在第 1 关有彩虹边框滤镜和彩带，其他关需要逐个确认有没有、像不像。
- [ ] 积累条冒猫图（meme cues）：现在只有第 1 关放了，其他关要不要放（待定）。
- [ ] 发布版里 C 键切画面风格的调试键保持关闭（已经只在 debug 版本里生效，确认一下即可）。

## 3. 关卡之间的衔接和过场

- [ ] 把四关一路玩下来，记下每个接缝（大关之间、大关里的小关之间）现在是怎么切的：ZOOM / CUT / 幕布 / 音乐过门。
- [ ] 第 1 关 → 第 2 关 SKY：UFO 吸猫接上天空关（和第 1 节一起做）。
- [ ] 第 2 关 → 第 3 关 TV WALL 的洗衣机开场。
- [ ] 第 3 关拍地球结尾（猫喷火飞出地球，今天刚加）→ 第 4 关 SPACESHIP。
- [ ] 每个接缝的画面切换要落在音乐的小节线上，和过门小节对齐。
- [ ] 每一关开头的倒数（READY 3 2 1）在每个接缝的表现要一致。

## 4. 暂停菜单

- [ ] 暂停转盘的按钮层被黑胶盖住：Kisa 今天修了，试玩确认一下。
- [ ] 暂停时音乐和节拍时钟一起停，继续时重新对上拍（叠轨音乐、喵谱子、节拍器都要对上）。
- [ ] 暂停菜单里加 SETTINGS：设置面板可以直接复用，`SettingsPanel.open_overlay(self)`，暂停时也能用（总 / 音乐 / 音效音量、全屏、判定延迟都在里面）。
- [ ] 重开 / 回主菜单 / 继续这几项都要试一遍，特别是在过场、fever、倒数的时候按暂停。

## 4.5 主菜单和设置

- [x] 主菜单加设置面板（左上角 SETTINGS 或 Esc，CREDIT 挪到右上角）：总 / 音乐 / 音效三条音量、全屏、判定延迟（和校准是同一个值）、进校准界面。存在 `user://settings.cfg`，下次打开还在。代码在 `scripts/core/settings.gd`（autoload `Settings`）和 `scripts/ui/settings_panel.gd`，测试 `tools/test_settings_menu.gd`。（2026-11-17）
- [x] 音频分成 Music、SFX 两条总线：Music 和 Conductor 下面的播放器走 Music，其它走 SFX，不用逐个改场景。（2026-11-17）
- [x] 宽屏下背景和 3D 转盘铺满整个窗口，不再是中间一块 4:3、两边露底色；4:3 下取景和原来一样。PLAY 放大并跟着猫点头轻跳，按钮鼠标悬停放大。（2026-11-17）
- [ ] 主菜单没有背景音乐（待定）。

## 5. 结局、Credits、Ending

- [ ] 最后一关打完到最终结算的过程：结算组件 `ui/result_widget.tscn`，评级、完成率按实际玩过的那几关算。
- [ ] Credits（`scenes/credits.tscn`、`scripts/credits.gd`）：名单、每个人的分工、素材来源，排版和滚动的节奏。
- [ ] Ending 的演出和音乐：结尾要有一段自己的音乐，不要直接断掉（待定）。
- [ ] 从 credits 回到主菜单的流程，以及能不能跳过 credits。

## 6. 编辑器整理，打包时不打进去

现在有好几套编辑工具：游戏内按 Tab 打开的面板（`scripts/tools/game_editor.gd`）、Kisa 的谱面编辑器（`scenes/tools/kisa/beat_editor.tscn`）、Sonnie 的 `levelkit/`、`scenes/tools/chart_editor.tscn`、Meow Studio、Jukebox，另外还有 `scenes/platformer_test.tscn`、`scenes/calibrate.tscn` 这些测试场景。

- [ ] 定下以后用哪几套，不用的挪走或者删掉（要先跟做的人确认）。
- [ ] 把编辑工具都归到一个目录下（比如 `dev/`），游戏代码不再引用它们。
- [ ] 导出配置 `export_presets.cfg` 里排除这个目录。现在的 `exclude_filter` 是一长串手写的 wav 文件名，换成按目录排除，用不到的音乐分轨也挪进一个不打包的目录。
- [ ] `autoload` 里的 `Registry`、`Sfx` 来自 `levelkit/core/`，要么挪进游戏代码，要么确认游戏不需要它们。
- [ ] 游戏内的 Tab 面板和 C、N 等调试键已经只在 debug 版本里生效；确认打出来的 release 版本里按了没反应，最好连代码都不打进去。

## 7. 优化（性能 + Web）

**性能**
- [ ] 着色器预热：`kisa/shader-warmup` 分支是 WIP，还没合进 main。测一下进关、切小关时卡不卡，再决定合不合。
- [ ] 各关帧率：先在低配机器上一路玩一遍，记下掉帧的地方。

**Web 版**
- [ ] 现在只有 Windows 的导出配置，要新加一个 Web 配置。
- [ ] 渲染器：项目现在用的是默认的 Forward+，Web 只支持 Compatibility。要么整体换成 Compatibility，要么只在 Web 版里用，并且逐个检查 shader 和画面风格在 Compatibility 下能不能用（漫画、Y2K、彩虹、万花筒这些）。
- [ ] 包体：音乐全是 WAV（`assets/audio` 约 486 MB、346 个文件），Web 版要转成 OGG，或者在导入设置里压缩，并且去掉没用到的分轨。
- [ ] 音频延迟：浏览器的音频延迟比桌面大，判定的校准（`scenes/calibrate.tscn`）在 Web 上要能用。
- [ ] 浏览器要求用户先点一下才能出声，开场要有一个「点击开始」。
- [ ] 在网页上（itch.io 之类）实际跑一遍：加载时间、内存、全屏、键盘输入。

## 8. 授权（暂缓）

- [ ] 猫 meme 图（`assets/memes/CREDITS.md`，7TV 表情没有标明授权）。
- [ ] Your Best Friend（Undertale）只给内部试玩用，公开发布前要换掉。
