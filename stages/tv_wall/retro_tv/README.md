# 粉色复古电视 retro_tv.glb（交接说明）

照 Kisa 的设定图（三视图 + 材质说明）做的低模电视，给「电视墙」关卡用。在云端用 Blender 5.3 脚本生成，**没有在 Godot 里跑过**。

## 文件
| 路径 | 说明 |
|---|---|
| `retro_tv.glb` | 模型，贴图已打包进去（约 240 KB） |
| `tv_screen.gd` | 屏幕动态换图/换色脚本（挂在 TV 根节点上，见下） |
| `textures/` | 同样的贴图单独一份，方便换图/改图 |
| `preview/` | 预览渲染图（Blender Cycles，不是游戏内效果）；`compare_with_concept.png` 是和设定图对照 |
| `source/` | 生成脚本和 .blend（`make_tex.py` 贴图、`build_tv.py` 建模导出、`patch_glb.py` 改材质参数、`render_tv.py` 渲染） |

## 尺寸和朝向
- 宽 1.0 m、高约 0.96 m（含脚）、深约 0.82 m。约 1500 三角面。
- 原点在**地面、占地中心**，方便绕洗衣机转着摆。
- 在 Godot 里屏幕朝 **+Z**（模型默认面向看 -Z 方向的相机）。要它面向洗衣机中心就 `look_at(中心)` 后再转 180°，或直接 `rotation.y = atan2(dir.x, dir.z)`。

## 节点树
```
TV (根)
├─ Shell            外壳+4只脚              材质 Shell
├─ Screen           屏幕（独立网格和 UV）     材质 Screen
├─ Controls         控制板+2个按钮+两侧散热格  材质 Controls
├─ ControlsDots_L / ControlsDots_R  小圆点贴片  材质 ControlsDecal
└─ Stickers (空节点)
    ├─ Sticker_Heart_TopL / Sticker_Heart_TopR / Sticker_Heart_L / Sticker_Heart_R / Sticker_Heart_Side
    ├─ Sticker_Star_L / Sticker_Star_R / Sticker_Star_Side
    ├─ Sticker_Flower_Top
    └─ Sticker_Whiskers_L / Sticker_Whiskers_R
```
每个网格只有 1 个材质槽（surface 0）。

## 材质
| 材质 | 贴图 | 怎么用 |
|---|---|---|
| Shell | `shell_gray.png` 中性浅灰+细网点 | 外壳颜色 = albedo_color × 灰贴图。默认 albedo_color (1.0, 0.56, 0.76) 粉 |
| Controls | `controls_gray.png` 三段灰度（散热格深 / 控制板中 / 按钮浅） | 同样乘 albedo_color 换色。默认 (0.93, 0.40, 0.62) |
| ControlsDecal | `controls_dots.png`（透明，Alpha Scissor 0.5） | 小圆点，乘同一个控制区颜色 |
| Screen | `screen_default.png` 640×486，同时做 albedo 和 emission | 屏幕画面，UV 0–1 铺满屏幕矩形（比例约 1.32:1） |
| Sticker_Heart / Star / Flower / Whiskers | `sticker_*.png` 256²（透明，Alpha Scissor 0.5） | 贴纸，自带深蓝描边，不随外壳染色 |

所有材质都是单面（背面剔除），贴纸用 Alpha Scissor（不进透明排序，深度正常写入）。

## 屏幕画面动态替换（推荐用 tv_screen.gd）
把 `tv_screen.gd` 放进项目，挂到每台电视实例的根节点 `TV` 上（类名 `RetroTVScreen`）。它会给每台电视复制一份自己的屏幕材质，所以每台可以放不同画面。
- Inspector：`screen_texture`（画面，留空 = 默认星星图）、`glow`（发光强度，0 = 不发光）、`screen_tint`（画面亮度/颜色，熄灭时可调暗）、`shell_color`、`controls_color`。
- 代码：`tv.set_screen(tex)`、`tv.set_screen(tex, 2.0)`、`tv.glow = 0.0`、`tv.shell_color = Color(...)`，运行时随时改，立刻生效。
- `screen_texture` 可以是任何 Texture2D：PNG、AnimatedTexture、`SubViewport.get_texture()`（屏幕里放一个 2D/3D 小场景）、`VideoStreamPlayer.get_video_texture()`（放视频）。传 ViewportTexture/视频贴图时画面每帧自己刷新。
- 屏幕 UV 是 0–1 铺满屏幕，比例约 1.32:1（640×486 就刚好不变形）。

## 不用脚本、手动换的写法
导入后材质是所有实例**共享**的。每台电视要不同颜色/画面，就给那台复制一份材质再改：

```gdscript
# tv = 实例化后的 retro_tv 场景根节点
func set_tv_color(tv: Node3D, shell_col: Color, ctrl_col: Color) -> void:
    _tint(tv.get_node("Shell"), shell_col)
    _tint(tv.get_node("Controls"), ctrl_col)
    _tint(tv.get_node("ControlsDots_L"), ctrl_col)
    _tint(tv.get_node("ControlsDots_R"), ctrl_col)

func _tint(mi: MeshInstance3D, col: Color) -> void:
    var m := mi.get_active_material(0).duplicate() as StandardMaterial3D
    m.albedo_color = col
    mi.set_surface_override_material(0, m)

func set_tv_screen(tv: Node3D, tex: Texture2D, glow := 1.0) -> void:
    var mi := tv.get_node("Screen") as MeshInstance3D
    var m := mi.get_active_material(0).duplicate() as StandardMaterial3D
    m.albedo_texture = tex
    m.emission_enabled = true
    m.emission_texture = tex
    m.emission_energy_multiplier = glow   # 点亮时调大（配合 WorldEnvironment glow 就会泛光），熄灭时设 0、albedo 换暗
    mi.set_surface_override_material(0, m)
```
- 屏幕放视频：把 `VideoStreamPlayer.get_video_texture()` 或 `SubViewport.get_texture()` 传给 `set_tv_screen` 即可。
- 换贴纸图：同理改 `Sticker_xxx` 节点的 `albedo_texture`；想整个项目统一换，直接替换 `textures/sticker_*.png` 再重新导出，或在导入设置里把材质提取成 .tres 改。
- 设定图里三个色块参考：粉 (1.0, 0.56, 0.76)、紫 (0.72, 0.62, 1.0)、薄荷 (0.50, 0.95, 0.85)；控制区用同色稍深一档（见 `preview/preview_colors.png`）。

## 和漫画滤镜（scripts/fx/comic_style.gd）的关系
- 模型不带描边（按 Kisa 要求去掉了），描边交给滤镜。贴纸 PNG 自己画的深蓝边保留。
- 外壳灰贴图里有一层很淡的网点；如果和滤镜网点打架，可以把 Shell 的 albedo_texture 清掉，只留 albedo_color。

## 已知和设定图不一样的地方
- 顶视图里斜面上的散热格：模型只做在左右两个侧面（跟右视图一致），从正上方看不到。
- 设定图正视图只画了 2 只脚；模型是 4 只（右视图有后脚），正面看两只后脚会从中间露出一点。
