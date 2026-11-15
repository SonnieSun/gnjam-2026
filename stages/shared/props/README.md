# 场景小模块（props）

一个"模块"是一个自己会动、自己会对游戏起反应的小东西，拖进任何 2D 场景就能用，不需要别的东西配合。
发光转圈猫（`stages/shared/tabby_cat`）就是这样一个模块；这里是照同样思路做的几个 2D 模块，
其中"一圈 / 一串 / 跟拍跳着转"是从 Cat Rotator 学来的（那边叫 Ring、Stream、Beat Step）。

打开 `props_demo.tscn` 按 F6 看全部：空格 = 按一下，F = 开 / 关 FEVER 的样子，R = 重来。

## 有哪些

| 名字 | 场景 | 是什么 |
|---|---|---|
| `spinner` | `meme_spinner.tscn` | 一只会转的 meme：按一下猛转一下，带惯性，连按越转越快越亮；每拍弹一下 |
| `ring` | `prop_ring.tscn` | 一圈：摆成圆，整圈慢慢转；按一下推一把；每拍半径弹一下 |
| `stream` | `prop_stream.tscn` | 一串：一个接一个流出去，边走边变大，到头再从头来（隧道、喷泉、一排流过去的猫）。速度按拍子算 |
| `orbit` | `prop_orbit.tscn` | 跟拍跳着转：每拍猛跳一格再弹回来，像秒针 |
| `tabby` | `tabby_card.tscn` | 发光转圈猫的 2D 版：把那只 3D 虎斑猫画在小画布上当一张图用 |

它们都会对三样东西起反应，每样都能在检查器的"反应"一栏关掉：**玩家按键**、**节拍**、**FEVER**（FEVER 里转得更快、更大、更亮）。
没有音乐的场景里也能用（按墙上的钟走）。

## 手动放

把上面的 `.tscn` 从文件面板拖进场景，在检查器里改：摆什么素材（`meme`，下拉里是所有能用的名字）、几份、多大、多快。
`ring` / `stream` / `orbit` 的"摆什么"可以不是一张 meme，而是**另一个模块的场景**（`item`）：
把 `tabby_card.tscn` 拖到 `prop_ring` 的 `item` 上就是一圈发光转圈猫；把 `prop_stream.tscn` 拖上去就是往四面八方喷。

## 用代码放

```gdscript
# 放一个
PropKit.spawn("ring", self, Vector2(640, 360), {"meme": "oiia", "count": 12, "radius": 260.0})
# 在一块区域里随机撒 10 只（最后的 3 是随机种子，种子一样撒出来就一样）
PropKit.scatter("spinner", self, 10, Rect2(0, 0, 1280, 720), {"meme": "popcat", "height": 80.0}, 3)
# 把某种模块摆成一圈
PropKit.ring_of("tabby", self, Vector2(640, 360), 6, 240.0)
```

字典里的名字就是检查器里的属性名。放好之后还可以随时改（`ring.count = 5` 会自己重摆），或者直接叫它动：
`spinner.spin()`、`module.on_hit()`。

## 加一个新模块

1. 写一个 `extends PropModule` 的脚本（要"把一样东西变成很多份"的话 `extends PropArranger`，只要写 `arrange()` 怎么摆）。
   重写 `on_hit()` / `on_beat(第几拍)` / `on_fever(开没开)`；用到 `_ready` 记得先调 `super()`。
2. 存一个只有根节点 + 这个脚本的 `.tscn`。
3. 在 `prop_kit.gd` 的 `SCENES` 里登记一个名字。

## 注意

- `tabby` 每张卡自己渲染一个小 3D 画面，一屏十来张没问题，几十张会卡。别的模块都只是图，很轻。
- 模块听的是"按了键"，不是"判定打中了"；想只在打中时动，把 `react_to_hit` 关掉，在关卡脚本里自己调 `on_hit()`。
- 还没接进 Tab 面板的 Memes 页（那一页的猫图是另一套数据）。要接的话，是让那一页的每只猫图可以选一个模块。
