# 迪斯科房间 P0 模型：猫砂盆、房间三面、星星吊灯。
# 用法（在项目根目录）：
#   blender -b --factory-startup --python _sandbox/spin_cat/model_src/build_p0.py -- _sandbox/spin_cat/model
# 输出 litter_box.glb、room_shell.glb、star_lamp.glb。
# 尺寸单位和 Godot 一致：猫高约 3.7、长约 4.7；猫脚在 y = 0，房间地板顶面在 y = -0.9。
# Blender 是 Z 朝上、-Y 朝前；导出 glTF 后变成 Godot 的 Y 朝上、+Z 朝前（朝镜头那边）。
# 风格：Low Poly 形体 + 低分辨率带颗粒的贴图（脚本里用随机噪点生成，打包进 GLB）。

import bpy, bmesh, math, os, random, sys

OUT = sys.argv[sys.argv.index("--") + 1]
os.makedirs(OUT, exist_ok=True)
random.seed(7)


# ---------------- 工具 ----------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def noise_image(name, base, amount=0.06, size=32, tiles=None, tile_colors=None):
    """低分辨率颗粒贴图。tiles = 每边几块砖（做地砖用）"""
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = []
    for y in range(size):
        for x in range(size):
            c = base
            if tiles:
                cell = size // tiles
                c = tile_colors[((x // cell) + (y // cell)) % 2]
                if x % cell == 0 or y % cell == 0:  # 砖缝
                    c = tuple(v * 0.88 for v in c)
            n = (random.random() - 0.5) * 2 * amount
            px += [min(max(c[0] + n, 0), 1), min(max(c[1] + n, 0), 1), min(max(c[2] + n, 0), 1), 1.0]
    img.pixels = px
    img.pack()
    return img


def material(name, color, rough=0.6, metal=0.0, alpha=1.0, grain=0.05, emission=None, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if image is None and grain > 0:
        image = noise_image(name + "_tex", color, grain)
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


def new_object(name, bm, mat, parent=None):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    if parent:
        obj.parent = parent
    # 简单的盒状 UV（贴图只是颗粒，不需要精确）
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=2.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    for p in mesh.polygons:
        p.use_smooth = False
    return obj


def chamfer_rect(w, d, c):
    """宽 w（x）深 d（y）、四角切掉 c 的八边形轮廓"""
    x, y = w / 2, d / 2
    return [(-x + c, -y), (x - c, -y), (x, -y + c), (x, y - c),
            (x - c, y), (-x + c, y), (-x, y - c), (-x, -y + c)]


def prism(points, z0, z1, bm=None):
    """把 2D 轮廓（逆时针）挤出成柱体"""
    bm = bm or bmesh.new()
    bot = [bm.verts.new((p[0], p[1], z0)) for p in points]
    top = [bm.verts.new((p[0], p[1], z1)) for p in points]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    return bm


def ring(outer, inner, z0, z1, bm=None):
    """两条同样点数的轮廓之间的空心环（围壁、灯壳用）"""
    bm = bm or bmesh.new()
    n = len(outer)
    ob = [bm.verts.new((p[0], p[1], z0)) for p in outer]
    ot = [bm.verts.new((p[0], p[1], z1)) for p in outer]
    ib = [bm.verts.new((p[0], p[1], z0)) for p in inner]
    it = [bm.verts.new((p[0], p[1], z1)) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([ob[i], ob[j], ot[j], ot[i]])  # 外侧
        bm.faces.new([ib[j], ib[i], it[i], it[j]])  # 内侧
        bm.faces.new([ot[i], ot[j], it[j], it[i]])  # 顶
        bm.faces.new([ob[j], ob[i], ib[i], ib[j]])  # 底
    return bm


def box(cx, cy, cz, sx, sy, sz, bm=None):
    x, y = sx / 2, sy / 2
    pts = [(cx - x, cy - y), (cx + x, cy - y), (cx + x, cy + y), (cx - x, cy + y)]
    return prism(pts, cz - sz / 2, cz + sz / 2, bm)


def star_points(outer, inner, cx=0.0, cy=0.0):
    pts = []
    for i in range(10):
        r = outer if i % 2 == 0 else inner
        a = math.pi / 2 + i * math.tau / 10
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def boolean_cut(obj, cutter):
    mod = obj.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_animations=False, export_image_format="AUTO")
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("EXPORTED", path, "tris", tris)


# ---------------- 猫砂盆 A02 ----------------
# Godot 坐标：中心在原点，猫砂面顶 y = 0（猫脚踩在上面），底脚贴地 y = -0.9；前面（+Z，朝镜头）有低入口。

def build_litter_box():
    reset()
    root = bpy.data.objects.new("LitterBox", None)
    bpy.context.collection.objects.link(root)

    cream = material("Base_Cream", (0.96, 0.88, 0.80), 0.55)
    ice = material("Wall_IceBlue", (0.45, 0.80, 0.86), 0.35, alpha=0.72, grain=0.03)
    purple = material("Handle_Purple", (0.58, 0.32, 0.78), 0.3, alpha=0.9, grain=0.02)
    lime = material("Clip_Lime", (0.72, 0.90, 0.25), 0.35, grain=0.02)
    yellow = material("Star_Yellow", (1.0, 0.80, 0.15), 0.4, grain=0.02)
    blue = material("Groove_Blue", (0.20, 0.55, 0.75), 0.4, grain=0.02)
    sand = material("Litter_Sand", (0.86, 0.72, 0.50), 0.95, image=noise_image("sand", (0.84, 0.70, 0.48), 0.16, 32))

    W, D = 7.6, 6.2  # 外框 x、y（Blender）
    # 底座：奶白，带四个小脚
    bm = prism(chamfer_rect(W, D, 0.7), -0.75, -0.15)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(sx * (W / 2 - 0.9), sy * (D / 2 - 0.8), -0.825, 0.9, 0.7, 0.15, bm)
    new_object("Base", bm, cream, root)

    # 围壁：冰蓝半透明，前面挖一个低入口
    outer = chamfer_rect(W - 0.2, D - 0.2, 0.65)
    inner = chamfer_rect(W - 0.75, D - 0.75, 0.45)
    walls = new_object("Wall", ring(outer, inner, -0.15, 0.95), ice, root)
    cutter = new_object("Cutter", box(0, -D / 2, 0.75, 3.4, 1.5, 1.0), cream)
    boolean_cut(walls, cutter)
    # 包边：围壁顶上一圈奶白，入口处同样挖掉，再在入口底边补一条
    rim = new_object("Rim", ring(chamfer_rect(W - 0.1, D - 0.1, 0.68), inner, 0.95, 1.12), cream, root)
    cutter2 = new_object("Cutter2", box(0, -D / 2, 0.85, 3.4, 1.5, 1.2), cream)
    boolean_cut(rim, cutter2)
    new_object("EntranceRim", box(0, -(D / 2 - 0.28), 0.32, 3.5, 0.6, 0.14), cream, root)
    for c in (cutter, cutter2):
        bpy.data.objects.remove(c)

    # 猫砂面：顶面 y = 0
    new_object("Litter", box(0, 0, -0.2, W - 0.8, D - 0.8, 0.4), sand, root)

    # 两侧紫色提手（椭圆环，低段数）和青柠卡扣
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(major_segments=10, minor_segments=4, major_radius=0.55, minor_radius=0.13,
                                         location=(sx * (W / 2 - 0.02), 0.6, 0.55), rotation=(0, math.pi / 2, 0))
        h = bpy.context.active_object
        h.name = "Handle"
        h.scale = (1.0, 1.6, 1.0)
        h.data.materials.append(purple)
        h.parent = root
        new_object("Clip", box(sx * (W / 2 - 0.02), -0.9, 0.0, 0.25, 0.55, 0.5), lime, root)

    # 正面：两颗黄星星 + 中间蓝色凹槽（贴在底座正面）
    y = -D / 2 - 0.02
    for sx in (-1, 1):
        bm = bmesh.new()
        pts = star_points(0.32, 0.14)
        verts_f = [bm.verts.new((sx * 2.1 + p[0], y, -0.45 + p[1])) for p in pts]
        verts_b = [bm.verts.new((sx * 2.1 + p[0], y + 0.1, -0.45 + p[1])) for p in pts]
        bm.faces.new(verts_f)
        bm.faces.new(list(reversed(verts_b)))
        for i in range(10):
            j = (i + 1) % 10
            bm.faces.new([verts_f[j], verts_f[i], verts_b[i], verts_b[j]])
        new_object("Star", bm, yellow, root)
    new_object("Groove", box(0, y + 0.03, -0.45, 2.0, 0.08, 0.32), blue, root)
    export("litter_box")


# ---------------- 房间 A01：只有地板、后墙、左墙 ----------------
# Godot 坐标：地板 16 x 16、顶面 y = -0.9；后墙在 z = -8，左墙在 x = -8，墙高 9。

def build_room():
    reset()
    root = bpy.data.objects.new("RoomShell", None)
    bpy.context.collection.objects.link(root)
    S = 16.0
    tiles = noise_image("floor_tiles", (0.95, 0.62, 0.72), 0.04, 64, tiles=8,
                        tile_colors=[(0.96, 0.62, 0.72), (0.99, 0.90, 0.86)])
    floor_mat = material("Floor_Tiles", (1, 1, 1), 0.5, image=tiles)
    back_mat = material("Wall_Back_Coral", (0.93, 0.40, 0.46), 0.85, grain=0.04)
    left_mat = material("Wall_Left_Lilac", (0.74, 0.52, 0.86), 0.85, grain=0.04)
    trim_mat = material("Skirting", (0.99, 0.90, 0.86), 0.6, grain=0.02)

    floor = new_object("Floor", box(0, 0, -1.1, S, S, 0.4), floor_mat, root)
    # 地板 UV：整块铺一张 8x8 砖的贴图
    uv = floor.data.uv_layers.active.data
    for poly in floor.data.polygons:
        for li in poly.loop_indices:
            v = floor.data.vertices[floor.data.loops[li].vertex_index].co
            uv[li].uv = ((v.x + S / 2) / S, (v.y + S / 2) / S)
    # Blender +Y = Godot -Z（后面），-X = Godot 左
    new_object("WallBack", box(-0.15, S / 2 + 0.15, 3.6, S + 0.3, 0.3, 9.0), back_mat, root)
    new_object("WallLeft", box(-S / 2 - 0.15, 0, 3.6, 0.3, S, 9.0), left_mat, root)
    new_object("SkirtingBack", box(0, S / 2 - 0.05, -0.65, S, 0.12, 0.5), trim_mat, root)
    new_object("SkirtingLeft", box(-S / 2 + 0.05, 0, -0.65, 0.12, S, 0.5), trim_mat, root)
    export("room_shell")


# ---------------- 星星吊灯 A08 ----------------
# 原点在星星中心；灯罩材质名叫 Emitter，游戏里每盏换颜色、按节拍发光；吊线往上 12。

def build_star_lamp():
    reset()
    root = bpy.data.objects.new("StarLamp", None)
    bpy.context.collection.objects.link(root)
    housing = material("Housing", (0.86, 0.56, 0.80), 0.5, grain=0.03)
    emitter = material("Emitter", (1.0, 0.85, 0.3), 0.4, grain=0.0, emission=(1.0, 0.85, 0.3))
    cable = material("Cable", (0.25, 0.12, 0.30), 0.7, grain=0.0)

    # 灯壳：星形外框环（正面朝 -Y），灯罩：里面一颗略厚的星，两面都露出来
    outer = star_points(0.85, 0.40)
    inner = star_points(0.68, 0.30)
    bm = bmesh.new()
    n = 10
    of = [bm.verts.new((p[0], -0.15, p[1])) for p in outer]
    ob = [bm.verts.new((p[0], 0.15, p[1])) for p in outer]
    inf = [bm.verts.new((p[0], -0.15, p[1])) for p in inner]
    inb = [bm.verts.new((p[0], 0.15, p[1])) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([of[j], of[i], ob[i], ob[j]])  # 外侧
        bm.faces.new([inf[i], inf[j], inb[j], inb[i]])  # 内侧
        bm.faces.new([of[i], of[j], inf[j], inf[i]])  # 正面边框
        bm.faces.new([ob[j], ob[i], inb[i], inb[j]])  # 背面边框
    new_object("Housing", bm, housing, root)

    bm = bmesh.new()
    ef = [bm.verts.new((p[0], -0.1, p[1])) for p in inner]
    eb = [bm.verts.new((p[0], 0.1, p[1])) for p in inner]
    bm.faces.new(ef)
    bm.faces.new(list(reversed(eb)))
    new_object("Emitter", bm, emitter, root)

    new_object("Cap", box(0, 0, 0.95, 0.22, 0.22, 0.2), housing, root)
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.04, depth=12.0, location=(0, 0, 1.05 + 6.0))
    c = bpy.context.active_object
    c.name = "Cable"
    c.data.materials.append(cable)
    c.parent = root
    export("star_lamp")


build_litter_box()
build_room()
build_star_lamp()
