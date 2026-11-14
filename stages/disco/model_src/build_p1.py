# 迪斯科房间 P1 模型：桌子 A03、CRT 电脑 A05、圆凳 A04、手柄墙灯 A10、五角星装饰 A13。
# 用法（在项目根目录）：
#   blender -b --factory-startup --python _sandbox/spin_cat/model_src/build_p1.py -- _sandbox/spin_cat/model
# 尺度和 build_p0.py 一致：猫高约 3.7；房间地板顶面 y = -0.9，墙高 9。
# 原点：家具在底面中心（放到地板上就是 y = -0.9）；墙饰在背面中心（贴墙放）。
# 发光部件的材质名以 Emitter 开头，和星星吊灯一样，游戏里可以按名字换色、按节拍闪。

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math
import disco_common as dc
from disco_common import (reset, make_root, material, pixel_image, new_object, planar_uv, stand_up, move,
                          prism, domed_prism, loft, ring, box, chamfer_rect, circle, star_points, offset_polygon)

dc.OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(dc.OUT, exist_ok=True)

PINK_PAINT = (0.96, 0.55, 0.70)


# ---------------- 桌子 A03 ----------------
# 宽 5、深 2.4、高 3.1（桌面顶）。前后腿各两条。

def build_desk():
    reset()
    root = make_root("Desk")
    paint = material("Desk_Paint", PINK_PAINT, 0.55, grain=0.05)
    W, D, H, T = 5.0, 2.4, 3.1, 0.25
    new_object("Top", prism(chamfer_rect(W, D, 0.15), H - T, H), paint, root)
    bm = None
    for sx in (-1, 1):
        for sy in (-1, 1):
            bm = box(sx * (W / 2 - 0.35), sy * (D / 2 - 0.3), (H - T) / 2, 0.3, 0.3, H - T, bm)
    new_object("Legs", bm, paint, root)
    dc.export("desk")


# ---------------- CRT 电脑 A05 ----------------
# 宽 2.3、总高 2.25；屏幕单独网格，材质 Screen（像素猫贴图，同时接自发光）。

CAT = [
    "..#.........#..",
    "..##.......##..",
    "..###########..",
    ".#############.",
    ".#############.",
    "####oo###oo####",
    "####oo###oo####",
    "#######o#######",
    "#####o#o#o#####",
    ".#####o#o#####.",
    "..###########..",
    "...#########...",
]


def screen_image():
    W, H = 24, 18
    ox, oy = (W - 15) // 2, (H - 12) // 2
    bg, white, dark = (0.30, 0.62, 0.95), (0.97, 0.97, 1.0), (0.14, 0.30, 0.62)

    def at(x, y):
        cx, cy = x - ox, y - oy
        if 0 <= cy < 12 and 0 <= cx < 15:
            ch = CAT[cy][cx]
            if ch == "#":
                return white
            if ch == "o":
                return dark
        # 扫描线：隔行稍暗
        return tuple(v * (0.9 if y % 2 else 1.0) for v in bg)

    return pixel_image("crt_screen", W, H, at, 0.03)


def build_crt():
    reset()
    root = make_root("CRT")
    shell = material("CRT_Shell", (0.97, 0.80, 0.80), 0.5, grain=0.05)
    screen = material("Screen", (1, 1, 1), 0.3, image=screen_image(), emission_image=True)
    pink = material("Button_Pink", (0.88, 0.40, 0.60), 0.5, grain=0.02)
    yellow = material("Button_Yellow", (1.0, 0.78, 0.15), 0.4, grain=0.02)
    green = material("Button_Green", (0.55, 0.85, 0.25), 0.4, grain=0.02)

    # 平放着建：x 右、y 上、z 朝前，最后 stand_up
    BW, BH, CY = 2.3, 1.9, 1.3  # 前框宽高、前框中心高度
    bm = prism(chamfer_rect(BW, BH, 0.22, 0, CY), 0.2, 0.7)  # 前框
    loft(chamfer_rect(2.0, 1.65, 0.2, 0, CY), 0.2, chamfer_rect(1.2, 1.0, 0.15, 0, CY + 0.05), -0.9, bm)  # 后壳收窄
    box(0, 0.25, 0.0, 0.6, 0.2, 0.5, bm)  # 支颈
    new_object("Shell", stand_up(bm), shell, root)
    new_object("Base", stand_up(box(0, 0.075, 0.0, 1.7, 0.15, 1.1)), shell, root)
    # 屏幕：前框正面往前一点点
    scr = new_object("Screen", stand_up(prism([(-0.78, CY - 0.55 + 0.1), (0.78, CY - 0.55 + 0.1),
                                               (0.78, CY + 0.6), (-0.78, CY + 0.6)], 0.7, 0.71, cap_bottom=False)),
                     screen, root)
    planar_uv(scr, 0, 2)
    # 前框下沿的按钮：薄色块
    y = CY - 0.72
    new_object("ButtonStrip", stand_up(box(-0.6, y, 0.71, 0.55, 0.1, 0.03)), pink, root)
    new_object("ButtonA", stand_up(box(0.55, y, 0.71, 0.13, 0.13, 0.03)), yellow, root)
    new_object("ButtonB", stand_up(box(0.78, y, 0.71, 0.13, 0.13, 0.03)), green, root)
    dc.export("crt")


# ---------------- 圆凳 A04 ----------------
# 座面直径 1.7、高 1.75；四条腿略外撇。

def build_stool():
    reset()
    root = make_root("Stool")
    paint = material("Stool_Paint", (0.98, 0.60, 0.74), 0.55, grain=0.05)
    new_object("Seat", prism(circle(0.85, 10), 1.45, 1.75), paint, root)
    bm = bmesh.new()
    s = 0.09
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        tx, ty = math.cos(a) * 0.5, math.sin(a) * 0.5  # 上端
        bx, by = math.cos(a) * 0.72, math.sin(a) * 0.72  # 下端（外撇）
        top = [(tx - s, ty - s), (tx + s, ty - s), (tx + s, ty + s), (tx - s, ty + s)]
        bot = [(bx - s, by - s), (bx + s, by - s), (bx + s, by + s), (bx - s, by + s)]
        loft(bot, 0.0, top, 1.45, bm)
    new_object("Legs", bm, paint, root)
    dc.export("stool")


# ---------------- 手柄墙灯 A10 ----------------
# 宽 2.9、高 1.57；背板深紫（正面贴十字键和按钮），外圈亮边是 Emitter。

def gamepad_outline():
    r = [(0.4, -0.5), (0.72, -0.6), (1.0, -0.85), (1.3, -0.8), (1.45, -0.45), (1.4, 0.05),
         (1.25, 0.55), (1.05, 0.72), (0.75, 0.7), (0.55, 0.55)]
    left = [(-x, y) for (x, y) in reversed(r)]
    return r + left


def gamepad_face_image():
    W, H = 64, 36
    base, lilac = (0.36, 0.17, 0.42), (0.85, 0.74, 0.95)
    # 背板范围 x -1.45..1.45、y -0.85..0.72 -> 贴图像素
    def to_px(x, y):
        return (x + 1.45) / 2.9 * W, (0.72 - y) / 1.57 * H

    dpx, dpy = to_px(-0.75, 0.05)
    btns = [to_px(0.75 + dx, 0.05 + dy) for dx, dy in ((0, 0.22), (0, -0.22), (-0.22, 0), (0.22, 0))]

    def at(x, y):
        fx, fy = x + 0.5, y + 0.5
        if (abs(fx - dpx) < 2.2 and abs(fy - dpy) < 6.5) or (abs(fx - dpx) < 6.5 and abs(fy - dpy) < 2.2):
            return lilac
        for bx, by in btns:
            if (fx - bx) ** 2 + (fy - by) ** 2 < 2.6 ** 2:
                return lilac
        return base

    return pixel_image("gamepad_face", W, H, at, 0.05)


def build_gamepad_light():
    reset()
    root = make_root("GamepadLight")
    back = material("Backplate", (1, 1, 1), 0.7, image=gamepad_face_image())
    rim = material("Emitter", (0.55, 0.52, 1.0), 0.4, grain=0.0, emission=(0.55, 0.52, 1.0))
    outer = gamepad_outline()
    inner = offset_polygon(outer, 0.2)
    plate = new_object("Backplate", stand_up(prism(outer, 0.0, 0.16)), back, root)
    planar_uv(plate, 0, 2)
    new_object("Emitter", stand_up(ring(outer, inner, 0.0, 0.28)), rim, root)
    dc.export("gamepad_light")


# ---------------- 五角星装饰 A13 ----------------
# 外径 0.8（直径 1.6）；正面收成低多边形鼓面。后墙一颗，猫砂盆正面两颗缩小复用。

def build_wall_star():
    reset()
    root = make_root("WallStar")
    orange = material("Star_Orange", (1.0, 0.62, 0.22), 0.45, grain=0.04)
    new_object("Star", stand_up(domed_prism(star_points(0.8, 0.38), 0.0, 0.14, 0.3)), orange, root)
    dc.export("wall_star")


build_desk()
build_crt()
build_stool()
build_gamepad_light()
build_wall_star()
print("REPORT", dc.REPORT)
