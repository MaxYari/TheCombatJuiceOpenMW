# Cinematic Combat

An OpenMW Lua mod that makes melee land harder: kills drop the world into slow
motion, the camera shakes when a hit connects, the screen blows out like a
camera caught by a sudden light, and Morrowind's spark effect is replaced with
one made of streaks that fly the way they are actually moving.

Needs **OpenMW 0.51** or newer and **[Max Yari's Script Services (MSS)](https://www.nexusmods.com/morrowind/mods/60256)**.
**[OpenMW Impact Effects](https://www.nexusmods.com/morrowind/mods/55508)** is
optional but strongly recommended - it is what decides where sparks happen.

## What it does

### Slow motion

Two of them, and every kill is checked against both:

* a **short** dip, on every kill by default;
* a **long** one, on the last enemy of a long fight by default.

Each has its own trigger, chance, time scale and duration. A trigger is the
loosest case it accepts - *every kill*, *last enemy of a fight*, *last enemy of a
long fight*, or *never* - and a kill qualifies if it is that case or a stricter
one. Since the kill that ends a long fight is also an ordinary kill, both can
qualify at once; when they do, **the longer one wins**. A fight counts as long
once it has been going for 20 seconds, which is itself a setting.

Knowing which kill ended the fight comes from the engine. OpenMW's combat music
is driven by a script on every NPC and creature that watches its own combat
targets and reports every change to the player - the same signal that starts and
stops the battle playlist. This mod listens to it, so it knows who is still
fighting you and how long they have been at it. It keeps working with combat
music switched off.

### Camera shake

Fires when a hit lands, decaying over a third of a second. Hits you take don't
shake the camera unless you turn that up. With **Dynamic Camera** installed it
goes through that mod's extra angle API, so the two add up instead of
overwriting each other.

### Kill flash

An exposure blow-out, not a vignette: highlights bloom out and smear towards the
middle of the screen, the darks fall away, the glare runs cold, and the whole
frame lifts - a camera, or an eye, caught by a light it was not ready for. It
snaps in over a couple of frames and takes most of a second to recover.

Nothing gets darker. The tone curve is a straight multiply, so every pixel comes
out at least as bright as it went in, and the top of the range clips to white:
on a dim interior frame that lifts the mean by half and blows out a third of the
image. There is a **shadow crush** knob for the look a real overexposed frame
has, where the darks fall away as the highlights blow - it is off by default,
because any amount of it darkens the darkest part of the screen, and in a
Morrowind interior that is most of the screen.

It runs as two passes: a quarter resolution bright pass, which thresholds the
image *after* exposure so a dim room still blooms once it has been blown out,
then a composite that spreads that buffer back over the image. Everything about it - glare amount,
threshold, radius, streak length, exposure, shadow crush and tint - is a uniform
you can tune live from the post processing HUD. It takes the same trigger
setting as the slow motion, so it can be limited to the end of a fight.

### Sparks

Morrowind spark effects are particles, and OpenMW draws NIF particles as
camera-facing squares: it parses `NiParticleRotation` and then ignores it
(`nifloader.cpp`, "RC_NiParticleRotation // unused"), and there is no
velocity-aligned particle mode. A stretched particle sprite would lie down in
the same screen direction for every spark, which looks wrong.

So the sparks in this mod are not particles at all. Each one is a pair of quads
crossed along its own axis, flying a ballistic arc that is **baked into
keyframes** by `tools/make_sparks.py`, turned at every key to face the direction
it is travelling at that moment - so the streak bends over as the spark falls.
The crossed pair keeps it visible from any angle; both triangle windings are
written so backface culling cannot hide it. They are white hot at the head, blue
down the tail, and there are few of them: five to eight per hit rather than a
cloud.

Every controller in the files clamps at its last key (`flags = 8|4`). NIF
controllers cycle by default, so one that ends before the effect is cleaned up
starts over - which showed up as a second burst appearing right at the end.

These are mesh replacers for `meshes/e/impact/metalSpark.nif`,
`parrySpark.nif` and `shieldBlock.nif`, so they apply to whatever plays them -
normally OpenMW Impact Effects. To go back to the originals, delete this mod's
`meshes/e/impact` folder.

**Where sparks already happen:** Impact Effects raycasts each swing, works out
what it struck, and sparks off bare metal, shields, ice armour and *heavy
armour on the body* - it picks the helmet, cuirass or greaves by how high the
hit landed, so it is not shield-only. Medium armour is the gap: it gets a sound
and no sparks. **Sparks On Medium Armour** in the settings fills that in.

**Impact lights:** sparks throw a very short lived light where they appear
(cold blue, ~0.1s), and hits on an actor that spark off nothing - flesh, cloth,
light armour - get a weaker, warmer one that is meant to go unnoticed. Struck
scenery gets the spark light but never the warm one.

Placing them takes some care. The engine's own hit position is not a contact
point: `getHitContact` takes the victim's origin - their feet - and raises it by
a *random* 20% to 100% of their height, so a light placed there lands on the
floor often enough to notice. The contact point Impact Effects raycast is used
when it is available, then a ray through the middle of the screen, and only then
the engine's guess.

Impact Effects does not always report, either: it bails out before its handlers
whenever it cannot name a material, which includes any bare body part, so an
unarmoured enemy never reaches the hook at all. Those hits are lit from the hit
event instead.

NIF lights are not loaded by OpenMW, so these are real light records spawned by
the mod, from a pool of three objects per colour that are parked disabled and
reused rather than created and destroyed per hit.

## Settings

Everything above is in Options → Scripts → **Cinematic Combat**, in four groups:
Slow Motion, Camera Shake, Kill Flash and Impact Lights.

## Installing

<!-- nexus-skip-start -->
Add the folder as a data path and enable `CinematicCombat.omwscripts` in the
launcher, after MSS. If this is the first OpenMW mod you have installed,
[read this first](https://modding-openmw.com/tips/installing-mods/).

## Building the assets

The meshes and textures in this repository are generated, and both scripts are
safe to re-run:

```sh
python3 tools/make_spark_textures.py     # textures/MaxYari/cinematic combat/spark_streak.png
<blender>/python/bin/python3 tools/make_sparks.py   # meshes/e/impact/*.nif
```

`make_sparks.py` needs numpy and Greatness7's `es3` NIF library, both of which
ship inside the Blender Morrowind plugin (`io_scene_mw`); set `ES3_LIB` if yours
is somewhere other than the default. Tunables - spark counts, speeds, lifetimes,
streak lengths, gravity, tint - are the `SPARKS` table at the top of the file.
Validate the result with the `niftest` tool that ships with OpenMW:

```sh
niftest -q meshes/
```

The scripts can be exercised without starting the game - `tools/tests/` stubs
the OpenMW Lua API and drives the real files through hits, kills, short and long
fights, every trigger, the time scale and the impact lights:

```sh
lua tools/tests/test.lua "scripts/MaxYari/cinematic combat"
```

The shader has its own checker, which applies the rules OpenMW's `.omwfx` parser
enforces - most usefully that comments are only legal inside GLSL blocks, since
a stray one anywhere else fails the whole file and, because the mod loads the
shader from Lua, would take the script down with it. It also compiles each pass
with `glslangValidator` when that is installed:

```sh
python3 tools/check_omwfx.py shaders/*.omwfx
```

## Releasing

`.github/workflows/nexus-release.yml` packs the mod and uploads it to Nexus on
every push to `main`. Before the first release, fill in `NEXUS_PAGE`,
`NEXUSMODS_FILE_ID` and `NEXUSMODS_MOD_ID` at the top of that file and add the
`NEXUSMODS_API_KEY` repository secret. The version published is the first
`version = ...` in `scripts/MaxYari/cinematic combat/player.lua`.

Enable the README → BBCode hook once per clone:

```sh
git config core.hooksPath .githooks
```
<!-- nexus-skip-end -->

## Credits

Max Yari. Spark meshes and textures generated with Greatness7's `es3` library.
