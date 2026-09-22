# Cinematic Combat

An OpenMW Lua mod that makes melee land harder: the world stops for a beat on
every hit, drops into slow motion on the kill that ends a fight, shakes the
camera, dims the screen edges for a moment, and replaces Morrowind's spark
effect with one made of streaks that fly the way they are actually moving.

Needs **OpenMW 0.51** or newer and **[Max Yari's Script Services (MSS)](https://www.nexusmods.com/morrowind/mods/60256)**.
**[OpenMW Impact Effects](https://www.nexusmods.com/morrowind/mods/55508)** is
optional but strongly recommended - it is what decides where sparks happen.

## What it does

### Hit stop

The instant a hit lands, the whole simulation drops to a fraction of its speed
for a tenth of a second and snaps back. No easing - an abrupt stop reads as
impact, a smooth one reads as slow motion.

The awkward part is timing. The engine fires the attack animation's hit key,
applies the hit, and only the *victim* is told whether it landed; that answer
comes back to the attacker an update or two later, by which time the weapon has
swung past the contact pose and the stop lands on the follow through.

So this mod holds the swing itself. The moment the hit key fires, before anybody
knows the result, the attacker's animation is paused (`skipAnimationThisFrame`,
the same one-frame hold MWScript's `SkipAnim` uses) for **Frames Held At The Hit
Key** frames. When the victim's answer arrives the hold is released and the real
hit stop takes over - or, on a miss, nothing happens and the swing carries on.
Two frames is usually right. Set it to 0 to turn the hold off and accept a
slightly late stop.

Enemies attacking you get the same hold, so their weapon stops on you rather
than past you.

### Kill slow motion

Moved here out of Dynamic Reticle, with the encounter logic it was missing.

OpenMW's combat music is driven by a script on every NPC and creature that
watches its own combat targets and reports every change to the player. That is
the engine's own "a fight is on / the fight is over" signal - the same one that
starts and stops the battle playlist - and this mod listens to it. So when you
kill somebody it knows whether anyone else is still fighting you, and the kill
that ends the encounter gets the slow motion **every time**.

Any other kill only rolls for it, on a chance that ships at **0** so the
encounter behaviour can be tested on its own. Turn it up for slow motion
scattered through a fight.

It keeps working with combat music switched off.

### Camera shake

Rides along with the hit stop, decaying over about a fifth of a second, stronger
when the hit lands on you. With **Dynamic Camera** installed it goes through
that mod's extra angle API, so the two add up instead of overwriting each other.

### Kill vignette

A quick post processing pulse on a kill: the screen edges sink and the middle
lifts. It is a gamma bend rather than a colour wash - the frame keeps its own
colours, blacks stay black, nothing clips.

### Sparks

Morrowind spark effects are particles, and OpenMW draws NIF particles as
camera-facing squares: it parses `NiParticleRotation` and then ignores it
(`nifloader.cpp`, "RC_NiParticleRotation // unused"), and there is no
velocity-aligned particle mode. A stretched particle sprite would lie down in
the same screen direction for every spark, which looks wrong.

So the long sparks in this mod are not particles. Each one is a pair of quads
crossed along its own axis, flying a ballistic arc that is **baked into
keyframes** by `tools/make_sparks.py`, turned at every key to face the direction
it is travelling at that moment - so the streak bends over as the spark falls.
The crossed pair keeps it visible from any angle; both triangle windings are
written so backface culling cannot hide it. Around them are the ordinary
particle sparkles, smaller than vanilla, blue-white instead of yellow, and
pulled down by gravity.

These are mesh replacers for `meshes/e/impact/metalSpark.nif`,
`parrySpark.nif` and `shieldBlock.nif`, so they apply to whatever plays them -
normally OpenMW Impact Effects. To go back to the originals, delete this mod's
`meshes/e/impact` folder.

**Where sparks already happen:** Impact Effects raycasts each swing, works out
what it struck, and sparks off bare metal, shields, ice armour and *heavy
armour on the body* - it picks the helmet, cuirass or greaves by how high the
hit landed, so it is not shield-only. Medium armour is the gap: it gets a sound
and no sparks. **Sparks On Medium Armour** in the settings fills that in.

**Light flash:** sparks can throw a very short lived light where they appear
(off-white blue, ~0.1s). NIF lights are not loaded by OpenMW, so this is a real
light record spawned by the mod, from a pool of three objects that are parked
disabled and reused rather than created and destroyed per hit.

## Settings

Everything above is in Options → Scripts → **Cinematic Combat**, in four groups:
Hit Stop, Kill Slow Motion, Camera Shake and Impact Effects.

## Installing

<!-- nexus-skip-start -->
Add the folder as a data path and enable `CinematicCombat.omwscripts` in the
launcher, after MSS. If this is the first OpenMW mod you have installed,
[read this first](https://modding-openmw.com/tips/installing-mods/).

## Building the assets

The meshes and textures in this repository are generated, and both scripts are
safe to re-run:

```sh
python3 tools/make_spark_textures.py     # textures/MaxYari/cinematic combat/*.png
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
