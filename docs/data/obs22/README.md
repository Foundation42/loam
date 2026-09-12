# OBS-22 / G69 — preserved runs

**In progress. No finding is concluded here.** These are the verbatim logs
the phase has produced so far, kept because they are the record a later
interpretation has to answer to, and because several of them refuted the
interpretation that was current when they were taken.

| log | what it is |
|---|---|
| `g69.log` | The registered comparison, ~9 min 46 s. **Failed** on Q2. Four arms, two acquisition trajectories, frozen threshold 1.30274 from seed `0x0CA1`. |
| `g69b.log` | First localisation of the `schedule`/5678 blow-up: per-intervention RMS, populations, births, fitting error; and a three-way fork at the worst sleep. |
| `g69c.log` | The same with the acquisition comparison corrected (frozen model scored at completion time) and two further forks: `norefine` and `guarded`. |
| `g69e.log` | The same with the `relabel` oracle probe added, and per-fork instrumentation at the forked sleep. |

## What the logs establish, and what they refuted

The registered comparison **failed Q2** and **refuted Q6**: no intervention
policy tested beat `none` on either objective, and the trigger's cold-start
restraint held on one acquisition trajectory (0 crossings) and failed
completely on the other (11 917 above-threshold ticks from t = 83).

The localisation then killed three explanations in order, each of them mine:

- **repeated halving** — refuted by counting. Populations regrow fully
  between sleeps: 645→322→**727**, 727→363→**817**. There is no cumulative
  shrinkage. (This refutes cumulative shrinkage only, not every effect of
  compression.)
- **compression** — the full-population fork is *worse* than halving, so
  compression is not necessary for the failure.
- **acquisition damage** — an instrumentation artefact. The first
  acquisition spans the step change, so its before/after were scored against
  different worlds. With the pre-acquisition model frozen and scored at
  completion time, acquisition is neutral once and helpful twice.
- **historical labels** — refuted by the `relabel` oracle probe. With every
  label re-read from the completion-time world the refinement **still**
  diverges, 0.12298 → 0.19900 on replay loss. Historical labels are
  therefore **not necessary** for the failure. *They are not thereby shown
  to be harmless: relabelling changes kernel selection, the linear solution
  and the refinement's starting state, so the 6.72213 → 0.70931 difference
  flows through all of that and is not one instability scaled by ten.*

What remains is the **nonlinear refinement diverging** — replay RMS
0.13965 → 0.35844 at t = 82 096, with the held-out world at 6.72213
afterwards — and a replay-loss acceptance check preventing it entirely.
`guarded` and `norefine` agree to every printed digit, which confirms the
guard's restored candidate is the pre-refinement candidate.

**What none of this establishes:** that a descent which *does* descend on
replay reliably improves the current world. And `guarded` still loses to
`none` on this trajectory (0.09896 against 0.08441), so removing the
catastrophe does not make the schedule worth its cost.

**Nor is the oracle arm's current-world damage attributable.** Comparing
`relabel` against historical-label `norefine` varies labels *and* refinement
together. The missing arm is `relabel + norefine`.

Unexplained: the sleep that diverges is the one starting from the worst
replay fit (0.13965 against 0.08118 and 0.07449). Whether that is step size
against curvature, the model state, or something else is untested — and
**starting RMS is not a curvature measurement**, so a reduced-rate fork
would establish rate sensitivity at that checkpoint and nothing more.

## The detector

`G69 (c)`, `(d)` and `(e)` are cheap gates, not logs, and they carry the
rest of the phase:

> On these uninterrupted-learning trajectories, the move increases surprise
> and the detector ratio under both initialisations. Only one combination
> crosses the frozen threshold. Initialisation affects the ratio's level and
> response, making threshold crossings sensitive to its history.

Scope, because it is easy to lose: these sequences come from **uninterrupted
learning**, while G69's own trigger/5678 arm intervened at 16 384 — so they
share only the *prefix* with it. The alternative initialisation was judged
at the incumbent's frozen threshold, so it cannot be called better or worse
as a policy. And the response's decay across the traced window is measured,
not attributed.

`Options.guard` defaults false. A guarded policy is a subsequent experiment,
not a change to the registered one.
