# Memo: the one-line change Combat Juice needs in OpenMW Impact Effects

**For:** the author of [OpenMW Impact Effects](https://www.nexusmods.com/morrowind/mods/55508)
**Against:** version 1.08, `scripts/ImpactEffects/player.lua`
**Applied locally:** yes, with the untouched file kept beside it as
`player.lua.bak-before-cinematic-combat`. **Re-apply it after updating the mod.**

## The bug

`getNpcArmor` returns a table for every case but one, where it returns a string:

```lua
local eq = Actor.getEquipment(o, slot)
if not eq then return "Unknown" end          -- <- a string
return matArmor[eq.recordId] or getArmorMat(eq.recordId)   -- <- tables
```

Its only caller indexes the result:

```lua
elseif hitMark then mat = getNpcArmor(o, hit)["hit"] end
```

Indexing a string in Lua goes to the string metatable, which has no `hit`, so
`mat` comes back `nil` rather than raising. A few lines later:

```lua
if not mat and types.Actor.objectIsInstance(o) then
    if not hitWater then return end          -- <- returns before runHandlers
```

So whenever the struck body zone has nothing equipped in it, the raycast result
is thrown away: no sound, no effect, and **no hit handler is called at all**.
That is not only naked enemies - it is a bare leg on someone wearing just a
cuirass, and any creature slot that comes back empty. Every mod that registers
through `addHitActorHandler` is blind to those hits.

## The change

```diff
-	if not eq then return "Unknown" end
+	if not eq then return { hit = "Unarmored" } end
```

`"Unarmored"` has no `matVfx` entry, so no effect is played for it, and the
raycast now reaches `runHandlers` like every other material.

One thing to decide: it has no `matSound` entry either, and `matSound[mat] or
"Dirt"` would give these hits a dirt thud they never had. Either add
`Unarmored = "Dmg"` to `matSound` to play the flesh impact deliberately, or
leave it out and let handlers suppress it. Combat Juice sets
`var.noSound = true` for the material so nothing changes audibly for anyone who
has not asked for it.

## Why it matters to us

Combat Juice puts a small light at the point of impact. Impact Effects'
raycast is the only source of a real contact point - the engine's own hit
position is `getHitContact`'s output, which is the victim's origin (their feet)
raised by a *random* 20-100% of their height, so a light placed there lands on
the floor as often as on the wound. With this change every hit on an actor
reports a position, and the mod needs no fallback at all.
