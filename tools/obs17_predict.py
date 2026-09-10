#!/usr/bin/env python3
"""obs17_predict — OBS-17's gate numbers, before its run.

Christian, on OBS-16:

    So far, rho has been changed by changing N, not k.  That matters
    because the actual policy is going to face: spectrum asks for k_s,
    evidence permits k_e, and then choose k = min(k_s, k_e).

    Hold replay ring fixed and sweep consolidation budget, so rho changes
    entirely through free-parameter count.  If the sign transition appears
    at the same approximate rho, then evidenceBudget() graduates from a
    descriptive fit to a real control law.

    The replay buffer does not merely determine whether sleep is possible;
    it places an upper bound on the model complexity that sleep may safely
    produce.

    python3 tools/obs17_predict.py
"""
print(__doc__.split("\n\n")[0]); print()
print("=" * 74)
print("OBS-17 — is rho a control law or a description?  PRE-REGISTERED")
print("=" * 74)
print("""
(1) THE COLLAPSE TEST

OBS-16 moved rho by RING SIZE at fixed budget.  If rho is the control
variable, moving it by BUDGET at fixed ring must give the same answer -- and
the two families must land on ONE CURVE when plotted against rho.

Two rings, budgets chosen to hit the same rho values:

    ring 2 048   rho = 2048/(10k)    k = 410, 205, 102, 51, 26
    ring 8 192   rho = 8192/(10k)    k = 410, 205, 102, 51
                                      (larger k exceeds the population)

    overlap in rho: 2, 4, 8  -- three shared points, reached from opposite
    directions.  In the 2 048 family a rho of 4 means k = 51; in the 8 192
    family it means k = 205.  Four times the model complexity at the same
    evidence ratio.

    PREDICTED  at every SHARED rho the two rings agree in SIGN
    PREDICTED  the zero crossing sits between rho 1 and rho 4 in both
               families, consistent with OBS-16's boundary near 2

    REFUTED IF the curves separate -- if a 51-kernel consolidation from
    2 048 points behaves differently from a 205-kernel one from 8 192 at
    the same rho, then rho is a description of one axis and not a law, and
    evidenceBudget() cannot be used to CHOOSE k.

(2) WHY THIS IS THE POLICY TEST AND OBS-16 WAS THE MECHANISM TEST

evidenceBudget returns a BUDGET.  Nothing so far has used it to pick one.
OBS-16 fixed k at 200 and showed the rule predicted each cell's sign, which
establishes that rho is the regime variable; it does not establish that
choosing k from N is safe, because k never moved.

    the spectrum proposes the budget; the evidence permits it

is a rule about k.  It has never been tested on k.

(3) THE ONE THING THAT COULD BREAK IT AND IS WORTH SAYING NOW

A smaller k is not merely a better-conditioned fit -- it is also a HARSHER
COMPRESSION.  Those pull in opposite directions, and rho only captures the
first.  So the honest possibility is that gain rises with rho up to a point
and then FALLS again as k becomes too small to represent the field at all,
which no evidence ratio can fix.

    PREDICTED  the high-rho end turns over: the largest rho in each family
               does NOT give the largest gain

    If it does turn over, rho is a floor and not an objective, and the
    policy is min(k_spectrum, k_evidence) exactly as Christian wrote it --
    never argmax over rho.

(4) NOT CLAIMED

One maturity (the mid model, which OBS-16 found has the most dynamic
range), one move, one fixture.  The population caps k, so the low-rho end
of the large-ring family is unreachable and the collapse is tested over
three shared points rather than six.
""")
print("=" * 74)
print("Frozen before the Zig was written.")
print("=" * 74)
