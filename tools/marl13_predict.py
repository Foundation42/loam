#!/usr/bin/env python3
"""marl13_predict — MARL-13's gate numbers, before its run.

Twelve phases and every field the campaign has learned was EXACT.
`truthOf` returns the answer; `rbf.target` returns the answer. Ambient
occlusion does not. It is (1/M)·Σ V(x, ωᵢ) over M sampled directions — a
Binomial(M, p)/M estimate with standard deviation √(p(1−p)/M), which is a
half at one ray and a sixteenth at sixty-four. G33 (a) measured the
fixture's estimator against that theory and it tracks it: σ 0.2114 against
0.2167 at four rays, 0.0541 against 0.0542 at sixty-four.

So this phase is about NOISE, and the occlusion cache is the honest place
to meet it — Christian named it on the morning MARL started, and MARL-11's
loss argued it is the regime MARL is actually for: a cache computes each
sample once, at whatever point the renderer asked about, and never sees it
again. A batch bake is not a slower option there, it is not an option.

The opponent is a DENSE GRID read by trilinear interpolation, at equal
bytes and equal ray budget. Equal bytes because memory is what a cache is
rationed by; equal rays because the rays are the expense being cached.
`rbf.zig` exists because Christian asked for a packed Gaussian set
"instead of the giant volume texture" — so the giant volume texture is who
it has to beat.
"""

import math

RATE_W = 0.5  # marl.Options.rate_w, the campaign's default


def misadjustment(mu):
    """NLMS steady-state excess MSE, as a multiple of the noise variance.

    The standard LMS result: a gradient step of size μ never settles on a
    noisy gradient, it hovers, and the hovering costs μ/(2−μ) of the noise
    variance no matter how much data arrives. This is the number the
    campaign has never had to care about, because until now the gradient
    was not noisy.
    """
    return mu / (2.0 - mu)


def main():
    print("MARL-13 — predictions, written before the run")
    print("=" * 72)

    # ── 1. The law ──────────────────────────────────────────────────────
    print("\n1. THE LAW: the learner has a noise floor, and it is the RATE's")
    print("   NLMS with step μ does not converge on noisy data, it hovers.")
    print("   The steady-state excess MSE is μ/(2−μ) times the measurement")
    print("   variance, WHATEVER the sample count — more data does not help,")
    print("   which is the opposite of everything MARL-11 found about this")
    print("   model and is why it needs saying out loud.")
    print(f"   {'rate_w':>8} {'μ/(2−μ)':>10} {'excess RMS':>12}")
    for mu in (0.5, 0.2, 0.1, 0.05, 0.02):
        m = misadjustment(mu)
        print(f"   {mu:>8.2f} {m:>10.4f} {math.sqrt(m):>11.3f}σ")
    print(f"   At the campaign's default of {RATE_W}, the floor is")
    print(f"   {math.sqrt(misadjustment(RATE_W)):.3f}σ — and σ at M rays is √(p(1−p)/M).")
    print()
    print("   So the model's error against the TRUE field decomposes as")
    print("       RMS² = bias² + μ/(2−μ) · V/M")
    print("   with V the field's mean p(1−p) and bias the representation")
    print("   error. That is LINEAR IN 1/M, which is a law rather than a")
    print("   threshold and is testable the way MARL-10's was.")
    print("   → MARL13_NOISE_LAW = 1.30, a ceiling on the fitted line's")
    print("     departure from the measured points across a fourfold sweep")
    print("     of M. Fitted, not assumed: the gate takes the two ends and")
    print("     checks the middle.")

    # ── 2. The rate that follows ────────────────────────────────────────
    print("\n2. The rate the law implies, derived and not swept")
    print("   Convergence needs (1−μ)^n small over the n samples a kernel")
    print("   sees; the floor wants μ small. With a budget of 8M rays at")
    print("   M = 16 that is 500 000 samples over ~1 500 kernels, so")
    print("   n ≈ 330 and:")
    print(f"   {'μ':>8} {'(1−μ)^330':>12} {'floor':>10}")
    for mu in (0.5, 0.2, 0.1, 0.05, 0.02, 0.01):
        print(f"   {mu:>8.2f} {(1-mu)**330:>12.2e} {math.sqrt(misadjustment(mu)):>9.3f}σ")
    print("   Anything above μ ≈ 0.02 has converged many times over, so the")
    print("   floor is the only term that still moves. μ = 0.05 costs")
    print(f"   {math.sqrt(misadjustment(0.05)):.3f}σ against {math.sqrt(misadjustment(0.5)):.3f}σ — a {math.sqrt(misadjustment(0.5))/math.sqrt(misadjustment(0.05)):.1f}x reduction — and still")
    print("   converges to within 1e-7 of its target.")
    print("   → MARL13_RATE = 2.0, a FLOOR on RMS(rate_w = 0.5) over")
    print("     RMS(rate_w = 0.05) at one ray a sample, where noise")
    print("     dominates everything else. Theory says 3.6; the floor is")
    print("     two, because the bias term does not shrink with the rate")
    print("     and puts a ceiling on how much of the 3.6 can show.")
    print("   This is MARL-12's √C again in shape: a default that was")
    print("   correct on the data the campaign happened to have, and wrong")
    print("   the moment the data changed character.")

    # ── 3. The budget question a renderer actually asks ─────────────────
    print("\n3. At a FIXED ray budget, how many rays a sample?")
    print("   R rays total, M a sample, R/M samples. Large M buys clean")
    print("   samples and few of them; small M buys noisy samples and many.")
    print("   The floor falls as 1/√M and the coverage falls as M, so there")
    print("   is an interior optimum and it is not at either end.")
    print("   → MARL13_INTERIOR = 1, asserted as a RELATION and not a")
    print("     number: the best M in a sweep of {1, 4, 16, 64, 256} is")
    print("     strictly inside it. If the best is M = 1 the floor does not")
    print("     bind and section 1 is wrong; if it is M = 256 then coverage")
    print("     is free and the campaign's whole evidence story is wrong.")

    # ── 4. The headline ─────────────────────────────────────────────────
    print("\n4. THE HEADLINE: a learned sparse field against a giant volume texture")
    print("   Equal bytes and equal rays. A kernel is 10 floats; a grid cell")
    print("   is one, so K kernels buy a grid of (10K)^(1/3) a side:")
    print(f"   {'kernels':>9} {'KiB':>8} {'grid':>7} {'cells':>9} {'rays/cell at 8M':>17}")
    for K in (500, 1500, 4000):
        b = K * 10 * 4
        g = int((b / 4) ** (1 / 3))
        print(f"   {K:>9} {b/1024:>8.1f} {g:>6}³ {g**3:>9} {8_000_000//(g**3):>17}")
    print()
    print("   The case FOR the grid, and it is stronger than it looks: at")
    print("   1 500 kernels the grid gets 24³ cells and ~578 rays each, so")
    print(f"   its own noise is only {math.sqrt(0.25/578):.3f} and it is limited by")
    print("   RESOLUTION rather than by noise. It also never has to work out")
    print("   where to look.")
    print("   The case FOR MARL: the grid spends its cells UNIFORMLY, and")
    print("   ambient occlusion is ~1 over the open majority of the cube and")
    print("   detailed only near geometry — which is the quiet slab of §8")
    print("   arriving in a third field. And MARL can put many samples")
    print("   through one kernel and average them; a grid cell gets one shot")
    print("   at its own centre and cannot.")
    print("   → MARL13_TEXTURE = 1.0, a CEILING on RMS(MARL)/RMS(grid) at")
    print("     equal bytes and equal rays, with MARL run at the rate")
    print("     section 2 derives. Pre-registered at parity, as MARL-11's")
    print("     headline was and for the same reason: it is the number that")
    print("     can embarrass the campaign, and a comfortable margin would")
    print("     stop it being able to.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL13_NOISE_LAW = 1.30   (ceiling, the 1/M line's departure)")
    print("  MARL13_RATE      = 2.0    (floor, RMS at 0.5 over RMS at 0.05)")
    print("  MARL13_TEXTURE   = 1.0    (ceiling, MARL over the grid)")
    print("  MARL13_INTERIOR  — a relation: the best M is strictly interior")


if __name__ == "__main__":
    main()
