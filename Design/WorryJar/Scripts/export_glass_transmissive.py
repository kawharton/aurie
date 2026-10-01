"""The APPROVED Stage-B transmissive glass, made compositable:
render the frozen jar with the approved transmissive glass_material over a
PURE BLACK world with the approved studio rig. Everything the glass does with
light (rims, speculars, window reflections, refractive base rings) lands on
black -> in-app a .screen blend lays it over the night and live fireflies.
Same ortho camera as the layered exports, so JarFrame stays valid."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
import export_worry_jar_assets as ex
import build_worry_jar as jar
import render_worry_jar_review as rig

OUT = os.path.join(os.path.dirname(HERE), "Review")
os.makedirs(OUT, exist_ok=True)
scene = ex.scene_setup(260)
scene.render.film_transparent = False
scene.cycles.max_bounces = 24
scene.cycles.transmission_bounces = 20
scene.cycles.transparent_max_bounces = 20
rig.setup_lights()
w = bpy.data.worlds.new("Black")
scene.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
glass = jar.build_glass()
glass.data.materials.append(jar.glass_material())
ex.jar_camera(scene)
ex.render(scene, os.path.join(OUT, "worry_jar_glass_add.png"), 1100, 1400)
print("TRANSMISSIVE ADD LAYER complete")
