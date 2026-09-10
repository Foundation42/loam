#!/usr/bin/env python3
"""obs16_predict — OBS-16's gate numbers, before its run.

Christian, on OBS-15:

    The key variable is now not age but IDENTIFIABILITY OF THE CONSOLIDATED
    PARAMETERISATION UNDER REPLAY:  rho = N_replay / N_free_params_kept

    The spectrum proposes the budget; the evidence permits it.

        k_keep <= N_replay / (rho_min * p)

    Do not ask a compressed model to remember more structure than its
    replay evidence can identify.

and the experiment: a 2-D grid rather than another 1-D sweep, because
maturity was never refuted in general — it was NON-DISCRIMINATING under an
evidence-starved fit, and any effect it had was buried.

    python3 tools/obs16_predict.py
"""
print(__doc__.split("\n\n")[0]); print()
print("=" * 74)
print("OBS-16 — does maturity matter once rho is not pathological?")
print("PRE-REGISTERED, before the run")
print("=" * 74)
print("""
(1) THE GRID, AND WHY THE BUDGET IS HELD FIXED

                low rho (0.5)   adequate (2.0)   high (8.0)
    young  (2k wake)
    mid    (20k)
    settled(80k)

k_keep is FIXED AT 200 in every cell, so the ring is sized by Christian's
own rule -- N_replay = rho * p * k_keep with p = 10 -- and rho is the only
thing that moves along that axis. Letting the budget follow the population
would change the conditioning and the compression ratio together, which is
the confound OBS-15 fell into from the other side.

    rho 0.5 -> 1 000 points     rho 2.0 -> 4 000     rho 8.0 -> 16 000

(2) MATURITY, MEASURED SO THAT IT ACTUALLY VARIES

OBS-15's readiness saturated: R64 read .98-.999 across the whole sweep, so
it could not have discriminated anything. Kernels accumulate updates fast --
about ninety are touched per event -- so a threshold of 64 is met almost at
once.

Two measures reported instead, both of which should vary:

    R1024   readiness at a threshold near the settled mean update count
    fresh   the share of CONTRIBUTION resting on kernels born since the
            world moved, from `born_at`

(3) THE REGISTERED PREDICTIONS

    PREDICTED  rho dominates: within every maturity row, gain rises with
               rho, and the rho = 0.5 column is negative throughout
               (OBS-15 measured -.56 at 0.53 points per parameter)

    PREDICTED (agent)      maturity is an INTERACTION, not a main effect:
               the spread of gain ACROSS maturities is smaller at rho = 8
               than at rho = 0.5.  Consolidation with ample evidence can
               repair a young population -- it does not merely select, it
               REFINES, and refinement is what fixes a badly placed kernel.

    PREDICTED (Christian)  maturity still matters at adequate rho

    The agent has lost the last three of these and is not taking the
    contrarian side for its own sake: the mechanism above is why. If the
    spread does NOT shrink, refinement cannot repair youth and
    effective-age inheritance moves back up the causal order, which is
    exactly what Christian's fourth item is for.

(4) THE RULE, AS CODE

`evidenceBudget(n_replay, rho_min, p)` returns the largest k the evidence
permits.  The phase's deliverable is not a number but that function and the
sentence it enforces.

    PREDICTED  a cell whose k exceeds its evidence budget at rho_min = 2
               has negative gain; one comfortably inside it does not

(5) NOT CLAIMED

One move, one fixture, one compression ratio. rho is varied by ring size at
fixed budget, never by budget at fixed ring, so nothing here says what
happens when the SPECTRUM asks for more than the evidence permits -- that is
the rule's actual use case and it needs the budget to move.
""")
print("=" * 74)
print("Frozen before the Zig was written.")
print("=" * 74)
