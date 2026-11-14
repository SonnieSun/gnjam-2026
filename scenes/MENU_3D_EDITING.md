# 菜单 3D 编辑入口

在 Godot 文件系统中双击 `res://scenes/menu_disc_3d.tscn`，切到顶部的 **3D**。
这是原生 Node3D 场景，可以直接选中、移动、旋转和缩放里面的模型。
选中 Camera 后启用摄像机预览，可查看游戏采用的透视构图。

| 文件 | 用途 |
|---|---|
| `menu_disc_3d.tscn` | 完整 3D 布景：猫、唱片、文字、灯光、摄像机和爪子落点。日常调整从这里开始。 |
| `menu_cat_3d.tscn` | 猫的单手打碟动作适配。关闭 `Preview Pose` 可暂停编辑器内的骨骼驱动。 |
| `cat_scratch_model.tscn` | 原生猫模型：可直接展开 Skeleton3D、网格、皮肤绑定和 AnimationPlayer；不依赖 FBX 导入场景。 |
| `../assets/menu/cat_material.tres` | 猫的材质与原始贴图，直接在 Inspector 中编辑。 |
| `menu.tscn` | 完整游戏菜单入口，保留原有输入、音效和切关逻辑。 |
| `menu_view.tscn` | 游戏运行时的显示包装，自动实例化上面的 3D 布景；美术无需在这里编辑。 |

## 常用调整

- 调猫的位置、大小、俯仰：选中 `Cat`，改 Transform。
- 调打碟爪落点：移动 `ScratchContact`；`Cat` 上的 `Scratch Width` 控制左右拨动距离。
- 调支撑爪落点：移动 `SupportContact`。
- 调唱片大小和厚度：选中 `Record/DiscMesh`，展开 Mesh。
- 调黑胶纹路、高光和星点：展开唱片材质的 Shader Parameters。
- 调关卡文字：展开 `Labels/Item1` 至 `Item5`，编辑 Anchor、Title、Sub。
- 调镜头：选中 `Camera`。它的位置和 FOV 会直接用于游戏。
- 调猫的网格或骨骼：打开 `cat_scratch_model.tscn`。这个文件没有姿势驱动脚本，可以直接检查骨骼和动画。

在布景中保存的摆放、文字和材质会用于菜单；旋转动画叠加在保存的摆放上。
F6 可以预览当前 3D 场景；F5 测试完整菜单与切关交互。

原始 `assets/art/CATS_Scratch.fbx` 和 `cat_basecolor_512.png` 均保留。
原生模型网格和动画已写入 `.tscn`，不是 `.godot` 缓存文件。

## 暗场聚光灯

- `WorldEnvironment → Environment → Ambient Light → Energy` 控制环境底光。
- `FillLight` 是场景补光，`Cat/CatFill` 是猫脸补光，调各自的 Light → Energy。
- `BeamLight2` 是暖色顶部聚光灯，控制照射方向、亮度、范围和软阴影。
- `BeamLight2/LightBeam` 是可编辑的 3D 光束外形，跟随聚光灯移动和旋转；材质的 `Opacity` 控制空气中光束的可见度。这使光束在透明菜单中也能正常显示。
- 原来的 `Beam` 和 `BeamLight` 已隐藏，保留供以后切换风格。
- 背景图片的明暗在 `menu.tscn → BackgroundLayer/Background/TextureRect → Self Modulate` 调整。
