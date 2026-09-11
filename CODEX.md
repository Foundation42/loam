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
  justify restarting a running suite or repeating one that passed.
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
| Replay policy and consolidation | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-11..18; src/consolidate.zig, G58-G65 |
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

Latest: OBS-18 / G65, replay COMPOSITION at equal N and equal k (2026-09-10).
Four admission rules — recent (ring), uniform (A-Res reservoir w=1), error
(w=surprise), uncovered (w=1-cover) — fed ONE stream by one model, so nothing
differs but which observations survive. `Event.cover` was added for it: the
continuous coverage computed since MARL-0 and discarded since MARL-0.

TWO EXPERIMENTS, complementary and both kept. AS A POLICY each rule uses its
own labels, because a rule over a non-stationary stream chooses WHEN to
observe as well as where, and that is part of the policy. AS A LOCATION every
label is re-read from the current world; that needs an oracle per point, so
it is a probe, not something deployable.

Both tables trade, which is Christian's registered Pareto expectation against
the agent's predicted sweep, and Christian wins on both readings. As a policy
the ring wins the current world and is LAST at preserving the old one, while
error-weighted replay is the reverse (A held: recent .13026, error .09117).
As a location only the immediate axis has a uniquely separated leader (error
by 3.07x, replicated) — and that is a claim about the LEADER, not the field:
counting pairs separated by more than each table's spread, relabelled A held
is 4 of 6. Replicating the rule under test is not optional; the error rule's
own two relabelled arms differ by .04007 on A re-fit, comparable to the
widest between-rule gap, so its downstream behaviour is unresolved.

The sentence: a buffer's LOCATIONS decide how well it fits the world it is
labelled for, and its LABELS decide which world that is — a SUMMARY, not a
demonstrated separation; the two have every reason to interact and it must
not be cited as a factorisation. Label validity is
relative to the world being EVALUATED, not absolute. What a relabelled buffer
loses is not evidence about the old world — only .0950 of this fixture is
contested — but its old-specific labels where the two worlds disagree.

REFUTED: the registered N_eff mechanism. `reached` is 1.000 in every arm —
there is no unreached ground, because a Gaussian basis holds down its own
leakage (33 of 692 kernels centred past the window, and `mu0` says 33 were
born there). This refutes the ROW-COUNT form of effective evidence only;
conditioning and uneven information across parameters stay open. It also
amends MARL-16: "zero is what an empty model already predicts" is true of an
EMPTY model and false of a populated one.

TWO CONTRACT FAILURES, both found by Astra in review, neither by the gate.
(1) The arms did not have equal k: sleepOn rounded each region's share
independently, delivering 345-347 against a budget of 346 while the header
printed 346. `allocate` is the fix — largest-remainder at exact=true, the
incumbent bit for bit at exact=false, so G62 (b), G63 and G64 keep
reproducing; G64 was re-run and matches its recorded table cell for cell.
(2) Reporting only "A re-fit" (performance after 20,000 further
observations) hid the policy table's own retention trade, because relearning
washes out what a sleep preserved. "A held" is now a separate column.

Replication is DESCRIPTIVE, not a confidence bound: three uniform arms and
two error arms, per-rule spreads reported separately because pooling them
assumes the rules vary alike. A margin printed as "3.07x the spread" sizes a
difference; it does not certify one.

Next: windowed error replay, pre-registered as a TRADEOFF hypothesis — can
it improve current-world fitting without giving up too much prior-world
retention? Both halves measured. It is a hypothesis, not a policy that
follows automatically — a recency window can straddle a regime change (the ring was
label-consistent here only because 20,000 B observations flushed all 8,192
slots), and restricting error-weighting to recent observations changes the
distribution it selects from. Needs matched recent/uniform controls,
observations placed around the transition, and replication of the error
policy itself.

G65 is the campaign's largest gate; use smoke plus G65 at commit, not the
full suite.
