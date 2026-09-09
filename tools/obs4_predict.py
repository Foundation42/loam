"""OBS-4 / G51 pre-registration: useful growth and fresh evidence.

Full factorial: simple/rich true potential x repeated/fresh windows x
correct/wrong dynamics x frozen/adaptive allocation x seeds7/19/41.
Reuse OBS-3 dictionary, cap25, birth score cutoff5e-9, Adam settings and
1200-update budget PER WINDOW; three windows, total3600 matched per arm.
Warmup is only the first400 global updates; birth opportunities every40
thereafter. Parameters, active set and optimizer moments persist across
windows. No deletion or rehoming. All41 sensitivities evaluated throughout.

Rich truth adds coefficient+.025 at candidate30 and -.025 at35 (width.09,
centres .4,.4 and .6,.6). They are outside the initial coarse span but in
the candidate dictionary; truth is still deliberately representable.
Each window has16 new initial positions, endpoints .16/.48 generated with
fine dt=.005. Fresh windows use separate deterministic RNG streams;
repeated controls reuse window0. A NEW independent 64-start evaluation
set is fixed across windows and never enters training or birth scores.
Record exact observations and source-coverage counts. This is transfer
across initial-condition samples of a stationary field, not long-horizon
free-running state evolution or a changing law.

Score every incoming batch and untouched evaluation set BEFORE updates,
then after1200 updates. Log history every120 updates; record all proposals
above threshold at the usual40-update birth cadence, including denials.
For requests: candidate/location/scale, coverage before intervention,
local pre-update residual energy, score, birth/denial, prior same-candidate
and same-site request count, and whether requested in an earlier window.
Spatial residual/source-coverage/path-count data distinguish sparse sensor
coverage from changing internal predicted paths. No heldout-driven stops.

Frozen directional hypotheses (report HELD/REFUTED, not retune):
1. Rich correct repeated-evidence adaptive arms birth AND have lower final
   train and untouched-evaluation RMS than rich correct frozen arms.
2. Rich correct fresh adaptive arms have lower evaluation RMS than frozen.
3. On incoming fresh windows1/2 (before fitting), rich correct adaptive
   arms transfer better than their frozen controls (pooled endpoint SSE).
4. Rich fresh adaptive correct dynamics beat wrong dynamics on final eval.
5. Rich fresh wrong dynamics have more cross-window repeated candidate
   requests than correct dynamics (pressure, not birth-death churn).
Report simple controls too; do not infer mismatch from K or requests alone.
No claim that true fine structure is uniquely identifiable from16 starts.
"""
if __name__ == '__main__':
    print('48 arms; 3 windows x1200 updates; cap25, 41 scored candidates')
    print('Rich truth: w30+=.025, w35-=.025; incoming and fixed eval scored before updates')
    print('Scientific predictions may fail; retain all histories and fixed settings')

# Post-sweep diagnostic amendment, before running G51(c): simple correct
# controls acquired unnecessary kernels, often after sub-micro error.
# First observed request was step1160. Use an explicitly inspection-chosen
# step800 checkpoint to compare continued coefficient updates with holding
# that state fixed, on repeated window0, with births disabled in both.
# Keep scoring candidate pressure every40 through3600. Hypothesis: continued
# optimisation alone can push birth scores above the existing cutoff;
# held state remains below. This is a mechanism diagnostic, NOT a proposed
# stopping policy or an independent confirmation on unseen seeds.
