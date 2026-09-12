# OBS-24 / G71 — preserved run

| log | what it is |
|---|---|
| `g71.log` | The fork, 2 min 15 s, EXIT 0. One prefix to t = 94 096, one consolidation, three continuations. Includes G71 (a)'s stubbed run above it. |

Two earlier runs of the same fork produced identical measurements. The first
failed on Q6's assertion, which is now reported rather than asserted, and
carried an un-netted births column. The second predated the interpretation
corrections below.

**Three identical runs on one seed establish REPRODUCIBILITY, not additional
replication.** The evidence is still one consolidation on one trajectory.

And the third run should not have happened: it was made to bring this log
into line with PROSE-ONLY edits, including edits to printed prose, which
CODEX's existing rule says does not justify a numerical run. The right
remedy was to compile-check the gate, keep the validated log, and annotate
the text-only delta.

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

**Both stages reduced historical replay RMS while increasing current-world
RMS** — the first by +0.11027, the refinement by a further +0.59486.

The first stage bundles **compression, kernel selection and the linear
refit**; this fork does not separate them. And 5.4x is a ratio of two RMS
increases, not a measure of field disagreement and not evidence of a shared
mechanism.

**The guard behaved exactly as specified** — the refinement did not raise
replay loss, so accepting it was correct. What this establishes is that
**replay non-increase is insufficient for current-world protection**, while
it remains useful against optimisation that worsens its own objective, which
is the OBS-22 failure it was built for.

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
- **A held-out split of the replay buffer would not be a world-aware rule.**
  It tests generalisation to held-out HISTORICAL evidence, and stale labels
  can approve the same harmful change. Held-out replay acceptance and
  current-world validation are separate questions.
- **Reproduction of OBS-23's arm is a TOLERANCE check**, 1e-5, not exact
  agreement: the recorded values were rounded to five decimals. Full
  precision is printed here so a later comparison can be exact.
- **Acceptance establishes non-increase**, not descent. That this refinement
  descended strictly is measured and reported, not inferred from the absence
  of a rejection.
