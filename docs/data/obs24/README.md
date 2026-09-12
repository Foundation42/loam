# OBS-24 / G71 — preserved run

| log | what it is |
|---|---|
| `g71.log` | The fork, 2 min 15 s, EXIT 0. One prefix to t = 94 096, one consolidation, three continuations. Includes G71 (a)'s stubbed run above it. |

An earlier run of the same fork produced identical measurements and failed on
Q6's assertion; Q6 is now reported rather than asserted and the births column
is netted to a common baseline. Nothing else differs.

## What it establishes

> At this consolidation, the refinement strictly lowered replay loss and
> raised same-world error more than threefold at the instant of adoption.
> Selection and the linear refit moved both measures the same way before it.
> Removing the refinement removed most of the damage; not consolidating
> removed all of it; and recovery was incomplete within the remaining
> horizon.

| point | replay | world |
|---|---|---|
| parent | 0.22300 | 0.16446 |
| linear | 0.12414 | 0.27473 |
| attempted / returned | 0.06259 | 0.86959 |

Replay is the selected buffer's **own historical labels**. World is held-out
probes against completion-time truth at t = 94 096, past `drift_hi` and
therefore stationary. Nothing is relabelled; there is no oracle in this fork.

**Both stages improve replay and damage the world** — the linear refit by
+0.11027, the refinement by a further +0.59486. That is why the acceptance
rule sees nothing: it reads the only measure that is improving.

## What may not be said from this log

- **Not "how often".** One consolidation, one trajectory, and the conclusion
  is CONDITIONAL ON THE PARENT the earlier sleeps produced. The first two
  sleeps are neither exonerated nor implicated: they built the state that
  fails.
- **Q3 and Q4's maxima are maxima over five checkpoints.** The model is
  unobserved for 2000 observations at a time; an excursion between them is
  not excluded.
- **Q6 is refuted and its shape matters more than its sign.** `linear` is far
  worse at the first checkpoint (0.27740 against 0.17629) and then recovers,
  ending marginally AHEAD of `skip` (0.14011 against 0.14958). A mean over
  five checkpoints scores an excursion and a recovery together.
- **Reproduction of OBS-23's arm is a TOLERANCE check**, 1e-5, not exact
  agreement: the recorded values were rounded to five decimals. Full
  precision is printed here so a later comparison can be exact.
- **Acceptance establishes non-increase**, not descent. That this refinement
  descended strictly is measured and reported, not inferred from the absence
  of a rejection.
