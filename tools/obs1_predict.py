"""OBS-1 / G48 pre-registration: known-flow state assimilation.

For a fixed invertible flow independent of MARL parameters theta,
  predicted(x,t) = M_theta(Phi_-t(x)).
Thus d predicted / d theta is the existing MARL parameter derivative
at the preimage. No flow-parameter derivative or materialisation is needed.

Fixture: standing scalar blob under rigid rotation; initially fit a blob
whose centre is displaced by +0.04 in x. Three seeds 7/19/41. Assimilate
30k noiseless scalar observations at random times over steps 1..40.
Observation positions are transported draws in the true initial 4-sigma
ball; this declared sensor distribution is not blind support discovery.
The learner receives only position, time and scalar measurement.

Arms: unchanged prior; inverse-coordinate updates; erroneous updates at
current coordinates; oracle updates at supplied original coordinates.
Identical priors and evidence in updated arms. No dynamics are learned.

Frozen directional predictions (margin 1, not a fitted effect size):
- inverse-coordinate updates reduce held-out future RMS below prior;
- they beat the erroneous current-coordinate update.
Aggregate squared errors over all three seeds; also print every seed.
The source-coordinate oracle diagnoses inverse integration error without
setting an unmotivated quantitative threshold on optimiser path drift.
Held-out points are independent. Score times 10,40,60: the last lies
beyond the entire training time window. Report local and whole-cube RMS,
model population, observation count and runtime. No uniqueness, sparse
coverage confidence, conservation or hidden-law recovery claim.

A separate contract test compares update event/prediction bits against
manual preimage observe, and finite-differences a kernel weight through
the delayed read. This is a fixed-flow derivative witness, not generic AD.
"""

if __name__ == '__main__':
    print('d M_theta(Phi_-t(x)) / d theta = d M_theta(p) / d theta at p=Phi_-t(x)')
    print('3 seeds; 30,000 observations each; training steps 1..40; held-out steps 10,40,60')
    print('Predicted pooled future SSE: corrected < prior and corrected < wrong-coordinate')
