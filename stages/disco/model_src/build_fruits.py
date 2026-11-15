# 迪斯科关卡路上撞的水果（占位用，超低模）：苹果、橙子、香蕉、西瓜。
# 用法（在项目根目录）：
#   blender -b --factory-startup --python stages/disco/model_src/build_fruits.py -- stages/disco/model
# 风格和房间模型一样：Low Poly 形体 + 脚本生成的低分辨率颗粒贴图。原点在水果中心（被撞飞时绕中心转），半径约 1.2。

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math
import disco_common as dc
from disco_common import reset, make_root, material, pixel_image, new_object, box, tube

dc.OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(dc.OUT, exist_ok=True)


def sphere(radius, u=6, v=4, squash=(1.0, 1.0, 1.0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    for vert in bm.verts:
        vert.co.x *= squash[0]
        vert.co.y *= squash[1]
        vert.co.z *= squash[2]
    return bm


def build_apple():
    reset()
    root = make_root("Apple")
    red = material("Apple_Red", (0.90, 0.16, 0.18), 0.45, grain=0.07)
    brown = material("Stem_Brown", (0.42, 0.26, 0.14), 0.8, grain=0.05)
    green = material("Leaf_Green", (0.35, 0.72, 0.25), 0.6, grain=0.05)
    new_object("Body", sphere(1.2, 6, 4, (1.0, 1.0, 0.9)), red, root)
    new_object("Stem", box(0.0, 0.0, 1.2, 0.14, 0.14, 0.5), brown, root)
    new_object("Leaf", box(0.35, 0.0, 1.3, 0.6, 0.3, 0.06), green, root)
    dc.export("fruit_apple")


def build_orange():
    reset()
    root = make_root("Orange")
    orange = material("Orange_Peel", (1.0, 0.58, 0.10), 0.7, grain=0.09)
    green = material("Orange_Top", (0.30, 0.62, 0.22), 0.6, grain=0.04)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.2)
    new_object("Body", bm, orange, root)
    new_object("Top", box(0.0, 0.0, 1.12, 0.3, 0.3, 0.12), green, root)
    dc.export("fruit_orange")


def build_banana():
    reset()
    root = make_root("Banana")
    yellow = material("Banana_Yellow", (1.0, 0.86, 0.22), 0.55, grain=0.06)
    brown = material("Banana_Tip", (0.38, 0.26, 0.12), 0.8, grain=0.04)
    # 一道弯：5 个点的弧线，四棱柱扫出来
    path = []
    for i in range(5):
        a = math.radians(-60 + i * 30)
        path.append((math.sin(a) * 1.5, 0.0, (1.0 - math.cos(a)) * 1.5 - 0.5))
    new_object("Body", tube(path, 0.42, 4), yellow, root)
    for p in (path[0], path[-1]):
        new_object("Tip", box(p[0], p[1], p[2], 0.3, 0.3, 0.3), brown, root)
    dc.export("fruit_banana")


def build_watermelon():
    reset()
    root = make_root("Watermelon")
    stripes = pixel_image("melon_stripes", 32, 8,
                          lambda x, y: (0.10, 0.36, 0.14) if (x // 4) % 2 == 0 else (0.36, 0.68, 0.26), 0.06)
    green = material("Melon_Rind", (1, 1, 1), 0.6, image=stripes)
    body = new_object("Body", sphere(1.25, 6, 4, (1.35, 1.0, 1.0)), green, root)
    # 条纹绕着长轴走：UV 的 u 用绕 x 轴的角度
    uv = body.data.uv_layers.active.data
    for poly in body.data.polygons:
        for li in poly.loop_indices:
            v = body.data.vertices[body.data.loops[li].vertex_index].co
            uv[li].uv = (math.atan2(v.z, v.y) / math.tau + 0.5, v.x / 3.4 + 0.5)
    dc.export("fruit_watermelon")


build_apple()
build_orange()
build_banana()
build_watermelon()
