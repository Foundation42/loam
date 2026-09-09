#!/usr/bin/env python3
"""alg1_predict — ALG-1's gate numbers, before its run.

Christian, Wednesday 9 September 2026: "I have developed a set of
algebraics we might want to test."  `docs/MARL_Field_Algebra.md`, and
`docs/MARL_ALGEBRA_CAMPAIGN.md` is the lab book it opens.

ALG-1 asks the design note's first question — **can one MARL move
another?** — with one correction the note could not have made about
itself, and it is the reason this file exists before the Zig does.

    §35 proposes V = (-y, x).  That is a LINEAR velocity field, so its
    flow map is a matrix exponential, so it is AFFINE — and an affine
    map acts on a gaussian's parameters in closed form.  The note's
    first experiment therefore has an exact answer that bypasses the
    mechanism it is trying to test.

That makes it a gift as a CONTROL and useless as the only arm, so ALG-1
runs four:

    E  rotation,     exact affine operator, no projection
    A  rotation,     semi-Lagrangian + projection
    B  swirl,        semi-Lagrangian + projection      <- the real test
    C  swirl, V as a MARL, semi-Lagrangian + projection

Everything below is derived from theory or from a number the campaign has
already measured.  Nothing here is fitted to a run, because no run has
happened.

    python3 tools/alg1_predict.py
"""

import math

# ── the kernel, as `marl.zig` has it ──────────────────────────────────
CUTOFF = 32.0                 # marl.CUTOFF, pinned to rbf.CUTOFF
CUTOFF_R = math.sqrt(CUTOFF)  # 5.65685...

# ── the fixture ───────────────────────────────────────────────────────
# A gaussian blob on the unit cube.  s is chosen so that the blob is
# several kernels wide at the basis MARL-25 settled on (regions 4 ->
# sigma_max = 0.0442): a blob narrower than one kernel would be measuring
# the clamp, not the transport.
BLOB_S = 0.08
BLOB_C = (0.75, 0.50, 0.50)   # radius 0.25 from the z-axis through the centre
STEPS_PER_REV = 40            # §35's "small dt", made explicit
REGIONS = 4                   # MARL-25: the free step
SIGMA_MAX = (1.0 / REGIONS) / CUTOFF_R
THRESHOLD = 0.02              # marl.Options.threshold, the projection's dead zone

# Per-step arc at the blob's radius, as a fraction of the blob's width.
# Below ~1 the semi-Lagrangian backtrace lands inside the blob it came
# from, which is the regime the scheme is stable in.
ARC = 0.25 * (2 * math.pi / STEPS_PER_REV)
CFL = ARC / BLOB_S


def chi3_tail(c):
    """P(chi^2_3 > c) — the mass of a 3-D gaussian beyond radius sqrt(c).

    Closed form for three degrees of freedom, so this file needs nothing
    but the standard library.
    """
    return math.erfc(math.sqrt(c / 2)) + math.sqrt(2 * c / math.pi) * math.exp(-c / 2)


def rms_grad_ball(s, k=3.0, n=200001):
    """RMS |grad F| over a ball of radius k*s about a gaussian blob's centre.

    |grad F| = (r/s^2) exp(-r^2/2s^2); the ball is sampled by its radial
    measure 3r^2/(ks)^3, integrated by the trapezoid rule.
    """
    acc = 0.0
    R = k * s
    for i in range(n):
        r = R * i / (n - 1)
        g = (r / s**2) * math.exp(-r * r / (2 * s * s))
        w = 3 * r * r / R**3
        acc += (g * g * w) * (R / (n - 1)) * (0.5 if i in (0, n - 1) else 1.0)
    return math.sqrt(acc)


def anchor_ball(s, k=3.0, n=200001):
    """(mean, RMS about the mean) of the blob over a ball of radius k*s.

    MARL-17's rule: an RMS without a constant predictor beside it is a
    number with no scale.  MARL-20's rule: take it where the field is.
    """
    m1 = m2 = 0.0
    R = k * s
    for i in range(n):
        r = R * i / (n - 1)
        f = math.exp(-r * r / (2 * s * s))
        w = 3 * r * r / R**3 * (R / (n - 1)) * (0.5 if i in (0, n - 1) else 1.0)
        m1 += f * w
        m2 += f * f * w
    return m1, math.sqrt(max(0.0, m2 - m1 * m1))


print(__doc__.split("\n\n")[0])
print()
print("=" * 72)
print("ALG-1 — does one MARL move another?   PRE-REGISTERED, before the run")
print("=" * 72)

# ── (1) the cutoff, and what it costs each derivative ─────────────────
print("""
(1) THE CUTOFF IS FREE IN THE VALUE AND EXPENSIVE IN THE DERIVATIVES

A kernel is exactly zero beyond r^2 = 32, and exp(-16) = 1.13e-7 at the
boundary, which is why exact locality has always been free (G17 c, d,
bitwise).  The derivatives do not inherit that.

    grad phi  = -phi * L v                       |L v| = sqrt(32)/sigma at the cutoff
    lap  phi  =  phi * (|L v|^2 - tr L L^T)

so each derivative multiplies the step at the cutoff sphere by
sqrt(32)/sigma.  This is a PREDICTION about a mechanism, not a threshold:
ALG-4 measures it, ALG-1 only has to not be surprised by it.
""")
tail = chi3_tail(CUTOFF)
print(f"    mass thrown away by the cutoff      {tail:.3e}")
print(f"    {'sigma':>10} {'value':>10} {'grad':>10} {'laplacian':>11}   basis")
for sigma, name in ((0.25 / CUTOFF_R, "regions 4"),
                    (1 / 6 / CUTOFF_R, "regions 6"),
                    (1 / 12 / CUTOFF_R, "regions 12")):
    phi = math.exp(-0.5 * CUTOFF)
    lv = CUTOFF_R / sigma
    tr = 3.0 / sigma**2
    print(f"    {sigma:10.4f} {phi:10.2e} {phi*lv:10.2e} {phi*abs(lv*lv-tr):11.2e}   {name}")

# ── (2) mass is closed form ───────────────────────────────────────────
print(f"""
(2) MASS IS CLOSED FORM, SO §13 NEEDS NO QUADRATURE

    integral phi = (2 pi)^(3/2) / det L,   det L = exp(sum of the log-diagonal)

which is already in the parameter vector — one multiply-add per kernel.
The hard cutoff removes {tail:.3e} of it, so the closed form is exact to a
part in {1/tail:,.0f}.  §13's "measure the conserved quantity before and after"
is not merely practical, it is free.

    PREDICTED  the closed form agrees with a dense quadrature of the same
               model to better than 1e-5 relative.
""")

# ── (3) the affine subgroup is exact ──────────────────────────────────
print("""(3) THE AFFINE SUBGROUP IS EXACT, AND THAT IS WHY ARM E EXISTS

    F(A^-1 x) is represented exactly by   mu' = A mu + b,
                                          L'  = chol(A^-T L L^T A^-1),
                                          w'  = w

Verified numerically over 4000 random kernels (float64 3.9e-15, float32
2.4e-6 — the f32 figure is the 3x3 Cholesky's rounding, so this is EXACT
but NOT bit-exact, unlike G31 (a) where rounding a difference commutes
with scaling by a power of two).

    PREDICTED  arm E, one revolution, {steps} composed rotations:
               population EXACTLY unchanged  (an equality, not a threshold)
               RMS against the analytic reference  <= 1.0e-4

    derivation  2.4e-6 worst case per step, accumulating as a random walk
                over {steps} steps: sqrt({steps}) * 2.4e-6 = {walk:.1e}.
                The bound is that with a 6x margin, because the walk
                argument is an argument and not a proof.
""".format(steps=STEPS_PER_REV, walk=math.sqrt(STEPS_PER_REV) * 2.4e-6))

# ── (4) the anchors ───────────────────────────────────────────────────
mean_g = (2 * math.pi) ** 1.5 * BLOB_S**3
anch_g = math.sqrt(math.pi**1.5 * BLOB_S**3 - mean_g**2)
mean_l, anch_l = anchor_ball(BLOB_S)
print(f"""(4) THE ANCHOR AND THE DENOMINATOR

MARL-20 was diluted by a global probe set and fixed it with a local one;
MARL-21 was then diluted AGAIN inside the local region.  Twice in two
phases, so it is a rule: probes where the field is, the global set
printed beside them.

    blob s = {BLOB_S}
    global probes (unit cube)    mean {mean_g:.5f}   anchor RMS {anch_g:.5f}
    local probes  (ball of 3s)   mean {mean_l:.5f}   anchor RMS {anch_l:.5f}

    {1 - (4/3*math.pi*(3*BLOB_S)**3):.3f} of the cube sees nothing at all, so a global RMS is
    {anch_l/anch_g:.1f}x smaller for a reason that has nothing to do with the model.

    PREDICTED  every ALG-1 RMS is reported on the LOCAL set with the
               global one beside it, and the headline is local.
""")

# ── (5) the projection's dead zone eats the tails ─────────────────────
r_theta = math.sqrt(2 * math.log(1 / THRESHOLD))
tail_theta = chi3_tail(r_theta**2)
print(f"""(5) WHERE MASS DRIFT COMES FROM, AND WHY ITS SIGN IS NOT OBVIOUS

The projection ignores any residual below threshold = {THRESHOLD}.  The blob
falls below that at r = {r_theta:.3f} s, and a 3-D gaussian carries
{tail_theta:.4f} of its mass beyond that radius.  So {100*tail_theta:.1f}% of the blob lives
in the projection's dead zone.

Two effects with opposite signs, which is why this is a measurement and
not a derivation:

    LOSS  the ARRIVING tail is never learned — the target is below
          threshold where the model predicts zero, so nothing happens
    GAIN  the DEPARTING tail is never unlearned — the same threshold
          protects the kernels the blob has left behind

    PREDICTED  |mass drift| over one revolution < 20%, and ONE-SIGNED in
               at least 80% of steps.  A drift that changes sign step to
               step would mean the dead-zone argument is wrong and the
               drift is the fit's noise, which is a different finding.

    NOT PREDICTED  which sign.  Saying so now is the point of saying it
                   now.
""")

# ── (6) arm C: what a velocity MARL's own error costs ─────────────────
rg = rms_grad_ball(BLOB_S)
T_REV = 2 * math.pi
print(f"""(6) ARM C IS ERROR PROPAGATION, WITH NO FREE PARAMETER

MARL-13 (d): a learned sparse field loses to a dense grid when the field
is non-trivial EVERYWHERE.  A rotational velocity field is non-zero
everywhere and grows linearly with radius — MARL-16's expensive object.
So arm C imports a representation error that has nothing to do with the
algebra, and the honest thing is to predict its size rather than discover
it.

A fixed velocity error dV is the SAME field every step, so the errors are
correlated and the blob is displaced by d = T * |dV| after time T, not by
sqrt(N) * dt * |dV|.  For small d,

    F(x - d) - F(x)  ~  d . grad F      =>   RMS error ~ |d| * RMS|grad F|

    RMS|grad F| over the ball of 3s   {rg:.4f}
    one revolution                    T = {T_REV:.4f}

    PREDICTED  excess RMS of arm C over arm B  =  T * |dV| * {rg:.4f}
               to within a factor of 2, with |dV| the velocity model's
               own measured RMS against the analytic V.

That is refutable in the only way that matters: if the excess is far
larger, something other than dV is being imported, and the something is
the finding.
""")

# ── (7) the closed path, and MARL-9/MARL-10's law ─────────────────────
print("""(7) A ROTATION IS A CLOSED PATH, SO MARL-9's LAW SHOULD APPLY

MARL-9: capacity is paid per THING LEARNED, not per change.  MARL-10 made
it a law rather than a threshold: n * dK flat, so growth is

    K(N) = K0 + A * H(N),      H(N) the harmonic number      (LOGARITHMIC)

Eighty moves reached 16 241 against the law's 15 726 (1.033x) where a
linear tail would have reached 23 396.

A blob on a rotation at angle theta occupies, at theta + 2 pi, exactly the
state it did before.  So one revolution is one full traversal of a closed
trajectory, and revolution n is MARL-9's n-th visit to a world it knows.
""")
A = 1.0
for N in (1, 2, 4, 8):
    H = sum(1.0 / i for i in range(1, N + 1))
    print(f"    {N:>2} revolutions   H(N) = {H:.4f}   dK(N)/dK(1) = {1.0/N:.4f}")
print(f"""
    PREDICTED  arm A (rotation, projected):
                 dK(2)/dK(1) <= 0.60      (the law says 0.50)
                 dK(4)/dK(1) <= 0.35      (the law says 0.25)
                 K(4) <= (K0 + A*H(4)) * 1.15,  A fitted from revolution 1
                                                alone, per MARL-10's 1.033x

    REFUTED IF  population grows LINEARLY across four revolutions.  That
                would say MARL-9 and MARL-10's law does not survive
                transport, which is a bigger result than the phase's own
                headline and would be the finding.

    NOTE  arm B's swirl is a Taylor-Green cell.  Its streamlines are
          closed but its angular velocity is not uniform, so the blob is
          SHEARED and never exactly recurs.  Arm B should therefore grow
          faster than arm A and slower than linear: it is a closed path
          carrying genuinely new structure.  No number is pre-registered
          for it — the ordering is.
""")

# ── (8) the leading edge ──────────────────────────────────────────────
print(f"""(8) THE LEADING EDGE IS INVISIBLE FROM THE KERNEL CENTRES

§11 and §35 project at the current kernel centres.  A transported blob
moves into regions where there are no kernels, so no projection point is
there, so nothing observes that the field has arrived.  The trailing edge
decays correctly and the leading edge never grows.

    the fix       project on {{x_i}} UNION {{x_i + dt V(x_i)}} — the mass is
                  going to the forward-advected centres, and MARL's birth
                  rule then fires on coverage where it arrives

    PREDICTED  the ablation (current centres only), one revolution:
                 mass  <= 0.50 x its starting value
                 centroid displacement <= 0.20 x the reference's arc

    the mutation  this IS the gate's mutation: drop the forward set and
                  the blob stays where it was and shrinks.
""")

# ── (9) the headline ──────────────────────────────────────────────────
print(f"""(9) THE HEADLINE, AND WHAT WOULD REFUTE THE PHASE

    PREDICTED  arm B, one revolution of the swirl, local probes:
                 RMS / anchor  <= 0.25        (a constant scores 1.00)
                 population    >= 1.5 x arm E's
                 mass drift    <  20%

    REFUTED IF (a) arm B is no better than a constant predictor;
               (b) arm A lands where arm E does at the same cost — then
                   the projection has learned nothing the closed form did
                   not already give, and the interesting operator is warp;
               (c) the CFL number below is wrong about stability.

    per-step arc at the blob's radius   {ARC:.4f}
    blob width s                        {BLOB_S:.4f}
    arc / s                             {CFL:.4f}

    A backtrace shorter than the blob's own width lands inside the blob
    it came from, which is the regime a semi-Lagrangian scheme is stable
    in.  At {CFL:.2f} there is a 2.5x margin.  If arm B is unstable anyway,
    the instability is the projection and not the scheme, and THAT is a
    finding about P and not about advection.
""")

print("""(10) ONE CORRECTION, MADE BEFORE THE GATE RAN

(3) says arm E's number is "RMS against the analytic reference".  It is
not, and could not be: the model arm E starts from is a FIT, with its own
error against the blob, and a perfectly exact warp would still carry that
error into any score taken against the analytic field.

What G44 (b) measures instead is the warp against THE MODEL IT STARTED
FROM — at a quarter turn, read at the pre-image, and at a full revolution,
where the composition is the identity.  The bound of 1.0e-4 and its
derivation are unchanged; only the reference is.  Recorded here rather
than edited into (3), because a pre-registration that can be quietly
rewritten is not one.
""")

print("=" * 72)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 72)
