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
- **A `--test-filter` excludes non-matching test bodies from SEMANTIC
  ANALYSIS.** Compile-checking a newly written gate with some other gate's
  filter validates everything except the gate you just wrote. Check a new
  test with ITS OWN filter, or unfiltered. OBS-21 shipped a bad field access
  through three "clean" Debug compile-checks this way.
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
- **Aggregate statistics cannot substitute for structural invariants.**
  Two arms reading the same share are not thereby equivalent. Assert the
  invariant the design depends on — OBS-21's window matched on old-share
  while retaining 2709 expired entries and putting 881 into a sleep,
  because the gate checked the share and never the ring.
- **Replication must vary the STAGE whose uncertainty you are
  discussing.** Two sleep-time draws say nothing about acquisition
  variability; in OBS-21 the acquisition spread was 2.5x the selection
  spread and it governed the headline margin. Say which stage a spread
  belongs to, and what it still cannot isolate.
- **When a correction changes several things at once, report the delta
  and attribute none of it.** Naming a cause needs a matched ablation.

## Targeted recovery map

Use `rg -n 'topic' file` then read the surrounding section.

| Need | Read |
|---|---|
| Replay policy and consolidation | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-11..21; src/consolidate.zig, G58-G68 |
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

Latest: OBS-21 / G68, TARGETED REVISITING (2026-09-11, corrected 09-12).
Re-observation spends a real observation to ask again AT A LOCATION THE MODEL
CHOOSES. The phase's load-bearing decision: A RE-OBSERVATION IS AN
OBSERVATION — it pushes into the ring and evicts the oldest, so every
placement slides the window identically and ELIGIBILITY IS IDENTICAL BY
CONSTRUCTION, not merely equal in old-share. The gate asserts the ring's
invariants (nothing older than n - W, t % W == slot).

THE FIRST VERSION VIOLATED THAT CONTRACT AND IS KEPT AS HISTORICAL EVIDENCE:
it mutated slots IN PLACE and advanced Window.n, retaining 2709 entries older
than the cutoff, putting 881 into a sleep, destroying the timestamp-to-slot
mapping, and reporting a mean aimed lift of +0.39. A GREEN GATE DOES NOT
RESOLVE A CONTRACT IT NEVER ASSERTS.

THE FINDING: across two acquisition trajectories and two sleep selections
each, targeted revisiting produced lower post-sleep error than either uniform
alternative. Sleep improved the targeted models by 6-11% while WORSENING both
alternatives, under matched observation budgets and within-trajectory kernel
budgets. Means aimed .07044, revisit .10185, fresh .10471 (3.4x and 5.0x the
worst relevant spread). The no-budget reference is destructive at
-.3010/-.2034 — OBS-19 QUALITATIVELY, not its numerical checkpoint.

ACQUISITION REPLICATION EARNED ITS COST: fresh's acquisition spread (.01021)
is 2.5x its selection spread (.00407), and it governs the headline margin.
It varies the whole life INCLUDING the branch model, so it is not
acquisition-stage randomness isolated at a fixed parent.

HITS COUNT CONTESTED LOCATIONS OBSERVED, NOT WRONG LABELS REPAIRED: selection
ranges over the whole window including current entries, and a push leaves the
older copy until expiry. Untargeted 408/400 against a DERIVED 387; targeted
1359/1357. That establishes TARGETING CONCENTRATION.

SURVIVING: targeted acquisition beats fresh draws BEFORE any sleep
(.0770/.0761 vs .0849/.0859) — MARL-4's routing at consolidation time — and
UNTARGETED revisiting is WORSE than fresh draws, because it re-asks where the
model was already right.

WITHDRAWN: compounding of repair with reprioritisation. A frozen-score control
moved the selected old share .312 -> .276, the WRONG WAY; targeting
already-high-weight entries is sufficient and rescoring partly offsets it.
Under push semantics nothing is rescored in place.

NOT ATTRIBUTABLE: the correction reduced mean aimed lift from ~+0.39 to
+0.079, but it changed FIVE things at once (ring semantics, fixed k, removal
of a change-boundary oracle, the candidate population, a second trajectory).
Blaming the expired entries would need a matched ablation, not run.

STILL CONFOUNDED: observations and k matched within a trajectory, parent
populations not (688/689/686) — a query-budget comparison.

Next: a matched ablation if the effect's SIZE matters as much as its sign;
budget size; acquisition randomness at a FIXED parent; and still nothing
DETECTS a move.

G66 is the campaign's largest gate — twenty-two sleeps; G67 is ~8:45 with thirteen, almost all of it, each
~30 s and almost entirely the 400-step descent over 8192 replay points; all
nine adaptation runs together are ~14 s. Use smoke plus the affected gate at
commit, not the full suite.
