#!/usr/bin/env python3
"""marl15_predict — MARL-15's gate numbers, before its run.

Every byte count this campaign has quoted is `kernels × PARAMS × 4`, and
every grid it has been compared against is f32 too. So the comparisons are
FAIR but both sides are uncompressed, and MARL-14's headline — a distilled
model beating a dense grid 0.878 at a quarter of the memory — is a claim
about a representation nobody would ship.

It matters because the two sides do not quantize alike.

A GRID quantizes almost for free. Occlusion is a value in [0, 1]; eight
bits gives a step of 1/256 against an RMS of 0.16, so it is a straight 4x
saving that costs essentially nothing. That is the baseline getting
stronger for free.

An RBF SET does not. Its ten floats have wildly different sensitivities,
and one of them — the weight — sits in a sum where neighbouring kernels
CANCEL, which is where quantization error amplifies.

This program derives the per-field sensitivities, allocates bits from
them, and predicts what that does to MARL-14's position.
"""

import math

# The coarse distilled student of MARL-14, which is what a production
# build would actually ship.
REGIONS = 3
CUTOFF_R = math.sqrt(32.0)
SIGMA = (1.0 / REGIONS) / CUTOFF_R  # 0.0589 of the domain
RMS_F32 = 0.16309  # the distilled student's own error, MARL-14
N_OVER = 30.0  # kernels contributing at a point, order of magnitude


def main():
    print("MARL-15 — predictions, written before the run")
    print("=" * 72)
    print(f"\n  σ = {SIGMA:.5f} of the domain, RMS(f32) = {RMS_F32}, ~{N_OVER:.0f} kernels overlap")
    print("  Rounding is independent per kernel, so contributions add in")
    print(f"  quadrature: a √{N_OVER:.0f} = {math.sqrt(N_OVER):.1f}× multiplier on every term below.")

    # A quantization error of Δ, uniform, has rms Δ/√12.
    def rms_step(bits, span):
        return (span / (2 ** bits)) / math.sqrt(12)

    print("\n1. The CENTRE is the sensitive one, and σ is why")
    print("   ∂/∂μ of w·exp(−½r²) peaks at r = 1, where r·e^(−r²/2) = 0.6065.")
    print("   So a displacement ε costs about 0.6065·|w|·ε/σ — and σ is a")
    print(f"   seventeenth of the domain, so an error measured against the")
    print("   DOMAIN is amplified seventeenfold before it reaches the field.")
    print(f"   {'bits/axis':>10} {'step':>10} {'error':>10}")
    for b in (8, 10, 12, 16):
        e = math.sqrt(3 * N_OVER) * 0.6065 * rms_step(b, 1.0) / SIGMA
        print(f"   {b:>10} {1/2**b:>10.2e} {e:>10.4f}")
    print("   Twelve bits an axis is the knee; sixteen is comfortable.")

    print("\n2. The LOG-WIDTH, over the clamp's own range")
    print("   A relative width error δ changes the kernel by w·r²·e^(−r²/2)·δ,")
    print("   which peaks at r = √2 with value 2/e = 0.736. The clamp spans")
    print("   roughly four nats from h down to σ_min.")
    print(f"   {'bits':>10} {'error':>10}")
    for b in (6, 8, 10, 12):
        e = math.sqrt(3 * N_OVER) * 0.736 * rms_step(b, 4.0)
        print(f"   {b:>10} {e:>10.4f}")
    print("   Ten bits. Higher than it looks it should be, because the")
    print("   clamp's range is wide and the sensitivity is not small.")

    print("\n3. The WEIGHT, and it is the one with the cancellation risk")
    print("   Directly additive: δw·g, with g up to 1. Its span is the set's")
    print("   own measured range, which the gate reads rather than assumes.")
    print(f"   {'bits':>10} {'span 2':>10} {'span 8':>10}")
    for b in (8, 10, 12, 16):
        print(f"   {b:>10} {math.sqrt(N_OVER)*rms_step(b,2.0):>10.4f} {math.sqrt(N_OVER)*rms_step(b,8.0):>10.4f}")
    print("   Ten bits at a span of two; twelve if the weights have spread.")
    print("   The campaign has seen mean |w| of 13–17 in MARL-1's divergent")
    print("   regime, so the span is a property to MEASURE and not to guess.")

    print("\n4. The allocation, and what it saves")
    allocs = [
        ("f32, as everything has been measured so far", 32, 32, 32, 32),
        ("16 / 10 / 10 / 12", 16, 10, 10, 12),
        ("12 / 8 / 8 / 10", 12, 8, 8, 10),
        ("10 / 6 / 6 / 8", 10, 6, 6, 8),
    ]
    print(f"   {'allocation':>44} {'bits/k':>8} {'bytes/k':>9} {'saving':>8}")
    for name, mu, ld, off, w in allocs:
        bits = 3 * mu + 3 * ld + 3 * off + w
        print(f"   {name:>44} {bits:>8} {bits/8:>9.1f} {320/bits:>7.2f}x")
    print("   → MARL15_BITS = 1.05, a CEILING on RMS(quantized)/RMS(f32) at")
    print("     the 16/10/10/12 allocation — 120 bits, 15 bytes, a 2.7x")
    print("     saving. If a kernel cannot survive fifteen bytes the packed")
    print("     set is not a shippable representation and MARL-14's memory")
    print("     claim needs restating in f32 terms only.")

    print("\n5. THE HEADLINE, and it is expected to be close")
    print("   MARL-14: the distilled student scored 0.16309 at 31.8 KiB")
    print("   against a 20³ grid's 0.18580 at 31.3 — a ratio of 0.878.")
    print("   Quantize both and the grid gains MORE:")
    kern = 814
    b_marl = kern * 120 / 8
    print(f"     MARL   {kern} kernels × 120 bits = {b_marl/1024:.1f} KiB")
    for gb in (8,):
        cells = int(b_marl / (gb / 8))
        res = round(cells ** (1 / 3))
        gain = res / 20.0
        print(f"     grid   {gb} bits over the same {b_marl/1024:.1f} KiB = {cells} cells = {res}³")
        print(f"            {res}/20 = {gain:.2f}× the resolution, so its error falls to")
        print(f"            about {0.18580/gain:.5f} if error tracks cell size")
        pred = (RMS_F32 * 1.05) / (0.18580 / gain)
        print(f"     → predicted ratio ≈ {pred:.2f}")
    print("   → MARL15_HEADLINE = 1.15, a CEILING. NOT parity, and that is")
    print("     deliberate: the derivation above says quantization roughly")
    print("     CANCELS the distilled model's advantage and lands near 1.06,")
    print("     so a gate at parity would be pre-registering a refutation")
    print("     rather than testing anything. What 1.15 tests is whether an")
    print("     RBF set quantizes SUBSTANTIALLY worse than the sensitivity")
    print("     analysis says — which is the thing that would actually be")
    print("     news, and the thing that would make the packed set")
    print("     unshippable.")
    print("   The honest sentence either way: MARL-14's 0.878 is an f32")
    print("   number, and under quantization the two representations are")
    print("   expected to be about level on this field.")

    print("\n6. What is deliberately NOT built")
    print("   No bit-packed container. Quantization is applied by ROUNDING")
    print("   the trained parameters to the representable grid and scoring")
    print("   normally, with the byte count computed from the allocation.")
    print("   A packer would change no number here; it would only move them")
    print("   from one array to another, and it is the accuracy cost and the")
    print("   bit count that are under test.")

    # ── The extension, written after the first run and before the second ──
    print("\n" + "=" * 72)
    print("EXTENSION — region-relative centres. Written AFTER the sweep above")
    print("ran and BEFORE this one did, and labelled so the two cannot be")
    print("confused.")
    print("""
   The ablation found the centre is the only expensive field — 0.01872 of
   excess RMS at eight bits, against 0.00412 for the log-width, 0.00312 for
   the off-diagonal and EXACTLY ZERO for the weight. And its cost is a SPAN
   choice rather than a sensitivity: it is quantized over the whole extent,
   32 units, giving a step of 0.125 against a σ of 1.885 — 0.066σ.

   But a kernel's centre is inside its OWNING REGION by definition; that is
   what ownership means, and the clamp keeps it there. So the span is not
   the cube, it is the region: extent/regions. And `marble.setOf` already
   writes kernels in `predictAll`'s order — region by region, then each
   region's own list — so the grouping a decoder needs is already in the
   file. All that has to be stored is a count per region.
""")
    for r in (3, 6):
        import math as _m
        print(f"   regions = {r}: span falls {r}x, so the centre's error falls {r}x at the")
        print(f"   same bit count, or {_m.log2(r):.2f} bits an axis are free at the same error")
        print(f"   ({3*_m.log2(r):.1f} bits a kernel). The cost is a u16 count per region:")
        print(f"   {r**3} regions = {r**3*2} bytes, against 814 kernels x 54 bits = {814*54//8} bytes.")
    print()
    print("   → MARL15_RELATIVE = 2.5, a FLOOR on the centre's 8-bit excess")
    print("     ABSOLUTE over the same excess RELATIVE, at regions = 3. The")
    print("     geometry says 3.0; the floor is 2.5 because the excess is a")
    print("     small difference of two nearby RMS values and does not")
    print("     measure to three figures.")
    print()
    print("   And what it buys, propagated through the ablation's own numbers.")
    print("   At 6/5/5/6 — 54 bits, which measured 1.086 ABSOLUTE and so")
    print("   failed the ceiling:")
    import math as _m2
    e_mu = 0.01872 * 4 / 3.0   # two bits coarser is 4x; relative is 3x cheaper
    e_ld = 0.00412 * 8         # five bits is three coarser than eight
    e_of = 0.00312 * 8
    tot = _m2.sqrt(e_mu**2 + e_ld**2 + e_of**2)
    rms = _m2.sqrt(RMS_F32**2 + tot**2)
    print(f"     centre {e_mu:.4f}, log-width {e_ld:.4f}, off-diagonal {e_of:.4f}, weight 0")
    print(f"     total excess {tot:.4f} → RMS {rms:.5f} → {rms/RMS_F32:.3f}")
    print("   → MARL15_RBITS = 1.05, the SAME ceiling as MARL15_BITS, applied")
    print("     at 54 bits with relative centres — 6.75 bytes a kernel, a")
    print("     5.9x saving. The point of the number is that a bit budget")
    print("     which FAILED absolute must PASS relative, or the change has")
    print("     bought nothing worth the count table.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL15_BITS     = 1.05  (ceiling, RMS quantized over f32 at 120 bits)")
    print("  MARL15_HEADLINE = 1.15  (ceiling, MARL over grid, both quantized)")


if __name__ == "__main__":
    main()
