# 把 all.fbx 里的行星拆成单独的 GLB：每颗以星球本体中心为原点、本体半径缩成 1，贴图打包进 GLB。
# 用法（Blender 后台）：
#   blender -b --factory-startup --python build_planets.py -- <all.fbx> <贴图文件夹> <输出文件夹>
import bpy, sys, os
from mathutils import Vector, Matrix

fbx_path, tex_dir, out_dir = sys.argv[sys.argv.index("--") + 1:][:3]

# 输出文件名 -> (本体网格, [附带网格，如环])
GROUPS = {
	"planet_red": ("Planeta.011", ["Anillas"]),
	"planet_green": ("Planeta.001", []),
	"planet_jupiter": ("Sphere", []),
	"planet_saturn": ("Sphere.002", ["Sphere.001"]),
	"planet_earth": ("Sphere.003", []),
	"planet_twilight": ("Twilight- Fictional Planet.001", []),
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx_path)

# 贴图按文件名（不看扩展名）在贴图文件夹里重新找。贴图要先缩好（2048² PNG 缩到 1024 JPG），
# 这里不在 Blender 里缩：Blender 重新编码的 JPG Godot 读不了，原样读进来导出器才会原样打包
tex_files = {os.path.splitext(f)[0].lower(): f for f in os.listdir(tex_dir)}
for img in bpy.data.images:
	stem = os.path.splitext(os.path.basename(bpy.path.abspath(img.filepath)))[0].lower()
	if stem in tex_files:
		img.filepath = os.path.join(tex_dir, tex_files[stem])
		img.reload()
		print(f"TEX {tex_files[stem]} {img.size[0]}x{img.size[1]}")
	else:
		print("MISSING TEXTURE", img.name, stem)

# 带透明贴图的材质（环）用半透明混合
for mat in bpy.data.materials:
	if not mat.use_nodes:
		continue
	bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
	if bsdf and bsdf.inputs['Alpha'].is_linked:
		if hasattr(mat, "surface_render_method"):
			mat.surface_render_method = 'BLENDED'
		mat.blend_method = 'BLEND'
		mat.use_backface_culling = False

# 先把变换全部应用到网格上
for o in bpy.data.objects:
	o.select_set(o.type == 'MESH')
bpy.context.view_layer.objects.active = next(o for o in bpy.data.objects if o.type == 'MESH')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def world_bbox(o):
	pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


os.makedirs(out_dir, exist_ok=True)
for out_name, (body_name, extra) in GROUPS.items():
	body = bpy.data.objects[body_name]
	lo, hi = world_bbox(body)
	center = (lo + hi) * 0.5
	radius = max(hi - lo) * 0.5
	objs = [body] + [bpy.data.objects[n] for n in extra]
	for o in objs:
		o.data.transform(Matrix.Scale(1.0 / radius, 4) @ Matrix.Translation(-center))
		o.data.update()
	bpy.ops.object.select_all(action='DESELECT')
	for o in objs:
		o.select_set(True)
	path = os.path.join(out_dir, out_name + ".glb")
	bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
			export_apply=True, export_yup=True, export_animations=False)
	tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
	print(f"EXPORTED {out_name} tris={tris} radius_src={radius:.3f}")
