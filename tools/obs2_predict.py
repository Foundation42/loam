"""OBS-2 / G49: frozen geometry, before running measurements.

P(x)=sum w_i phi_i(x), v=-grad P + omega R(x-c).
For coefficient j, S_j = dx/dw_j obeys
  dS_j/dt = (-Hessian P + omega R) S_j - grad phi_j.
Differentiate the SAME explicit midpoint integrator used for prediction.
A source coefficient affects later gradients through position; omitting
-Hessian P*S is the executable mutation.

Derivative audit: f64, all nine coefficients, seeds 7/19/41, lengths
1/8/32/64 at dt=.02, strong and weak initial influence, centred +/-
perturbations 1e-3/1e-4/1e-5. Tolerance abs 1e-9 + rel 1e-3 times the
larger derivative magnitude; all perturbation sizes must pass. Finite
precision near zero is judged by the absolute floor. Report both errors.
Prediction: dropping the position sensitivity fails at least one check.

Recovery headline: f32 coefficients and computation, 3 seeds, 9 fixed
Gaussian kernels (3x3 centres .25/.5/.75; sigma .22; z=.5), no births.
Hidden coefficients alternate signs with seed-dependent amplitudes in
[.015,.045]. 16 observed initial positions uniform in [.15,.85]^2;
endpoints at .16 and .48, truth midpoint steps .005, model steps .02.
400 full-batch Adam updates lr=.003, beta=.9/.999, eps=1e-8, initial w=0.
Arms: correct omega=0; wrong prescribed omega=.3. Same observations,
fixed capacity, updates and RHS evaluations. Extra rotation cannot be
cancelled everywhere by a scalar potential (nonzero circulation), though
finite observations may not uniquely identify that mismatch.

Held out: independent 64 starts in the same square, .48 endpoints.
Report train/heldout endpoint RMS, gradient error on 25x25 grid, coefficient
RMS, initial error, kernel count, update count, RHS/kernel evaluations,
and timings. Endpoints only enter learning, not velocities or potential.
Frozen directional predictions pooled across seeds:
correct heldout error < initial error; correct < wrong dynamics;
correct potential-gradient error < zero-field baseline.
No adaptive expenditure or sparse-field identifiability claim. K=9 and
births=0 by construction; adaptive mismatch diagnosis is a later stage.
"""
if __name__ == '__main__':
    print('Sdot_j = (-H(P) + omega R) S_j - grad(phi_j)')
    print('Audit: 3 seeds x 4 lengths x 3 starts x 9 weights x 3 epsilons')
    print('Recovery: 2 arms x 3 seeds x 400 updates x 32 endpoint observations')

# Amendment after first run (retain the original refutation): the raw
# eps=.001 central difference failed for seed41,n8,weight5, gradient7.6e-6.
# Before rerunning: record raw failures by epsilon; additionally evaluate
# D(h/2) and Richardson (4D(h/2)-D(h))/3, cancelling the O(h^2) term.
# Require extrapolated derivatives at every h to meet the SAME tolerances.
# This tests the truncation-error explanation, without relaxing thresholds.
