#!/usr/bin/env python3
"""marl9_predict — MARL-9's gate numbers, before its runs.

MARL-8 closed reuse in its transplant form and left one question open, and
it is a FIXTURE question before it is an architecture question: every drift
this campaign has run has been the same shell translated. So when capacity
grows linearly with the number of moves, we cannot tell whether the model
is paying per CHANGE or per THING LEARNED — the two have been the same
number all along.

MARL-9 separates them. Two arms, same six moves, same exemplar budget:

    CYCLE — alternate between two worlds, A B A B A B. Six changes, two
            worlds' worth of distinct structure.
    WALK  — six genuinely different worlds. Six changes, six worlds'
            worth.

If capacity tracks CHANGES the two arms grow identically. If it tracks
DISTINCT STRUCTURE the cycling arm plateaus after the second world,
because it has seen everything it is being shown.

That is the whole experiment, and it needs no new mechanism at all.
"""

# Measured in MARL-6's hysteresis, used as a baseline and not a threshold.
HYST = (4339, 7883)


def main():
    print("MARL-9 — predictions, written before the runs")
    print("=" * 70)
    b, a = HYST
    print("\n0. What is already known, and it points one way")
    print(f"   MARL-6's single round trip A → B → A took {b} child kernels to")
    print(f"   {a} — a factor of {a/b:.2f} — and the return spike was the same size")
    print("   as the departure. Coming home was as expensive as leaving, and the")
    print("   old world's representation conferred no advantage on its own")
    print("   former world. One round trip is thin evidence; six is not.")

    print("\n1. The prediction, and the interesting outcome is its failure")
    print("   → MARL9_RECURRENCE = 0.9: child population after six moves,")
    print("     cycling over walking. At or above this the two arms are the")
    print("     same and capacity is paid PER CHANGE — the model is billed for")
    print("     the event, not for what it learned, which is the wrong")
    print("     currency and a much sharper statement of MARL-7's pathology")
    print("     than 'capacity is bought'.")
    print("   Derived from MARL-6's hysteresis, which is a two-move version of")
    print("   the cycling arm and showed no saving whatever.")
    print()
    print("   If it FAILS — if cycling is materially cheaper — then latent")
    print("   reuse exists, MARL-8's failure was about its mechanism rather")
    print("   than about the possibility, and the dictionary idea is worth")
    print("   building. That is the more interesting result and it is why the")
    print("   threshold is written in the direction that makes it visible.")

    print("\n2. Accuracy must be comparable, or the comparison is not one")
    print("   → MARL9_FAIR = 1.15: RMS of the cycling arm over the walking")
    print("     arm at the end. A cycling world is genuinely easier — it has")
    print("     half the distinct structure — so the cycling arm should if")
    print("     anything be MORE accurate. Well outside that band in either")
    print("     direction means the arms are not comparable and the population")
    print("     numbers cannot be read against each other.")

    print("\n3. Reported, not gated")
    print("   Whether the cycling arm's error at world A improves across its")
    print("   three visits. That is the closest thing this architecture has to")
    print("   'remembering', and one run on one fixture should not be allowed")
    print("   to settle it either way.")
    print()


if __name__ == "__main__":
    main()
