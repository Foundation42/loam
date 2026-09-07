#!/usr/bin/env python3
"""marl_predict — the numbers MARL-0's gates assert, computed BEFORE the run.

`g13_predict.py`'s shape, and for the same reason: a threshold a gate reads
must come from somewhere other than the first result, or the gate is a
recording of what happened rather than a test of what should. This is a
SECOND PROGRAM. It reimplements the truth field from `src/marl.zig`'s
constants and nothing else — no loam, no learner — so that if the two ever
disagree about what the target is, one of them is wrong and it says so.

    python3 tools/marl_predict.py

Everything printed here is written into `src/thresholds.zig` as a PROPOSED
value with the derivation beside it. The measured results go in the ledger,
never into this file.
"""

import math

# ── the truth, transcribed from src/marl.zig's Truth ──────────────────
SHELL_C = (0.30, 0.62, 0.46)
SHELL_R = 0.20
SHELL_W = 0.025
SHELL_A = 0.9
SWELL_A = 0.35
WINDOW_LO = 0.55
WINDOW_HI = 0.70
QUIET_X = 0.90
TAU = 2 * math.pi


def window(x):
    if x <= WINDOW_LO:
        return 1.0
    if x >= WINDOW_HI:
        return 0.0
    u = (x - WINDOW_LO) / (WINDOW_HI - WINDOW_LO)
    return 0.5 * (1 + math.cos(math.pi * u))


def swell(p):
    return (SWELL_A
            * math.sin(TAU * (0.9 * p[0] + 0.13))
            * math.cos(TAU * (0.7 * p[1] - 0.21))
            * math.sin(TAU * (0.6 * p[2] + 0.37)))


def shell(p):
    r = math.dist(p, SHELL_C)
    t = (r - SHELL_R) / SHELL_W
    if t * t > 16:
        return 0.0
    return SHELL_A * math.exp(-t * t)


def truth(p):
    return window(p[0]) * swell(p) + shell(p)


# ── the variance split ────────────────────────────────────────────────
# An empty model predicts zero everywhere, so its mean square error IS the
# truth's own mean square. What the gate's gain must not be able to buy is
# "learned the easy half": if either part alone were worth the threshold,
# a learner that never resolved the shell could pass.

def variance_split(n=400_000, seed=12345):
    rs = seed
    def rnd():
        nonlocal rs
        rs = (rs * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        return ((rs >> 40) & 0xFFFFFF) / 16777216.0
    tot = sw = sh = cross = 0.0
    for _ in range(n):
        p = (rnd(), rnd(), rnd())
        a = window(p[0]) * swell(p)
        b = shell(p)
        tot += (a + b) ** 2
        sw += a * a
        sh += b * b
        cross += 2 * a * b
    return tot / n, sw / n, sh / n, cross / n


# ── volumes, by the same Monte Carlo ──────────────────────────────────
def volumes(n=400_000, seed=999):
    rs = seed
    def rnd():
        nonlocal rs
        rs = (rs * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        return ((rs >> 40) & 0xFFFFFF) / 16777216.0
    band = quiet = 0
    for _ in range(n):
        p = (rnd(), rnd(), rnd())
        if abs(math.dist(p, SHELL_C) - SHELL_R) < 2 * SHELL_W:
            band += 1
        if p[0] > QUIET_X:
            quiet += 1
    return band / n, quiet / n


CUTOFF = 32.0
CUTOFF_R = math.sqrt(CUTOFF)
B1, B2 = 0.9, 0.999


def main():
    print("MARL-0 — predictions, written before the run")
    print("=" * 68)

    ms, sw, sh, cross = variance_split()
    rms0 = math.sqrt(ms)
    print("\n1. The empty model's held-out RMS, and what half of it each part is")
    print(f"   mean square of the truth      {ms:.6f}   (RMS {rms0:.4f})")
    print(f"     the windowed swell           {sw:.6f}   {100*sw/ms:5.1f}%")
    print(f"     the shell                    {sh:.6f}   {100*sh/ms:5.1f}%")
    print(f"     cross term                   {cross:+.6f}   {100*cross/ms:5.1f}%")
    g_swell = math.sqrt(ms / (ms - sw)) if ms > sw else float("inf")
    g_shell = math.sqrt(ms / (ms - sh)) if ms > sh else float("inf")
    print(f"   gain from learning the SWELL perfectly and the shell not at all: {g_swell:.2f}")
    print(f"   gain from learning the SHELL perfectly and the swell not at all: {g_shell:.2f}")
    gate = 2.0
    frac = 1 - 1 / gate**2
    print(f"   → a gate at gain {gate:.0f} needs {100*frac:.0f}% of the variance removed,")
    print(f"     which neither part alone can supply. MARL0_RMS_GAIN = {gate:.0f}")

    band, quiet = volumes()
    print("\n2. Where capacity should go")
    print(f"   shell band  (|r−R| < 2W)      volume {band:.5f}")
    print(f"   quiet slab  (x > {QUIET_X})        volume {quiet:.5f}   truth ≡ 0 there")
    print("   The asymmetry, not the value: a shell birth is driven by an")
    print("   amplitude-0.9 ridge at every exemplar that lands on it; a quiet")
    print("   birth needs a leakage cascade — each generation's residual is the")
    print("   previous generation's Gaussian tail — to stay above the surprise")
    print("   threshold across a gap wider than a kernel's reach. A decade is a")
    print("   FLOOR with headroom, not an estimate. MARL0_CAPACITY_RATIO = 10")

    print("\n3. Locality — how many kernels one exemplar can touch")
    for cov in (0.35,):
        r_cov = math.sqrt(-2 * math.log(cov))
        ratio = CUTOFF_R / r_cov
        print(f"   coverage {cov}: a birth is refused once some kernel reads above it,")
        print(f"     i.e. once a kernel sits within r_cov = {r_cov:.4f} Mahalanobis widths.")
        print(f"     Kernels therefore pack at about one per ball of that radius, while")
        print(f"     each is non-zero out to r_cut = {CUTOFF_R:.4f}. The count overlapping")
        print(f"     any point is the volume ratio: (r_cut/r_cov)³ = {ratio**3:.1f}")
    print(f"   → MARL0_MAX_TOUCHED = 120 (twice the estimate: descent widens kernels")
    print(f"     past their birth width, and the packing estimate ignores overlap)")
    print(f"   → MARL0_MAX_TOUCHED_FRACTION = 0.05 of the model, for §20's")
    print(f"     proposition 2 — 'a tiny fraction of model state'")

    print("\n4. Interference — the radius beyond which a learning event changes")
    print("   NOTHING, bitwise")
    print("   AMENDED after the first run, and recorded in thresholds.zig: what")
    print("   follows was derived for Adam, which turned out to be the wrong")
    print("   optimiser per-exemplar. An NLMS step has no a-priori bound, so the")
    print("   model carries an explicit trust region and the bound is now")
    print("   h·(2 + steps·trust) = 0.5000 at the defaults. The Adam derivation")
    print("   is kept below because Adam is kept, as an instrument.")
    print("   A touched kernel's cutoff box reaches at most h, so if it covers x")
    print("   its centre is within h of x; its support is then within 2h of x. A")
    print("   step displaces the centre by at most Δ = steps · rate · K, with")
    kk = (1 - B1) / math.sqrt(1 - B2)
    print(f"   K = (1−β₁)/√(1−β₂) = {kk:.4f} bounding Adam's |m̂|/√v̂. A birth places")
    print("   a kernel AT x with reach ≤ h. So nothing outside 2h + Δ can move.")
    print(f"   {'regions':>9} {'h':>8} {'2h':>8} {'Δ(3,0.02)':>10} {'bound':>8}")
    for reg in (4, 6, 8):
        h = 1 / reg
        d = 3 * 0.02 * kk
        print(f"   {reg:>9} {h:>8.4f} {2*h:>8.4f} {d:>10.4f} {2*h+d:>8.4f}")
    print("   This is the PROVABLE bound and it is loose; the radius actually")
    print("   observed is the finding, and belongs in the ledger, not here.")

    print("\n5. What is NOT gated")
    print("   Cost per event. The gate asserts counts and PRINTS nanoseconds with")
    print("   the build mode named — G5's rule, because a timing is a property of")
    print("   the machine and a count is a property of the model.")
    print()


if __name__ == "__main__":
    main()
