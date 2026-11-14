# 转圈猫 + 迪斯科猫砂盆关卡（试验版）

## 怎么放
把整个 `_sandbox` 文件夹解压到项目根目录（和 `project.godot` 同一层），得到 `res://_sandbox/spin_cat/`。
需要项目里已有 Sonnie 的 framework（`main.tscn`、`scripts/core/*`、`scripts/sections/ring_section.gd`、`assets/fantasy/*`、`assets/memes/*`）。
Godot 4.7。第一次打开编辑器会自动导入 `model/CATS.fbx` 和贴图。

## 怎么跑（在编辑器里打开场景后按 F6）
| 场景 | 内容 |
|---|---|
| `disco_test.tscn` | **主要的**：迪斯科猫砂盆关卡，完整流程 |
| `spin_ring_test.tscn` | 缩圈 + 3D 小屋转圈猫 |
| `spin_cat_3d_test.tscn` | 只有 3D 猫，测转圈手感 |
| `spin_cat_test.tscn` | 2D oiia 序列帧版转圈猫 |

操作：空格（或 Z / X / J / K / 鼠标左键）。按一下猫转一圈，按住一直转，松手停。R 重来。

## 迪斯科关卡流程
进度：成功（Perfect / Good）+1，Miss -1。
- 0：镜头贴近猫和猫砂盆，房间很暗；每 +1 镜头拉远一档
- 5：星星灯掉下来，场景变亮
- 10：迪斯科灯球掉下来一直转，彩色光扫场
- 15：2D 跳舞猫从两边进场
- 20 起：猫带着判定圈离开猫砂盆，沿 `disco_room.tscn` 里 `DriftPath` 的点漂移（慢转 + 歪头 + 浮动），成功往前、Miss 往回
- 进度掉回门槛以下，对应阶段会收回

长按：谱面里音符后面接 `=`，例如 `k=======s.......`。长按只在本关卡脚本里判定，不计入 HUD 分数。

## 文件
| 文件 | 作用 |
|---|---|
| `spin_cat_3d.gd` | 3D 转圈猫组件（SubViewport 渲染到 2D） |
| `disco_stage.gd` | 舞台导演：阶段、运镜、灯光、跳舞猫、漂移，参数都是 `@export` |
| `disco_section.gd` / `disco.tscn` | 关卡本体，继承 `ring_section.gd`，另外处理长按 |
| `disco_room.tscn` | 房间、猫砂盆（占位几何体）和各种定位点 |
| `spin_ring_test.gd` | 测试入口：借用 `main.tscn`，换成只有一关的谱面 |
| `spin_cat.gd` | 2D 序列帧版转圈猫 |

没有改动任何团队文件（`main.tscn`、`scripts/` 下的都没动）。模型除了猫都是占位。
