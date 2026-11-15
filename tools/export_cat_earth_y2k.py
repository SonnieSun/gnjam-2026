"""Export the approved Blender scene as a portable FBX for the rhythm level.

Run with Blender 5.3 --background --factory-startup SOURCE.blend --python this_file.
The source .blend is never saved or modified. Procedural shader appearance is
baked into images, while the original skin and native scene motion stay in FBX.
"""
import bpy
import hashlib
import json
import math
import os
import shutil
import struct
import zlib
import numpy as np
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, 'assets', 'models', 'cat_earth_y2k')
CACHE = os.path.join(OUT, '.export_cache')
os.makedirs(CACHE, exist_ok=True)
with open(os.path.join(CACHE, '.gdignore'), 'w') as f:
    f.write('')
SOURCE = bpy.data.filepath
scene = bpy.context.scene
source_hash = hashlib.sha256(open(SOURCE, 'rb').read()).hexdigest()
scene.frame_set(1)

def write_png(path, pixels):
    """Write a portable sRGB RGB PNG from linear shader values."""
    value = np.clip(pixels, 0, 1)
    srgb = np.where(value <= .0031308, value * 12.92, 1.055 * np.power(value, 1/2.4) - .055)
    data = np.uint8(np.clip(srgb * 255 + .5, 0, 255))
    # Blender UV v=0 is the lower image edge; PNG starts at the top.
    rows = data[::-1]
    height, width, _ = rows.shape
    raw = b''.join(b'\x00' + row.tobytes() for row in rows)
    def chunk(kind, content):
        return struct.pack('>I', len(content)) + kind + content + struct.pack('>I', zlib.crc32(kind+content) & 0xffffffff)
    image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',width,height,8,2,0,0,0))
    image += chunk(b'sRGB',b'\x00') + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b'')
    temporary = path + '.writing'
    with open(temporary,'wb') as f: f.write(image)
    os.replace(temporary,path)

visible = [o for o in scene.objects if not o.hide_render and o.visible_get()]
background = next(o for o in visible if o.name.startswith('Galaxy •'))
far_stars = next(o for o in visible if o.name.startswith('Starfield •'))
camera = scene.camera
camera_metadata = {'blender_position':list(camera.location),
                   'blender_rotation_euler':list(camera.rotation_euler),
                   'godot_position':[camera.location.x,camera.location.z,-camera.location.y],
                   'godot_target':[.36,1.95,-.22], 'orthographic_size':camera.data.ortho_scale}
original_camera_scale = camera.data.ortho_scale
original_resolution = (scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage)
hidden = {o:o.hide_render for o in scene.objects}
for o in scene.objects:
    if o.type == 'MESH': o.hide_render = o not in (background,far_stars)
camera.data.ortho_scale *= 1.3  # Plate matches the existing overscan background quad.
scene.render.resolution_x=2048
scene.render.resolution_y=2048
scene.render.resolution_percentage=100
scene.render.image_settings.media_type='IMAGE'
scene.render.image_settings.file_format='PNG'
scene.render.image_settings.color_mode='RGB'
scene.render.filepath=os.path.join(CACHE,'galaxy_backdrop.png')
scene.render.film_transparent=False
scene.render.engine='CYCLES'
scene.cycles.samples=16
scene.cycles.use_denoising=False  # Only camera-emission surfaces; do not smear tiny stars.
try:
    preferences=bpy.context.preferences.addons['cycles'].preferences
    preferences.compute_device_type='OPTIX'
    preferences.get_devices()
    for device in preferences.devices: device.use=device.type=='OPTIX'
    scene.cycles.device='GPU'
except Exception:
    scene.cycles.device='CPU'
bpy.ops.render.render(write_still=True)
os.replace(scene.render.filepath,os.path.join(OUT,'galaxy_backdrop.png'))
for o,value in hidden.items():o.hide_render=value
camera.data.ortho_scale=original_camera_scale
scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage=original_resolution

def image_from_packed(image, filename):
    path=os.path.join(OUT,filename)
    if image.packed_file:
        with open(path+'.writing','wb') as f:f.write(image.packed_file.data)
        os.replace(path+'.writing',path)
    else:
        shutil.copy2(bpy.path.abspath(image.filepath),path)
    replacement=bpy.data.images.load(path,check_existing=False)
    replacement.colorspace_settings.name='sRGB'
    return replacement

def portable_material(name, image=None, base=(1,1,1,1), metallic=0, roughness=.8, emission=0):
    material=bpy.data.materials.new(name)
    material.use_nodes=True
    material.diffuse_color=base
    p=material.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=base
    p.inputs['Metallic'].default_value=metallic
    p.inputs['Roughness'].default_value=roughness
    p.inputs['Emission Color'].default_value=base
    p.inputs['Emission Strength'].default_value=emission
    if image:
        texture=material.node_tree.nodes.new('ShaderNodeTexImage')
        texture.image=image
        texture.interpolation='Linear'
        material.node_tree.links.new(texture.outputs['Color'],p.inputs['Base Color'])
        if emission:material.node_tree.links.new(texture.outputs['Color'],p.inputs['Emission Color'])
    return material

cat=next(o for o in visible if o.type=='MESH' and o.name=='GEO-CATS.001')
rig=cat.parent
earth=next(o for o in visible if o.name=='Earth_Surface')
earth_spin=earth.parent
stars=sorted([o for o in visible if o.name.startswith('Y2K_Star_')],key=lambda o:o.name)
glints=sorted([o for o in visible if o.name.startswith('Y2K_Glint_')],key=lambda o:o.name)

cat_image=next(n.image for n in cat.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE')
cat_image=image_from_packed(cat_image,'cat_basecolor_512.png')
cat.data.materials.clear()
cat.data.materials.append(portable_material('CatMaterial',cat_image,roughness=.9))
earth_image=next(n.image for n in earth.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE')
earth_image=image_from_packed(earth_image,'earth_day_clouds.jpg')
earth.data.materials.clear()
earth.data.materials.append(portable_material('EarthMaterial',earth_image,roughness=.78))

star_materials={}
for index,obj in enumerate(stars):
    old_material=obj.data.materials[0]
    key='blue_purple' if index in (0,2,4) else 'purple_blue'
    if key not in star_materials:
        ramp=next(n.color_ramp for n in old_material.node_tree.nodes if n.type=='VALTORGB')
        stops=sorted([(e.position,np.array(e.color[:3],dtype=np.float32)) for e in ramp.elements],key=lambda row:row[0])
        grid=np.linspace(0,1,256,dtype=np.float32)
        u,v=np.meshgrid(grid,grid)
        factor=.56*u+.44*v
        pixels=np.zeros((256,256,3),dtype=np.float32)
        for (a,ca),(b,cb) in zip(stops,stops[1:]):
            mask=(factor>=a)&(factor<=b)
            t=np.clip((factor-a)/(b-a),0,1)
            t=t*t*(3-2*t)
            colors=ca[None,None,:]+(cb-ca)[None,None,:]*t[:,:,None]
            pixels[mask]=colors[mask]
        path=os.path.join(OUT,'star_'+key+'.png')
        write_png(path,pixels)
        image=bpy.data.images.load(path,check_existing=False)
        material=portable_material('Star_'+key,image,metallic=.3,roughness=.28,emission=.045)
        material.node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.38
        star_materials[key]=material
    mesh=obj.data
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='BakedGradientUV')
    minimum=Vector((min(v.co.x for v in mesh.vertices),min(v.co.y for v in mesh.vertices)))
    maximum=Vector((max(v.co.x for v in mesh.vertices),max(v.co.y for v in mesh.vertices)))
    span=maximum-minimum
    for loop in mesh.loops:
        point=mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv=((point.x-minimum.x)/span.x,(point.y-minimum.y)/span.y)
    mesh.materials.clear()
    mesh.materials.append(star_materials[key])

for index,obj in enumerate(glints):
    old=obj.data.materials[0].node_tree.nodes.get('Principled BSDF')
    color=tuple(old.inputs['Base Color'].default_value)
    obj.data.materials.clear()
    obj.data.materials.append(portable_material('GlintMaterial'+str(index+1),base=color,metallic=.35,roughness=.32,emission=.4))

plate_image=bpy.data.images.load(os.path.join(OUT,'galaxy_backdrop.png'),check_existing=False)
background.data.materials.clear()
background.data.materials.append(portable_material('GalaxyBackdrop_Unshaded',plate_image,roughness=1,emission=1))
uv=background.data.uv_layers.active
for loop in uv.data:
    loop.uv=((loop.uv.x+.15)/1.3,(loop.uv.y+.15)/1.3)

mapping={rig:'CatRig',cat:'CatMesh',earth_spin:'EarthSpin',earth:'EarthMesh',background:'GalaxyBackdrop',camera:'SceneCamera'}
mapping.update({o:'Star%02d'%(i+1) for i,o in enumerate(stars)})
mapping.update({o:'Glint%02d'%(i+1) for i,o in enumerate(glints)})
for obj,name in mapping.items():obj.name=name
far_stars.hide_render=True

scene.frame_start=0
scene.frame_end=96  # Normalize the original1..97 keys to exact0..4second FBX time.
scene.render.fps=24
scene.name='CatEarthLoop'
selected=[rig,cat,earth_spin,earth,background,camera]+stars+glints
shifted_actions=set()
for obj in selected:
    for owner in (obj,obj.data if obj.data else None):
        if owner is None or not owner.animation_data or not owner.animation_data.action:
            continue
        action=owner.animation_data.action
        if action in shifted_actions:continue
        shifted_actions.add(action)
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.co.x-=1
                            key.handle_left.x-=1
                            key.handle_right.x-=1
                        curve.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in selected:
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active=rig
scene.frame_set(0)
export_file=os.path.join(CACHE,'cat_earth_y2k.fbx')
bpy.ops.export_scene.fbx(filepath=export_file,use_selection=True,
                         object_types={'EMPTY','MESH','ARMATURE','CAMERA'},
                         global_scale=1,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',
                         axis_forward='-Z',axis_up='Y',use_space_transform=True,bake_space_transform=False,
                         use_mesh_modifiers=True,mesh_smooth_type='OFF',add_leaf_bones=False,
                         use_armature_deform_only=False,bake_anim=True,bake_anim_use_all_actions=False,
                         bake_anim_use_nla_strips=False,bake_anim_force_startend_keying=True,
                         bake_anim_step=1,bake_anim_simplify_factor=0,path_mode='STRIP',embed_textures=False)
final_file=os.path.join(OUT,'cat_earth_y2k.fbx')
os.replace(export_file,final_file)

assert hashlib.sha256(open(SOURCE,'rb').read()).hexdigest()==source_hash
metadata={
    'source_blend':SOURCE,'source_sha256':source_hash,'source_modified':False,
    'fbx':'res://assets/models/cat_earth_y2k/cat_earth_y2k.fbx',
    'animation':{'expected_take':'CatEarthLoop','fps':24,'source_frames':[1,97],'fbx_frames':[0,96],'duration_seconds':4.0,
                 'loop_frames':[1,96],'contacts_frames':[30,78],
                 'contacts_seconds':[(30-1)/24,(78-1)/24],
                 'windup_hold_seconds':[[14/24,24/24],[62/24,72/24]],
                 'single_swat_seconds':2.0,'clock_offset_for_120bpm_hit_on_beats_2_6':5/24},
    'camera':camera_metadata,
    'nodes':{o.name:{'type':o.type,'parent':o.parent.name if o.parent else None} for o in selected},
    'materials':{
        'CatMesh':{'albedo':'cat_basecolor_512.png','roughness':.9},
        'EarthMesh':{'albedo':'earth_day_clouds.jpg','roughness':.78,'specular':.23},
        'GalaxyBackdrop':{'albedo':'galaxy_backdrop.png','shading':'unshaded','double_sided':True},
        'Star01_03_05':{'albedo':'star_blue_purple.png','metallic':.3,'roughness':.28,'coat':.38,'emission':.045},
        'Star02_04':{'albedo':'star_purple_blue.png','metallic':.3,'roughness':.28,'coat':.38,'emission':.045}},
    'export_notes':['Original cat skin and all native active actions baked together into one scene take.',
                    'The galaxy and460 tiny distant stars were baked into one2048px plate; original five puffy stars and two glints remain3D.',
                    'Set GalaxyBackdrop material unshaded in Godot; FBX cannot encode Blender camera-only shader.',
                    'FBX image filenames are stripped to portable adjacent filenames.']}
with open(os.path.join(OUT,'scene_metadata.json'),'w',encoding='utf-8') as f:json.dump(metadata,f,indent=2,ensure_ascii=False)
with open(os.path.join(OUT,'README.md'),'w',encoding='utf-8') as f:
    f.write('# Cat Earth Y2K FBX\n\nExported from the approved rounded blue/purple Y2K Blender scene. Source .blend was not modified.\n\n'
            'The FBX contains the original cat skeleton/skin, Earth, five rounded stars, two glints, scene camera, and a galaxy background plane. '
            'All active motion is baked at24fps into one4second scene take, normalized toFBXframes0..96 fromsourceframes1..97. '
            'Contacts are at29/24s and77/24s. Windup/strike/recovery and reverse Earth impulse spin are unchanged.\n\n'
            'FBX does not support the source procedural galaxy or gradient shaders. The galaxy and tiny far stars are baked into '
            'galaxy_backdrop.png; rounded stars have explicit UVs and baked blue/purple gradient maps. Use unshaded material on GalaxyBackdrop. '
            'Camera, node names and material settings are documented in scene_metadata.json.\n\n'
            'Earth texture: NASA/Goddard Space Flight Center, Reto Stöckli, enhancements by Robert Simmon. '
            'https://science.nasa.gov/earth/earth-observatory/the-blue-marble-true-color-global-imagery-at-1km-resolution/\n')
print('FBX_EXPORT_COMPLETE',final_file,os.path.getsize(final_file))
print('EXPORTED_NODES',json.dumps([o.name for o in selected]))
