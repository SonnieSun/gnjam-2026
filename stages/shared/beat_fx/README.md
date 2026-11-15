# BeatFx：统一的节拍效果组件

挂在任何物品下面，让它的效果（胀缩、自发光、灯光、颜色、shader 参数、动画）跟着音乐里某个声音一下一下地走。
音乐系统和别的代码可以按「频道名」找到所有挂了它的物品，统一调强度或关掉。现有代码不需要知道它存在。

## 文件
| 文件 | 说明 |
|---|---|
| `beat_fx.gd` | 组件本体（`class_name BeatFx`） |
| `beat_fx_test.tscn` / `.gd` | 测试场景，F6 运行：一排方块各跟一个频道，1 / 2 / 3 换关，↑ ↓ 调积累条进度 |
| `hits/` | 打点表：每段音乐 loop 里每一下落在第几拍，低 / 中 / 高频分开（自动生成，别手改） |
| `tools/make_hit_tables.mjs` | 生成打点表的脚本（Node.js），换了音乐或加了 loop 后在项目根目录跑：`node stages/shared/beat_fx/tools/make_hit_tables.mjs` |

## 跟什么声音（source）
| source | 频道名 | 什么时候响 | 每关不同吗 |
|---|---|---|---|
| BEAT | `beat`（或 `beat/0.5` 这种） | 每 `every_beats` 拍，可错开 `beat_offset` | 只和 BPM 有关 |
| BAR | `bar` | 每小节第一拍 | 只和 BPM 有关 |
| CHART | `chart:kick` / `chart:snare` / `chart:hat` / `chart:any` | 谱面里这种鼓的音符那一拍 | 是：每关、每个小关谱面不一样 |
| LANE | `lane:<轨道>/<频段>`，如 `lane:meow/all`、`lane:beat/high`、`lane:bass/low` | 这条轨现在正在放的那段 loop 里的每一下；轨道静音时不响，淡入淡出时强度跟着音量 | 是：每关同名的轨放的是不同的 loop |

轨道名就是 `levels/music/<大关>.json` 里 lanes 的 id：`beat`（节奏）、`bass`（低音）、`bed`（和声）、`lead`（旋律）、
`peak`（高潮）、`meow`（猫鼓）、`kiai`（鬼畜）、`fx`（事件）、`fill`（过门）。
频段：`all` 不分；`low` 大致是底鼓、低音；`mid` 是军鼓、拍手、人声；`high` 是镲。
`hit`（打中唱）轨是玩家打中时才唱的，不跟时钟走，没有打点表。

## 效果（effect）
| effect | 作用在 | amount 的意思 |
|---|---|---|
| SCALE | 父节点（2D / 3D / Control）的 scale | 胀多少，0.2 = 大 20% |
| GLOW | 父节点下所有模型的自发光（材质各复制一份，不影响别的物品；没开自发光的用自己贴图发光） | 自发光加多少 |
| LIGHT | 灯（Light3D / Light2D）的亮度 | 亮多少倍 |
| MODULATE | 2D 节点的 modulate | 亮多少倍 |
| SHADER_PARAM | 父节点下 ShaderMaterial 的 `shader_param` 参数（必须是 float） | 加多少 |
| ANIMATION | 父节点下的 AnimationPlayer，每一下从头放 `animation_name` | 不用 |
| NONE | 什么都不改，只发 `hit(strength)` 信号、更新 `pulse` | 不用 |

`decay_beats`：每一下多少拍落回去。`min_strength`（LANE）：比这小声的那一下不理。
一个物品要几种效果就挂几个。`target` 可以指定别的节点，空着就是父节点。

## 用法
场景里：选中物品 → 加 Node 子节点 → 挂 `beat_fx.gd` → 检查器里选 source / effect。

代码里：
```gdscript
BeatFx.attach(lamp, {"source": BeatFx.Source.LANE, "lane": "meow", "effect": BeatFx.Effect.LIGHT, "amount": 1.5})
```

找到 / 控制一组：
```gdscript
for fx in BeatFx.find("lane:meow/all"):   # 也可以用自己起的 tag
    print(fx.get_parent().name)
BeatFx.set_gain("chart:kick", 0.0)        # 这一组全关；1 = 正常，可以 > 1
```

## 注意
- SCALE 每帧改父节点的 scale；父节点自己还在做缩放动画的话包一层。
- SHADER_PARAM 改的是材质本身：几个物品共用同一个 ShaderMaterial 时会一起变。
- 打点表是 json，导出游戏时要在导出设置里把 `*.json` 加进「非资源文件」。
- 打点表是从 wav 自动分析的：起音位置误差大约几毫秒；很软的音（铺底和声、拉长的猫叫）可能漏掉或多出一两下。
