# MARL Campaign

**Multiresolution Adaptive Radial Learning**\
**Project:** Loam / Matryoshka\
**Status:** Initial experimental campaign\
**Date:** 7 September 2026

## 1. Premise

MARL explores a continual-learning architecture built from the same
principles as Loam: sparse hierarchical structure, strictly local work,
immutable published state, deterministic parallel updates, and adaptive
allocation of computation.

The central idea is simple:

> **Learning is the local deformation of a sparse multiresolution
> predictive field in response to surprise.**

Rather than training a monolithic parameter set with global
backpropagation, MARL represents knowledge as a hierarchy of local
predictive regions. Each region contains a compact set of radial basis
functions (RBFs). Observations are routed to the relevant region,
predictions are made locally, and prediction error produces a
correspondingly local deformation.

Learning therefore becomes continuous, sparse, asynchronous and
naturally parallel.

The initial campaign deliberately avoids solving the general
high-dimensional routing problem. MARL-0 will operate directly in Loam's
existing 3-D spatial domain so that the learning dynamics can be tested
using infrastructure that already exists.

------------------------------------------------------------------------

## 2. Architectural Mapping from Loam

A large part of MARL should be a reinterpretation of existing Loam
machinery rather than a parallel implementation.

  Loam                       MARL
  -------------------------- -----------------------------------------
  Spatial coordinate         Exemplar / latent coordinate
  Brick                      Local predictive region / chart
  Field samples              Learned local function
  RBF compression            Live predictive representation
  Operator                   Learning / surprise operator
  RegionUpdate               Local learning deposit
  Attention                  Unresolved surprise / learning priority
  Active set                 Regions requiring further learning
  Refinement                 Additional model capacity
  Settling                   Convergence
  Erosion / simplification   Forgetting / model compression
  Immutable snapshot         Stable inference model
  Next world state           Concurrently learned model

A useful design constraint is:

> **The substrate should not know that learning is happening.**

Where practical, the existing tree, scheduling, update, publication,
hashing and concurrency machinery should remain generic. MARL should
supply different local state and operators.

------------------------------------------------------------------------

## 3. Surprise-Driven Learning

For an observation

\[ (x,y) \]

the current local field produces

\[ `\hat `{=tex}y = f_B(x) \]

and surprise is represented initially by the residual

\[ e = y-`\hat `{=tex}y. \]

A local RBF contribution may be written as

\[ `\Delta `{=tex}f(x)=`\alpha `{=tex}K(\|x-c\|/`\sigma`{=tex}). \]

The important property is locality. A surprising exemplar does not
initiate global backpropagation. It modifies only the RBFs responsible
for the prediction and, where appropriate, a bounded neighbourhood or
hierarchical learning cone.

Conceptually:

``` text
observe
   |
route to local region
   |
predict
   |
measure surprise
   |
   +-- insignificant --> done
   |
   +-- significant
          |
          +--> update nearby RBF parameters
          +--> raise regional attention
          +--> accumulate residual evidence
          |
          +-- capacity sufficient --> settle
          |
          +-- capacity insufficient --> grow/refine
```

Existing RBF gradients for weight, centre and anisotropic geometry are
particularly attractive here: the predictive field can literally move
and reshape itself around surprising observations.

------------------------------------------------------------------------

## 4. The Brick Becomes a Local Chart

Loam's current brick is intrinsically three-dimensional. That is ideal
for MARL-0, but should not be naively generalized into a
high-dimensional hyperoctree.

The eventual MARL brick is better understood as a **local chart**.

A possible future form is:

``` text
MarlBrick
    routing descriptor
    centre in exemplar / latent space
    local basis or projection
    RBF kernels
    surprise statistics
    attention
    changed_ns
    summary
    hash
```

For a high-dimensional exemplar

\[ x`\in`{=tex}`\mathbb{R}`{=tex}\^{D} \]

a chart may operate in a much smaller learned local coordinate system

\[ z=P_B(x-`\mu`{=tex}\_B),
`\qquad `{=tex}z`\in`{=tex}`\mathbb{R}`{=tex}\^{d},`\quad `{=tex}d`\ll `{=tex}D.
\]

This is potentially important computationally. If the locally relevant
dimensionality is small, both inference and local backpropagation can
become extremely cheap.

The architecture should therefore avoid committing prematurely to the
dimensionality or shape of a MARL brick. Finding the useful local
representation is part of the research programme.

------------------------------------------------------------------------

## 5. Learned Topology

Refinement should not simply mean "error exceeded a threshold."

A stronger criterion is **structured residual surprise**.

Repeated unpredictable noise should not cause unlimited growth. Repeated
coherent error should.

For example, if residual exemplars inside a region form two stable
clusters, the parent representation may be conflating two
distinguishable regimes. That is evidence for refinement or creation of
child charts.

This leads to a useful principle:

> **The topology of the model is learned from the topology of its
> mistakes.**

Capacity should consequently accumulate where the learned function is
genuinely complicated while simple or empty regions remain cheap.

------------------------------------------------------------------------

## 6. Continuous Learning and Publication

Loam's immutable publication model gives MARL an attractive concurrency
model almost for free:

``` text
Snapshot N
    |
    +--> arbitrary concurrent inference

Learning workers
    |
    +--> consume surprise
    +--> build local updates
    +--> merge deterministically
    |
Snapshot N+1
```

Inference need not stop while learning occurs.

Independent surprises in unrelated regions can be processed in parallel.
Overlapping updates are reconciled through the existing deterministic
update machinery rather than through uncontrolled mutation of shared
model state.

This should be preserved as a first-class MARL property.

------------------------------------------------------------------------

# MARL-0: First Experiment

## 7. Objective

Demonstrate that a sparse collection of local RBFs can learn an unknown
3-D function continuously from individual exemplars using only local
updates.

Do **not** solve high-dimensional routing yet.

Do **not** build a conventional epoch-based training loop.

Do **not** introduce architectural machinery unless the experiment
requires it.

The question for MARL-0 is simply:

> **Can Loam learn a field by continuously depositing surprise?**

------------------------------------------------------------------------

## 8. Experimental Target

Choose a deterministic function

\[ f:`\mathbb{R}`{=tex}^{3}`\rightarrow`{=tex}`\mathbb{R}`{=tex}^{N} \]

with a mixture of easy and difficult regions.

Useful properties:

-   broad smooth structure;
-   one or more sharp/localized features;
-   regions of near-constant output;
-   enough structure to reveal whether capacity concentrates
    appropriately.

Start with (N=1) unless the existing RBF path makes multiple channels
essentially free.

The ground-truth function should be directly evaluable so prediction
error can be visualized everywhere.

------------------------------------------------------------------------

## 9. Minimal Learning Loop

For each randomly sampled exemplar:

``` text
x = sample_domain()
target = truth(x)

brick = locate(x)
prediction = brick.predict(x)
residual = target - prediction
surprise = metric(residual)

if surprise > learning_threshold:
    brick.learn(x, target)
    brick.attention += surprise
```

`brick.learn()` should initially be deliberately boring:

1.  Find RBFs whose support contains the exemplar.
2.  Run a small fixed number of local gradient/Adam steps.
3.  Update only those kernels.
4.  If no useful kernel covers the exemplar, create one.
5.  Record post-update residual.

No global optimization pass is permitted in the first experiment.

------------------------------------------------------------------------

## 10. Initial Kernel Policy

Keep kernel birth simple.

When a surprising exemplar is insufficiently covered:

-   create an RBF centred at the exemplar;
-   use a conservative default scale/precision;
-   initialize its output weight from the residual;
-   allow subsequent local gradients to move and reshape it.

For MARL-0, impose a small per-region kernel budget.

When the budget is exhausted, **record the event rather than immediately
inventing a sophisticated refinement algorithm**. Saturation data is
itself useful evidence for designing MARL-1.

------------------------------------------------------------------------

## 11. Metrics

Track at minimum:

-   exemplar count;
-   mean prediction error;
-   recent-window prediction error;
-   maximum prediction error;
-   RBF count;
-   active region count;
-   updates per exemplar;
-   time per prediction;
-   time per learning update;
-   number of kernel births;
-   number of saturated regions;
-   spatial distribution of surprise.

Particularly interesting:

### Locality

How many kernels and regions are touched by one learning event?

### Interference

After learning exemplar (x), how much does prediction error change at
distant exemplars?

### Convergence

Do repeatedly observed regions settle without global training?

### Capacity allocation

Do difficult regions naturally acquire more kernels/work than simple
regions?

### Cost

Does local backprop become sufficiently small that continuous learning
is practical?

------------------------------------------------------------------------

## 12. Visualisation

This experiment should be visible.

Render one or more slices through the 3-D domain showing:

-   ground truth;
-   MARL prediction;
-   absolute surprise/error;
-   RBF centres and approximate extents;
-   regional attention;
-   kernel density.

The most useful visual may simply be the error field evolving over time.

The desired behaviour is immediately recognizable:

``` text
initially:
    surprise almost everywhere

then:
    broad regions settle

later:
    activity remains around difficult structure

eventually:
    computation concentrates around unresolved detail
```

If MARL works, we should be able to **watch the model discover where it
needs to think harder**.

------------------------------------------------------------------------

# Campaign Progression

## 13. MARL-0 --- Local Online RBF Learning

**Goal:** prove the basic learning dynamics in existing 3-D Loam space.

Success means:

-   prediction error falls continuously;
-   updates remain local;
-   no epoch/global backprop is required;
-   learned regions settle;
-   difficult regions attract disproportionate work.

------------------------------------------------------------------------

## 14. MARL-1 --- Adaptive Capacity

Add:

-   principled kernel birth;
-   kernel budgets;
-   structured residual statistics;
-   refinement triggered by persistent structured surprise;
-   kernel pruning/merging.

Test whether model capacity follows epistemic complexity.

------------------------------------------------------------------------

## 15. MARL-2 --- Erosion and Forgetting

Explore controlled forgetting:

-   decay kernels that cease to explain observations;
-   merge redundant kernels;
-   collapse unnecessary refinement;
-   retain rarely used but strongly supported knowledge;
-   distinguish absence of evidence from contradictory evidence.

The aim is a dynamic equilibrium of growth and erosion rather than
monotonically increasing model size.

------------------------------------------------------------------------

## 16. MARL-3 --- Local Charts

Replace the assumption that the learning domain is globally 3-D.

Investigate local projections/bases so high-dimensional exemplars can be
represented by low-dimensional predictive charts.

Questions include:

-   fixed versus learned local dimensionality;
-   PCA-like incremental bases;
-   random projections;
-   learned projections;
-   routing by distance, similarity or prediction responsibility;
-   overlap between charts;
-   chart birth and splitting.

This is expected to be the first major new architectural problem beyond
existing Loam machinery.

------------------------------------------------------------------------

## 17. MARL-4 --- Hierarchical Surprise

Allow surprise to propagate through the hierarchy.

A coarse region should explain what it can cheaply. Finer children
should exist only where the parent leaves structured residuals.

Inference may then become progressive:

``` text
coarse prediction
      |
 uncertainty/error estimate
      |
 sufficient? ---- yes ---> return
      |
      no
      |
 descend into finer chart
```

The same hierarchy therefore controls both **learning resolution** and
**inference cost**.

------------------------------------------------------------------------

## 18. MARL-5 --- Real ML Tasks

Only after the mechanics are understood should MARL be tested on
conventional datasets or embedding spaces.

Candidate progression:

1.  synthetic regression;
2.  synthetic classification;
3.  streaming/non-stationary classification;
4.  compact embedding-space prediction;
5.  continual learning with concept drift;
6.  associative / contextual memory tasks.

The purpose is not initially to beat transformers or MLPs on benchmark
accuracy. It is to establish whether MARL offers a qualitatively useful
combination of:

-   continuous learning;
-   bounded local updates;
-   low interference;
-   sparse computation;
-   adaptive capacity;
-   parallel learning;
-   stable concurrent inference;
-   interpretable spatial allocation of model effort.

------------------------------------------------------------------------

# Immediate Implementation Plan

## 19. Before-Bed Build

Keep tonight's experiment brutally small.

### A. Add a MARL experiment executable/test

Prefer an isolated experiment using existing Loam/RBF components rather
than modifying core abstractions prematurely.

### B. Define one scalar 3-D truth function

Something visually interesting but deterministic.

### C. Add online prediction

Evaluate the current local RBF field at an arbitrary point.

### D. Add one-exemplar learning

Adapt the existing RBF gradient machinery so a small number of optimizer
steps can be applied to the local kernels responsible for one exemplar.

### E. Add kernel birth

If the point has no useful support, seed a kernel there.

### F. Stream exemplars

Run perhaps:

``` text
1
10
100
1,000
10,000
100,000
```

observations and report error/cost at logarithmic checkpoints.

### G. Dump visualization data

At minimum produce a regular 2-D slice of:

``` text
x, y, truth, prediction, abs_error
```

for quick inspection/rendering.

------------------------------------------------------------------------

## 20. Questions MARL-0 Should Answer

By the end of the first run we want evidence for or against five
propositions:

1.  **Local RBF learning converges at all.**
2.  **A useful update touches only a tiny fraction of model state.**
3.  **Previously learned distant regions remain substantially
    undisturbed.**
4.  **The cost per learning event is low enough to contemplate
    continuous operation.**
5.  **The resulting error field looks like something Loam's existing
    adaptive machinery can exploit.**

If those are broadly true, MARL-1 is justified.

If they are not, the experiment is small enough that we will know *why*
without having built an ML cathedral first.

------------------------------------------------------------------------

## 21. Working Principles

1.  **Reuse Loam before generalizing Loam.**
2.  **Surprise drives work.**
3.  **Learning is local by default.**
4.  **Parallelism follows locality.**
5.  **Capacity grows only where residual structure demands it.**
6.  **Inference reads stable snapshots while learning builds the next.**
7.  **Do not confuse noise with complexity.**
8.  **Measure interference explicitly.**
9.  **Keep the local representation small enough that backprop is
    cheap.**
10. **Let experiments determine the eventual shape of the MARL brick.**

------------------------------------------------------------------------

## 22. One-Line Definition

> **MARL is a sparse hierarchy of local predictive fields whose topology
> and RBF geometry continuously deform in response to structured
> surprise.**
