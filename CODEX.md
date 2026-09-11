# Codex: recover here first

Christian asked for this file on 2026-09-09. It supersedes CLAUDE.md for
Codex's workflow and recovery. Read the relevant source or ledger section
when needed; do not load CLAUDE.md or entire campaign books by default.
User instructions take precedence. Keep this file short and current.

## Testing and commits

- Default: run nothing. Run only the gate whose contract a change affects.
- Normal commit check: smoke plus the affected targeted gates. Full suite
  roughly once per active day, or for a specific broad regression concern;
  NOT every commit. Never per edit/recovery or just for reassurance.
  This supersedes the earlier commit-boundary full-suite rule.
- Reuse a passing check of unchanged code. Documentation changes do not
  justify restarting a running suite or repeating one that passed. **This
  covers PRINT STRINGS and comments too** — compilation validates a format
  string; a twelve-minute gate does not need to. Keep the validated
  numerical log, and note the text-only delta beside it. OBS-19 spent a
  12:43 run on two print strings before this was written down.
- **Never cancel a run by matching command text.** Use the tool's session
  handle or a captured PID. `pkill -f` matches the pattern against the
  wrapper's own command line, so a kill issued from a command that mentions
  the filter kills itself — and if the kill is chained ahead of an edit and
  a run, the edit silently never lands and the run executes against
  unmodified source. That happened TWICE in one OBS-19 session, once
  producing a full ten-minute run of a gate that was not the gate on disk.
  Check the output of an edit before trusting a run that follows it.
- `zig build test -Dtest-filter='G47 (c)'` selects a gate; ReleaseSafe is
  the default. `zig build test` runs the smoke set; `zig build test-full`
  explicitly runs all regression/research gates. No daily job is installed.
- In this sandbox append `--cache-dir /tmp/marl-codex-cache
  --global-cache-dir /tmp/marl-codex-global` (on the same command line).
- Zig build can buffer all test output until completion. An empty log
  does not mean a hung process. Resume an existing tool session; do not
  launch a duplicate test run after compaction.
- Christian authorized committing this investigation. Review the diff,
  include its lab notes, commit; no push was requested.

## Scientific contract

- Pre-register a new comparison in tools/*_predict.py and thresholds.zig
  before measuring it. Thresholds are Christian's: never retune to pass.
- Preserve historical gate configurations and core defaults. New options
  must not silently spill into old experiments.
- Separate representation error, learner error, transport error and
  integration error with controls. Compare fields on identical probes;
  subtracting two RMS errors does not measure field disagreement.
- Headline measurements use f32 masters; quantization is a separate arm.
- Distinguish fixed evidence from fixed compute; report query cost as
  well as fitting cost. A fixture result is not a universal solver rule.

## Targeted recovery map

Use `rg -n 'topic' file` then read the surrounding section.

| Need | Read |
|---|---|
| Replay policy and consolidation | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-11..19; src/consolidate.zig, G58-G66 |
| Complexity and fresh windows | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-4; src/observational_windows.zig, G51; docs/data/obs4 |
| Adaptive inverse births | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-3; src/adaptive_inferred.zig, G50; docs/data/obs3 |
| Hidden potential inference | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-2; src/inferred.zig, G49 |
| Observational state inference | docs/MARL_OBSERVATIONAL_CAMPAIGN.md; src/observed.zig, G48 |
| Current field experiments | docs/MARL_ALGEBRA_CAMPAIGN.md, sections 5b/5c |
| Latest measured decisions | tail of docs/implementation-notes.md |
| MARL learner, support, gather | src/marl.zig; G17 and G45 |
| Gaussian primitive contracts | src/rbf.zig; G17 pins |
| Derivatives, affine warp, transport | src/field.zig; G44 |
| Selective transport diagnostic | src/field.zig; G46 |
| Deferred materialisation | src/deferred.zig; G47 |
| Frozen predictions | tools/alg1_predict.py, width_predict.py, alg2_predict.py |
| Gate registration and execution | src/loam.zig, build.zig |
| Earlier MARL research | docs/MARL_CAMPAIGN.md, search by phase |
| loam snapshots/fronts/seams | CLAUDE.md relevant section, src/tests.zig |

## Current research state

Completed baseline commit: b53ea5a, field algebra and G44–G46.
- Fixed gather correctness for transformed kernels exceeding local reach.
- Decoupled support width from ownership via opt-in support_edges.
  Wider kernels help the smooth blob; sharp features trade accuracy for
  population. Defaults unchanged.
- Local-Jacobian push error dominates original fit error on the swirl.
  Backtracing into an unchanged model is the useful reference.
- G46 selective pullback beats random selection, but weight-only ranking
  matches the local-error estimator here. No measured scheduler speedup.

Completed ALG-2 / G47 (d7870d0), recorded in lab book section 5c.
- Immutable checkpoint teacher; cheap pushed view and accurate pullback
  reads between fresh fits. Never train on the cheap view or analytic truth.
- 40-step swirl, seeds 7/19/41, 240k total fitting examples: mean cheap
  error/constant for k=1/2/5/10/20/40 is
  .4794/.2438/.1341/.0989/.1097/.1960. k10 wins at each seed.
- Final-only scoring prefers k40; pullback reads prefer fewer fits but
  pay increasing integration cost. No universal cadence established.
- 60k PER FIT control: k1 uses 2.4M examples, mean .2278; k10 uses 240k,
  mean .0989. Starvation explains some, not all, repeated-fit loss.
- Targeted G47(a/b/c) passed. A second full run was cancelled at
  Christian's request: the earlier full suite passed at b53ea5a today.
  Do not restart it. Normal commit validation now uses the smoke set,
  which passed 12/12 tests in 18.85 s including compilation (~3 s run).
- Remaining research: long-horizon behaviour, conservation, support
  discovery and actual scheduling costs. These are future beats.

Completed OBS-1 / G48 (ea22c84): fixed-flow observations update the source
MARL at the preimage. Corrected/prior RMS .12553; wrong coordinates grow
~900 kernels, but spatial footprint confounds mismatch interpretation.

Completed OBS-2 / G49 (038b0ea); docs/MARL_OBSERVATIONAL_CAMPAIGN.md.
Frozen 9-kernel potential inferred from trajectory endpoints. Correct/prior
held-out RMS .003332, correct/wrong-dynamics .002397, with matched work.
972 f64 sensitivity checks: raw large-step FD prediction refuted in four
cases; smaller steps pass. Recorded Richardson amendment passes unchanged
tolerances, worst relative error 2.65e-6. Missing-position-feedback mutation
fails 936 checks. Targeted G49(a/b) passed. Headline recovery uses f32.
Completed OBS-3 / G50 (6ca9260), restricted candidate activation, not core MARL
births or moving geometry. 41 shared candidates, active cap25, 4 arms.
Correct stays K9; wrong adds16 at every seed, then requests4 more. Wrong
adaptive/frozen RMS: train .3432, heldout1.8230. Prior coverage at every
birth centre >=.8133. Histories and spatial records in docs/data/obs3.
All arms share RHS/search counts; active coefficient updates differ.
No death policy, hence no birth-death churn claim.
Shared sensitivities live in src/trajectory.zig; G49 stays unchanged.

Completed OBS-4 / G51, rich truth + repeated/fresh windows, 48 arms.
Rich correct adaptive/frozen evaluation RMS .108451 (repeated), .015934
(fresh); incoming fresh-window RMS ratio .087542 before learning. Both
rich fresh dynamics finish K25, but wrong/correct repeat requests66/0;
correct/wrong final eval .007673. All five prereg comparisons held.
Crucial controls: simple correct dynamics can also birth and worsen eval;
one correct rich repeated-data seed has13 repeated requests. K/pressure
alone is NOT a mismatch classifier. Diagnostic G51(c): from an accurate
step800 simple fit, continued updates cause7/8/10 false birth requests,
holding the state causes0. No main thresholds/rates retuned. This is an
inspection-derived mechanism diagnostic, not a validated stopping policy.
Records in docs/data/obs4 include sensors, window-pre-update scores,
evaluation history, coverage, requests and diagnostic. G51(a/b/c) passed
separately; use smoke at commit, not the full suite.

Latest: OBS-19 / G66, WINDOWED error replay (2026-09-11). OBS-18's queue item,
pre-registered as a TRADEOFF: can error's locations and the ring's labels be
had together? Not with an EXPONENTIAL window, and why is the phase. A hard
cutoff is a different object and is UNTESTED — no impossibility established.

A recency window costs LITTLE to keep. Let the A-Res weight grow with the
observation index, w_eff = w*exp(t/tau); the key is ln(u)*exp(-t/tau)/w, fixed
at admission and still correct later because exp(T/tau) is common to every
slot. No expiry queue, no periodic scan, no second heap — a result about
EXPONENTIAL WEIGHTING, NOT a costing of a hard sliding window; it adds
arithmetic and `Replay.t` is 8 bytes a slot (64 KiB at N=8192, diagnostics
only). tau is a PRICE, not a cutoff: dt = tau*ln(w2/w1) observations of age
per factor of weight, and tau is an E-FOLDING time (half-life tau*ln2 = 2839).
tau = N/2 is DERIVED — the soft edge is ~4tau wide and must span the fresh
pool, or the window IS a ring whatever weight it carries.

Held as a LOG MAGNITUDE, K = -log(-ln u) + log w + t/tau. Written directly,
exp(-t/tau) underflows past t/tau = 745 and an A-Res key is NEGATIVE, so the
factor gives -0.0, which sorts ABOVE every live key: the oldest exemplars
become unevictable. The rule does not break, it INVERTS. Clamping the exponent
was rejected BEFORE any measurement — it trades inversion for SATURATION, the
window becoming a uniform reservoir over the clamped tail. G66 (a) is the
mutation and is in the SMOKE SET; the clamped form fails it at 700*tau.
`Replay.t` is written by every rule and read by none — `admit` decides from
the index in hand — so it cannot move a selection; tau = 0 is the incumbent
arithmetic and G61/G65 reproduce.

TWO SLEEPS IN ONE LIFE, M/N = 0.5 and 2.0, because OBS-18 slept 20,000 clear
of the move and its ring was clean BY THE FIXTURE'S TIMING. Nine arms: a 2x2
of measure x window, each cell replicated, plus the ring — which needs no
replicate and that is not an omission, it is deterministic in the stream and
its spread is zero by construction.

AT M/N = 0.5 EVERY ARM LOSES. 4096 fresh observations for 8192 slots means at
least half of EVERY buffer is pre-move, (N-M)/N = .500, the ring exactly on
the floor; the un-slept model at .10270 beats its best child at .12352. A
sibling of OBS-17's k_min — there is a t_min. But the MECHANISM is NOT
isolated: the model is also less converged at the early offset (before .10270
against .08002), so staleness and immaturity move together and the floor
argument only says no rule can AVOID staleness, not that staleness does the
damage. Retention
goes the other way: error replay takes A from the control's .12504 to .05224,
and the ring is WORST at retention, worse than not sleeping.

AT M/N = 2.0 THE RING WINS OUTRIGHT, 9.25x over windowed error and 4.14x over
windowed uniform. OBS-18's oracle advantage does NOT survive being earned.

THE INTERVENTION, Astra's, and it is what makes the claim causal — the
wrong-label count is descriptive and establishes nothing alone. Same parent,
same locations, same keep count, same algorithm, only labels re-read from the
world being evaluated (an oracle per point: a probe, not a policy):
  uni@tau .06238->.04999   uni@tau' .05855->.05195
  err@tau .06475->.02866   err@tau' .06672->.03004      ring .04650
CHANGING LABELS ALONE REVERSES THE RANKING in both tested draws: .02866 and
.03004 against the ring's .04650 — 38% and 35% LOWER error. Lead with those
absolutes, not gap-closed percentages, which depend on each arm's original
deficit. Bounded to the intervention: historical labels CAUSE substantial
current-world loss through this pipeline; it does NOT show locations and
labels act independently, since a label change moves selection, refit and
refinement alike. The uniform draws close ~78%/~55% and do NOT reach the ring,
so their residual is not labels alone. Refreshing COSTS the error arms
retention (.12486->.13479, .12112->.13512).

THE MECHANISM. `old` counts pre-move slots, but only .095 of this cube is
contested, so what matters is contested AND stale. stale against old: recent
.000/.000, uniform .648/.659, error .617/.639, uni@tau .045/.036 all track;
err@tau .161/.076, +.085 replicated at +.082. AN EXPONENTIAL PRICE CAN BE
PAID, AND WHAT PAYS IT IS ADVERSELY SELECTED. NOT because the rule discovers
after the move that an old sample is wrong — ADMISSION SURPRISE IS FROZEN AT
OBSERVATION TIME and nothing reprioritises an old entry (Astra) — but because
A-era surprise already concentrates on the structure the worlds will LATER
disagree about. At the same tau err@tau carries 276 wrong labels and uni@tau
37; mean absolute discrepancy among wrong labels .324 and .393, total squared
discrepancy 4.4% and 23.0% of squared B signal on each buffer's own points.

Enrichment goes 3.08x -> 2.09x at M/N = 0.5 and 3.66x -> 2.09x at M/N = 2.0.
The two windowed values round alike (2.0901, 2.0864) but TWO CHECKPOINTS ARE
TWO POINTS — no ceiling and no timing-independence established. What it does
refute is P8's REASONING, which had the erasure specific to M < N.

NOT REFUTED: the measure. At MATCHED staleness (.639 vs .659) error beats
uniform on BOTH axes, 4.10x and 3.29x. What is refuted is that a WINDOW can
deliver that at the ring's freshness. Ordering five rules by staleness is NOT
a monotone trade — unbounded error beats unbounded uniform on BOTH axes — and
one tau is one point, so "an exchange rate interpolates" is a hypothesis for a
tau sweep, not a result. Windowed error IS on the Pareto surface, at the
OPPOSITE corner from the prediction: retains better than the ring by 3.04x,
worse than unbounded error by 7x. The ring's position is STRUCTURAL — the only
rule whose membership is decided by TIME ALONE, so past M = N it carries
exactly zero wrong labels.

Four of eight registered predictions refuted (P4, P5, P7, P8); thresholds left
standing and marked. OBS19_WINDOW_OLD was derived on the UNIFORM rule (the
predictor can only simulate w = 1) and is asserted THERE ALONE — err@tau reads
.076 against the .05 ceiling, and that excess IS the finding. Spending one
rule's number on another is this campaign's standing mistake.

P8's NUMERICAL prediction failed and its MECHANISM is UNRESOLVED: the offsets
differ in parent, convergence, replay contents, normalisation denominator and
kept budget (343 vs 367) — five confounds, so no replacement is claimed.

RECORDED FINDING: at the tested decay scale and checkpoints, exponential
error-weighted replay retains more prior-world information and sacrifices
current-world fit relative to the ring. Same-points refresh controls show
historical labels cause substantial current-world loss, while error-selected
locations remain effective when supplied current labels. HARD-WINDOW SYNTHESIS
REMAINS UNTESTED.

Next, and the phase points straight at it — Astra's specification, well posed
as it stands: A HARD CUTOFF, ERROR-WEIGHTED SELECTION WITHIN ITS ELIGIBLE
POOL, MATCHED UNIFORM SELECTION, REPLICATED POLICIES. A price can be paid, a
cutoff cannot.
ITS KEY CONTRACT: IDENTICAL ELIGIBLE OBSERVATIONS for the error and uniform
selections, with the cutoff preventing EITHER rule from retaining an expired
sample. That is what makes it a test of selection-within-eligibility rather
than another comparison of two different pools. Then a tau sweep; a t_min swept at a FIXED model state; a
windowed measure NOT correlated with the regime change (uncovered). The A re-fit column is exploratory with no unslept
reacquisition baseline, so the gate prints the raw column and no pairwise
ranking; err@tau's own replicates differ by .0250 on it.

G66 is the campaign's largest gate — twenty-two sleeps, almost all of it, each
~30 s and almost entirely the 400-step descent over 8192 replay points; all
nine adaptation runs together are ~14 s. Use smoke plus the affected gate at
commit, not the full suite.
