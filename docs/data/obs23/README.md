# OBS-23 / G70 — preserved runs

| log | what it is |
|---|---|
| `g70.log` | The registered comparison, 15 min 55 s, EXIT 0. Six arms, two acquisition trajectories, per-phase means and the error at all 52 checkpoints with the seeds kept apart. |

An earlier run of the same comparison produced **identical** figures for
every registered quantity (Q1 −0.00401, Q2 +0.03584, Q3 −0.02596, Q4 0.87983,
Q5 0) and is not preserved separately: it differed only in carrying a wrong
births column and no checkpoint trace, both of which this run fixes. The
agreement is a REPRODUCIBILITY check on identical seeds, not independent
replication: the evidence is still two acquisition trajectories.

## What it establishes

> At the tested timings, targeted revisiting improved trajectory error on
> both seeds. Adding consolidation worsened it, although revisiting reduced
> the penalty relative to consolidation alone. Delaying all three
> consolidations by 4096 observations increased error on both seeds, with
> strongly seed-dependent magnitude; the responsible intervention and
> mechanism remain unlocalised.

Astra's wording. `revisit` is the first policy in this campaign to beat
`none` — 0.08090 / 0.08607 against 0.08492 / 0.08828, about 4.7% and 2.5%.

**The claim is a policy contrast at the tested placements, not an attribution
of every OBS-22 controller's result to consolidation.** Revisiting alone
improved mean trajectory error; adding consolidation worsened it. OBS-22's
other arms differ in timing as well, and nothing here reaches them.

`both` reproduces OBS-22's `informed` arm to every digit per trajectory,
which validates **that arm's numerical continuity** and not the lattice; the
evidence for the other five paths is G70 (a)'s structural checks.

## What the phase means and traces add

**The aggregate hid a phase-level reversal.** `both` has the lowest observed
mean error in the step phase (0.07181) and the stationary stretch after it
(0.05788) and still loses over the full trajectory, its deficit accumulating
in the drift and tail. A measured variation in policy performance across
phases, with an open mechanism — it does not establish that gradual change is
what makes a consolidation hurt.

**The visible damage in the 5678 tail gap is late, not a first-window
effect — which does not exclude the earlier sleeps as contributors to the
state that failed.** The
arms are identical to the digit through t = 28 000; `sleep@t` separates at
30 000 and `sleep@t+r` at 36 000, the first checkpoint after each one's first
sleep. Then `sleep@t+r` runs 0.16067 → **0.92824** → 0.90681 across
t = 94 000–98 000, immediately after its third consolidation at 94 096, with
**zero guard rejections**.

That establishes that acceptance did not ensure a beneficial trajectory
policy. It does NOT establish a locally harmful descending refinement —
that needs same-world measurements immediately before and after the
operation, which this gate does not take. And *appears after* is not *caused
by*: the model feeding that sleep was shaped by the two before it.

## What may not be said from this log

- **C6 is not a window comparison.** It shifts all three placements; only the
  first pair is about stale-versus-fresh labels, and historical labels are
  not necessarily wrong where the worlds agree. It contrasts two complete
  *schedules*, and after the first differing sleep everything downstream
  differs.
- **A tail gap does not exonerate an early sleep.** An early intervention can
  act late; the aggregate simply cannot attribute.
- **C5 may not be read as "sleep uses repaired evidence better."** The
  targeting signatures show the second and third interventions of `revisit`
  and `both` aim at different places, so "sleep changes what gets revisited
  next" fits equally. The first intervention's targets are identical, and
  asserted.
- **Q4 is refuted, and the saving did not disappear** — 12% fewer final
  kernels and 7% lower checkpoint-mean, against **2.25× as many kernel-birth
  events** (1903 against 844) at EQUAL paid observation budgets — more
  topology rebuilding, not more acquisition. The compute is unpriced. The
  bound stands unstruck.
