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
| Replay policy and consolidation | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-11..20; src/consolidate.zig, G58-G67 |
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

Latest: OBS-20 / G67, the HARD CUTOFF (2026-09-11). Astra's specification
after OBS-19, and its contract decided the design: IDENTICAL ELIGIBLE
OBSERVATIONS for the error and uniform selections, the cutoff preventing
EITHER rule from retaining an expired sample.

THE SYNTHESIS EXISTS, on this fixture and at this timing. h-err@2N reaches
.03787/.03733 against the ring's .05390 — 29.5x the spread, 30% lower error,
replicated, ZERO wrong labels, NO ORACLE. OBS-19 could only reach that shape
by relabelling from the truth.

IT DECOMPOSES, and the resource-matched control is already in the table:
h-uni@2N IS a ring of 2N subsampled uniformly to N — same retained history,
same k, differing only in the weight — and it beats the N-ring at
.05139/.05069, about 5%. Error weighting adds a further 26%. A SIXTH of the
30% is the POOL, five sixths the MEASURE. The comparison against the N-ring is
NOT resource-matched: both hard arms retain W = 2N plus the selected N-slot
buffer and scan the pool at selection time.

A per-rule reservoir COULD have carried the contract — OBS-18's and OBS-19's
reservoirs all got the SAME stream, and two rules keeping different subsets is
what selection rules ARE, not a confound (Astra). What a shared object adds is
that hard-cutoff ELIGIBILITY becomes explicit and ENFORCEABLE. So
`consolidate.Window` is a LITERAL SHARED OBJECT — one deterministic ring of
the last W, no sampling in it, every rule selecting from the same bytes.
Selection happens AT THE SLEEP (A-Res over a static pool IS weighted sampling
without replacement) and surprise/cover are stored AS OBSERVED, so nothing
reprioritises with hindsight. `Replay.admitAt` lets a selected buffer carry
the OBSERVATION index rather than its selection order; `admit` delegates to it
and is unchanged bit for bit.

It separates WHAT YOU KEEP (W observations) from WHAT YOU CONSOLIDATE ON (N).
The cutoff's honest price is the first: 2x at W = 2N, 4x at 4N, against the
exponential form's N and no expiry machinery at all.

THE MEASURE AT IDENTICAL ELIGIBILITY: h-err@2N beats h-uni@2N by 19.1x — same
object, same k, differing only in Compose.weight. This ISOLATES the selection
rule; it is NOT the campaign's first legitimate comparison of selection rules.
What is new is that eligibility is PINNED.

THE CONTRACT AS A MEASUREMENT: refreshing the 2N arms changes the result by
EXACTLY ZERO, .03787 -> .03787 bit for bit. Nothing to refresh. Far stronger
than counting labels.

A HARD CUTOFF GUARANTEES ELIGIBILITY, NEVER VALIDITY. At W = 4N half the pool
is pre-move, EVERY arm goes negative, and the error rule carries 1166/1129
wrong labels against uniform's 409/387 (registered 388) — OBS-19's adverse
selection surviving the change of mechanism. A cutoff removes the ability to
BUY past the window, not the measure's preference for the contested band
inside it. And W = 2N is clean only because 2N = M exactly: THE FIXTURE'S
TIMING, not something a policy knows.

SELECTION FREEDOM IS WORTH SOMETHING AND THE CUTOFF SPENDS IT. Registered as
an asymmetry BEFORE the run: refreshed, the WIDE window's locations BEAT the
clean one's, .02918/.02829 against .03787/.03733. A WIDER WINDOW IS THE BETTER
INSTRUMENT AND THE WORSE POLICY. But DETECTING THE MOVE DOES NOT RECOVER IT —
those better locations INCLUDE pre-move observations, and cutting at the move
REMOVES them rather than supplying current labels; an exact detected cutoff is
the 2N history already tested (Astra).

NOT CLAIMED: retention, so not dominance either. Ring .12933 against h-err@2N
.13184/.13486 is 0.83x the spread on first draws and 1.33x on means — the
leader-versus-mean conflation Astra caught in OBS-19. Both printed, neither
asserted.

Next: where a larger pool of VALIDLY LABELLED points could come from, since
detection cannot supply it — observing longer before consolidating, or
RE-OBSERVING old locations under the current world, which is a different
mechanism from replay. Then a sweep of the move time against fixed W, to say
how sharp the cliff is.

G66 is the campaign's largest gate — twenty-two sleeps; G67 is ~8:45 with thirteen, almost all of it, each
~30 s and almost entirely the 400-step descent over 8192 replay points; all
nine adaptation runs together are ~14 s. Use smoke plus the affected gate at
commit, not the full suite.
