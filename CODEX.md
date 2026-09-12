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
- **Controls distinguish NECESSITY, CONTRIBUTION and SUFFICIENCY, and
  prose must preserve those distinctions.** A fork showing a factor is
  not needed for a failure has not shown it contributes nothing. OBS-22
  narrowed four explanations and eliminated one; a draft called all four
  "killed".
- **Separate a claim that needs a new EXPERIMENT from one that needs a
  RE-READ.** "Not a response to anything" took a no-move counterfactual
  to overturn; a peak contrast misread as a climb took only rereading
  the numbers already printed. Conflating them mis-prices the next step.

## Targeted recovery map

Use `rg -n 'topic' file` then read the surrounding section.

| Need | Read |
|---|---|
| Replay policy and consolidation | docs/MARL_OBSERVATIONAL_CAMPAIGN.md OBS-11..24; src/consolidate.zig, G58-G71; docs/data/obs22..obs24 |
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

Previously: OBS-22 / G69, WHEN IS INTERVENTION WORTH ITS COST? (2026-09-12).
Astra's framing, replacing "detect the change": surprise also rises because a
model is undertrained, and detection is ILL-POSED here by construction — the
trajectory holds a 30,000-observation gradual drift with no instant to name.
Every phase from OBS-18 to OBS-21 was told when the world moved; this is the
first where the policy decides.

THREE CONTRACT BUGS WERE CAUGHT BEFORE ANY CODE EXISTED and are recorded in
the predictor: calibration that saw its own future; a budget promised EXACT
while the policy could stay silent (now AT MOST three, unspent capacity
becoming ordinary observations); and an unstated CLOCK (every paid
observation advances it, revisits included, so drift continues THROUGH an
intervention).

BUILD THE CHEAP STRUCTURAL GATE FIRST. G69 (a) drives the REAL controller
with the sleep stubbed — eleven scenarios, seconds — and found three bugs
that would otherwise have surfaced nine minutes into a run: zero-init opens
the ratio at 8.00 from the update rates alone; an unready request is DEFERRED
and a horizon-blocked one REFUSED, both counted; the event order is
observation -> sleep -> score; and the drift snapshot comes from
interventions STARTED, not from a trigger scheduled arms never touch.

THE COMPARISON. Threshold frozen at 1.30274 = mean 1.07993 + 3 x sd .07427 —
the mean being 1.08 vindicates `mean + 3 sd` over `1 + 3 sd`, since a
stationary world does not imply a ratio centred at one. Results: none
.08492/.08828, informed .09079/.11294, trigger .09387/.11328, schedule
.22949/.43382 (whole / drift+tail).

Q6 REFUTED — no intervention policy beat NOT intervening. Q2 REFUTED and
ACQUISITION-DEPENDENTLY — 0 cold-start ticks on one trajectory, 11,917 on the
other. Readiness makes an EXECUTION test vacuous, so the claim is asked of
CROSSINGS.

ONE CATASTROPHE, LOCALISED, and four of my explanations died: populations
REGROW (645->322->727) so cumulative shrinkage is refuted; the full-population
fork is WORSE so compression is not necessary; acquisition "damage" was an
INSTRUMENTATION ARTEFACT (the acquisition spans the step, so before/after were
scored against different worlds); and an oracle relabelling STILL diverges, so
historical labels are not necessary either. What remains is ONE NONLINEAR
REFINEMENT DIVERGING — replay .13965 -> .35844, held-out world 6.72213 — which
OBS-11's registered null names exactly and nothing noticed. A replay-loss
acceptance check prevents it entirely (guarded == norefine, restore verified
byte-for-byte). That establishes THIS RULE PREVENTS THIS FAILURE, not that a
descending replay loss improves the current world.

THE DETECTOR, in three cheap gates. (c) traces both trajectories: seeds of
.049409 and .006119, an eightfold gap, because one first observation has
EXACTLY zero surprise. The slow half-life of 16,384 is where the seed's
contribution HALVES, not a cutoff. (d) replays the IDENTICAL surprise sequence
through an alternative specified in advance: cold-start ticks 11,917 -> 0.
(e) forks at the change into MOVE and NO MOVE: the move raises the ratio in
EVERY cell. RECORDED — the move increases surprise and the ratio under both
initialisations; only one combination crosses; initialisation affects the
ratio's LEVEL AND ITS RESPONSE, so crossings are sensitive to its history.

Next: `relabel + norefine`, the missing arm; a reduced-rate fork with a sparse
loss trace (starting RMS is NOT a curvature measurement); a guarded POLICY as
its own experiment; Q4's per-trajectory drift-and-tail spread.

G66 is the campaign's largest gate — twenty-two sleeps; G67 is ~8:45 with thirteen, almost all of it, each
~30 s and almost entirely the 400-step descent over 8192 replay points; all
nine adaptation runs together are ~14 s. Use smoke plus the affected gate at
commit, not the full suite.

Previously: OBS-23 / G70, WHAT DOES AN INTERVENTION ACTUALLY COST? (2026-09-12).
OBS-22's Q6 refutation was UNATTRIBUTED: "an intervention" is two mechanisms
— 4,096 targeted revisits paid out of the same horizon, and a consolidation —
and it measured their sum against zero. This is the 2x2, at OBS-22's
privileged `informed` placement so the trigger is not a third factor.

SIX ARMS, NOT FOUR, AND THE CLOCK IS WHY. An arm spending r on revisits
cannot also consolidate at the fire instant, so `both` sleeps at t+r; its
matched no-revisit cell is PLACED at t+r and sleeps immediately. `sleep@t`
isolates that offset; `unguarded` prices the guard decision.

A CLOCK BUG WAS CAUGHT IN REVIEW BEFORE THE SLEEPS WERE PAID FOR. The
immediate-sleep path did not exist when OBS-22 was written, and adding it
REINTRODUCED OBS-22's score-ordering bug on the new branch — it scored
30,000/60,000/90,000 and only then consolidated. The rule applies to each
half separately: an arm spending r completes r LATER than it starts, so a
checkpoint at its start instant belongs BEFORE it; one spending none
completes where it starts, so that checkpoint must WAIT. G70 (a) picks toy
timings where EVERY sleep lands on a checkpoint and asserts both paths, with
exactly one score per checkpoint. Mutation: restoring the old behaviour
drives check-before-sleep 0 -> 3 on exactly the immediate arms. G69 was
RE-RUN rather than argued — all 29 distinct numbers reproduce.

THE CONTRACT THAT MAKES ATTRIBUTION POSSIBLE. The fresh-draw RNG advances
once per fresh observation and never for a revisit, so `none`, `sleep@t` and
`sleep@t+r` draw IDENTICAL locations and the revisiting arms a PREFIX —
asserted by hash. Hashes alone are not enough, because a controller side
effect moves no query: G70 (a) also asserts that with the sleep stubbed the
six arms collapse to exactly TWO trajectories, matched on error by phase,
population, peak and births.

RESULTS. revisit .08090/.08607, none .08492/.08828, both = unguarded
.09079/.11294 (OBS-22's informed arm, to every digit — that validates THAT
ARM's numerical continuity, not the lattice), sleep@t .09284/.10806,
sleep@t+r .12076/.16354. Paired contrasts, formed WITHIN a trajectory:
C1 -.00401, C2 +.03584, C3 +.00989, C4 -.02997, C5 (interaction) -.02596,
C6 +.02792. Every sign replicates on both trajectories; C2, C5 and C6 have
between-trajectory differences LARGER than their means.

THE STATEMENT (Astra's): at the tested timings, targeted revisiting improved
trajectory error on both seeds. Adding consolidation worsened it, although
revisiting reduced the penalty relative to consolidation alone. Delaying all
three consolidations by 4,096 observations increased error on both seeds,
with strongly seed-dependent magnitude; the responsible intervention and
mechanism remain unlocalised.

Q1, Q2, Q2', Q3, Q5 HELD. Q4 REGISTERED AND REFUTED at .87983 against
[.40, .80], REPORTED and not asserted, the bound left standing to be struck.
THE SAVING MISSED THE PREDICTION; IT DID NOT DISAPPEAR — ~12% fewer final
kernels, 7% lower checkpoint-mean, while error is worse and PEAK is 1.067,
above one. There IS a trade; it is smaller than registered and UNPRICED.

AND THE RESOURCE ACCOUNT INVERTS ONCE BIRTHS ARE COUNTED PROPERLY. A
consolidating arm performs 2.25x as many KERNEL-BIRTH EVENTS — 1903 against
844 — to end 12% smaller, because every sleep discards kernels the birth rule
re-purchases. PAID OBSERVATION BUDGETS ARE EQUAL, so this is MORE TOPOLOGY
REBUILDING and NOT more acquisition; the compute it costs is UNPRICED. The first run printed 292 and read as the opposite: A SLEEP
REPLACES THE MODEL AND THE CHILD'S BIRTH COUNTER STARTS AT ZERO, so one read
at the end measures only the last segment. What exposed it is an invariant
nobody had registered — NOTHING DIES EXCEPT AT A CONSOLIDATION, so `none`
read births EXACTLY equal to its final population. Now asserted, and the
total banked at every replacement.

THE AGGREGATE HID A PHASE-LEVEL REVERSAL, and it belongs beside the
headline. `both` has the LOWEST OBSERVED mean error in the step phase
(.07181) and the stationary stretch after it (.05788) and STILL LOSES over
the full trajectory, its deficit accumulating in DRIFT and TAIL. That is a
measured variation in policy performance across phases with an OPEN
mechanism — it does NOT establish that gradual change is what makes a
consolidation hurt, since those phases are also everything downstream of
three interventions.

AND THE 5678 TAIL GAP IS A LATE EXCURSION. The arms are identical to the
digit through t = 28,000; sleep@t separates at 30,000 and sleep@t+r at
36,000 — the first checkpoint after each one's first sleep, which is the
ordering rule visible in the data. Then sleep@t+r runs .16067 -> .92824 ->
.90681 across t = 94,000-98,000, immediately after its THIRD consolidation at
94,096, with ZERO rejections. That localises the VISIBLE DAMAGE and does NOT
exclude the earlier sleeps as contributors to the state that failed. APPEARS
AFTER IS NOT CAUSED BY.

C6 IS NOT A WINDOW COMPARISON. It shifts all three placements, and only the
first pair is about stale-versus-fresh labels — historical labels are not
necessarily wrong, since the worlds agree outside the contested region. It
contrasts two complete SCHEDULES: after the first differing sleep the models
differ, later windows carry different surprise weights, and every subsequent
consolidation starts elsewhere. The tail gap arriving late is an inability to
ATTRIBUTE, NEVER AN EXONERATION — an early intervention can act late.

ZERO GUARD REJECTIONS, and sleep@t+r/5678 still reached .14489/.22312. That
establishes acceptance did not ensure a beneficial trajectory POLICY. It does
NOT establish a locally harmful descending refinement, which needs same-world
measurements immediately before and after the operation.

THE FEEDBACK CHANNEL, measured rather than conceded. A consolidation's effect
INCLUDES what it does to later acquisition. The first intervention's targets
are a CONTRACT (nothing has slept when they are chosen) and all three
revisiting arms agree exactly; the second and third DIFFER on both
trajectories. So C5 may NOT be narrated as "sleep uses repaired evidence
better" — "sleep changes what gets revisited next" fits it equally.

THE RECORD THE NEXT PHASE NEEDS. Tally carries the error at all 52
checkpoints, seeds apart, with its own contract asserted: the k-th sits at
exactly (k+1)*check, the count matches the objective, the trace sums to
err_sum BIT FOR BIT, and the phase segmentation partitions the same
checkpoints. The first visible separation says WHERE TO INVESTIGATE, not
where the causal difference originated.

Next (OBS-24, Astra's design): PRESERVE THE COMMON PARENT immediately before
sleep@t+r/5678's THIRD consolidation at t = 94,096. Compare SKIP, GUARDED
CONSOLIDATION and LINEAR-REFIT-ONLY, scoring each against the SAME
COMPLETION-TIME WORLD before continuing with identical fresh queries. That
distinguishes damage from this consolidation from damage from its REFINEMENT,
and needs no further full-lattice run. Also owed: the magnitude of the targeting divergence;
pricing the 12% capacity saving; `revisit` at other budgets.

PROCESS: `pkill -f` matched its own wrapper AGAIN and killed the cancelling
command. The rule was already here and was not followed. Use the captured
task handle.

G70 is now the campaign's largest gate at ~16 min; G70 (a) is seconds and
sleeps not at all.

Latest: OBS-24 / G71, THE REFINEMENT THAT DESCENDED, AND DAMAGED (2026-09-12).
OBS-23 localised the damage on acq 5678 to ONE consolidation at t = 94,096,
ACCEPTED by the guard. OBS-22 had registered the gap that leaves: recovery
from a REJECTED refinement establishes nothing about an accepted one. This
forks that single consolidation. 2:15, no further full-lattice run.

THE HEADLINE. Replay on the buffer's OWN HISTORICAL LABELS, world on held-out
probes against completion-time truth at a STATIONARY instant, no relabelling
anywhere: parent .22300/.16446, linear .12414/.27473, attempted = returned
.06259/.86959. THE REFINEMENT STRICTLY HALVED REPLAY LOSS AND TRIPLED
SAME-WORLD ERROR AT THE INSTANT OF ADOPTION. Q1 +0.59486, Q2 +0.70513 — the
damage is IMMEDIATE, not emergent.

AND NOT THE REFINEMENT ALONE (unregistered, from the same four points). The
first stage moved replay .22300 -> .12414 and world .16446 -> .27473. BOTH
STAGES REDUCED HISTORICAL REPLAY RMS WHILE INCREASING CURRENT-WORLD RMS — the
whole of what was measured. That first stage BUNDLES compression, kernel
selection and the linear refit and this fork does not separate them; 5.4x is
a RATIO OF TWO RMS INCREASES, not field disagreement and not evidence of a
shared mechanism.

THE GUARD BEHAVED EXACTLY AS SPECIFIED — the refinement did not raise replay
loss, so accepting it was correct. The finding is about the CRITERION: REPLAY
NON-INCREASE IS INSUFFICIENT FOR CURRENT-WORLD PROTECTION. It keeps its use
against optimisation that worsens its own objective, the OBS-22 failure it
was built for.

CONTINUATIONS, identical fresh queries: skip max .19722 mean .17569, linear
.27740/.18471, guarded .92824/.50425. Q3, Q4 (both halves), Q5 HELD. Q6
REFUTED (.18471 vs .17569) — OBS-22's precedent does not carry; reported, not
asserted. Its SHAPE matters more: linear is far worse at the first checkpoint
then recovers to end AHEAD of skip, so a five-checkpoint mean scores an
excursion and a recovery together.

CONSTRUCTION CONTRACTS, all Astra's. `Split` duplicates the post-linear
candidate INSIDE the real consolidation and the attempted refinement beside
it, so both branches come from the SAME BYTES — a seed is a weaker guarantee.
`Hand` takes the LIVE parent for the control, because `adopt` zeroes Adam
moments, step counters, updates and drift origins and returns a fresh model
with a fresh residual ring WHICH GATES BIRTHS. Reproduction of OBS-23's arm
is a TOLERANCE check at 1e-5, NOT exact agreement (the recorded values were
rounded); full precision now printed. Acceptance gives NON-INCREASE only.
Maxima are over FIVE CHECKPOINTS and cannot exclude an excursion between them.

A SECOND BIRTHS BASELINE BUG, same class as OBS-23's, opposite direction: a
raw `stats.births` credited `skip` with 804 because it continues a model
created at the second consolidation. Netted at the fork: skip 240, linear 297,
guarded 385, with k_final 1202/778/866 — the consolidated branches BIRTH MORE
and END SMALLER. Twice in two phases: A COUNTER READ ACROSS A FORK NEEDS A
BASELINE AT THE FORK.

SCOPE: one consolidation, one trajectory, CONDITIONAL ON THE PARENT the
earlier sleeps produced. Nothing says how often this happens.

Next, and VALIDATION DESIGN COMES BEFORE REPLICATION (Astra): replication says
how often this happens, validation design says whether an available signal can
distinguish the harmful update at all. A HELD-OUT SPLIT OF THE REPLAY BUFFER
IS NOT A WORLD-AWARE RULE — it tests generalisation to held-out HISTORICAL
evidence, and stale labels can approve the same harmful change. Call it
HELD-OUT REPLAY ACCEPTANCE; keep CURRENT-WORLD VALIDATION separate. A recent
validation stream could supply current evidence, but its timing,
representativeness and OBSERVATION COST need explicit treatment. Then: why the
buffer and the world disagree (staleness, coverage, or the error weighting);
then the same fork at the other two consolidations and on 1234.
