#!/usr/bin/env python3
"""marl8_predict — MARL-8's gate numbers, before its runs.

MARL-7 established the pathology precisely: accuracy is flat under repeated
drift, capacity grows linearly, and the accumulated capacity is LOAD-BEARING
so none of it can be deleted. The model never reuses anything — every world
costs a fresh allocation.

MARL-8 recycles at the refine/unrefine boundary. A retiring region's child
goes to a POOL instead of being destroyed; a refining region draws from the
pool, translated to its own origin, instead of starting empty. Positions and
shapes are carried and WEIGHTS ARE RESET, because MARL-1 established that
with topology fixed the weights are the convex fast part (NLMS) and geometry
is what deformation spends 2.15× buying. Carry the expensive thing; relearn
the cheap one in the new region's own terms against its own parent.

Note what this does NOT need: the optimiser. Reuse is an allocator
operation. The exact locality that stops a gradient walking a kernel across
the domain says nothing about an allocator moving one.
"""

MARL7 = {"start": 5233, "end_none": 10997, "end_unrefine": 10878,
         "moves": 6, "retirements": 15, "per_retirement": 70}


def main():
    print("MARL-8 — predictions, written before the runs")
    print("=" * 70)
    m = MARL7
    per_move = (m["end_none"] - m["start"]) / m["moves"]
    recycled = m["retirements"] / m["moves"] * m["per_retirement"]
    print("\n0. What recycling can possibly recover")
    print(f"   MARL-7's six moves bought {m['end_none'] - m['start']} kernels, {per_move:.0f} a move.")
    print(f"   Unrefinement retired {m['retirements']} regions over the same run — {m['retirements']/m['moves']:.1f} a move")
    print(f"   at about {m['per_retirement']} kernels each, so roughly {recycled:.0f} a move are")
    print(f"   available to borrow: {100*recycled/per_move:.0f}% of what is being bought.")
    print("   Recycling is BOUNDED BY THE RETIREMENT RATE, and that ceiling is")
    print("   the first thing the run has to be read against.")

    print("\n1. Growth must fall, and by about what is available")
    target = 0.85
    print(f"   → MARL8_GROWTH = {target}: child population after six moves, over")
    print("     the same run without recycling. Derived from the ceiling above:")
    print(f"     {100*recycled/per_move:.0f}% of new kernels could be borrowed, so a fifth off the")
    print("     growth is the ask, with room for transplants that do not take.")

    print("\n2. Accuracy must not pay for it")
    print("   A transplanted kernel arrives with weight zero, so at the moment of")
    print("   transplant the prediction is UNCHANGED — the mechanism cannot make")
    print("   things worse instantly, only slowly if the geometry is wrong for")
    print("   its new home.")
    print("   → MARL8_NO_REGRESSION = 1.05: RMS with recycling over RMS without,")
    print("     at the same exemplar count. Five percent is the noise band these")
    print("     runs have shown between seeds.")

    print("\n3. The borrowed capacity must actually be used")
    print("   Transplanted kernels start at w = 0. If they are in the wrong place")
    print("   for their new region they will stay near zero and the mechanism is")
    print("   a no-op dressed as a saving.")
    print("   → MARL8_ADOPTION = 0.5: transplanted kernels whose |w| has risen")
    print("     above a tenth of the child's mean |w|. Half is a floor: some")
    print("     fraction of any donor set lands where the new region has nothing")
    print("     for it to do.")

    print("\n4. And one interaction worth predicting explicitly")
    print("   MARL-7 found unrefinement does not repay, and had to run at a")
    print("   conservative factor to stay quiet in a still world. With recycling")
    print("   a spurious retirement is CHEAP — the capacity is banked, not")
    print("   destroyed — so aggressive unrefinement may become affordable.")
    print("   Reported, not gated: whether factor 1.5 with recycling beats")
    print("   factor 3 with it.")
    print()


if __name__ == "__main__":
    main()
