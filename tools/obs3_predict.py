"""OBS-3 / G50 pre-registration: matched candidate coverage and adaptive birth.

Reuse OBS-2 data, dynamics, coefficient optimizer and three seeds. Start
with its nine active coarse kernels. Offer both models the identical 32
newborn shapes: 4x4 locations (.2,.4,.6,.8)^2 at widths .14 and .09.
Max active K=25; candidate dictionary K=41. Inactive coefficients stay zero.
All 41 sensitivities are evaluated in EVERY arm, including frozen controls,
so candidate-search work is equal even when populations differ.

Four arms: correct/wrong omega (0/.3) x frozen/adaptive allocation.
1200 full-batch updates, same Adam(.003,.9,.999,1e-8). First 400 updates
have no births (OBS-2's original budget). At updates 440,480,...,1200,
inspect pre-update loss gradient g_j and Gauss-Newton diagonal h_j from
the current batch. Candidate score = g_j^2/(2*h_j), the one-coefficient
linearised predicted loss reduction. Admit the best inactive candidate
if score > .5*(1e-4)^2 and capacity permits. This is a declared accuracy
target, not inferred sensor noise. Zero-weight birth is function-preserving;
newborn Adam moment and bias clocks start at zero. Old moments persist.

Frozen predictions: pooled adaptive wrong births > adaptive correct births;
late births (updates>800) greater under wrong dynamics; adaptive correct
held-out RMS < adaptive wrong. Print refutations without changing knobs.
Frozen arms distinguish allocation effects from extra fitting iterations.
No assertion that adaptive beats frozen under wrong dynamics: overfitting
may worsen generalisation. No births/deaths churn claim (no death policy).

Record every 40 updates: pre-update train/heldout error, K, birth requests,
actual births, denied requests, weight-update L1, RHS and basis work.
Per birth: x,y,sigma, prior maximum active Gaussian coverage, local
pre-update residual energy weighted by phi_j at observation starts,
g_j,h_j,score. Record spatial residual bins on the common 4x4 start grid,
and visited 4x4 world bins/outside flag along predicted integration points.
Candidate coverage and sensor coverage are matched; internal paths may
still differ and are reported, not assumed identical.

Only topology/masking/work/gradient contracts are hard gates. Directional
scientific predictions are printed as HELD/REFUTED and retained in notes.
This experiment uses a restricted birth dictionary, not original MARL's
online coverage birth and not moving-geometry differentiation.
"""
if __name__ == '__main__':
    print('9 initial + 32 candidates; active cap25; 4 arms x3seeds x1200 updates')
    print('birth score=g^2/(2h); score cutoff=5e-9; opportunities440..1200 by40')
    print('Predictions: wrong>correct total births and late births; correct<wrong heldout RMS')
