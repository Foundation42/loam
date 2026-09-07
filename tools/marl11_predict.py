#!/usr/bin/env python3
"""marl11_predict — MARL-11's gate numbers, before its run.

Ten phases and every comparison in them was MARL against MARL. `rbf.fit`
is the first thing to measure against that this campaign did not write:
the same anisotropic Gaussian, the same CUTOFF, the same evaluator, fitted
by BATCH ADAM to a real material field, gated since before MARL existed.

But it does not start level. `rbf.fit` carries two ORACLES that MARL has
no equivalent of:

    the seed  — centres are placed ON vein voxels, so every kernel starts
                where the structure is;
    the pool  — half of every batch is drawn FROM vein voxels, so a field
                that is a few per cent vein is sampled as though it were
                half.

Both are hand-built versions of exactly what MARL-3 and MARL-4 spent two
phases discovering it could not do for itself: MARL-3 found capacity
concentration is bounded by EVIDENCE concentration, and MARL-4 found
biasing the stream is the only lever that moves it — from 1.65 to 2.50,
where the oracle here is worth 1/f.

So the comparison is a 2x2, one variable a cell:

                       uniform seed+pool     vein-biased (oracle)
    rbf   batch Adam         B                      A
    MARL  online NLMS        D                      C

A/B is what the oracle is worth to a batch optimiser. D/B is the question
this phase exists to ask: BIRTH-FROM-SURPRISE against SEED-THEN-DESCENT,
with neither side told where the structure is.

This program designs the gate's fixture, measures its geometry on the same
grid the Zig will build, and freezes the four numbers from that geometry
and from the campaign's own measured constants. The fixture is mirrored
term for term in `marbleFixture` (src/marble.zig).
"""

import math

# ── The campaign's constants, not this program's ─────────────────────────
CUTOFF_R = math.sqrt(32.0)  # marl.CUTOFF_R
REGIONS = 6  # marl.Options.regions
COVERAGE = 0.35  # marl.Options.coverage
THRESHOLD = 0.02  # marl.Options.threshold
MARL4_BEST_CONCENTRATION = 2.50  # MARL-4's best, on the synthetic truth

# ── The fixture ──────────────────────────────────────────────────────────
# One warped sheet vein through a cube. Extent is a POWER OF TWO so the
# unit-cube-to-volume rescale (mu' = E*mu, L' = L/E) is exact in f32 and
# a MARL model IS an rbf.Set, bit for bit, rather than nearly one.
RES = 32
EXTENT = 32.0
VEIN = 0.72  # the blend's softness; MARBLE_VEIN/40 * EXTENT, the marble's own ratio
HALF_THICK = 0.90
WARP_AMP = 2.2
WARP_FREQ = 2.0 * math.pi / EXTENT


def phi(p):
    """Signed insideness of the sheet: positive inside the vein.

    A plane through the cube's middle, normal +z, warped by one period of
    a product of sines in x and y — a sheet rather than a slab, which is
    what makes an ellipsoid worth more than a sphere here.
    """
    x, y, z = p
    mid = EXTENT * 0.5
    surf = mid + WARP_AMP * math.sin(WARP_FREQ * x) * math.cos(WARP_FREQ * y)
    return HALF_THICK - abs(z - surf)


def vein_blend(f, vein):
    """bark.veinBlend, term for term."""
    t = min(1.0, max(0.0, (f + vein) / (2.0 * vein)))
    return t * t * (3.0 - 2.0 * t)


def measure():
    """Volume fractions on the fixture's own grid."""
    cell = EXTENT / RES
    n_elig = 0  # blend > THRESHOLD: where an empty model is surprised at all
    n_band = 0  # 0 < blend < 1: the soft edge, where the structure lives
    n_full = 0  # blend == 1: solidly inside
    total = RES ** 3
    for k in range(RES):
        for j in range(RES):
            for i in range(RES):
                p = ((i + 0.5) * cell, (j + 0.5) * cell, (k + 0.5) * cell)
                a = vein_blend(phi(p), VEIN)
                if a > THRESHOLD:
                    n_elig += 1
                if 0.0 < a < 1.0:
                    n_band += 1
                if a >= 1.0:
                    n_full += 1
    return n_elig / total, n_band / total, n_full / total


def main():
    sigma = (1.0 / REGIONS) / CUTOFF_R  # a newborn's width, unit-cube
    sigma_v = sigma * EXTENT  # ... and in the volume's units
    r_cov = math.sqrt(-2.0 * math.log(COVERAGE))  # useful out to here
    f_elig, f_band, f_full = measure()

    print("MARL-11 — predictions, written before the run")
    print("=" * 72)

    print("\n0. The fixture, measured on its own grid")
    print(f"   {RES}^3 over an extent of {EXTENT:g} (a power of two: the rescale is exact)")
    print(f"   one warped sheet, half-thickness {HALF_THICK:g}, blend softness {VEIN:g}")
    print(f"   birth-eligible (blend > {THRESHOLD})   {f_elig:.4f} of the cube")
    print(f"   the soft band (0 < blend < 1)     {f_band:.4f}")
    print(f"   solidly inside (blend = 1)        {f_full:.4f}")
    print(f"   a newborn kernel is sigma = {sigma:.5f} of the domain = {sigma_v:.3f} in volume")
    print(f"   units, and useful (reads > {COVERAGE}) out to {r_cov:.3f} sigma = {r_cov*sigma_v:.3f}.")
    print(f"   Against the vein's half-thickness of {HALF_THICK:g} that is {sigma_v/HALF_THICK:.2f}x — a")
    print("   newborn is about as wide as the structure is thick, which is the")
    print("   marble's own proportion (sigma 1.18 against a band of 0.9 at the")
    print("   defaults) and is why descent has to NARROW kernels here rather than")
    print("   merely place them.")

    # ── 1. Concentration ────────────────────────────────────────────────
    # A birth needs surprise above THRESHOLD. In the matrix the target is
    # exactly zero and an empty model predicts exactly zero, so there is
    # no learning event and no birth: MARL's quiet slab, arriving on a
    # real field. What DOES leak capacity outward is the model's own tail
    # — a newborn carries the residual as its weight, so a kernel of
    # weight w reads above THRESHOLD out to sqrt(2 ln(w/THRESHOLD)) sigma,
    # and cancelling that costs kernels on the matrix side of the edge.
    w_typ = 0.5  # a newborn's weight is the residual it was born on
    r_leak = math.sqrt(2.0 * math.log(w_typ / THRESHOLD))
    # The eligible slab is the band plus that leak on each side.
    half_elig = HALF_THICK + 0.83 * VEIN  # blend > THRESHOLD at t ~ 0.084
    half_spend = half_elig + r_leak * sigma_v
    ceiling = 1.0 / f_elig
    predicted = ceiling * half_elig / half_spend
    print("\n1. Where the capacity goes")
    print(f"   The matrix is EXACTLY zero and an empty model predicts EXACTLY zero,")
    print(f"   so surprise there is 0 <= {THRESHOLD} and nothing is born. The ceiling on")
    print(f"   concentration is therefore 1/f = {ceiling:.2f}, not the 1 of a uniform")
    print("   allocator.")
    print(f"   Against that: a newborn's own tail reads above the threshold out to")
    print(f"   {r_leak:.2f} sigma = {r_leak*sigma_v:.3f}, so the spent slab is half-width")
    print(f"   {half_spend:.3f} where the eligible one is {half_elig:.3f}.")
    print(f"   → concentration ~ {ceiling:.2f} x {half_elig:.3f}/{half_spend:.3f} = {predicted:.2f}")
    floor = max(MARL4_BEST_CONCENTRATION, round(predicted * 0.75, 1))
    print(f"   MARL11_CONCENTRATION = {floor:.1f} — a floor, at 75% of that, and never")
    print(f"   below MARL-4's best of {MARL4_BEST_CONCENTRATION} on the synthetic truth. Below MARL-4's")
    print("   number the phase would be claiming a real field is HARDER to place")
    print("   capacity on than the one the mechanism was designed against.")

    # ── 2. What the oracle is worth ─────────────────────────────────────
    # rbf.fit seeds a FIXED N. Seeded uniformly, a kernel lands in the
    # matrix with probability 1 - f_elig, and it is not merely useless
    # there: beyond CUTOFF_R sigma the gaussian is a HARD zero, so its
    # gradient is exactly zero and Adam can never move it. It is dead on
    # arrival. Only kernels seeded within reach of the sheet can learn.
    sigma_seed = VEIN  # rbf seeds logDiag = -log(vein)
    reach_seed = CUTOFF_R * sigma_seed
    half_live = half_elig + reach_seed
    f_live = min(1.0, f_elig * half_live / half_elig)
    print("\n2. What the seed oracle is worth to rbf")
    print(f"   rbf seeds at sigma = vein = {sigma_seed:g}, so a kernel reaches {reach_seed:.2f}.")
    print(f"   Seeded UNIFORMLY, only those within that of the sheet see any")
    print(f"   gradient at all — beyond the cutoff the gaussian is a hard zero and")
    print(f"   Adam can never move a centre that has never been touched.")
    print(f"   Live fraction {f_live:.3f}, so arm B has ~{1/f_live:.1f}x fewer effective kernels")
    print(f"   than arm A at the same N.")
    # RMS of a radial-basis fit falls about as N^(-1/d) for a d-dimensional
    # structure; a sheet is 2-D, so halving effective N costs sqrt(2).
    worth = math.sqrt(1.0 / f_live)
    print(f"   A 2-D structure fitted by N kernels has error ~ N^(-1/2), so")
    print(f"   B/A ~ sqrt({1/f_live:.1f}) = {worth:.2f}.")
    oracle = round(max(1.5, worth * 0.6), 1)
    print(f"   MARL11_ORACLE_WORTH = {oracle:.1f} — a floor at 60% of that. It has to be")
    print("   a floor and not an estimate: what this number is FOR is making the")
    print("   headline comparison honest, and it fails loudly if the oracle turns")
    print("   out not to matter, in which case arms C and D are the same test.")

    # ── 3. The headline ─────────────────────────────────────────────────
    print("\n3. The headline: D/B, discovery against seeding")
    print("   Neither side is told where the structure is. rbf places N kernels")
    print("   uniformly and descends; MARL places none and births where it is")
    print("   surprised. The campaign's own findings say MARL should WIN this:")
    print("     MARL-3: capacity concentration is bounded by evidence")
    print("             concentration — and surprise IS evidence, so a birth")
    print("             cannot land where the field is already right;")
    print("     MARL-1: deformation buys 2.15x AFTER the topology is found, and")
    print("             a dead kernel in the matrix never gets to spend it.")
    print("   Against MARL: it sees each exemplar once, where rbf sees a 32k pool")
    print("   sixty-odd times with a global optimiser and full second-moment")
    print("   information. MARL-6R priced that: a sixth of the evidence cost 2%")
    print("   of the accuracy (G24, 0.980x for 0.184x the work), so evidence is")
    print("   cheap on the margin and placement is not.")
    print("   MARL11_DISCOVERY = 1.0 — a CEILING on D/B. MARL, with no oracle,")
    print("   must match or beat batch Adam with no oracle at matched kernel")
    print("   count. This is the one number that can embarrass the campaign, and")
    print("   it is pre-registered at parity rather than at a comfortable margin")
    print("   precisely so that it can.")

    # ── 4. The price of being online ────────────────────────────────────
    print("\n4. C/A: the price of being online, oracle held equal")
    print("   Both sides get the vein-biased stream; the difference is one pass")
    print("   of local NLMS against 2000 batches of global Adam. MARL-0 measured")
    print("   Adam as WRONG per exemplar (RMS rose 0.131 -> 0.151 over 200k), but")
    print("   this is Adam in the regime it was designed for, so that finding")
    print("   does not transfer and MARL should be expected to lose.")
    print("   MARL11_ONLINE_COST = 2.0 — a CEILING on C/A. Losing by more than")
    print("   2x to a batch optimiser given the same evidence would say the")
    print("   online learner is not a competitive fitter, only a cheap one, and")
    print("   that is worth knowing before an irradiance cache is built on it.")

    print("\n5. Not a threshold: the conversion")
    print(f"   With an extent of {EXTENT:g}, mu' = E*mu and L' = L/E are exact scalings")
    print("   in f32, and (q/E - mu) == (q - E*mu)/E exactly, because rounding a")
    print("   difference commutes with scaling by a power of two. So a MARL model")
    print("   converted to an rbf.Set must read BIT-IDENTICALLY through")
    print("   rbf.Set.eval to what marl.Model.predictAll reads on the unit cube.")
    print("   Gated as equality, with no tolerance: the claim being made is that")
    print("   the online learner's output IS an rbf set, not that it is close to")
    print("   one, and an epsilon would let the two drift until a renderer that")
    print("   loaded one showed something else.")

    print("\n" + "=" * 72)
    print("POST HOC — added after the run, and labelled so it cannot be")
    print("mistaken for a prediction.")
    print("""
   D/B came in at 1.95 and the headline was refuted. The reasoning above
   was not wrong about its parts — concentration 4.17 against arm B's 1.33
   says surprise-driven birth places capacity three times better than
   blind seeding, exactly as claimed. It was wrong that placement was the
   binding constraint, which is an assumption ten phases of placement work
   made it very easy to hold without noticing it was an assumption.

   G31 (c) is the diagnostic, and what it asserts is DIRECTION with no
   magnitude, precisely because it is post hoc. It rests on MARL-6R's
   prior finding that under-evidence is a smooth gradient and not a
   cliff: if the loss were representational, more of the same stream
   would not help and the RMS would flatten; if it is evidence, the RMS
   falls while the CONCENTRATION — a geometric property of where a birth
   is allowed to land — stays put. Measured over a 64-fold stream:

        32 768   RMS 0.14255   conc 4.17   1 583 kernels
       131 072   RMS 0.09237   conc 3.63   2 403
       524 288   RMS 0.06492   conc 3.61   2 928
     2 097 152   RMS 0.05145   conc 3.75   3 285

   The RMS crosses arm B (0.0732) between the second and third rows and
   arm A (0.0546) by the fourth. So the online learner is not a worse
   fitter than batch Adam; it is a hungrier one, and it buys kernels
   rather than passes to get there.

   What this does NOT license is moving MARL11_DISCOVERY. The equal-data
   protocol is what makes the 2x2 a comparison, and a threshold that gets
   relaxed until the result clears it measures nothing at all. It stays
   at 1.0, refuted, for Christian to strike.
""")
    print("=" * 72)
    print("Frozen for src/thresholds.zig:")
    print(f"  MARL11_CONCENTRATION = {floor:.1f}   (floor, arm D)")
    print(f"  MARL11_ORACLE_WORTH  = {oracle:.1f}   (floor, B/A)")
    print(f"  MARL11_DISCOVERY     = 1.0   (ceiling, D/B)")
    print(f"  MARL11_ONLINE_COST   = 2.0   (ceiling, C/A)")


if __name__ == "__main__":
    main()
