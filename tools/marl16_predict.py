#!/usr/bin/env python3
"""marl16_predict — MARL-16's gate numbers, before its run.

MARL-13 found the thing this phase fixes. A hard cutoff makes a Gaussian
decay to EXACTLY zero, so a constant non-zero background is not free: it
has to be held up by overlapping kernels everywhere it extends. Ambient
occlusion is ≈1 across the open majority of a cube, and MARL lost to a
dense grid 1.854× on it.

Every field this campaign has learned before that had a ZERO background —
the synthetic truth's quiet slab, the marble's matrix — so it never needed
the term `rbf.zig` has had from the day it was written: "the entry is the
BIAS: the matrix costs nothing, only the structure costs kernels."

MARL-13 measured the size of the hole by NEGATING the target — learning
1 − AO instead of AO, one line and no new code — and got 1.40× the accuracy
for 14% less capacity. But that is a trick that needs to be told what the
background is. A learned bias does it without being told.

## The part that is not free, and it is the campaign's own claim

`CUTOFF` gives EXACT locality: a learning event cannot disturb a distant
region, structurally, and G17 (c)/(d) measure it bitwise. **A global bias
breaks that** — every update to it moves the whole field at once.

So the bias is not merely an accuracy feature, it is a TRADE, and the
honest way to build it is to make the trade measurable. The bias is learned
as a RUNNING MEAN (step 1/n) rather than an EWMA, so its step decays and
exact locality is recovered in the limit; an EWMA would leave a permanent
floor under which no region is ever undisturbed. `rate_bias > 0` puts that
floor back deliberately, for a field that drifts.
"""


def main():
    print("MARL-16 — predictions, written before the run")
    print("=" * 72)

    print("\n1. What a learned bias should recover, and why NOT all of it")
    print("   MARL-13's inversion set the background to the value of the")
    print("   LARGEST FLAT REGION — open sky, where 1 − AO is zero. A")
    print("   least-squares bias does not converge there. It converges to")
    print("   the MEAN of whatever the kernels have not explained, which is")
    print("   the same thing only when one region dominates the query")
    print("   distribution.")
    print("   On the volume-uniform occlusion field, open sky is the")
    print("   majority but not overwhelmingly so, so the bias should land")
    print("   between the mean and the mode and recover MOST of the 1.40×.")
    print("   → MARL16_BIAS = 0.85, a CEILING on RMS(bias)/RMS(no bias) —")
    print("     at least a 1.18× improvement, against the 1.40× that being")
    print("     TOLD the background was worth. Set below the inversion's")
    print("     number on purpose: a gate at 0.714 would be claiming a")
    print("     learned constant matches a supplied one, and the")
    print("     least-squares argument above says it should not.")

    print("\n2. It must not COST capacity")
    print("   The bias removes work from the kernels; it cannot add any. A")
    print("   birth needs surprise above θ, and a converged bias makes the")
    print("   residual over the flat majority SMALLER, so fewer events clear")
    print("   θ there and fewer births follow.")
    print("   The one way it could go wrong is the warm-up: the bias starts")
    print("   at zero, so the first few hundred exemplars are surprised")
    print("   everywhere and may buy kernels before it converges. A running")
    print("   mean converges in the first handful — b = y exactly at n = 1 —")
    print("   which is why the step is 1/n and not a small constant.")
    print("   → MARL16_KERNELS = 1.0, a CEILING on K(bias)/K(no bias).")

    print("\n3. THE TRADE: what it costs in locality")
    print("   `CUTOFF` makes locality exact and G17 (c)/(d) measure it")
    print("   bitwise: a learning event cannot disturb a distant region")
    print("   because every kernel it does not touch contributes a HARD")
    print("   zero. A global bias is not local at all — one update moves")
    print("   every point in the domain by the same amount.")
    print("   Learned as a running mean, that amount is |e|/n, so it decays")
    print("   and exact locality is recovered in the limit:")
    print(f"   {'n':>10} {'step':>12} {'a residual of 0.3 moves the field by':>40}")
    for n in (10, 1000, 100_000, 1_000_000):
        print(f"   {n:>10} {1.0/n:>12.2e} {0.3/n:>40.2e}")
    print("   → MARL16_LOCALITY = 1.5, a CEILING on (the whole-field")
    print("     disturbance from one late event) × n / |residual|. One is")
    print("     what a pure running mean gives exactly; the slack is for the")
    print("     kernels' own contribution to the same event, which is local")
    print("     and is not what this number is about.")
    print("   The point is to state the trade rather than to hide it: MARL")
    print("   buys a background term and gives up EXACT locality for")
    print("   ASYMPTOTIC locality. An EWMA would give up both — its step")
    print("   never decays, so no region is ever undisturbed again — and")
    print("   that is what `rate_bias > 0` is for, knowingly, on a field")
    print("   that drifts.")

    print("\n4. Default OFF")
    print("   `Options.bias` defaults false so that every number from G17 to")
    print("   G35 is untouched, which matters more than usual: the suite is")
    print("   four minutes and is not being run on every edit.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL16_BIAS     = 0.85  (ceiling, RMS with bias over without)")
    print("  MARL16_KERNELS  = 1.0   (ceiling, kernels with bias over without)")
    print("  MARL16_LOCALITY = 1.5   (ceiling, disturbance × n / residual)")


if __name__ == "__main__":
    main()
