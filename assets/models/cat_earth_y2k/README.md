# Cat Earth Y2K FBX

Exported from the approved rounded blue/purple Y2K Blender scene. Source .blend was not modified.

The FBX contains the original cat skeleton/skin, Earth, five rounded stars, two glints, scene camera, and a galaxy background plane. All active motion is baked at24fps into one4second scene take, normalized toFBXframes0..96 fromsourceframes1..97. Contacts are at29/24s and77/24s. Windup/strike/recovery and reverse Earth impulse spin are unchanged.

FBX does not support the source procedural galaxy or gradient shaders. The galaxy and tiny far stars are baked into galaxy_backdrop.png; rounded stars have explicit UVs and baked blue/purple gradient maps. Use unshaded material on GalaxyBackdrop. Camera, node names and material settings are documented in scene_metadata.json.

Earth texture: NASA/Goddard Space Flight Center, Reto Stöckli, enhancements by Robert Simmon. https://science.nasa.gov/earth/earth-observatory/the-blue-marble-true-color-global-imagery-at-1km-resolution/
