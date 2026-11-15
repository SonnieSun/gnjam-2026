# ORBIT CAT：关卡与美术编辑

ORBIT CAT 使用主菜单的第 2 格，对应 `levels/level_2.tres`。这一格原先是披萨关卡的占位副本；其他四个大关、菜单的五格布局和原有菜单猫动作保留。

这个关卡接入的是现有 `SongChart → SectionDef → Spin3DSection` 节拍系统。`levelkit/level_editor.tscn` 是另一套四轨跑酷工具，本关不通过那套 JSON 世界编辑器加载。

## 素材与场景

| 文件 | 用途 |
| --- | --- |
| `assets/models/cat_earth_y2k/cat_earth_y2k.fbx` | 从已确认的 Blender 场景导出的猫、地球、圆润蓝紫星星、背景与动画。 |
| `assets/models/cat_earth_y2k/cat_earth_model.tscn` | 完整可编辑的原生 3D 模型、骨骼、蒙皮与 AnimationPlayer；材质已修正为 Godot 资源。 |
| `assets/models/cat_earth_y2k/*_material.tres` | 猫、地球、星系、蓝紫星星和小闪光的可编辑材质。 |
| `assets/models/cat_earth_y2k/scene_metadata.json` | 原镜头、材质、节点名和动画时刻等导出记录。 |
| `assets/models/cat_earth_y2k/README.md` | FBX 贴图烘焙与来源说明。 |
| `scenes/sections/cat_earth.tscn` | 接入现有玩法、判定圈和编辑器预览的小关入口。 |
| `levels/level_2.tres` | 大关标题、120 BPM、三段谱面、进度条和过关条件。 |
| `levels/music/level_2.json` | 保留的叠轨音乐配置；当前 `use_in_game = false`，以大关 `.tres` 的伴奏与速度为准。 |

原始 Blender 文件仍在 `E:\REPLAY II\GN-game jam\cat_earth_animation\cat_earth_y2k_scene.blend`，没有作为 `.blend` 放进 Godot 工程。工程仍关闭 Blender 自动导入，关卡使用实际导出的 FBX 及其贴图。

FBX 不支持原 Blender 的程序星系材质和渐变节点，所以星系与细小远星烘焙为背景贴图，五颗立体星星保留网格并使用蓝紫渐变贴图。原猫的骨骼与蒙皮保留。导出的完整动作在 24 fps 下持续 4 秒，含第 97 帧循环校验端点；两次接触点是第 30、78 帧，对应动画时间 `29/24`、`77/24` 秒。

## 玩法和谱面

点击鼠标左键，或按空格、Z、X、J、K，沿用全游戏同一个 `hit` 输入。快速蓄力也是谱面的一部分，需要实际连续按下；按住一个键不会自动完成连打。

每小节 4 拍，谱面每行通常为 16 格：

```text
h.h.h.h.s.......
```

`h` 是蓄力踩镲音符，`s` 是随后重拍地球的军鼓音符，`.` 是休止。三段依次是 WARM UP、CHARGE UP、SUPERNOVA，蓄力区的音符逐步加密。普通节拍判定、鼓声、成绩与连击统一由原 `Judge` 处理；关卡接收判定结果积攒力量和控制表现，不另写第二套输入判定。

蓄力音符用于攒力量，过关积累条在正式击打时推进，避免只连点蓄力就提前过关。`SpinSection.gauge_result(note, result)` 是对此开放的统一钩子，其他关卡默认沿用原来的积累条规则。

三段的积累条满值分别是 20、30、40。满条后依旧在下一个小节线切换，第三段完成后通关。关卡音乐采用 `.tres` 的 120 BPM；`levels/music/level_2.json` 当前保留的是合并带来的 DISCO 两段叠轨配置，`use_in_game` 已关闭。若要启用叠轨，应先为猫猫三段关卡配置对应的音乐，并保持 120 BPM。

第 2 关曾因合并冲突同时包含 DISCO 和 ORBIT CAT，导致 Godot 无法解析资源并在菜单进入时中断。当前 `levels/level_2.tres` 已恢复为 ORBIT CAT，DISCO 谱面和完整音乐配置另存于 `levels/alternates/`，不加入主菜单扫描。

## 在 Godot 中编辑

双击 `levels/level_2.tres`，在 Inspector 中编辑 `sections` 列表。每一段的场景、`bars`、`gauge_max`、`gauge_events`、`fx_cues` 和 `meme_cues` 都沿用现有编辑规范。新小关场景放在 `scenes/sections/` 后，会自动出现在 `SectionDef.scene_file` 下拉框中。

运行完整游戏，选择第 2 格进入 ORBIT CAT。按 Tab 打开现有游戏内编辑面板，可以调积累条、Camera 特效、Memes、Music 和 Pattern；修改 Pattern 后点 **Restart stage with new pattern** 重新铺谱，点 **Save** 才写回资源文件。面板开启时，命中和漏打不会推动积累条。保持每小节的重拍位置与蓄力段对应，再调整蓄力音符的密度。

3D 小关沿用固定节点结构：

```text
CatEarthSection (Node2D，@tool)
└─ View (SubViewportContainer)
   └─ Viewport (SubViewport)
      ├─ Camera (Camera3D)
      ├─ Sun (DirectionalLight3D)
      └─ World (Node3D)
         └─ ... Focus (Marker3D，作为唯一名称访问)
```

`Focus` 可以挂在需要跟随的模型节点下面，判定圈会通过这个标记投影到画面，不要求它直接位于 `World` 下。

模型、材质、灯光和背景应保存在场景或资源文件中，脚本只负责按拍子控制动作。需要摆放时，先关闭小关根节点的 **Preview Playing**；这样预览会回到保存的姿势，再移动、旋转或缩放节点。开启后检查预览。动画叠加应基于 `rest(node)`，保存前通过 `restore_rest()` / `_on_restore()` 恢复，避免把某一帧的临时姿势误存成新摆放。

日常美术编辑入口为 `scenes/sections/cat_earth.tscn`。`World/CatEarth` 是整套模型的布局根节点；`Focus` 随它移动，`CameraPose` 与 `CameraTarget` 控制机位和朝向。根节点的“原动画与节拍”分组保存源帧率、循环帧数、起播帧与每次挥爪拍数；“连续点击蓄力”分组保存蓄力区间、重拍位置、目标次数与最低蓄力比例；“提示与反馈”分组保存提示卡位置、颜色和开关。4/6/8 次连打由各段 Pattern 决定，实际目标自动跟随谱面。

动画内的骨骼和星星位置属于已烘焙的关键帧。整体摆放请移动 `World/CatEarth`；修改某个已动画节点的轨迹应编辑其 AnimationPlayer 轨道，或在 Blender 中修改后重新导出。F6 单独运行小关用于自动节拍预览，实际输入测试从主菜单第 2 格进入。

FBX 重新导入后，运行 `tools/build_cat_earth_model.gd` 重新生成原生模型和材质包装，再检查场景。该步骤会重建 `cat_earth_model.tscn`，因此需要保留的手动模型修改应先备份。原生模型不是指向 `.godot` 缓存的副本，提交仓库后可以独立重建导入缓存。

## 检查修改

从完整菜单进入第 2 格，依次检查三段：蓄力音符能连续输入、重拍与音乐和接触姿势对齐、积累条按正式击打推进、满条在小节线上切段。再检查 R 重来、Esc 回菜单和 Tab 面板保存。

美术调整后，在暂停预览的状态保存场景，重新打开确认摆放没有被某一帧覆盖。播放完整 4 秒动作，检查猫耳、举爪、地球与装饰星星之间的空隙。只替换贴图时，等待 Godot 重新导入后检查材质；替换 FBX 时按上述步骤刷新原生模型。

自动回归命令：`Godot --headless --path . --script res://tools/test_cat_earth_level.gd`。它使用现有 Judge 模拟真实输入，检查蓄力不足、漏打、编辑状态冻结、三段过关、源动画接触帧和保存前恢复。

菜单入口回归：`Godot --headless --path . --script res://tools/test_cat_earth_menu_entry.gd`。它先检查第 2 关资源能否读取，再操作原菜单转到第 2 格，经过实际开始转场进入关卡，并返回菜单。
