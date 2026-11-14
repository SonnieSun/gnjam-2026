# 迪斯科房间 P2 模型：折线装饰牌 A12、花形墙灯 A11、饮料罐 A06（粉/绿两罐）、小盆栽 A07、电线 A14。
# 用法（在项目根目录）：
#   blender -b --factory-startup --python _sandbox/spin_cat/model_src/build_p2.py -- _sandbox/spin_cat/model
# 尺度、原点和 build_p1.py 一样；墙饰原点在背面中心，小物原点在底面中心。

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math
import disco_common as dc
from disco_common import (reset, make_root, material, pixel_image, new_object, stand_up,
                          prism, domed_prism, loft, box, chamfer_rect, circle, tube)

dc.OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(dc.OUT, exist_ok=True)


# ---------------- 折线装饰牌 A12 ----------------
# 宽 1.4、高 2.2；橙黄底牌 + 粉色折线条（六段，每段一个小方条，接头处互相压住）。

def build_zigzag_plaque():
    reset()
    root = make_root("ZigzagPlaque")
    board = material("Board_Orange", (1.0, 0.70, 0.25), 0.6, grain=0.05)
    strip = material("Strip_Pink", (0.98, 0.42, 0.62), 0.5, grain=0.04)
    new_object("Board", stand_up(prism(chamfer_rect(1.4, 2.2, 0.06), 0.0, 0.12)), board, root)
    pts = [(-0.32 if i % 2 == 0 else 0.32, 0.72 - i * 0.24) for i in range(7)]
    w = 0.17
    bm = bmesh.new()
    for i in range(6):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        dx, dy = x1 - x0, y1 - y0
        l = math.hypot(dx, dy)
        ux, uy = dx / l, dy / l
        nx, ny = -uy * w / 2, ux * w / 2
        ex, ey = ux * w / 2, uy * w / 2  # 两头各多出半个宽度，接头不留缝
        quad = [(x0 - ex - nx, y0 - ey - ny), (x1 + ex - nx, y1 + ey - ny),
                (x1 + ex + nx, y1 + ey + ny), (x0 - ex + nx, y0 - ey + ny)]
        if (quad[1][0] - quad[0][0]) * (quad[2][1] - quad[0][1]) - (quad[1][1] - quad[0][1]) * (quad[2][0] - quad[0][0]) < 0:
            quad.reverse()
        prism(quad, 0.12, 0.25, bm, cap_bottom=False)
    new_object("Strip", stand_up(bm), strip, root)
    dc.export("zigzag_plaque")


# ---------------- 花形墙灯 A11 ----------------
# 直径约 1.9；深粉紫背板 + 八瓣花 Emitter + 花心 Emitter_Center。

def flower_outline(scale=1.0, n=48):
    pts = []
    for i in range(n):
        a = i * math.tau / n
        r = 0.62 + 0.33 * abs(math.cos(4 * a)) ** 0.7
        pts.append((math.cos(a) * r * scale, math.sin(a) * r * scale))
    return pts


def build_flower_light():
    reset()
    root = make_root("FlowerLight")
    back = material("Backplate", (0.62, 0.22, 0.45), 0.7, grain=0.05)
    petal = material("Emitter", (1.0, 0.50, 0.78), 0.4, grain=0.0, emission=(1.0, 0.50, 0.78))
    center = material("Emitter_Center", (1.0, 0.80, 0.88), 0.4, grain=0.0, emission=(1.0, 0.80, 0.88))
    new_object("Backplate", stand_up(prism(flower_outline(1.0, 32), 0.0, 0.1)), back, root)
    new_object("Emitter", stand_up(domed_prism(flower_outline(0.93, 32), 0.1, 0.24, 0.34, cap_bottom=False)),
               petal, root)
    new_object("Emitter_Center", stand_up(domed_prism(circle(0.3, 8), 0.3, 0.38, 0.44, cap_bottom=False)),
               center, root)
    dc.export("flower_light")


# ---------------- 饮料罐 A06 ----------------
# 高 0.62、直径 0.44；八边柱 + 收窄的罐顶。同一个形状导出粉、绿两罐（只差标签颜色）。

def can_label(name, color):
    stripe = (0.98, 0.95, 0.92)

    def at(x, y):
        if y < 3 or y > 28:  # 上下两头银色
            return (0.75, 0.75, 0.78)
        if 13 <= y <= 17:  # 中间白条
            return stripe
        return color

    return pixel_image(name, 8, 32, at, 0.04)


def build_can(name, color):
    reset()
    root = make_root("DrinkCan")
    label = material("Can_Label", (1, 1, 1), 0.35, metal=0.3, image=can_label(name + "_label", color))
    top = material("Can_Top", (0.78, 0.78, 0.80), 0.3, metal=0.8, grain=0.03)
    body = new_object("Body", prism(circle(0.22, 8, phase=math.pi / 8), 0.0, 0.54, cap_bottom=True), label, root)
    # 标签 UV：v 按高度，u 按角度（贴图只有横条，接缝看不出来）
    me = body.data
    uv = me.uv_layers.active.data
    for li, loop in enumerate(me.loops):
        c = me.vertices[loop.vertex_index].co
        uv[li].uv = ((math.atan2(c.y, c.x) / math.tau) % 1.0, c.z / 0.54)
    new_object("Top", loft(circle(0.22, 8, phase=math.pi / 8), 0.54, circle(0.17, 8, phase=math.pi / 8), 0.62),
               top, root)
    dc.export(name)


# ---------------- 小盆栽 A07 ----------------
# 高约 1.3；八边形粉色花盆 + 深棕土面 + 茎 + 五片单面叶子（叶子材质双面显示）。

def leaf(bm, base, yaw, pitch, length, width):
    """一片叶：底尖、中间宽、顶尖，中脉微微拱起；yaw 朝向、pitch 抬起角"""
    ca, sa = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)

    def p(t, s, lift=0.0):  # t 沿叶长，s 横向
        d = t * length
        x = d * cp
        z = d * sp + lift
        return (base[0] + ca * x - sa * s, base[1] + sa * x + ca * s, base[2] + z)

    v0 = bm.verts.new(p(0.0, 0.0))
    vl = bm.verts.new(p(0.45, -width / 2))
    vr = bm.verts.new(p(0.45, width / 2))
    vm = bm.verts.new(p(0.45, 0.0, 0.05))
    vt = bm.verts.new(p(1.0, 0.0))
    for f in ([v0, vl, vm], [v0, vm, vr], [vl, vt, vm], [vm, vt, vr]):
        bm.faces.new(f)


def build_plant():
    reset()
    root = make_root("PottedPlant")
    pot = material("Pot_Pink", (0.92, 0.52, 0.56), 0.6, grain=0.05)
    soil = material("Soil", (0.30, 0.19, 0.12), 0.95, grain=0.10)
    green = material("Leaf", (0.42, 0.66, 0.24), 0.6, grain=0.08)
    green.use_backface_culling = False
    stem = material("Stem", (0.32, 0.55, 0.18), 0.6, grain=0.04)

    bm = loft(circle(0.24, 8, phase=math.pi / 8), 0.0, circle(0.32, 8, phase=math.pi / 8), 0.5)
    prism(circle(0.36, 8, phase=math.pi / 8), 0.5, 0.6, bm)  # 盆沿
    new_object("Pot", bm, pot, root)
    new_object("Soil", prism(circle(0.31, 8, phase=math.pi / 8), 0.5, 0.605, cap_bottom=False), soil, root)
    new_object("Stem", prism(circle(0.035, 4), 0.6, 1.0, cap_bottom=False), stem, root)
    bm = bmesh.new()
    leaf(bm, (0, 0, 0.98), 0.3, 1.35, 0.42, 0.2)  # 顶上一片，几乎竖着
    for k, (yaw, h) in enumerate(((0.0, 0.8), (math.pi, 0.84), (math.pi / 2, 0.9), (-math.pi / 2, 0.74))):
        leaf(bm, (0, 0, h), yaw + 0.4, 0.45, 0.45, 0.2)
    new_object("Leaves", bm, green, root)
    dc.export("potted_plant")


# ---------------- 电线 A14 ----------------
# 一条在竖直面里垂下的 U 形线，原点在左端点。默认两头间距 SPAN、下垂 SAG（改这两个数重跑就能换长度）；
# 在 Godot 里小幅缩放（0.7~1.4 倍）也行，缩太多线会变粗/变扁。

SPAN, SAG = 5.5, 1.8


def build_cable():
    reset()
    root = make_root("Cable")
    rubber = material("Cable_Rubber", (0.18, 0.10, 0.20), 0.7, grain=0.04)
    path = []
    for i in range(6):
        t = i / 5
        path.append((t * SPAN, 0.0, -SAG * (1 - (2 * t - 1) ** 2)))  # 抛物线，五段
    new_object("Cable", tube(path, 0.035, 4), rubber, root)
    dc.export("cable")


build_zigzag_plaque()
build_flower_light()
build_can("drink_can_pink", (0.95, 0.38, 0.62))
build_can("drink_can_green", (0.45, 0.80, 0.30))
build_plant()
build_cable()
print("REPORT", dc.REPORT)
