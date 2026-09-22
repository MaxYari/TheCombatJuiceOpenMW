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

TEX = "textures\\MaxYari\\cinematic combat\\"
STREAK_TEX = TEX + "spark_streak.png"

# Alpha: blending on, SRC_ALPHA + ONE (additive), no alpha test.
ALPHA_ADDITIVE = 13
# Z buffer: test against the depth buffer, don't write to it.
ZBUFFER_TEST_ONLY = 1
# Controller flags: active (0x8) + clamp at the last key (0x4) so nothing loops.
CTRL_ACTIVE_CLAMP = 12

GRAVITY = 700.0  # units/s^2, pulling -Z, baked into the arcs.


# ---------------------------------------------------------------- per-file setup

SPARKS = {
    # Weapon on metal: the loudest of the three.
    "metalSpark.nif": dict(
        seed=20260921,
        streaks=8,
        streak_speed=(170.0, 430.0),
        streak_life=(0.22, 0.40),
        streak_length=(9.0, 22.0),
        streak_width=(0.85, 1.5),
        cone=(0.0, 125.0),      # degrees away from +Z that streaks are thrown
    ),
    # Parry / weapon on armour. Impact Effects also scales this one to 0.5.
    "parrySpark.nif": dict(
        seed=760921,
        streaks=6,
        streak_speed=(150.0, 360.0),
        streak_life=(0.20, 0.34),
        streak_length=(8.0, 18.0),
        streak_width=(0.8, 1.35),
        cone=(0.0, 125.0),
    ),
    # Shield block: fewer, shorter, more of a scuff.
    "shieldBlock.nif": dict(
        seed=550821,
        streaks=5,
        streak_speed=(120.0, 300.0),
        streak_life=(0.18, 0.30),
        streak_length=(6.0, 14.0),
        streak_width=(0.75, 1.2),
        cone=(0.0, 110.0),
    ),
}

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


def build_streak(index, rng, cfg):
    """One keyframed streak: a lit quad cross flying a baked ballistic arc."""
    speed = rng.uniform(*cfg["streak_speed"])
    life = rng.uniform(*cfg["streak_life"])
    length = rng.uniform(*cfg["streak_length"]) * (0.6 + 0.4 * speed / cfg["streak_speed"][1])
    width = rng.uniform(*cfg["streak_width"])
    direction = random_cone_direction(rng, cfg["cone"])
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

def build(name, cfg):
    rng = random.Random(cfg["seed"])
    children = [build_streak(i, rng, cfg) for i in range(cfg["streaks"])]
    root = nif.NiNode(name="CinematicCombatSpark", flags=10, children=children)
    stream = nif.NiStream()
    stream.root = root
    return stream


def build_lightsource():
    """An empty node. A Light record needs a model, and the spark flash light
    has nothing to draw - it is there for its radius alone."""
    stream = nif.NiStream()
    stream.root = nif.NiNode(name="CinematicCombatLightSource", flags=10)
    return stream


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    out = root / "meshes" / "e" / "impact"
    out.mkdir(parents=True, exist_ok=True)
    for name, cfg in SPARKS.items():
        stream = build(name, cfg)
        stream.save(out / name)
        print(f"wrote {out / name} ({(out / name).stat().st_size} bytes, "
              f"{cfg['streaks']} streaks)")

    light_dir = root / "meshes" / "MaxYari" / "cinematic combat"
    light_dir.mkdir(parents=True, exist_ok=True)
    build_lightsource().save(light_dir / "lightsource.nif")
    print(f"wrote {light_dir / 'lightsource.nif'}")


if __name__ == "__main__":
    main()
