#!/usr/bin/env python3
"""Bakes the spark meshes in meshes/e/impact/.

    <blender>/python/bin/python3.13 tools/make_sparks.py [outdir]

Needs numpy and Greatness7's `es3` NIF library, both of which ship inside the
Blender Morrowind plugin (io_scene_mw). Point ES3_LIB at another copy if yours
lives somewhere else. Everything written here is generated from the numbers in
SPARKS below - no mesh from another mod is reused.

Each file is a set of *streaks*: flat cross-shaped quads flying a ballistic arc
that is baked into NiKeyframeControllers, each one turned to face the direction
it is travelling. OpenMW draws NIF particles as camera-facing squares and
ignores NiParticleRotation entirely (nifloader.cpp: "RC_NiParticleRotation //
unused"), so a particle can not be aligned to its velocity - but a keyframed
node can, and the arc bends the streak as it falls. Two quads crossed along the
streak axis keep it visible from any angle, and the triangles are written twice
with both windings so backface culling can't hide one.

Every controller clamps at its last key (flags 8|4). With the default "cycle"
extrapolation a controller that ends before the effect does starts over, which
looked like a second burst appearing just before the effect was cleaned up.

Each family of sparks is baked several times over, with different counts and
seeds, and some of the variants carry a cluster of sparks thrown much harder
than the rest - they leave fast, travel several times as far and outlive the
burst. Variant 1 keeps the name Impact Effects plays, the rest sit in
meshes/MaxYari/combat juice/sparks/ and the mod picks between them at
random. The loose cluster files there are added on top of impacts whose effect
this mod does not replace outright.

The effect is spawned through the engine's VFX path, which hands every
controller in the file the effect's own clock and deletes the effect once the
longest controller ends, so the whole burst plays once and disappears.
"""

import math
import os
import random
import sys
from pathlib import Path

ES3_LIB = os.environ.get(
    "ES3_LIB", "/home/deck/.config/blender/5.1/scripts/addons/io_scene_mw/lib")
sys.path.insert(0, ES3_LIB)

import numpy as np  # noqa: E402
from es3 import nif  # noqa: E402

TEX = "textures\\MaxYari\\combat juice\\"
STREAK_TEX = TEX + "spark_streak.png"

# Alpha: blending on, SRC_ALPHA + ONE (additive), no alpha test.
ALPHA_ADDITIVE = 13
# Z buffer: test against the depth buffer, don't write to it.
ZBUFFER_TEST_ONLY = 1
# Controller flags: active (0x8) + clamp at the last key (0x4) so nothing loops.
CTRL_ACTIVE_CLAMP = 12

GRAVITY = 700.0  # units/s^2, pulling -Z, baked into the arcs.


# ---------------------------------------------------------------- per-file setup

FAMILIES = {
    # Weapon on metal: the loudest of the three.
    "metal": dict(
        replaces="metalSpark.nif",
        variants=4,
        seed=20260921,
        streaks=(5, 9),
        speed=(170.0, 430.0),
        life=(0.22, 0.40),
        length=(9.0, 22.0),
        width=(0.85, 1.5),
        cone=(0.0, 125.0),      # degrees away from +Z that streaks are thrown
        fast_chance=0.65,
        fast_count=(2, 4),
    ),
    # Parry / weapon on armour. Impact Effects also scales this one to 0.5.
    # N'Garde plays meshes/e/spark.nif for its weapon clashes, so a copy of
    # this burst goes there too and its clashes throw these sparks - provided
    # this mod loads after it.
    "parry": dict(
        replaces="parrySpark.nif",
        also=["meshes/e/spark.nif"],
        variants=4,
        seed=760921,
        streaks=(4, 7),
        speed=(150.0, 360.0),
        life=(0.20, 0.34),
        length=(8.0, 18.0),
        width=(0.8, 1.35),
        cone=(0.0, 125.0),
        fast_chance=0.5,
        fast_count=(2, 3),
    ),
    # Shield block: fewer, shorter, more of a scuff.
    "shield": dict(
        replaces="shieldBlock.nif",
        variants=3,
        seed=550821,
        streaks=(4, 6),
        speed=(120.0, 300.0),
        life=(0.18, 0.30),
        length=(6.0, 14.0),
        width=(0.75, 1.2),
        cone=(0.0, 110.0),
        fast_chance=0.4,
        fast_count=(1, 3),
    ),
}

# The hard-thrown sparks. Two to four times the speed of the rest and a longer
# life, so they leave the impact as long streaks and are still travelling when
# the burst around them has gone out.
FAST = dict(
    speed=(520.0, 980.0),
    life=(0.35, 0.60),
    length=(24.0, 52.0),
    width=(0.7, 1.15),
    cone=(0.0, 95.0),
)

# Loose clusters of those, spawned on top of impacts this mod does not take over.
CLUSTERS = dict(count=3, seed=31337, streaks=(3, 5))

# The texture carries the colour - white hot at the head, blue down the tail.
STREAK_EMISSIVE = (1.0, 1.0, 1.0)


def vec(*values):
    """es3 stores every vector field as a numpy array, so tuples get converted."""
    if len(values) == 1 and isinstance(values[0], (tuple, list)):
        values = values[0]
    return np.array(values, dtype=np.float32)


# ---------------------------------------------------------------------- helpers

def texturing_property(filename):
    source = nif.NiSourceTexture(
        filename=filename,
        pixel_layout=nif.NiSourceTexture.PixelLayout.PALETTIZED_4,
        use_mipmaps=nif.NiSourceTexture.UseMipMaps.YES,
        alpha_format=nif.NiSourceTexture.AlphaFormat.SMOOTH,
        is_static=1,
    )
    return nif.NiTexturingProperty(
        apply_mode=nif.NiTexturingProperty.ApplyMode.APPLY_MODULATE,
        base_texture=nif.NiTexturingPropertyMap(
            source=source,
            clamp_mode=nif.NiTexturingPropertyMap.ClampMode.CLAMP_S_CLAMP_T,
            filter_mode=nif.NiTexturingPropertyMap.FilterMode.FILTER_TRILERP,
        ),
    )


def quat_from_direction(direction):
    """Quaternion (w, x, y, z) rotating local +X onto `direction`."""
    x = np.asarray(direction, dtype=np.float64)
    x /= np.linalg.norm(x)
    up = np.array([0.0, 0.0, 1.0])
    if abs(np.dot(x, up)) > 0.999:
        up = np.array([0.0, 1.0, 0.0])
    y = np.cross(up, x)
    y /= np.linalg.norm(y)
    z = np.cross(x, y)
    m = np.column_stack((x, y, z))  # columns are the rotated basis vectors

    trace = m[0, 0] + m[1, 1] + m[2, 2]
    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        w, qx, qy, qz = 0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        w, qx, qy, qz = (m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        w, qx, qy, qz = (m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
        w, qx, qy, qz = (m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s
    q = np.array([w, qx, qy, qz])
    return q / np.linalg.norm(q)


def random_cone_direction(rng, cone):
    """Unit vector at a random angle from +Z, within `cone` degrees."""
    lo, hi = (math.radians(a) for a in cone)
    theta = math.acos(np.interp(rng.random(), [0, 1], [math.cos(lo), math.cos(hi)]))
    phi = rng.uniform(0.0, 2.0 * math.pi)
    st = math.sin(theta)
    return np.array([st * math.cos(phi), st * math.sin(phi), math.cos(theta)])


# -------------------------------------------------------------------- streaks

def streak_geometry(length, width):
    """Two quads crossed along -X, head at the origin, tail at -length."""
    tail_w = width * 0.32
    verts, uvs, tris, normals = [], [], [], []
    for axis in range(2):  # 0: width along Y, 1: width along Z
        def v(x, w):
            return (x, w, 0.0) if axis == 0 else (x, 0.0, w)
        normal = (0.0, 0.0, 1.0) if axis == 0 else (0.0, 1.0, 0.0)
        base = len(verts)
        verts += [v(0.0, -width), v(0.0, width), v(-length, tail_w), v(-length, -tail_w)]
        normals += [normal] * 4
        uvs += [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
        quad = [(base + 0, base + 1, base + 2), (base + 0, base + 2, base + 3)]
        # Both windings, so the quad is visible from either side without
        # needing a NiStencilProperty.
        tris += quad + [tuple(reversed(t)) for t in quad]

    data = nif.NiTriShapeData(
        vertices=np.array(verts, dtype=np.float32),
        normals=np.array(normals, dtype=np.float32),
        uv_sets=np.array([uvs], dtype=np.float32),
        triangles=np.array(tris, dtype="<H"),
        center=vec(-length * 0.5, 0.0, 0.0),
        radius=float(math.hypot(length, width)),
    )
    return data


def build_streak(index, rng, params):
    """One keyframed streak: a lit quad cross flying a baked ballistic arc."""
    speed = rng.uniform(*params["speed"])
    life = rng.uniform(*params["life"])
    length = rng.uniform(*params["length"]) * (0.6 + 0.4 * speed / params["speed"][1])
    width = rng.uniform(*params["width"])
    direction = random_cone_direction(rng, params["cone"])
    v0 = direction * speed
    drag = rng.uniform(1.1, 2.2)  # 1/s, air slowing the spark down

    steps = 9
    rotations, translations, scales = [], [], []
    for i in range(steps + 1):
        t = life * i / steps
        # Velocity with linear drag plus gravity, and its integral for position.
        decay = math.exp(-drag * t)
        vel = v0 * decay + np.array([0.0, 0.0, -GRAVITY * t])
        pos = v0 * (1.0 - decay) / drag + np.array([0.0, 0.0, -0.5 * GRAVITY * t * t])
        if np.linalg.norm(vel) < 1e-4:
            vel = v0
        q = quat_from_direction(vel)
        rotations.append((t, *q))
        translations.append((t, *pos))
        # Hold full size, then collapse over the last third.
        f = i / steps
        scale = 1.0 if f < 0.62 else max(0.05, 1.0 - (f - 0.62) / 0.38)
        scales.append((t, scale))

    keyframe_data = nif.NiKeyframeData(
        rotations=nif.NiRotData(key_type=nif.NiRotData.KeyType.LIN_KEY,
                                keys=np.array(rotations, dtype=np.float32)),
        translations=nif.NiPosData(key_type=nif.NiPosData.KeyType.LIN_KEY,
                                   keys=np.array(translations, dtype=np.float32)),
        scales=nif.NiFloatData(key_type=nif.NiFloatData.KeyType.LIN_KEY,
                               keys=np.array(scales, dtype=np.float32)),
    )
    keyframe_controller = nif.NiKeyframeController(
        flags=CTRL_ACTIVE_CLAMP, frequency=1.0, phase=0.0,
        start_time=0.0, stop_time=life, data=keyframe_data,
    )

    # Fade the streak out over its life so it dies as light rather than shrinking
    # to a dot. Additive blending turns alpha straight into brightness.
    alpha_keys = [(0.0, 1.0), (life * 0.45, 0.9), (life * 0.8, 0.35), (life, 0.0)]
    material = nif.NiMaterialProperty(
        name=f"CC Streak {index}",
        ambient_color=vec(0.0, 0.0, 0.0),
        diffuse_color=vec(0.0, 0.0, 0.0),
        specular_color=vec(0.0, 0.0, 0.0),
        emissive_color=vec(STREAK_EMISSIVE),
        shine=0.0,
        alpha=1.0,
        controller=nif.NiAlphaController(
            flags=CTRL_ACTIVE_CLAMP, frequency=1.0, phase=0.0,
            start_time=0.0, stop_time=life,
            data=nif.NiFloatData(key_type=nif.NiFloatData.KeyType.LIN_KEY,
                                 keys=np.array(alpha_keys, dtype=np.float32)),
        ),
    )
    material.controller.target = material

    shape = nif.NiTriShape(
        name=f"CC Streak {index}",
        flags=2,
        data=streak_geometry(length, width),
        properties=[
            texturing_property(STREAK_TEX),
            nif.NiAlphaProperty(flags=ALPHA_ADDITIVE, test_ref=0),
            nif.NiZBufferProperty(flags=ZBUFFER_TEST_ONLY),
            material,
        ],
    )

    node = nif.NiNode(
        name=f"CC Streak Pivot {index}",
        flags=0,
        children=[shape],
        controller=keyframe_controller,
        # First key's pose, for the frame before the controller runs.
        translation=vec(0.0, 0.0, 0.0),
    )
    keyframe_controller.target = node
    return node


# ----------------------------------------------------------------------- build

def build_streaks(streaks):
    """Wrap a list of streak nodes into a finished NIF."""
    root = nif.NiNode(name="CombatJuiceSpark", flags=10, children=streaks)
    stream = nif.NiStream()
    stream.root = root
    return stream


def build_variant(cfg, rng, with_fast):
    """One spark burst: the ordinary streaks, plus a hard-thrown cluster."""
    params = dict(speed=cfg["speed"], life=cfg["life"], length=cfg["length"],
                  width=cfg["width"], cone=cfg["cone"])
    count = rng.randint(*cfg["streaks"])
    streaks = [build_streak(i, rng, params) for i in range(count)]

    fast = 0
    if with_fast:
        fast = rng.randint(*cfg["fast_count"])
        streaks += [build_streak(count + i, rng, FAST) for i in range(fast)]

    return build_streaks(streaks), count, fast


def build_lightsource():
    """An empty node. A Light record needs a model, and the spark flash light
    has nothing to draw - it is there for its radius alone."""
    stream = nif.NiStream()
    stream.root = nif.NiNode(name="CombatJuiceLightSource", flags=10)
    return stream


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    impact_dir = root / "meshes" / "e" / "impact"
    spark_dir = root / "meshes" / "MaxYari" / "combat juice" / "sparks"
    impact_dir.mkdir(parents=True, exist_ok=True)
    spark_dir.mkdir(parents=True, exist_ok=True)

    for family, cfg in FAMILIES.items():
        rng = random.Random(cfg["seed"])
        for n in range(1, cfg["variants"] + 1):
            with_fast = rng.random() < cfg["fast_chance"]
            stream, count, fast = build_variant(cfg, rng, with_fast)
            # Variant 1 keeps the name Impact Effects plays, so it is what any
            # other mod spawning these meshes gets.
            path = (impact_dir / cfg["replaces"]) if n == 1 else (spark_dir / f"{family}_{n}.nif")
            stream.save(path)
            print(f"wrote {path.name:<20} {count} streaks"
                  + (f" + {fast} thrown hard" if fast else ""))
            for also in cfg.get("also", []) if n == 1 else []:
                stream.save(root / also)
                print(f"wrote {Path(also).name:<20} (a copy of {cfg['replaces']})")

    rng = random.Random(CLUSTERS["seed"])
    for n in range(1, CLUSTERS["count"] + 1):
        count = rng.randint(*CLUSTERS["streaks"])
        stream = build_streaks([build_streak(i, rng, FAST) for i in range(count)])
        path = spark_dir / f"cluster_{n}.nif"
        stream.save(path)
        print(f"wrote {path.name:<20} {count} streaks thrown hard")

    light_dir = root / "meshes" / "MaxYari" / "combat juice"
    build_lightsource().save(light_dir / "lightsource.nif")
    print(f"wrote {'lightsource.nif':<20} (the spark flash light's model)")


if __name__ == "__main__":
    main()
