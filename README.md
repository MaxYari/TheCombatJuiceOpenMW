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

The image smears out from the middle of the screen, the highlights bloom cold,
and the light in the room turns blue for a moment.

**It rides one of the slow motions** - the short one, the long one, or either -
and runs for exactly as long as that slow motion does, so the two always start
and end together and there is no second duration to keep in step. A kill with no
slow motion gets no flash. It also runs the *same shape*, phase for phase: in on
the same curve, held for the same stretch, and released on the mirror of the slow
motion's own recovery, so the screen comes back exactly as the world does. On its
own tail it used to be all but gone a third of the way through the slow motion,
while everything was still crawling.

Its bones come from the death imagespace in the Skyrim mod
[Sanguine Symphony](https://www.nexusmods.com/skyrimspecialedition/mods/148388),
read out of that mod's plugin - it ships no shaders, and its only screen effect
is three imagespace modifiers its SKSE plugin fires on a death. Their recipe is
`radial blur 0.15`, `contrast x1.3`, `saturation 0`, `tint red at 0.059`, over
half a second peaking a tenth of the way in. **The zoom blur is taken from it as
it stands** - the blur is what reads as impact. The timing is not quite: those
curves snap to a peak a tenth of the way in and fall straight back, while the
footage holds its peak - brightness there ramps over a frame or two, sits flat
for about seven, then takes twenty more to return. Held, the flash is at full
strength long enough to be seen rather than passed through.

The colour is not, and it cannot be. That mod's flash drains saturation to 0 and
washes toward white, and **desaturation cannot overshoot neutral** - it moves the
channels together, it never crosses them over. The footage crosses them over: a
frame that reads r 0.251 / b 0.211 comes out r 0.285 / b 0.317, and its brightest
quarter goes from warm to cold as well. So the cold cast in that video is the
recorder's own setup on top of the mod, not something the mod does. The mod page
agrees - it lists no ENB requirement and says everything is done in-engine.

The look is still the thing worth having, so the colour here is tuned to those
frames rather than to the plugin.

**Colour has to be brought in, not scaled up.** A cold tint over the bloom does
nothing in a torchlit room: multiplying warm light by a blue tint only takes red
out of it, because there is no blue in it to raise. So the bloom is *repainted* -
reduced to its own brightness and given the tint's colour.

**And it is held off the shadows.** Laid over the whole frame the same colour
reads as a filter dropped on the screen; kept to what is already lit it reads as
the light in the room going cold, which is the thing worth having. The wash and
the tint fade in from **Lit From** upwards, so on a cave screenshot the shadows
and midtones come out as they went in and the highlights gain 0.18 of blue over
red. Dark places therefore flash less by design - if you want more of one, lower
Lit From or raise Cold Wash.

Contrast is off by default for the same reason the shadow crush was: it turns
about a pivot, and in a cave most of the screen sits below any sensible pivot,
so it darkens the very thing it is supposed to light up.

Measured on the reference's own frames, the flash there lifts red by 0.03 while
lifting green and blue by 0.09 and 0.11 - it turns the frame cold - and
saturation nearly doubles. So the bloom is tinted cold, a cold tint goes over
the frame, and saturation is pushed up rather than drained, a little harder than
the footage does it so the cold reads as deliberate: on a dark interior the
defaults come out `r 0.286 g 0.339 b 0.416`. **Tint Amount** is the knob for
that - 0.25 is the least that flips a warm room cold, 0.35 ships, past 0.5 it
turns into a blue filter.

For the original look instead: saturation `0`, tint `1.0, 0.22, 0.18`, tint
amount `0.059`. Every part of it is a live uniform in the post processing HUD.

**A trap worth knowing about:** OpenMW saves every post-processing uniform you
touch into `~/.config/openmw/shaders.yaml`, keyed by technique and uniform name,
and the parser prefers a saved value over the default in the shader file
(`technique.cpp`, where each uniform looks itself up in `ShaderManager`). A value
saved under a name survives that name changing meaning, which is how an earlier
`uContrast` - a shadow crush that defaulted to 0 - ended up as a contrast
multiplier of 0 and flattened the whole screen to one grey. Rename the technique
when the uniform set changes meaningfully, and give a uniform a new name rather
than a new meaning.

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
scenery gets the spark light but never the warm one, and being hit yourself
lights nothing at all: it would be lighting your own face.

A Morrowind light has no brightness field. What it lights is the magnitude of
its colour, and the radius is only how far it reaches - so **Power** scales the
colour, leaving the reach alone. The warm one ships at a third, which reads as a
glint off the blow rather than a lamp being lit next to you.

Nor can a light already in the world be dimmed: its colour belongs to the record
rather than to the object, and a record cannot be edited once it exists. So a
light is played as a short run of three, each darker than the last, which fades
it out instead of having it vanish between one frame and the next.

**Where the blow landed** is worked out here rather than taken from anyone else,
because neither available answer is good enough. The engine's hit position is
`getHitContact`'s output - the victim's origin, their feet, raised by a *random*
20% to 100% of their height - so a light placed there lands on the floor as
often as on the wound. Impact Effects casts a ray from the camera through the
middle of the screen, which is right only while you are looking straight at what
you are hitting; swing at someone off to the side and the ray goes past them.

So: look down the camera first, since that is where the player's attention is,
and if that ray does not land on the victim, cast one straight at them, level at
chest height - from the race's own height for an NPC, and from the engine's
position for anything else. An enemy hitting *you* skips the camera step, having
none, and takes the ray between the two of you.

Sparks are the exception: they light on Impact Effects' own ray, because that is
where the sparks themselves are, and the warm light stays out of the way for a
moment afterwards.

Impact Effects also has to report bare body parts for its spark hook to be worth
anything, and as shipped it does not - it throws the raycast away before calling
any handler whenever it cannot name a material. **A one-line change fixes it**,
and [docs/impact-effects-unarmored.md](docs/impact-effects-unarmored.md) is a
memo to send its author. It is applied to the local install with the original
kept alongside; re-apply it after updating that mod.

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
