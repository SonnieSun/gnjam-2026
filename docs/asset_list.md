# 三关素材清单

整理时间：2026-11-15，按团队仓库 `develop_kisa` 当前工作区（含别的线程未提交的改动）读出来的。没改、没提交任何文件。

**怎么查的**：从 `levels/level_1/2/3_*.tres` 和 `levels/music/level_*.json` 出发，顺着场景、脚本里的 `res://` 路径、`preload`、`class_name` 一路追下去。代码里现场生成的东西（程序画的圈、内嵌在 .gd 里的 shader）单独列出。

**作者怎么判断**：看 git 里谁第一次提交了这个文件（括号里是最后改的人，和第一次不同时才写）。`sunnyyan991` = Kisa 这边（包括 Claude / Codex 帮做的），`Sonnie Sun` = Sonnie，`EiZi233` = EiZi，`moumou94` = moumou。「来源」一栏是从工作日志、README、CREDITS 里查到的出处，查不到就留空。

---

## 一、三关共用（框架 / 全局）

### 共用素材（在两关以上直接用到）

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 3D 猫（坐姿，转圈猫用） | `stages/shared/cat/CATS.fbx` | Kisa 提供 | 第 1 关 迪斯科主角转圈猫（`spin_cat_3d.gd`）；第 2 关 电视墙房间里的猫（`tv_wall_room.gd`） |
| 猫贴图 | `stages/shared/cat/cat_basecolor_512.png` | Kisa（Claude 补的贴图） | 第 2 关 洗衣机上的猫头 |
| 披萨猫（抓挠猫模型） | `assets/art/CATS_Scratch.fbx` | moumou | 第 3 关 两段都用；主菜单转盘的猫也是它（`scenes/cat_scratch_model.tscn`） |
| 那不勒斯披萨 | `stages/space_shooter/model/neapolitan_pizza.glb` | Codex 做（ImageGen 贴图） | 第 3 关 打星球段、披萨猫段 |
| 星云天空盒（蓝紫 512） | `stages/spaceship/skybox/nebula_512_blue.jpg` | 从 Kisa 给的 FBX 全景图缩出来、压暗偏蓝紫（Claude） | 第 3 关 两段的天空 |
| 猫 meme 动图 | `assets/memes/*.png`（banana、apple、oiia、nyan、nyanrun、popcat、flower、catjam） | Sonnie 转的序列帧，原图是 7TV 表情（**未标明授权**，见 `assets/memes/CREDITS.md`） | 第 1 关 2D 跳舞猫、圆台观众猫、popcat 提示图；第 2 关 拍地球的 meme 纸片 |
| 分层音乐（EiZi 第 1 关那套） | `assets/audio/music/scene1/skeleton/`、`cat_band/`、`events/s1_X_fill_4b.wav` | EiZi | 三关都用（各关 `levels/music/*.json`） |
| 鬼畜猫 riff 谱子 | `levels/music/patterns/kichiku_riff.json` | EiZi | 第 2、3 关音乐 |
| 鼓采样 + 伴奏（fantasy） | `assets/fantasy/kick.wav`、`snare.wav`、`hat.wav`、`backing_no_drums.ogg` | Sonnie | 第 2、3 关的按键鼓声；伴奏写在 .tres 里，但被叠轨音乐替代（见下） |

> **音乐说明**：三关的 `levels/music/*.json` 都开了 `use_in_game: true`，按 `main.gd` 的逻辑，游戏里放的是 EiZi 的叠轨音乐，**.tres 里写的伴奏（第 1 关的 `disco_layers` 11 条分轨、第 2/3 关的 `backing_no_drums.ogg`）不会放**。按键鼓声（kick/snare/hat）还是用 .tres 里的。这条是看代码得出的，没进游戏听过。

### 框架里所有关都会用到的东西

| 类型 | 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|---|
| 字体 | CandyGem 位图字体 | `assets/fonts/CandyGem/CandyGem.fnt`（+ `.png`） | Kisa 提供 | HUD 分数、评级 |
| UI | HUD（分数、连击、判定字、积累条、结算） | `main.tscn` 里的 HUD 节点，`scripts/hud.gd` | Sonnie（Kisa 改过计分和评级） | 所有关 |
| UI | 暂停转盘 / 一路玩 | `scripts/pause_menu.gd` | Kisa（Claude） | 所有关，Esc |
| UI | 主菜单 3D 黑胶转盘 | `scenes/menu.tscn`、`menu_disc_3d.tscn`、`menu_cat_3d.tscn`、`assets/menu/*.gdshader`（beam、spot_beam、vinyl、neon_arrow）、`assets/art/bg.png`、`assets/mv/tex/face_closedw.png` | moumou、Sonnie | 选关入口 |
| UI | 音乐工具界面（按键、旋钮贴图） | `assets/ui/*.png`、`assets/ui/theme.tres` | EiZi | 喵谱子工作室 / 点唱机（编辑工具，不是游戏画面） |
| 特效 | 命中星星（程序画） | `scripts/fx/star_burst.gd` | Sonnie | 第 2 关和第 3 关披萨猫段的命中特效（第 1 关被 Y2K 特效换掉，第 3 关打星球段关掉了） |
| 特效 | 冲击圈 | `scripts/fx/shock_ring.gd` | Sonnie | 所有关 |
| 特效 | 全屏特效 | `assets/shaders/screen_fx.gdshader` + `scripts/fx/screen_fx.gd` | Sonnie | 所有关 |
| 特效 | 漫画滤镜（按 C 切换） | `assets/shaders/comic/comic.gdshader`、`comic_outline.gdshader`、`comic_screen_forward.gdshader`，`scripts/fx/comic_style.gd` | Sonnie | 第 2 关洗衣机开场默认开；第 3 关披萨猫段可切 |
| 特效 | Y2K 画面风格 | `assets/shaders/y2k/`（era_jpeg_encode、era_output、fever_rainbow、glass_aero、light_beam、theme_grade），`scripts/fx/y2k_style.gd` | Sonnie | 按 C 切到 Y2K 时的 3D 小关（第 3 关披萨猫段） |
| 特效 | 积累条冒猫图 | `scripts/fx/meme_cues.gd`、`meme_sprite.gd`、`meme_lib.gd` | Sonnie | 框架功能；三关目前只有第 1 关放了一张 popcat |
| 音效 | 打中 / Miss / 转圈喵 | `assets/audio/sfx/hit_meow_perfect_a~c.wav`、`hit_meow_good_a~c.wav`、`miss_meow.wav`、`glitch_meow.wav`、`spin_meow_a/b.wav` | EiZi | 所有关（`HitMeow` 节点） |
| 音效 | 底鼓 | `assets/audio/sfx/kick.wav` | EiZi | 喵谱子工作室 |

---

## 二、第 1 关 DISCO（迪斯科房间 → 上路 → 圆台 → 结尾飞碟吸猫）

小关场景：`scenes/sections/kisa/disco.tscn`；脚本 `scripts/sections/kisa/disco_section.gd`、`stages/disco/disco_stage.gd`、`disco_road.gd`（最初 Kisa，现在最后改的是 Sonnie）。

### 3D 模型

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 转圈猫 | `stages/shared/cat/CATS.fbx`（共用） | Kisa 提供 | 主角 |
| 等距小屋背景 | `stages/shared/iso_room.tscn` | Kisa（Claude） | 转圈猫组件自带 |
| 猫砂盆、房间空壳、星星吊灯 | `stages/disco/model/litter_box.glb`、`room_shell.glb`、`star_lamp.glb` | Claude 用 Blender 脚本建（照 Codex 的三视图） | 房间 |
| 灯球 | `stages/disco/model/disco_ball.glb` | Kisa 给的现成模型（animated-disco-ball-low-poly），Claude 导出 GLB | 房间、上路 |
| 家具墙饰 11 件 | `stages/disco/model/desk.glb`、`crt.glb`、`stool.glb`、`gamepad_light.glb`、`wall_star.glb`、`zigzag_plaque.glb`、`flower_light.glb`、`drink_can_pink.glb`、`drink_can_green.glb`、`potted_plant.glb`、`cable.glb` | Claude 用 Blender 脚本建（照 Codex 的三视图） | 房间（`stages/disco/disco_room.tscn`） |
| 水果 4 个 | `stages/disco/model/fruit_apple.glb`、`fruit_orange.glb`、`fruit_banana.glb`、`fruit_watermelon.glb` | Claude 用 Blender 脚本建（超低模占位） | 上路撞水果 |
| 站立猫 | `stages/abduction/model/cat_stand.fbx` | Kisa 提供 | 结尾换成站立猫、吸猫段 |
| UFO | `stages/abduction/model/ufo/ufo.fbx`（`stages/abduction/ufo.tscn`） | Kisa 提供 | 结尾飞碟、吸猫段 |

### 贴图和图片

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 站立猫贴图 | `stages/abduction/model/cat_stand_basecolor.png` | Kisa 提供（git 显示 Sonnie 初始提交里就有同一张） | 站立猫 |
| UFO 贴图 | `stages/abduction/model/ufo/ufo_texture.png` | Kisa 提供 | UFO |
| 猫 meme | `assets/memes/oiia、banana、apple、nyanrun`（跳舞猫），`banana、apple、oiia、nyan、flower、popcat、nyanrun、catjam`（圆台观众），`popcat.png`（提示图） | 7TV 表情，Sonnie 转（共用） | 2D 跳舞猫、圆台、`Targets/Cat1` |

### 特效和 shader

| 素材 | 路径 | 作者 | 用在哪 |
|---|---|---|---|
| Y2K 命中特效 | `stages/shared/y2k_fx/`（`y2k_burst.gd`、`y2k_burst_style.gd/.tres`、`y2k_hit_fx_swap.gd`、`shapes/` 27 个形状图 + 各自 `_glow.png` 光晕图） | Kisa（Claude，形状从 Kisa 给的参考图切出来） | 把框架的命中星星换成 Y2K 彩色图形，**只在第 1 关**挂了 |
| 猫轮廓边光 | `stages/disco/cat_rim.gdshader` | Kisa（Claude） | 主角猫 |
| 聚光灯光柱 | `stages/disco/spot_beam.gdshader` | Kisa（Claude） | 猫头顶光柱、上路 |
| 转圈光波 | `stages/disco/spin_wave.gdshader` | Kisa（Claude） | 每次转圈地上扩散 |
| 灯球镜面 / 光束 / 闪点 | `stages/disco/disco_ball_mirror.gdshader` + `.tres`、`disco_ball_beam.gdshader`、`disco_glint.gdshader` | Sonnie | 灯球 |
| 路面 | `stages/disco/road_floor.gdshader` | Kisa（Sonnie 改过） | 上路、舞池、霓虹网格 |
| 上路背景 | `stages/disco/road_backdrop.tscn`、`road_backdrop.gd`、`wire_shape.gd`、`rainbow_band.gdshader` | Sonnie | 上路后的背景线框和彩虹带 |
| 节拍发光 / 节拍引导条 | `scripts/fx/beat_glow.gd`、`scripts/chart/beat_guide_strips.gd` | Sonnie | 上路 |
| 判定圈、收圈、长按带 | 代码画（`disco_section.gd`） | Kisa（Claude） | 房间段 |
| 吸猫段的云、光束、光圈 | 写在 `stages/abduction/abduction_stage.gd` 里的内嵌 shader | Kisa（Claude，Sonnie 改过） | 结尾吸猫 |

### 天空和环境

| 素材 | 说明 | 作者 |
|---|---|---|
| 房间夜晚灯光 | 环境光、月光、星星灯点光、灯球射灯，全在 `disco_stage.gd` 的 Inspector 参数里 | Kisa（Claude） |
| 上路背景 | 见上面 `road_backdrop` | Sonnie |
| 吸猫夜空紫云 | `abduction_stage.gd` 内嵌 | Kisa（Claude） |

### 音乐和音效

| 素材 | 路径 | 作者 / 来源 | 说明 |
|---|---|---|---|
| 叠轨音乐（实际放的） | `levels/music/level_1_disco.json` → `assets/audio/music/scene1/` 下 skeleton、rhythm_variants（half/club/break）、style_disco、style_futurebass、cat_band、events（fill、meow、seal）、ask_answer/`s1_QA_B_4b.wav` | EiZi | 160 BPM |
| 按键鼓声 | `assets/disco_layers/kick.wav`、`snare.wav`、`hat.wav` | Kisa（编曲线程生成） | 写在 `level_1_disco.tres` |
| 迪斯科分层循环 v3（11 条） | `assets/disco_layers/room_00~04_*.ogg`、`road_00/05~09_*.ogg` | Kisa（编曲线程生成，说明见 `assets/disco_layers/README.md`） | 写在 .tres 里，但被叠轨音乐替代，**按代码看现在不会放** |

---

## 三、第 2 关 TV WALL（洗衣机开场 → 拍地球 TAP / RAPID）

小关场景：`scenes/sections/kisa/tv_wall_intro.tscn`、`earth_slap.tscn`；拍地球现在是 Sonnie 的版本（`earth_slap_stage.gd`、`earth_slap_section.gd` 最后改的是 Sonnie）。

### 3D 模型

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 洗衣机 | `stages/tv_wall/washer/washing_machine.tscn` | Kisa 给的 WashingMachine 分享包 | 开场中间 |
| 猫头 | `stages/tv_wall/washer/CATS_head_only.fbx` | 同上分享包 | 洗衣机上转的猫脸 |
| 粉色复古电视 | `stages/tv_wall/retro_tv/retro_tv.glb` | Claude 在云端用 Blender 建（照 Kisa 的设定图 / Codex 三视图） | 10 台电视 |
| 猫（电视墙房间） | `stages/shared/cat/CATS.fbx`（共用） | Kisa 提供 | `tv_wall_room.gd` |
| 拍地球的猫 + 地球 + 星星 | `assets/models/cat_earth_y2k/cat_earth_y2k.fbx`（`cat_earth_model.tscn`） | moumou | 拍地球两段 |

### 贴图和图片

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 洗衣机贴图 | `stages/tv_wall/washer/Washingmachine_Base_Color_Photoreal.png` | 分享包 | 洗衣机 |
| 猫头贴图 | `stages/shared/cat/cat_basecolor_512.png`（共用） | Kisa | 猫头 |
| 拍地球猫贴图 | `assets/models/cat_earth_y2k/cat_basecolor_512.png` | moumou | 猫 |
| 地球贴图 | `assets/models/cat_earth_y2k/earth_day_clouds.jpg` | moumou 放的，原图 NASA Blue Marble（见该文件夹 README） | 地球 |
| 银河背景 | `assets/models/cat_earth_y2k/galaxy_backdrop.png` | moumou（烘焙出来的） | 拍地球背景 |
| 星星渐变 | `assets/models/cat_earth_y2k/star_blue_purple.png`、`star_purple_blue.png` | moumou | 圆润星星 |
| 材质 | `assets/models/cat_earth_y2k/` 下 cat / earth / galaxy / glint_blue / glint_purple / star_blue / star_purple 的 `_material.tres` | moumou | 同上 |
| 猫 meme 纸片 | `assets/memes/banana、oiia、popcat、nyan、apple、flower`（共用） | 7TV 表情，Sonnie 转 | 拍地球里翻转的纸片 |

### 特效和 shader

| 素材 | 路径 | 作者 | 用在哪 |
|---|---|---|---|
| 电视屏幕 | `stages/tv_wall/tv_screen.gdshader` | Kisa（Claude） | 电视屏幕 |
| 结尾屏幕放下一小关画面 | `stages/tv_wall/intro/tv_intro_screen.gdshader` | Kisa（Claude） | 结尾钻进电视 |
| 玻璃 | `stages/tv_wall/glass_aero.gdshader` | Kisa（Claude，复制自 Sonnie 的 kit） | 电视墙房间 |
| 洗衣机震动镜头 | `stages/tv_wall/washer/washing_hit_lens.gdshader` | 分享包里拿的 | 发电震动 |
| 漫画滤镜 | 框架的 ComicStyle（共用） | Sonnie | 开场默认开，按 C 切 |
| 新闻条、连点提示、HOLD FAILED 字 | 代码画（默认字体） | Sonnie / Kisa | 拍地球、开场 |

### 天空和环境

| 素材 | 说明 | 作者 |
|---|---|---|
| 开场黑底 | 代码设置 | Kisa（Claude） |
| 拍地球银河背景 | 上面的 `galaxy_backdrop.png` 贴在背景板上 | moumou |

### 音乐和音效

| 素材 | 路径 | 作者 | 说明 |
|---|---|---|---|
| 叠轨音乐 | `levels/music/level_3_tv_wall.json` → scene1 的 skeleton、cat_band、`style_chip/`（keys、hook、peak）、events/fill，`patterns/kichiku_riff.json` | EiZi | 实际放的 |
| 按键鼓声 | `assets/fantasy/kick/snare/hat.wav`（共用） | Sonnie | |
| 伴奏 | `assets/fantasy/backing_no_drums.ogg`（共用） | Sonnie | 被叠轨音乐替代 |
| 蓄力 / 满了的音效 | `assets/audio/sfx/hit_meow_good_a.wav`、`clap.wav` | EiZi | 拍地球 |

---

## 四、第 3 关 SPACESHIP（披萨猫打星球 → 披萨猫过圈 / 九宫格 / 万花筒）

小关场景：`scenes/sections/kisa/space_shooter.tscn`、`space_pizza.tscn`；第二段脚本 `space_pizza_section.gd` 继承 Sonnie 的 `scripts/sections/pizza_section.gd`。

### 3D 模型

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 披萨猫 | `assets/art/CATS_Scratch.fbx`（共用） | moumou | 两段主角 |
| 那不勒斯披萨 | `stages/space_shooter/model/neapolitan_pizza.glb`（共用） | Codex | 猫脚下 |
| 行星 6 颗 | `stages/spaceship/planets/planet_red.glb`、`planet_green.glb`、`planet_jupiter.glb`、`planet_saturn.glb`、`planet_earth.glb`、`planet_twilight.glb` | Kisa 给的 all.fbx（减面版），Claude 转 GLB、贴图缩小 | 打星球段的靶子 |
| 食物子弹 5 个 | `stages/space_shooter/food/food_bao.glb`、`food_taco.glb`、`food_cupnoodle.glb`、`food_burger.glb`、`food_rollcake.glb` | 另一个 Claude 线程做的 | 打星球段发射 |
| 发光四芒星 | `stages/space_shooter/star/four_point_star.glb` | Kisa（Claude 建，照 Codex 的四芒星设定图） | 猫转圈时冒出的星星粒子 |

### 贴图和图片

| 素材 | 路径 | 作者 / 来源 | 用在哪 |
|---|---|---|---|
| 行星、食物、披萨贴图 | 都打包在各自 .glb 里 | 同上 | |
| 星云天空盒 | `stages/spaceship/skybox/nebula_512_blue.jpg`（共用） | Kisa 给的全景图，Claude 缩小调色 | 两段天空 |

### 特效和 shader

| 素材 | 路径 | 作者 | 用在哪 |
|---|---|---|---|
| 四芒星发光 | `stages/space_shooter/star/star_glow.gdshader` | Kisa（Claude） | 转圈星星 |
| 玻璃环 / 天空网格 / 水面 | `assets/shaders/dream/glass_ring.gdshader`、`sky_grid.gdshader`、`water.gdshader` | Sonnie | 披萨猫段（天空球和水面在这关是藏起来的，玻璃环在用） |
| 九宫格、万花筒 | 关卡里 `fx_cues` 触发框架的画面效果（`grid3`、`kaleido`） | Sonnie | 披萨猫段后半 |
| 猫身上的判定圈、星球拖尾、+分飘字 | 代码画 / 代码生成（`space_shooter_section.gd`） | Kisa（Claude） | 打星球段 |
| 段间运镜 + 画面叠化 | `space_pizza_section.gd` | Kisa（Claude） | 打星球 → 披萨猫 |

### 天空和环境

| 素材 | 说明 | 作者 |
|---|---|---|
| 星云天空盒 | 两段都用 `nebula_512_blue.jpg` | Kisa（Claude） |
| 灯光 | `space_shooter.tscn` 里的 Sun 平行光；披萨猫段沿用 Sonnie 的 pizza 场景灯光 | Kisa / Sonnie |

### 音乐和音效

| 素材 | 路径 | 作者 | 说明 |
|---|---|---|---|
| 叠轨音乐 | `levels/music/level_4_spaceship.json` → scene1 的 skeleton、cat_band、`style_eurobeat/`（keys、hook、peak）、events/fill，`patterns/kichiku_riff.json` | EiZi | 实际放的 |
| 按键鼓声 | `assets/fantasy/kick/snare/hat.wav`（共用） | Sonnie | |
| 伴奏 | `assets/fantasy/backing_no_drums.ogg`（共用） | Sonnie | 被叠轨音乐替代 |

---

## 五、文件在、但三关现在没用到的（顺手查到的）

| 素材 | 路径 | 作者 / 来源 | 情况 |
|---|---|---|---|
| 猫屁股喷火图 | `stages/earth_slap/fx/cat_rocket_flame.png` | Codex ImageGen 生成 | 拍地球换成 Sonnie 的版本后，喷火飞出的结尾没了，现在没有地方引用这张图 |
| 吸猫关 VHS 滤镜 | `stages/abduction/vhs.gdshader` | Kisa（Claude） | 吸猫现在只作为迪斯科结尾，没用这个滤镜 |
| 第二批猫 meme | `assets/cats/`（webp 动图，来源见 `assets/cats/CREDITS.md`） | Sonnie 放的 | MemeLib 支持，但三关目前点名用的都是 `assets/memes/` 那批 |
| 发光转圈猫（虎斑 / 三花 / 橘猫 / 奶牛猫） | `stages/shared/tabby_cat/` | Kisa（Claude，模型和花色贴图 Codex 做） | 组件做好了，还没放进任何一关 |
| 主菜单喵谱子 | `levels/music/patterns/menu_theme.json`、`menu_meow_drums.json` | Kisa（Claude） | 本地未跟踪，没接进游戏 |

## 需要留意的

- **猫 meme 版权**：`assets/memes/` 那批是 7TV 表情，CREDITS 里写着「未标明授权」，公开发布前要确认或替换。`grumpy.png` 是 CC BY-SA 2.0（三关没用到）。
- **地球贴图**：NASA Blue Marble，需要署名（见 `assets/models/cat_earth_y2k/README.md`）。
- 第 1 关 .tres 里的迪斯科分层音乐和第 2/3 关的 fantasy 伴奏按代码看都被叠轨音乐替代了，没进游戏确认过。
