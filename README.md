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

Each has its own trigger, chance, time scale and duration. The long one is
Dynamic Reticle's kill slowdown: same 0.2 floor, and **1.5 seconds**, which is
what that effect really took. Its settings read 0.05 / 0.1 / 0.3, but it counted
them with simulation time, and simulation time is the thing being slowed - at a
0.2 floor a "0.1 second" hold is half a second of real time. Measured against
its own loop at 60fps the whole thing came to 1.52s, split 4% easing in, 30%
held, 66% easing out, which is the shape both slow motions use here. A trigger is the
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

The image smears out from the middle of the screen, contrast snaps up, the
highlights bloom cold, and the whole frame turns from warm to blue for a moment.

Its bones come from the death imagespace in the Skyrim mod
[Sanguine Symphony](https://www.nexusmods.com/skyrimspecialedition/mods/148388),
read out of that mod's plugin - it ships no shaders, and its only screen effect
is three imagespace modifiers its SKSE plugin fires on a death. Their recipe is
`radial blur 0.15`, `contrast x1.3`, `saturation 0`, `tint red at 0.059`, over
half a second peaking a tenth of the way in. **The zoom blur and the timing are
taken from it as they stand** - the blur is what reads as impact, and the timing
is a twentieth of a second to snap on and the rest to let go.

The colour is not. That mod's flash drains to grey and puts red back in; the
footage it was shown in does the opposite, and the footage is what this is tuned
to match. Measured on its own frames, the flash there lifts red by 0.03 while
lifting green and blue by 0.09 and 0.11 - it turns the frame cold - and
saturation nearly doubles. So the bloom is tinted cold, a cold tint goes over
the frame, and saturation is pushed up rather than drained. Alongside its own
frames the defaults land at `r 0.292 g 0.307 b 0.317` against the reference's
`0.285 / 0.317 / 0.317`.

For the original look instead: saturation `0`, tint `1.0, 0.22, 0.18`, tint
amount `0.059`. Every part of it is a live uniform in the post processing HUD.

`tools/preview_flash.py` runs the shader's arithmetic over a screenshot outside
the game, reading the defaults out of the shader file, so a change can be
checked without a kill to test it on:

```sh
<blender>/python/bin/python3 tools/preview_flash.py shot.png out.png [uName=value ...]
```

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

The warm one waits for the hit to be confirmed. Impact Effects casts its ray on
the swing's `min hit` key, before the engine has ruled on the attack, so it
reports a material whether the blow lands or misses; the light on flesh holds
until the victim says the hit was real, an update or two later. Sparks are left
alone - a blade skating off a pauldron rings either way, and the cold light
belongs with the sparks that are already flying.

Every one of them is placed at the contact point Impact Effects raycast, and
nowhere else. The engine's own hit position is no use for this: `getHitContact`
takes the victim's origin - their feet - and raises it by a *random* 20% to 100%
of their height, so a light placed there lands on the floor as often as on the
wound.

That means Impact Effects has to report every hit, and as shipped it does not:
it throws the raycast away before calling any handler whenever it cannot name a
material, which includes any bare body part. **A one-line change fixes it**, and
[docs/impact-effects-unarmored.md](docs/impact-effects-unarmored.md) is a memo
to send its author. It is applied to the local install, with the original kept
alongside - re-apply it after updating that mod, or hits on unarmoured enemies
stop lighting up.

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
