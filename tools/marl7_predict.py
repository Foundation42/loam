#!/usr/bin/env python3
"""marl7_predict — MARL-7's gate numbers, before its runs.

Christian asked that erosion be split into two operations that had been
bundled: KERNEL DEATH (remove locally useless basis functions) and
UNREFINEMENT (remove a child level when the parent alone is sufficient
again). Two measurements decided which of them MARL-7 can be about, and
they were run before any mechanism was written.

  1. Do obsolete kernels self-identify? NO. After a large drift, pre-move
     child kernels now outside the band carry mean |w| 0.1219 — LARGER
     than the stationary control's off-band kernels at 0.0832, and smaller
     than the kernels born since the move at 0.1555. Weight does not
     separate obsolete from useful.

  2. Are they load-bearing? YES, and more so after drift. Silencing them:

         stationary    RMS 0.03082 → 0.04373   (1.42×)
         small drift       0.05018 → 0.07430   (1.48×)
         large drift       0.04861 → 0.07573   (1.56×)

So the corrective archaeology is NOT separable capacity sitting beside the
useful kind. It is a contamination INSIDE otherwise-useful kernels: the
same kernel fits the swell's fine structure and cancels the frozen
parent's stale contribution, and no deletion can take one without the
other. Deleting a correction while the thing it corrects remains is not a
repair.

Therefore MARL-7 is UNREFINEMENT ONLY, and kernel death is not the tool
for drift. The two must go together or not at all: drop the child level
and unfreeze the parent in the same act, so the stale error and its
correction leave together.
"""

MARL6 = {  # measured, sharpness ×2, drift at 200 000 — baselines, not thresholds
    "stationary": (0.03166, 0.07146, 4339, 0.974),
    "small":      (0.05203, 0.09281, 4339, 0.818),
    "large":      (0.04861, 0.08968, 4339, 0.607),
}
HYSTERESIS = (4339, 7883)   # child kernels before A→B→A, and after


def main():
    print("MARL-7 — predictions, written before the runs")
    print("=" * 70)

    print("\n0. The mechanism, and why it is safe by construction")
    print("   A region unrefines when its PARENT ERROR — the EWMA of")
    print("   |y − parent(x)| over routed exemplars — has grown well past what")
    print("   it was when the region was refined. That is the definition of the")
    print("   parent having stopped being a valid coarse level there.")
    print("   The act drops the child's kernels in that region, unfreezes the")
    print("   parent's, and returns the region to the parent's stream.")
    print("   MARL-6R's safety analysis says this is the SAFE half of erosion:")
    print("   under-basis-density is the catastrophe, and unrefinement removes")
    print("   a LEVEL while leaving the parent's density there untouched.")

    print("\n1. It must fire where the structure left, and nowhere else")
    print("   → MARL7_UNREFINE_PRECISION = 0.75 of unrefined regions must be")
    print("     ones the current band has left. Same floor and same reasoning")
    print("     as MARL2_PRECISION: a region beside the departure can be")
    print("     legitimately disturbed without the band having left it.")
    print("   → MARL7_STATIONARY_QUIET = 0 unrefinements when nothing moves.")
    print("     Absolute, and derivable: the parent's error in a refined region")
    print("     is what the child was created to absorb, and in a stationary")
    print("     world it does not grow — MARL-6 measured the stationary")
    print("     control's parent flat at 0.0715 across 100 000 exemplars.")

    print("\n2. It must actually repair, and the bar is MARL-6 without it")
    lo = MARL6["large"][0]
    print(f"   MARL-6's large drift recovers to {lo:.5f} with a parent stuck at")
    print(f"   {MARL6['large'][1]:.5f} — the parent contributes nothing to the repair")
    print("   because it is neither observing nor free to move. Unrefinement")
    print("   hands those regions back to a parent that learns them the way it")
    print("   learns any structure, and MARL-2 established the parent alone")
    print("   reaches about 0.07 on this target from scratch.")
    print("   → MARL7_RECOVERY = 0.9: total RMS after large drift, over")
    print("     MARL-6's. A tenth is a modest ask for handing the work back to")
    print("     a mechanism that is not frozen, and deliberately modest —")
    print("     unrefinement also throws away a level's worth of fitted")
    print("     capacity, and the transient may eat much of the gain.")

    print("\n3. It must stop the archaeology accumulating")
    b, a = HYSTERESIS
    print(f"   MARL-6's A → B → A left {a} child kernels from {b} — a factor of")
    print(f"   {a/b:.2f}, with worse accuracy than the state it returned to. If")
    print("   unrefinement works, the regions abandoned on the way out are")
    print("   collapsed rather than carried, and the return trip does not pay")
    print("   for them twice.")
    print(f"   → MARL7_HYSTERESIS_GROWTH = 1.4: child kernels after A → B → A")
    print(f"     over the count before, against MARL-6's {a/b:.2f}. Not 1.0 —")
    print("     the new world genuinely needs its own capacity.")

    print("\n4. Reported, not gated")
    print("   Whether a region that unrefines is later RE-refined, and how")
    print("   often. A cycle of refine → unrefine → refine is either healthy")
    print("   adaptation or a limit cycle, and one run cannot tell which.")
    print()


if __name__ == "__main__":
    main()
