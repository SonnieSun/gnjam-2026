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
- [ ] 全屏 retro 滤镜测试（2026-11-17 加的，debug 版本里 F4 开关、F5 换预设）：照 runway-tm-sequel 的 era 输出，整个画面（3D、2D、HUD、菜单）变成约 480 线方像素，四个预设：16 位 VGA、JPEG q35、JPEG q15 4096 色、256 色。代码 `scripts/fx/retro_screen.gd`（autoload `RetroScreen`），shader `assets/shaders/retro/retro_screen.gdshader`。1080p 下每帧多 0.1~0.5 ms。要不要正式用、用哪个预设、要不要放进设置面板（待定）。

## 3. 关卡之间的衔接和过场

- [ ] 把四关一路玩下来，记下每个接缝（大关之间、大关里的小关之间）现在是怎么切的：ZOOM / CUT / 幕布 / 音乐过门。
- [ ] 第 1 关 → 第 2 关 SKY：UFO 吸猫接上天空关（和第 1 节一起做）。
- [ ] 第 2 关 → 第 3 关 TV WALL 的洗衣机开场。
- [ ] 第 3 关拍地球结尾（猫喷火飞出地球，今天刚加）→ 第 4 关 SPACESHIP。
- [ ] 每个接缝的画面切换要落在音乐的小节线上，和过门小节对齐。
- [ ] 每一关开头的倒数（READY 3 2 1）在每个接缝的表现要一致。

## 4. 暂停菜单

- [x] 暂停时节拍时钟、音乐都停住，继续后从停的地方接着走，不跳（原来继续后时钟会往前跳暂停的时长，那几秒的音符全判漏打）。倒数时暂停也一样。（2026-11-17）
- [x] 关卡里的计时器（倒数、换关、片尾字幕）暂停时也停（原来照走）。（2026-11-17）
- [x] 转盘停在正在玩的那一关时按钮是 RESUME（回车 / 点击继续），拨到别的关变 PLAY；继续时翻过的关会还原（原来翻过再继续，打完会接错下一关）。（2026-11-17）
- [x] 暂停里左上角 SETTINGS 能开设置面板；面板开着时 Esc 只关面板。测试 `tools/test_pause_menu.gd`（要开窗口跑）。（2026-11-17）
- [ ] 按钮层被黑胶盖住（Kisa 11-17 修的）：真人试玩时顺便看一眼。

## 4.5 主菜单和设置

- [x] 主菜单加设置面板（左上角 SETTINGS 或 Esc，CREDIT 挪到右上角）：总 / 音乐 / 音效三条音量、全屏、判定延迟（和校准是同一个值）、进校准界面。存在 `user://settings.cfg`，下次打开还在。代码在 `scripts/core/settings.gd`（autoload `Settings`）和 `scripts/ui/settings_panel.gd`，测试 `tools/test_settings_menu.gd`。（2026-11-17）
- [x] 音频分成 Music、SFX 两条总线：Music 和 Conductor 下面的播放器走 Music，其它走 SFX，不用逐个改场景。（2026-11-17）
- [x] 宽屏下背景和 3D 转盘铺满整个窗口，不再是中间一块 4:3、两边露底色；4:3 下取景和原来一样。PLAY 放大并跟着猫点头轻跳，按钮鼠标悬停放大。（2026-11-17）
- [ ] 主菜单没有背景音乐（待定）。

## 5. 结局、Credits、Ending（2026-11-18 定的更新计划）

**现在的样子**（看代码得出的）：披萨满条后在小节线上补一个七彩结束音符，空一小节就直接弹结算；没有结尾演出，也没有结尾段音乐，
收束和弦 `end_g_major` 只在去下一关时才放（`Music.bridge_out`），最后一关根本不放。结算是在游戏画面上直接盖一个面板
（`ui/result_widget.tscn`），底下披萨 fever 一直循环；字是一整段等宽文本，四关成绩合在一起；6 秒后自动跳 credits
（`main.gd` 的 `credits_after_seconds`）。Credits 是星球大战式滚动，只有 6 个名字，没有分工和素材来源，
音乐还是披萨那段接着放。

整条线改成：**最后一下 → 结算 → 片尾曲 + Credits → 主菜单**。披萨和结算里康康舞曲一直循环（结算里弱化），片尾曲是专门的。

**5.1 最后一关的最后一下**——用户 11-18 定：音乐不收，康康舞曲一直循环；只是最后一下要有一个不一样的瞬间
- [x] 七彩结束音符那一拍：画面中间砸下大字 ALL CLEAR、全屏白闪、画面顶一大下、镲 + 一声长 MIAO（G 调，和康康 fever 同调）。单独玩前面几关时字是 LEVEL CLEAR。（`main.gd` 的 `_final_pop`、`hud.gd` 的 `final_pop`，2026-11-18）
- [x] 一小节后结算弹进来，那个大字飞上去变成结算的标题。（2026-11-18）

**5.2 结算界面**——先不做每关评分（2026-11-18 重做，`ui/result_widget.tscn`、`scripts/ui/result_widget.gd`）
- [x] 背景画面和康康舞曲都接着循环，但弱化：音乐压低 9 dB、削掉高频（`Settings.duck_music`），画面压暗模糊。离开结算就恢复。
- [x] 不用方框面板，整屏摆，和游戏 HUD 同一套美术：评级字母后面一圈转着的光芒；分数用彩虹果冻数字从 0 滚上去；PERFECT / GREAT / GOOD / MISS 用涂鸦字配次数。
- [x] lore 就是一堆 meow：三张歪着拍上去的贴纸，每张一只猫 meme + 几句 meow，第一张的语气跟评级走（S 是 MEOW!!!，C 是 meow...）。
- [x] 跟着拍子一样一样弹出来（标题、评级盖章、分数、判定次数、贴纸各配一声）。
- [x] 不自动跳走：按 NEXT 去 Credits；R 重打最后一关。
- [ ] 真人打一遍看节奏和字的大小（预览：`tools/preview_final_result.gd`，开窗口跑，会自己按 N）。
- [ ] `tools/test_result_widget.gd` 本来就跑不起来（`--script` 下找不到 Conductor，改之前也一样），要修。

**5.3 片尾曲和 Credits**
- [ ] 片尾曲先试「慢版」：康康舞曲（或全游戏的几首）放慢重新渲染，猫唱。
- [ ] 用户提的另一个方向：星球大战主题曲的猫版。注意这首还在版权期（John Williams / Lucasfilm），和 Your Best Friend 一样只能内部试玩用，公开发布要换掉；要试的话用户给 MIDI，用 cat_sound 管线渲染。
- [ ] Credits 内容（要用户提供名单和分工）：每个人做了什么；音乐来源（Mutopia 公有领域 MIDI 等）、字体、模型、meme 图（和第 8 节授权一起核对）；特别感谢。
- [ ] 排版：分段标题，Credits 滚完的时间和片尾曲一样长；最后停在猫猫图 + THANK YOU FOR PLAYING。
- [ ] 从主菜单 CREDIT 按钮打开的快速版用同一份内容。

**5.4 回到主菜单**
- [ ] Credits 结束淡出回主菜单；按住快进、Esc 跳过保留。
- [ ] 回主菜单后的表现（待定）：转盘停回第 1 关、标一个「已通关」（比如格子上的小星星），主菜单音乐接上。

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
- [ ] 洗衣机开场的外星人（`stages/tv_wall/washer/alien/green_alien.fbx`）是从 ProjectSpin 拿来的 `Green Alien.fbx`，原始来源和授权没查（2026-11-18 加的）。
