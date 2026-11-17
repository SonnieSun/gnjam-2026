# 迪斯科灯球的低面数版本（2026-11-15）：对着原来的 disco_ball.glb 重建，
# 球：32 段 x 16 圈的 UV 球，每一面内缩出一片镜子（Specchio）+ 一圈黑色缝（Dettagli），
#     不再用单独的一层黑色网格；镜面效果仍由游戏里的 disco_ball_mirror.gdshader 按每片的平面法线算。
# 吊链换成一根普通的绳子（Rope，不是金属，游戏里不会被换成镜面材质）。
# 大小和位置跟原模型一样（球半径 4.2，球心 y=6.415，绳子顶 y=19.8），disco_room.tscn 里的缩放和偏移不用改。
# 用法：blender -b --python build_disco_ball_lowpoly.py -- <输出.glb> [<输出.blend>]
#   （或者 pip install bpy 之后 python build_disco_ball_lowpoly.py -- ...）
import bpy, bmesh, sys
args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]

RADIUS = 4.2
CENTER_Y = 6.415
SEGMENTS = 32
RINGS = 16
GROUT = 0.03          # 缝的宽度（相对每片的大小，越大缝越粗）
ROPE_RADIUS = 0.16
ROPE_TOP = 19.8
ROPE_SIDES = 8

bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic, roughness, emission=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    if emission:
        b.inputs["Emission Color"].default_value = emission
        b.inputs["Emission Strength"].default_value = 0.35
    return m


# 和原模型同名同参数：游戏按 metallic >= 0.5 找镜面那一份，换成 disco_ball_mirror 材质
mirror = material("Specchio", (0.85, 0.72, 0.98, 1.0), 0.6, 0.3, (0.85, 0.72, 0.98, 1.0))
grout = material("Dettagli", (0.0, 0.0, 0.0, 1.0), 0.0, 0.5)
rope_mat = material("Rope", (0.12, 0.1, 0.11, 1.0), 0.0, 0.9)

# ---- 球：每一面内缩出一片镜子，内缩出来的一圈当缝（按每片大小的比例，极点附近的小片缝也细）----
me = bpy.data.meshes.new("Sphere")
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=SEGMENTS, v_segments=RINGS, radius=RADIUS)
tiles = list(bm.faces)
res = bmesh.ops.inset_individual(bm, faces=tiles, thickness=GROUT, use_even_offset=True, use_relative_offset=True)
tile_set = set(tiles)
for f in bm.faces:
    f.material_index = 0 if f in tile_set else 1
    f.smooth = False
bm.to_mesh(me)
bm.free()
me.materials.append(mirror)
me.materials.append(grout)
ball = bpy.data.objects.new("Sphere", me)
ball.location = (0.0, 0.0, CENTER_Y)  # Blender 是 Z 朝上，导出 glTF 时变成 Y 朝上
bpy.context.scene.collection.objects.link(ball)

# ---- 绳子 ----
rme = bpy.data.meshes.new("Rope")
bm = bmesh.new()
bottom = CENTER_Y + RADIUS - 0.15  # 稍微插进球里一点，接缝看不见
length = ROPE_TOP - bottom
bmesh.ops.create_cone(bm, cap_ends=True, segments=ROPE_SIDES, radius1=ROPE_RADIUS, radius2=ROPE_RADIUS, depth=length)
for f in bm.faces:
    f.smooth = True
bm.to_mesh(rme)
bm.free()
rme.materials.append(rope_mat)
rope = bpy.data.objects.new("Rope", rme)
rope.location = (0.0, 0.0, bottom + length / 2.0)
bpy.context.scene.collection.objects.link(rope)

for o in (ball, rope):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
        export_animations=False, export_apply=True, export_image_format="AUTO")
if len(args) > 1:
    bpy.ops.wm.save_as_mainfile(filepath=args[1])
for o in (ball, rope):
    print(o.name, len(o.data.polygons), "faces", sum(len(p.vertices) - 2 for p in o.data.polygons), "tris")
