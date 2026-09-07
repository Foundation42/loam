#!/usr/bin/env python3
"""marl14_predict — MARL-14's gate numbers, before its run.

Christian's idea, in his words: "after the MARL is built, you create
another MARL and sample from the first one and inject into the second one.
If you do it smartly it might be possible to significantly reduce the
number of kernels ... for many applications it doesn't have to be perfect,
an approximation is fine. And if we have the master copy, we can distill to
our hearts content."

It lands on two things MARL-13 measured a few hours ago, which is why it is
worth running rather than reasoning about.

**The teacher is NOISELESS.** MARL-13 found noise enters by three doors —
the weights, the geometry, and the topology — and that the third one, the
model birthing on noise, cannot be closed by any learning rate. A teacher's
output is a deterministic sum of gaussians. Sampling it closes all three at
once, for free, with no new mechanism.

**The teacher is UNLIMITED.** MARL-11 found the binding constraint is
EVIDENCE, and lost to a batch optimiser that could re-read its pool. A
teacher can be queried anywhere, any number of times. The student is the
first learner in this campaign that is not evidence-starved.

And one thing it must NOT be confused with. MARL-8 recycled a retiring
region's kernels into a new region and failed, concluding that "geometry is
cheap to acquire locally and worthless imported". Distillation imports NO
geometry. The student starts empty and discovers its own topology from a
cheap oracle. If it works, MARL-8's finding stands untouched; the two are
not in tension.
"""


def main():
    print("MARL-14 — predictions, written before the run")
    print("=" * 72)

    print("\n0. The scoring rule, and it is the whole of the method")
    print("   The student is scored against the TRUE field, never against")
    print("   its teacher. Scored against the teacher it would be measuring")
    print("   how well it copies a copy, which improves as both get worse.")
    print("   Every number below is RMS against the same 4 096-ray reference")
    print("   probes MARL-13 used.")

    print("\n1. Naive distillation: the same options, a clean teacher")
    print("   Births need surprise above θ AND no kernel already covering")
    print("   within the responsibility radius. The coverage half is purely")
    print("   geometric and identical for teacher and student, so most of")
    print("   the population should survive the copy. What should NOT")
    print("   survive is the noise-driven part: MARL-13 measured 9 923")
    print("   kernels at one ray a sample against 7 656 at sixteen for the")
    print("   same 60 000 samples, so ~20-30% of a noisy model's capacity is")
    print("   bought on noise and a clean teacher cannot sell it.")
    print("   → MARL14_FREE = 0.95, a CEILING on K(student)/K(teacher) at")
    print("     matched options. A modest free saving, attributed to the")
    print("     noise doors closing. If it comes in near 1.0 the noise")
    print("     births were not where MARL-13 said they were; if it comes in")
    print("     very low, the coverage rule is not what governs population")
    print("     and three phases have been misreading it.")

    print("\n2. THE LEVER: an approximation is allowed to be an approximation")
    print("   `threshold` gates learning events, and a birth needs one. With")
    print("   a NOISY field a high threshold is dangerous — you cannot tell a")
    print("   real residual from a sampling wobble, which is exactly the")
    print("   third door. With an EXACT teacher every residual above θ is")
    print("   real structure, so θ becomes a clean accuracy dial: the student")
    print("   stops buying kernels once it is within θ of its teacher.")
    print("   This is Christian's 'it doesn't have to be perfect' as a")
    print("   mechanism rather than a hope.")
    print("   → MARL14_TRADE = 1.5, a CEILING on the RMS cost of HALVING the")
    print("     population. Stated as a frontier rather than a point: find")
    print("     the θ that gets K(student) ≤ K(teacher)/2 and check the RMS")
    print("     has risen by no more than half again.")

    print("\n3. The other lever: a coarser basis")
    print("   σ_max = h/√CUTOFF with h = 1/regions, so halving `regions`")
    print("   doubles every kernel. Tiling a d-dimensional interesting set")
    print("   with balls of twice the radius needs 2^d fewer of them:")
    print(f"   {'regions':>8} {'σ (unit)':>10} {'volume 3-D':>12} {'shell 2-D':>11}")
    import math
    base = (1.0 / 6) / math.sqrt(32.0)
    for r in (6, 4, 3):
        s = (1.0 / r) / math.sqrt(32.0)
        print(f"   {r:>8} {s:>10.5f} {(s/base)**3:>11.1f}x {(s/base)**2:>10.1f}x")
    print("   A shell around geometry is nearly 2-D, so regions 6 → 3 should")
    print("   cost about a quarter of the population, not an eighth.")
    print("   → MARL14_COARSE = 3.0, a FLOOR on K(teacher)/K(student) at")
    print("     regions 3. Below the 4x the geometry predicts, because the")
    print("     shell has thickness and the clamp will not let a kernel")
    print("     exceed h on any axis.")

    print("\n4. Generation loss, and why it should be small")
    print("   A→B→C. The usual fear about distilling a distillation is that")
    print("   error compounds. It should compound LESS here, and for a")
    print("   structural reason: B is a sum of anisotropic gaussians, which")
    print("   is EXACTLY the student's hypothesis class. The truth is not.")
    print("   So A→B pays a representation cost and B→C pays almost none —")
    print("   the second student is fitting something it can represent")
    print("   perfectly, given enough kernels.")
    print("   → MARL14_GENERATION = 1.0, a CEILING on")
    print("     (RMS_C/RMS_B) ÷ (RMS_B/RMS_A): the second copy must cost no")
    print("     more than the first. If it costs more, the hypothesis-class")
    print("     argument is wrong and iterated distillation is a dead end.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL14_FREE       = 0.95  (ceiling, K_student/K_teacher, same options)")
    print("  MARL14_TRADE      = 1.5   (ceiling, RMS cost of halving the population)")
    print("  MARL14_COARSE     = 3.0   (floor, K_teacher/K_student at regions 3)")
    print("  MARL14_GENERATION = 1.0   (ceiling, the second copy over the first)")


if __name__ == "__main__":
    main()
