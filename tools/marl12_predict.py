#!/usr/bin/env python3
"""marl12_predict — MARL-12's gate numbers, before its run.

MARL-11 measured the campaign against `rbf.fit` on ONE channel: the vein's
blend, which is where a vein's geometry lives. `rbf.fit` fits NINE — the
blend and the eight material columns it multiplies — and the nine share
one centre and one shape. That sharing is the entire reason a packed set
is cheaper than a volume texture, and the campaign has never tested it,
because until this phase MARL's kernel carried a single weight.

So MARL-12 widens the kernel from `w: f32` to `w: [C]f32`, C comptime, and
asks the one question the widening makes askable:

    **What does sharing one geometry across nine channels cost, and what
    does it save?**

The refactor's own gate comes first and is not a threshold: at C = 1 every
number from G17 to G31 must be IDENTICAL, because nothing about the
arithmetic changed. That is checked by running the suite against HEAD and
diffing, and by G31 (a) still reading bit-for-bit equal.

Everything below is written before a single C = 9 run.
"""

import math

# ── What the widening changes, exactly ───────────────────────────────────
GEOM_FLOATS = 9  # centre (3), log-diagonal (3), off-diagonal (3)
RBF_CHANNELS = 9


def main():
    print("MARL-12 — predictions, written before the run")
    print("=" * 72)

    # ── 1. The population ───────────────────────────────────────────────
    print("\n1. Nine channels should cost the SAME NUMBER of kernels as one")
    print("   A birth needs two things: surprise above θ, and no existing")
    print("   kernel reading above `coverage` within the responsibility")
    print("   radius. The second is PURELY GEOMETRIC — it is a max over")
    print("   gaussians and knows nothing about channels — so nine channels")
    print("   cannot buy a birth that one channel would not have bought at")
    print("   the same place.")
    print("   What nine channels DO change is how often surprise clears θ:")
    print("   the magnitude is a max over channels, so it is never smaller")
    print("   than channel 0's alone, and more learning events mean more")
    print("   gradient steps, more centre drift, and a little more")
    print("   opportunity for a birth somewhere a kernel has moved away")
    print("   from.")
    print("   → MARL12_COUNT = 1.15, a CEILING on K(9)/K(1) at equal data.")
    print("   Above that, 'the geometry is paid for once' is false and a")
    print("   packed set is not the saving it is sold as.")

    # ── 2. The packing ──────────────────────────────────────────────────
    print("\n2. What the sharing saves, and it is arithmetic, not a threshold")
    print(f"   {'C':>3} {'packed':>8} {'separate':>10} {'ratio':>7}")
    for C in (1, 3, 9):
        packed = GEOM_FLOATS + C
        sep = C * (GEOM_FLOATS + 1)
        print(f"   {C:>3} {packed:>8} {sep:>10} {packed/sep:>7.2f}")
    print("   Nine channels in one kernel is 18 floats; nine independent")
    print("   scalar models at the same kernel count is 90. So the packed")
    print("   set is 5x smaller — and that is a fact about the layout, not")
    print("   a measurement, so the gate asserts it as EQUALITY of counts")
    print("   rather than as a bound. What is not free is the accuracy, and")
    print("   that is (3).")

    # ── 3. What the sharing costs ───────────────────────────────────────
    print("\n3. What the sharing costs: the blend's own error, C = 9 over C = 1")
    print("   Inside a single material every channel is A(x) times a")
    print("   constant, so the nine are exactly COLLINEAR and one Gaussian")
    print("   basis carries all of them with per-channel weights at no loss")
    print("   whatsoever. A fixture with one material could therefore only")
    print("   agree with the hypothesis, which is why the sheet carries TWO,")
    print("   split across x: the material changes while the geometry does")
    print("   not, so a kernel spanning the seam must put two different")
    print("   constants on one Gaussian.")
    sigma_v = ((1.0 / 6) / math.sqrt(32.0)) * 32.0
    seam_share = 2 * sigma_v / 32.0
    print(f"   A kernel is sigma = {sigma_v:.3f} wide in the volume's units, and the")
    print(f"   seam is one plane, so the compromised fraction is about")
    print(f"   2*sigma/extent = {seam_share:.3f} — six per cent of the sheet.")
    print("   And note WHERE it is compromised: channel 0 is the same")
    print("   function on both sides of the seam, so the blend itself is not")
    print("   in conflict at all. What moves is the GEOMETRY, because the")
    print("   centres and shapes now descend on the sum over nine channels")
    print("   of each weight's attribution rather than on one.")
    print("   → MARL12_SHARING = 1.25, a CEILING on blend-RMS(C=9) over")
    print("   blend-RMS(C=1) at matched capacity. Six per cent of kernels")
    print("   pulled off their best blend-only placement, on a 2-D structure")
    print("   whose error goes as N^(-1/2), is about 1.03; the ceiling is")
    print("   eight times that margin, because the geometry's descent is")
    print("   NOT confined to the seam and this is the first time anyone has")
    print("   looked.")

    # ── 4. Against the baseline ─────────────────────────────────────────
    print("\n4. Against rbf.fit at nine channels")
    print("   MARL-11 found the binding constraint is EVIDENCE and not")
    print("   placement, and nothing about the widening changes how much")
    print("   evidence a stream carries — the same exemplars arrive, each")
    print("   now carrying nine numbers instead of one. If anything the")
    print("   evidence per kernel goes UP, since one exemplar now constrains")
    print("   nine weights on the same geometry.")
    print("   → MARL12_ONLINE_COST = 2.0, a CEILING on D/B at nine channels,")
    print("   the same shape and the same value as MARL11_ONLINE_COST. Using")
    print("   the same number is the point: if the widening has not changed")
    print("   what binds, it should sit in the same place.")

    print("\n5. Not a threshold: the refactor is INERT")
    print("   `Marl(C)` is a comptime generic and `Marl(1)` must reproduce")
    print("   every number the campaign has recorded, bit for bit, because")
    print("   no arithmetic changed. Two things make that true rather than")
    print("   hoped for:")
    print("     - the channel magnitude is a MAX over channels, which at")
    print("       C = 1 is `@abs` exactly;")
    print("     - the geometry's attribution accumulates FROM channel 0")
    print("       rather than from a zero, because `0 + (-0.0)` is `+0.0`")
    print("       and a sign of zero there reaches `moveCentre`.")
    print("   Checked by diffing the whole suite's printed numbers against")
    print("   HEAD, not by a threshold.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL12_COUNT        = 1.15   (ceiling, K(9)/K(1))")
    print("  MARL12_SHARING      = 1.25   (ceiling, blend RMS at 9 over at 1)")
    print("  MARL12_ONLINE_COST  = 2.0    (ceiling, D/B at nine channels)")


if __name__ == "__main__":
    main()
