# 飞碟吸猫关卡

本机原型，只在 `_sandbox/`，不进仓库。

## 怎么跑
- `abduction_test.tscn`：F6 自己玩。空格 / Z / X / J / K / 鼠标左键按。
- 想看自动打的演出：在 `abduction.tscn` 根节点勾 `autoplay`（正式玩记得关）。

## 玩法
夜空、紫色云，飞碟在上面用绿白色光束照着站着的猫，整个画面套一层 VHS 效果（噪点、扫描线、色彩错位、滚动干扰带）。
- 每个音符是一个光圈，从飞碟顺着光束往下套，套到猫身上的那一拍按键。
- 打中：光圈变色扩散，猫像前面关卡的转圈猫一样快速转一整圈（落回正面），往上升一格（升起来后会轻轻晃）。没打中：光圈变红往下掉，猫掉一格，镜头抖，全屏红闪。
- 攒满 `hits_needed`（默认 8）下：猫边转边缩小被吸进飞碟 → 飞碟闪一下 → 飞走 → 空几拍 → 飞回来，猫重新出现在地上，进度清零重来。
- 飞碟不在的时候来的音符照样会被 Judge 判定（没按就算 Miss），舞台不理它们；测试谱面在每轮之后留了 2 小节空白。
判定用 Sonnie 的 Judge，没改。

## 文件
| 文件 | 说明 |
|---|---|
| `abduction_section.gd` | 关卡脚本，继承 `SpinSection`，把判定结果转给舞台；`approach_beats`（光圈提前几拍出发）、`miss_flash`、`autoplay` |
| `abduction_stage.gd` | 3D 舞台：天空、云、飞碟、光束、猫、光圈、镜头、吸进去的流程 |
| `vhs.gdshader` | 全屏 VHS / CRT 效果 |
| `abduction.tscn` | 关卡场景；参数在根节点和 `Stage` 节点的 Inspector 里调，VHS 参数在 Stage 的 `screen_material` 里 |
| `abduction_test.tscn` | F6 测试入口 |
| `model/cat_stand.fbx`、`model/cat_stand_basecolor.png` | Kisa 给的站立猫和贴图（FBX 里记的贴图路径是 Kisa 电脑上的原文件，所以贴图在代码里贴） |
| `ufo.tscn`、`model/ufo/ufo.fbx`、`model/ufo/ufo_texture.png` | Kisa 给的 UFO（机身用贴图，灯和玻璃罩的贴图没给，在 ufo.tscn 里配了发光绿灯和半透明蓝玻璃）；放大 6.6 倍、底面中心对到 (0, -2.6, 0)，和原飞碟一样大 |

只读复用：`_sandbox/spin_cat/spin_ring_test.gd`（测试入口，套 main.tscn）。

## 常调的参数（Stage 节点）
- 猫：`cat_height`、`cat_yaw_degrees`、`cat_self_light`（夜里脸的亮度）、`lift_spin_speed`、`lift_wobble_degrees`、`hit_pop`、`hit_spin_time`（打中转一圈用几秒）
- 飞碟：`saucer_position`、`saucer_tilt_degrees`、`saucer_scale`、`saucer_bob`
- 光束：`beam_top_radius`、`beam_bottom_center` / `beam_bottom_radius`（地面上那个圆，按 Kisa 画的红线摆；光束是上下都是水平圆的斜锥，光圈是水平截面）、`beam_color` / `beam_core_color`、`beam_energy`、`beam_light_energy`
- 玩法：`hits_needed`、`miss_drop`、`max_lift`（攒满前最高升到几成）
- 光圈：`ring_color`、`ring_scale`、`ring_thickness`
- 吸进去以后：`absorb_beats`、`away_beats`、`gone_beats`、`return_beats`、`away_offset`、`absorb_flash_energy`
- 镜头：`camera_position`、`camera_target`、`camera_fov`、`camera_follow`、`camera_sway`、`miss_shake`
- 天空：颜色、月光、`clouds`（每朵 x, y, z, 大小）、`cloud_drift`

## 已知
- 编辑器里不预览 3D 画面（只显示一行字）。
- 测试入口借用 spin_ring_test.gd，左下角调试信息里关卡名显示的是 "SPIN CAT"。
- 飞碟用本关自己的 `ufo.tscn`（不再用 stages/shared/saucer.tscn，飞船关卡不受影响）。换模型时保持底面中心在 `beam_top_local`（默认 (0, -2.6, 0)）。
- 猫站在飞碟正下方（`cat_ground` = (-4.5, 0, 0)），在光柱中间。
