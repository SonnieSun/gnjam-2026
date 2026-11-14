# 迪斯科房间建模脚本的公用工具（build_p1.py、build_p2.py 共用）。
# 做法和 build_p0.py 一样：Low Poly 形体 + 脚本生成的低分辨率颗粒贴图，打包进 GLB。
# 坐标：Blender Z 朝上、-Y 朝前；导出后是 Godot 的 Y 朝上、+Z 朝前。
# 墙饰和 CRT 这类「正面朝前」的东西先平放着建（x 右、y 上、z 朝前），再用 stand_up 立起来。

import bpy, bmesh, math, os, random

OUT = "."
random.seed(7)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


# ---------------- 贴图 ----------------

def clamp01(v):
    return min(max(v, 0.0), 1.0)


def pixel_image(name, w, h, color_at, amount=0.05):
    """color_at(x, y) 返回 (r, g, b)，y 从上往下数；每个像素再加一点颗粒"""
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = []
    for by in range(h):
        y = h - 1 - by  # Blender 图片从下往上存
        for x in range(w):
            c = color_at(x, y)
            n = (random.random() - 0.5) * 2 * amount
            px += [clamp01(c[0] + n), clamp01(c[1] + n), clamp01(c[2] + n), 1.0]
    img.pixels = px
    img.pack()
    return img


def noise_image(name, base, amount=0.06, size=32):
    return pixel_image(name, size, size, lambda x, y: base, amount)


def material(name, color, rough=0.6, metal=0.0, alpha=1.0, grain=0.05, emission=None, image=None,
             emission_image=False):
    """emission_image=True 时贴图同时接到自发光（CRT 屏幕用）"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if image is None and grain > 0:
        image = noise_image(name + "_tex", color, grain)
    tex = None
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
    if emission_image and tex is not None:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


# ---------------- 网格 ----------------

def stand_up(bm):
    """平放建的（z 朝前）立起来：(x, y, z) -> (x, -z, y)，正面变成 -Y（Godot +Z）"""
    for v in bm.verts:
        x, y, z = v.co
        v.co = (x, -z, y)
    return bm


def move(bm, dx, dy, dz):
    bmesh.ops.translate(bm, verts=bm.verts, vec=(dx, dy, dz))
    return bm


def new_object(name, bm, mat, parent=None):
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    if parent:
        obj.parent = parent
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


def planar_uv(obj, ax_u=0, ax_v=2, flip_v=False):
    """按两根轴做平面投影 UV（正面贴图用）：默认 Blender x -> u、z -> v"""
    me = obj.data
    vs = [v.co for v in me.vertices]
    u0, u1 = min(v[ax_u] for v in vs), max(v[ax_u] for v in vs)
    v0, v1 = min(v[ax_v] for v in vs), max(v[ax_v] for v in vs)
    uv = me.uv_layers.active.data
    for li, loop in enumerate(me.loops):
        c = me.vertices[loop.vertex_index].co
        u = (c[ax_u] - u0) / (u1 - u0)
        v = (c[ax_v] - v0) / (v1 - v0)
        uv[li].uv = (u, 1 - v if flip_v else v)


def prism(points, z0, z1, bm=None, cap_bottom=True):
    """2D 轮廓（逆时针）沿 z 挤出"""
    bm = bm or bmesh.new()
    bot = [bm.verts.new((p[0], p[1], z0)) for p in points]
    top = [bm.verts.new((p[0], p[1], z1)) for p in points]
    if cap_bottom:
        bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
    return bm


def domed_prism(points, z0, z1, z_peak, bm=None, cap_bottom=True):
    """挤出后正面不是平的，而是收到中心一个尖点（低多边形的鼓面）"""
    bm = bm or bmesh.new()
    bot = [bm.verts.new((p[0], p[1], z0)) for p in points]
    top = [bm.verts.new((p[0], p[1], z1)) for p in points]
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    peak = bm.verts.new((cx, cy, z_peak))
    if cap_bottom:
        bm.faces.new(list(reversed(bot)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([bot[i], bot[j], top[j], top[i]])
        bm.faces.new([top[i], top[j], peak])
    return bm


def loft(pts0, z0, pts1, z1, bm=None):
    """两条点数相同的轮廓之间连成台体（两头封口）"""
    bm = bm or bmesh.new()
    a = [bm.verts.new((p[0], p[1], z0)) for p in pts0]
    b = [bm.verts.new((p[0], p[1], z1)) for p in pts1]
    if z1 > z0:
        bm.faces.new(list(reversed(a)))
        bm.faces.new(b)
    else:
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
    n = len(pts0)
    for i in range(n):
        j = (i + 1) % n
        f = [a[i], a[j], b[j], b[i]]
        bm.faces.new(f if z1 > z0 else list(reversed(f)))
    return bm


def ring(outer, inner, z0, z1, bm=None):
    bm = bm or bmesh.new()
    n = len(outer)
    ob = [bm.verts.new((p[0], p[1], z0)) for p in outer]
    ot = [bm.verts.new((p[0], p[1], z1)) for p in outer]
    ib = [bm.verts.new((p[0], p[1], z0)) for p in inner]
    it = [bm.verts.new((p[0], p[1], z1)) for p in inner]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([ob[i], ob[j], ot[j], ot[i]])
        bm.faces.new([ib[j], ib[i], it[i], it[j]])
        bm.faces.new([ot[i], ot[j], it[j], it[i]])
        bm.faces.new([ob[j], ob[i], ib[i], ib[j]])
    return bm


def box(cx, cy, cz, sx, sy, sz, bm=None):
    x, y = sx / 2, sy / 2
    pts = [(cx - x, cy - y), (cx + x, cy - y), (cx + x, cy + y), (cx - x, cy + y)]
    return prism(pts, cz - sz / 2, cz + sz / 2, bm)


def chamfer_rect(w, d, c, cx=0.0, cy=0.0):
    x, y = w / 2, d / 2
    pts = [(-x + c, -y), (x - c, -y), (x, -y + c), (x, y - c),
           (x - c, y), (-x + c, y), (-x, y - c), (-x, -y + c)]
    return [(p[0] + cx, p[1] + cy) for p in pts]


def circle(r, n, cx=0.0, cy=0.0, phase=0.0):
    return [(cx + math.cos(phase + i * math.tau / n) * r, cy + math.sin(phase + i * math.tau / n) * r)
            for i in range(n)]


def star_points(outer, inner, cx=0.0, cy=0.0):
    pts = []
    for i in range(10):
        r = outer if i % 2 == 0 else inner
        a = math.pi / 2 + i * math.tau / 10
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def offset_polygon(points, d):
    """逆时针多边形往里缩 d（斜接）"""
    n = len(points)
    out = []
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]
        e1 = (p1[0] - p0[0], p1[1] - p0[1])
        e2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*e1), math.hypot(*e2)
        n1 = (-e1[1] / l1, e1[0] / l1)
        n2 = (-e2[1] / l2, e2[0] / l2)
        k = 1.0 + n1[0] * n2[0] + n1[1] * n2[1]
        out.append((p1[0] + d * (n1[0] + n2[0]) / k, p1[1] + d * (n1[1] + n2[1]) / k))
    return out


def tube(path, radius, sides=4, bm=None):
    """沿折线走的细管（电线用），两头平切封口"""
    bm = bm or bmesh.new()
    rings = []
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        t = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        tl = math.sqrt(sum(c * c for c in t))
        t = tuple(c / tl for c in t)
        # 线在 xz 平面里，第二根轴取 y
        side = (0.0, 1.0, 0.0)
        up = (t[1] * side[2] - t[2] * side[1], t[2] * side[0] - t[0] * side[2], t[0] * side[1] - t[1] * side[0])
        r = []
        for k in range(sides):
            ang = math.pi / sides + k * math.tau / sides
            c, s = math.cos(ang) * radius, math.sin(ang) * radius
            r.append(bm.verts.new((p[0] + side[0] * c + up[0] * s,
                                   p[1] + side[1] * c + up[1] * s,
                                   p[2] + side[2] * c + up[2] * s)))
        rings.append(r)
    for i in range(len(rings) - 1):
        for k in range(sides):
            m = (k + 1) % sides
            bm.faces.new([rings[i][k], rings[i][m], rings[i + 1][m], rings[i + 1][k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---------------- 导出 ----------------

REPORT = []


def tris_count():
    return sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
                              export_animations=False, export_image_format="AUTO")
    t = tris_count()
    REPORT.append((name, t))
    print("EXPORTED", path, "tris", t)
