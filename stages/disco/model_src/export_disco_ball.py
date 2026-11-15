# 把 Kisa 给的迪斯科球（animated-disco-ball-low-poly.zip 里的 .blend）导出成 GLB。
# 用法：blender -b <那个.blend> --python export_disco_ball.py -- <输出.glb>
# 原镜面材质在没有环境反射的房间里会发黑（编辑器里尤其明显），这里直接把镜面改成
# 带一点自发光的淡紫镜面，这样编辑器预览和游戏里都不黑。不带原文件的动画，旋转由游戏代码控制。
import bpy, sys
out = sys.argv[sys.argv.index("--") + 1]
TINT = (0.85, 0.72, 0.98, 1.0)
m = bpy.data.materials.get("Specchio")
if m and m.use_nodes:
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        for link in list(bsdf.inputs["Base Color"].links):
            m.node_tree.links.remove(link)
        bsdf.inputs["Base Color"].default_value = TINT
        bsdf.inputs["Metallic"].default_value = 0.6
        bsdf.inputs["Roughness"].default_value = 0.3
        bsdf.inputs["Emission Color"].default_value = TINT
        bsdf.inputs["Emission Strength"].default_value = 0.35
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type == "MESH":
        o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=False, export_apply=True)
