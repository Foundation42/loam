# Loop Loft — Growth as Authoring

**Companion to loop-loft-campaign.md. Motivation, comparative systems, and
technical approach — framed for presentation (GDC 2027/8 target).**
Foundation42 · Entrained AI Research Institute · draft 2026-08-30

---

**You don't model the tree — you model the growing; the tree falls out.**

That sentence is the entire pitch. Everything below unpacks it.

## 1. The human problem

The cost of a 3D world is almost entirely authoring labor. Engines render
more than small teams can afford to make; the bottleneck moved from the GPU
to the person years ago and never moved back. The industry's answer has been
to industrialize the labor — outsourcing, photogrammetry, asset stores —
which scales the studios that can pay for it and locks out everyone else.

The deeper problem is the representation. Mainstream tools treat geometry as
data: a bag of vertices, where every edit is surgery on the bag. Surgery
requires a surgeon. The skill floor for "make a good-looking pillar" is
measured in years, and the skill floor for "make a thousand pillars that
belong to the same world" is a team.

Loop Loft treats geometry as a program instead. A structure is a small
function — spine, frames, a ring of state evolving as it extrudes — and the
mesh is just that function sampled at a chosen resolution. Any point on the
surface is evaluated, not stored. The person's job moves up a level: they no
longer place vertices, they shape the rules and the environment the rules
grow through, and they judge the results. Taste and verdicts instead of
surgery.

This is a continuation of a long bet: that authoring should keep rising
toward intent, and that the machine should absorb the mechanism underneath.
What has changed is that the surrounding engine — fields in space, live
knobs, a test discipline — is finally strong enough to hold the whole idea
at once.

And because the same growing can fall out as a pillar, a canyon wall, or a
creature, the tool stops being a tree tool. It is a biosphere with a
geology.

## 2. Comparative systems

Every existing family solves a slice of this, and each slice illuminates a
design decision we made differently.

**L-systems and specialized growers (SpeedTree and descendants).** The
closest ancestors — grammar-driven growth, genuinely program-not-data. But
they are domain-locked: the tree grower doesn't make terrain, the terrain
tool doesn't make creatures, and none of them share context. Each asset is
grown in a vacuum and pasted into the world afterwards. Loop Loft keeps the
growth-grammar insight and removes the domain lock (one machine, many
outputs) and the vacuum (growth samples the world's fields as it goes, so a
whole street agrees on its character without any asset talking to another).

**Node-graph proceduralism (Houdini, Blender geometry nodes).** Maximum
generality, and the proof that geometry-as-program works at production
scale. The cost is that every asset is its own bespoke program, authored by
an expert, and the graphs bottom out in the same vertex-bag operations —
the program describes edits to data rather than growth of form. There is
also no world coupling: a Houdini network doesn't know it's being evaluated
in the blighted district. Loop Loft is far narrower — one generator shape,
deliberately — and buys back with that narrowness a fixed state vector,
guaranteed watertightness, shared topology across assets, and field
coupling.

**Heightfield terrain (World Machine, Gaea, every in-engine terrain
system).** The ultimate special case: a function that can only say "up."
Erosion simulation on heightfields is genuinely beautiful work, but
overhangs, arches, caves and sea stacks are famously bolted-on hacks
because the representation cannot express them. A loop-lofted ridgeline is
a horizontal spine; the arch is the bend knob; the hoodoo is the taper
knob. The exotic cases cost nothing because tube topology never had the
up-only constraint.

**Tile and constraint solvers (Wave Function Collapse and kin).** Excellent
at discrete arrangement, structurally unable to blend. The transitional
building between two districts has to be authored as its own tile. In Loop
Loft the transitional building cannot be anything else — it grew across the
boundary and sampled both fields on the way up.

**Scanned and ML-generated geometry (photogrammetry, Nanite-scale capture,
3D diffusion, splats).** The opposite pole: pure data, no program. The
outputs can be spectacular and are essentially dead — no semantic handles,
no parameters, frequently not watertight, unmergeable with anything. You
can render them; you cannot ask them questions or grow a variant. We treat
these as complementary (reference, backdrop, capture) rather than
competition, because the thing we're optimizing — editability,
coherence, meaning — is the thing they discard.

The axis that actually separates Loop Loft from all five: **parameters
belong to space, not to the asset.** Authored property volumes — and,
later, fields cast by the structures themselves — mean growth is a query
against the world: growth(seed, fields) → mesh. Coherence, transitions and
world editing stop being features and become consequences. Repaint the
volume, regrow the street — an editor-time loop in v1, with live in-game
regrowth a recorded, costed step behind one named piece of BVH work rather
than an open question.

## 3. Technical approach

The machine is small enough to state completely.

**Spine and frames.** A control spline, parametrized by arc length, carries
rotation-minimizing (parallel transport) frames. Frenet frames are banned —
they twist violently at inflection points, and arches have inflection
points. Bending the spine back to the ground is how an arch is authored;
there is no arch case.

**The ring.** N vertex slots, fixed for the whole build. Fixed N is the
load-bearing choice: it makes each loop a fixed-size state vector, which
makes loop n a function of loop n−1 — the generator is a 1D cellular
automaton on a ring, extruding as it runs. It also makes triangulation
trivial, watertightness structural, and every asset topologically
identical to every other (which is what later makes creatures
interpolable). Triangle removal is a post-process; the invariant holds
during growth.

**The state vector.** Per slot: radial residual r, vertical jitter dz
(clamped to half the ring spacing — the manifold guarantee), tangential
drift dθ (twist, spiral grain, features that migrate rather than sit in
columns), a semantic tag, and an age counter. Per ring: arc position, base
radius, roll, and a few slow morphogen scalars.

**The update rule.** r[n] = r[n−1] + noise + impulses − k·(r[n−1] −
envelope). A leaky integrator toward a morphogen envelope. The residual is
the state, and k is a material property: long time constant and a bulge
born at ring 40 rides the whole column as a flute; short and it heals into
local bark. Combined with dθ, persistent residuals advect helically —
corkscrew (Solomonic) columns from two numbers. Residual amplitude is also
a free importance signal: decimation collapses where it is near zero,
texturing reads it as wear, and semantics can derive from it (a slot whose
residual stays hot for k rings earns a ridge tag).

**Tags are behavioral contracts.** The semantic tag is not a material ID;
it is a promise the rest of the engine can act on. The direction of travel:
a ridge tag reinforces itself through the enzyme that laid it down; a hinge
tag marks a line the actuator system can articulate; a window tag marks a
region a fracture or grammar system can address — with no additional
authoring pass, because the tags were deposited by the same growth that
made the shape. The generator doesn't just make shapes; it makes geometry
that already means something. v1 ships the smallest honest version of this
— one derived tag, one enzyme — but the contract framing is why the
channel exists at all.

**Fields.** Before growth, differentiable property volumes exist in space —
authored, or deposited by gameplay systems. Growth samples them per ring at
the spawn tick and stamps the sampled values onto the recipe as provenance,
so (seed, samples) reproduces the mesh byte-identically and any two
structures can be diffed by asking which field values differed. Fields
drive values (taper here, gnarl there) and, more interestingly, the rule
itself: a mechanization field blends the update from flowing residuals to
lattice-snapped ones, so a single structure slides from grown to
manufactured as it passes through the volume. Sampling the gradient gives
tropism — spines that lean toward light and away from blight.

**Branching.** Knots on the spine partition the ring by tag arcs; each
child arc resamples to the full N and continues under the same machine.
Topologically a pair-of-pants split; practically, degenerate seam triangles
deleted after the build. Branching is quarantined behind its own gates
because it carries most of the topology risk.

**The rig for free.** Because every vertex is defined relative to the spine
and its frames, posing the spine deforms the mesh with no skinning pass —
the (s, θ) coordinates are the weights. Branch knots are joints. This is
the horizon argument for characters, and it costs v1 nothing beyond the
decisions already made.

**Proof discipline.** Seven pre-registered gates, each shipped with a
mutation that must bite: determinism, watertightness (Euler characteristic,
two triangles per edge), manifold-under-jitter, field provenance, blend
continuity, branch conservation, and a curvature guard for the one real
geometric dragon (rings crossing the center of curvature on tight bends).
A gate whose mutation doesn't bite is a finding about the gate.

## 4. What Matryoshka supplies

Loop Loft is small because the engine underneath it is not. Each dependency
below already exists and already has its own test discipline; the generator
inherits rather than invents.

**Differentiable fields are native.** Grade volumes, light volumes, and the
casts system ($ channels, superposition, caster-owned volumes, leaky-
integrator decay) are the engine's existing vocabulary — "differentiable
fields for everything" predates this project. Growth reading fields is a
new consumer of an old mechanism, and the eventual generator-rig idea
(structures casting the fields their own branches grow through, the way a
meristem casts auxin) is one new capability on the same substrate: a knot
may cast.

**Recipes are archetypes.** The archetype/instance spine already unifies
grade volumes, lights, sound, sensors, actuators and prims. A generator is
one more tenant: the recipe is the archetype, a grown structure is an
instance referencing it, regrow is re-evaluation. Provenance stamps ride
the same records the asset-pack system already hashes, so grown assets
version, branch and ship like everything else.

**Geometry is evaluated, not imported.** The engine's north star has
geometry living in the substrate store with a heterogeneous BVH whose leaf
types are evaluated on the fly — terrain, particles, volumetrics as
recipes referenced at query time rather than stored triangles. A grown
structure is precisely such a recipe. v1 bakes at cut time into the static
tree; live regrowth is a named customer of an already-recorded fill
(per-BLAS lattice work), not a surprise.

**The console closes the loop.** Knobs are plane paths; panels are
documents; a panel can X-ray the renderer's own G-buffer, and buttons run
console lines. If growth parameters are plane paths, every recipe is
tunable live from the same panels, and a residual-heat surface is one line
away from being an X-ray view — the person turns a knob and watches the
column re-grow. rill supplies the other half: enzymes as dataflow over
tags and fields, no imperative rules anywhere.

**The house makes claims falsifiable.** Bit-determinism on static scenes,
frozen references, mutation-tested gates, deferred fills recorded with
pointers and paying customers, and a standing rule that a comment nobody
can falsify is a bug waiting to ship. A generative system is exactly the
kind of software that degenerates into vibes without this; here it plugs
into a culture where "it grew correctly" is a byte-identity statement.

## 5. What it does not do

Credibility is cheaper bought here than in the Q&A. The machine makes
tubes: genus 0 by construction, branches that split but never rejoin — no
handles, no torus, no arch-that-merges-back. That is a parked design
question with a recorded revisit trigger, not an oversight. Hard-edged,
boxy, CSG-flavored forms fight the smoothing vocabulary; the mechanization
field is the bridge toward manufactured looks, but v1's native register is
soft. Growth is build/cut-time in v1 — "repaint and regrow" is an editor
loop today, a gameplay loop only after the named BLAS fill is paid. Tight
bends are bounded by the curvature guard rather than solved. And nothing
here makes leaves, fur, or thin shells; those are different machines, and
pretending otherwise would break the one-algorithm claim rather than
extend it.

## 6. Where it goes

v1 is a single-spine machine with a field read path, one derived tag, one
enzyme. The horizon, in order of ambition: branching structures; terrain as
grown leaf types; generator rigs — growth instantiating its own fields,
hierarchically, so an oak is authored as soil and light plus a rig that
recursively supplies the rest; and creatures. The jump from column to
creature is smaller than it sounds, and the mechanics say why: the machine
does not change. A column is a vertical spine with radially symmetric
fields; a creature is a roughly horizontal spine with bilaterally mirrored
fields and knot placement. The spine is the rig, fixed N makes all fauna
points in one state space, and anything that grows near the blight zone
comes up already corrupted because it sampled the same air the pillars
did.

One algorithm. What distinguishes a column from a canyon from a creature is
which fields it grew through and where its knots landed. The person
supplies the world's intent; the world grows to meet it.
