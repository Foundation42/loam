"""G45: geometry prediction, written before the width sweep ran.

A width cap is h * support_edges / sqrt(32). The scalar fixture has
sigma=0.08: support_edges=2 at regions=4 is the first integer setting
that permits that isotropic shape. Doubling width increases coverage
volume eightfold, but is not an eightfold population prediction: births
are conditioned on surprise and deformation changes coverage.

Pre-registered comparisons: over seeds 7,19,41, 60k exemplars each,
mean kernels at support=2 < support=1, mean RMS <= 1.25*support=1.
Control: support=2 with half birth_width permits widening by descent
while starting at the historical newborn width. support=4 is diagnostic.
All keep regions=4, responsibility=3, rates and exemplar streams fixed.
"""
import math

if __name__ == "__main__":
    for edges in (1, 2, 4):
        sigma = 0.25 * edges / math.sqrt(32)
        print(f"support_edges={edges}: sigma_max={sigma:.6f}, "
              f"admits_blob={sigma >= 0.08}, relative_coverage_volume={edges**3}")

# G46 pre-registration, added before the selector diagnostic ran:
# Model: support_edges=4, regions=4, the same 60k blob fits and three seeds.
# Calibrate each kernel at 32 independent points within two widths of its
# source centre, comparing its pushed value at the forward-advected point
# with its original value. Rank by abs(weight) * RMS(kernel discrepancy).
# Compare top-half correction with eight equally-sized random subsets on
# unseen final queries. Predicted mean field RMS(top-half) < mean RMS(random).
# Zero corrected is all-push; all corrected is the immutable source read
# through the backtrace. The exact shared backtrace is computed once per
# query; selective kernel correction does NOT eliminate this cost.

# Follow-up control added after G46's first run: compare the same subsets
# ranked by abs(weight) alone. No predicted advantage is registered here;
# the purpose is to test whether probing earns its cost beyond importance.
