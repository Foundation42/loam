"""ALG-2 / G47 pre-registration, prepared before the interval sweep.

Question: how often should a transported learned field be materialised?
N=40 steps of the standing swirl. Keep the most recent materialisation
immutable. Its cheap view is pushed by local Jacobians between fits;
its accurate view backtraces into that immutable model. At a checkpoint,
fit a fresh model to transported examples of that model, NEVER the
already approximated cheap view and NEVER analytic target values.

Primary resource constraint: 240k training exemplars TOTAL over the 40
steps, excluding the common initial 60k fit. Intervals 1,2,5,10,20,40.
Mean per-frame error is the mean of same-frame RMS, on 128 local probes
at each frame, not just the end-frame result. Global final probes also
report leakage. Support_edges=1 and other Options.best values remain.

Predictions, frozen before running:
1. Mean cheap-view RMS has an interior minimum: min(k=2,5,10,20) is
   strictly smaller than min(k=1,k=40), averaged over seeds 7,19,41.
   Too-frequent fits split evidence among too many new populations;
   too-infrequent fits allow local-affine error to accumulate.
2. The k=40 endpoint has smaller final RMS than k=1 at equal evidence.
3. At k=1 the cheap and backtraced views are the same published model;
   their readings agree bitwise. Both require zero query backtrace work.
4. A k=40 run performs one fit, exactly 240k observes; all intervals
   consume exactly the same total. No original-model target oracle is
   substituted for checkpoint teachers in the main arm.

Control, if k=1 loses: give EACH fit 60k exemplars (the initial fit's
budget), at k=1,10,40. This distinguishes starvation from an intrinsic
cost of repeated projection. Its work is explicitly unequal: 2.4M,
240k,60k. No new winning default follows from this auxiliary control.

No prediction of monotone improvement, mass conservation, or exact
recurrence on this swirl. Runtime, peak/final population, final/global
error, intermediate error and query backtrace steps are reported apart.
"""

STEPS = 40
TOTAL = 240_000
INTERVALS = (1, 2, 5, 10, 20, 40)

if __name__ == '__main__':
    for k in INTERVALS:
        fits = STEPS // k
        exemplars = TOTAL // fits
        mean_pending = sum(i % k for i in range(1, STEPS + 1)) / STEPS
        print(f'k={k:2} fits={fits:2} exemplars/fit={exemplars:6} '
              f'total={fits*exemplars} mean_query_RK4_steps={mean_pending:.2f}')
