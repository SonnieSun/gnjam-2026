# 飞船关卡（毛毛开飞船撞行星）

本机原型，只在 `_sandbox/`，不进仓库。

## 怎么跑
- `spaceship_test.tscn`：F6 自己玩。空格 / Z / X / J / K / 鼠标左键按。
- `spaceship_autoplay_test.tscn`：F6 自动打，看演出用。

## 玩法
两种视角按小节来回切（默认 8 小节冲刺 + 8 小节太阳系，循环）：
- 冲刺：镜头追在飞船斜后上方，行星从前方飞来，正好在那一拍飞进飞船前面竖着的白色判定圈。
- 太阳系：镜头一边绕一边升到正上方，飞碟在中心，周围一圈圈轨道，飞碟外面没有判定圈。每颗行星：① 从飞碟附近飞出去停到轨道上 → ② 停住抖动，身上套一个黄色收缩圈往里缩 → ③ 最后 1/4 拍超高速直线冲向飞碟。收缩圈缩到贴住行星的那一拍 = 撞上飞碟 = 按键。
- 太阳系结束时镜头俯冲回追尾视角，星星加速、视野放大，冲一下。
行星都拖着彗星尾巴。
那一刻按键：猫转一圈，行星被撞飞（圈闪黄 / 绿 + 星星特效）。
没按到：行星撞上飞船，红色爆炸、镜头抖、全屏红闪。
猫每次按键都会转，按住一直转（和迪斯科关卡一样）。判定用 Sonnie 的 Judge，没改。

## 文件
| 文件 | 说明 |
|---|---|
| `spaceship_section.gd` | 关卡脚本，继承 `SpinSection`，把判定结果转给舞台；`autoplay` 调试开关 |
| `space_stage.gd` | 3D 舞台：星空、行星、判定圈、跟拍镜头、飞船晃动、阶段接口 |
| `saucer.tscn` | 占位飞碟（默认）。换模型时保持：猫站在原点、脚踩 y = 0，前方是 -Z；有 `Flames` 节点的话会跟拍子变化 |
| `ship.tscn` | 原来的占位火箭，根节点 `ship` 换成它就切回去。同样（基本形状拼的）。换模型时保持：猫站在原点、脚踩 y = 0，机头朝 -Z；有 `Flames` 节点的话尾焰会跟拍子变长 |
| `spaceship.tscn` | 关卡场景；参数在根节点和 `Stage` 节点的 Inspector 里调 |
| `spaceship_autoplay.tscn` | 继承 spaceship.tscn，只打开 autoplay |

只读复用：`_sandbox/spin_cat/spin_cat_3d.gd`（3D 转圈猫）、`_sandbox/spin_cat/spin_ring_test.gd`（测试入口，套 main.tscn）。

## 常调的参数（Stage 节点）
- 判定点和行星：`hit_point`、`ring_radius`、`spawn_distance`、`spawn_spread`、`knock_velocity`
- 星空：`fly_speed`、`beat_speed_punch`
- 运镜：`near_distance` / `far_distance` / `dolly_beats`（忽近忽远）、`sway_degrees`（左右摇）、`roll_degrees`（歪头）、`beat_punch`（每拍顶一下）、`camera_yaw` / `camera_pitch`
- 视角切换：`dash_bars` / `solar_bars`（各几小节，solar_bars = 0 就只有冲刺）、`transition_beats`、`transition_orbit_degrees`、`dash_boost` / `dash_boost_fov` / `dash_boost_beats`
- 太阳系：`solar_height`、`solar_ring_radius`、`orbit_radii`、`out_beats`（飞出去几拍）、`charge_beats`（冲刺几拍）、`aim_shake`、`shrink_start_radius` / `shrink_color` / `shrink_thickness`（行星身上的收缩圈）、`aim_line` / `aim_line_color` / `aim_line_width` / `aim_dash`（索敌线）
- 尾巴：`trail_points` / `trail_seconds` / `trail_width`
- 根节点：`approach_beats`（行星提前几拍出现）、`ship`（飞碟 / 火箭）

## 分阶段推进（预留口子，还没有演出）
- 打中进度 +1，Miss -1（`SpaceStage.progress`）。
- `stage_at` 填门槛，比如 `[10, 20]` = 进度 10 进第 1 阶段，20 进第 2 阶段；换阶段会发 `stage_changed(stage)`。
- `beat_punch`、`sway_degrees`、`roll_degrees` 是「每阶段」数组，多填几个数后面的阶段镜头就更猛。
- 新演出写在 `SpaceStage._enter_stage()` 里，或者接 `stage_changed` 信号。
- 视角切换开始时发 `view_changed(solar)`，`solar_weight`（0 冲刺 ~ 1 太阳系）可以读。

## 已知
- 编辑器里不预览 3D 画面（只显示一行字）。
- 测试入口借用 spin_ring_test.gd，左下角调试信息里关卡名显示的是 "SPIN CAT"。

## 天空盒
- `skybox/nebula_1024.png`：Kisa 给的 Alien Space Nebula 全景图（原图 7680×3840 嵌在 FBX 里），缩到 1024×512、导入用显存压缩，PanoramaSkyMaterial 当天空。环境反射只算一次（radiance 32），亮度用 `background_energy_multiplier` 调，不会每帧重算天空。
- Stage 节点「天空盒」组：`sky_texture`（留空 = 纯色）、`sky_energy` / `sky_solar_energy`（冲刺 / 俯视亮度）、`sky_yaw_degrees`、`sky_solar_pitch_degrees`（俯视时把星云翻到镜头下面）、`sky_drift_degrees`。

## 行星模型
- `planets/planet_*.glb`：Kisa 给的 all.fbx 拆成 6 颗（红星+绿环、绿星、木星、土星+环、类地、Twilight），本体半径 1、原点在中心。Godot 导入时把贴图另存在同一文件夹。
- 用 `model_src/build_planets.py`（Blender 后台）重新生成；贴图要先缩好（2048² PNG 缩成 1024 JPG），不能在 Blender 里缩：Blender 重新编码的 JPG Godot 读不了。
- 舞台 `Stage` 节点：`planet_models` 不为空就随机挑模型代替代码做的球（不再随机加环），`planet_model_colors` 是各自的尾巴颜色，`planet_model_glow` / `planet_model_roughness` 调亮度和哑光。

## 星云粒子星空
- 往后飞的短线去掉了：`spaceship.tscn` 里 Stage 的 `star_count = 0`（代码没改，改回 700 就回来）。
- `stars/star_field.gd` + `star_flare.gdshader` + `star_cloud.gd`：关卡场景里的 `Stars` 节点。由 `clouds` 列表里一团团星云粒子组成，每团（StarCloud）可调方向、距离、大小（三个方向）、count（密度）、concentration（往中心挤）、粒子大小、colors（颜色渐变）、透明度、亮星比例和大小、中心柔光、漂动幅度；另有一层散在整个天上的背景星星。全部一次画完，跟拍闪、慢慢漂。
- 天空盒：`skybox/nebula_512_blue.jpg`（512×256，压暗偏蓝紫），在 Stage 上指定；亮度由 `Y2kLook` 节点的 sky_energy / sky_solar_energy 定。
