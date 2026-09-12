# OBS-25 / G72 — preserved run

| log | what it is |
|---|---|
| `g72.log` | The registered comparison, 2 min 9 s, EXIT 0. Includes G72 (a)'s stubbed run above it. |

An earlier run produced identical measurements and carried no verdict block;
the verdict lines and the two assertions for the questions that HELD were
added afterwards, which is a code change and not prose. Every measured value
is unchanged.

## What it establishes

> At this fork, none of the three available signals ranked the candidate set
> as the held-out probes did: each selected the linear candidate where the
> probes selected the parent. Current labels and no prior exposure were not
> sufficient — fresh evidence estimated the parent to within 0.3% while
> underestimating both consolidated candidates several-fold.

| family | parent | linear | refined | selects |
|---|---|---|---|---|
| DIAGNOSTIC world | **0.16446** | 0.27467 | 0.76761 | parent |
| held-out replay | 0.16952 | 0.14012 | 0.14145 | linear |
| recent window | 0.08019 | 0.06081 | 0.15614 | linear |
| fresh | 0.16393 | 0.08138 | 0.11028 | linear |

Q0 HELD (the reduced-fit candidate still harms). Q1 REFUTED, by 0.9%. Q2
HELD, 2.5677 against 1.0095. **Q3 REFUTED**, and it is the phase.

Eight draws of 256 on the frozen candidates: six select `linear`, two select
`refined`, none selects `parent`. Systematic at this V, not draw noise.

Continuations from 94 352, all trained on the same 256 already-paid
observations: parent 0.17569, linear 0.18404, refined 0.47338. **All three
signals avoided the catastrophic candidate and none selected the best one.**

## What may not be said from this log

- **No acceptance policy.** One consolidation, one trajectory, one parent,
  ONE statistic, and no false-alarm rate on consolidations that were fine.
  A selection either way shows what this minimum-RMS rule does on that
  evidence, never that no rule on it could discriminate.
- **The families are EVIDENCE SOURCES, not isolated effects.** Held-out
  against recent varies label age AND location sampling; recent against fresh
  varies prior learning exposure AND location sampling. Nothing here isolates
  label age, which would need matched locations.
- **The concentration hypothesis is UNTESTED.** That the damage sits where a
  256-point draw under-samples fits every number, and so does the candidates
  being wrong where the diagnostic probes happen to sit. Separating them
  needs the per-probe error distribution and a sweep of V.
- **These are not OBS-24's candidates.** They are fitted on a reduced buffer
  and none of OBS-24's figures is asserted here.
