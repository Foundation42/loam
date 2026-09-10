#!/usr/bin/env python3
"""obs7_predict — OBS-7's gate numbers, before its run.

The note's §29 level 3, by way of its §27:

    Once structured residuals can be detected, introduce a small library
    of candidate operators ... the experiment succeeds if optimisation
    drives the true coefficient toward its value while irrelevant
    operator coefficients approach zero.

OBS-1 did level 1 (state), OBS-2 level 2 (parameters of a hidden
potential), and OBS-6 made the structural-pressure signal readable by
removing the optimiser's wander from it.  §29: "each level should be
demonstrated independently before proceeding to the next."

**The rig already contains a hidden operator.**  `trajectory.zig`'s law is

    xdot = omega * R (x - c)  -  sum_i w_i grad phi_i(x)

and OBS-3 through OBS-6 used `omega` as a KNOWN, GIVEN knob: correct = 0,
wrong = 0.3.  Level 3 is the same rig with omega taken away — the truth has
it, the learner is not told, and must find it in a library.

    python3 tools/obs7_predict.py
"""

import math

# The sampled region, from `observational_windows.start`: 0.15 + 0.7*u.
LO, HI = 0.15, 0.85
C = 0.5
OMEGA = 0.3          # OBS-3/OBS-4's own value, not a new one


def rms_d():
    """RMS |x - c| over the sampled square, in closed form.

    E[d^2] per axis is the variance of a uniform on [-.35,.35] = .35^2/3.
    """
    h = (HI - LO) / 2
    return math.sqrt(2 * h * h / 3)


print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-7 — operator inference, and the identifiability it exposes")
print("PRE-REGISTERED, before the run")
print("=" * 74)

u = rms_d()
print(f"""
(1) THE LIBRARY, AND THE HELMHOLTZ PREDICTION THAT COMES WITH IT

Five affine velocity candidates, with d = x - c.  Only the first is in the
truth.  Each is given its own learnable coefficient alongside the nine
potential coefficients the learner already fits.

    k  operator V_k(x)      is it a gradient?
    0  (-d_y,  d_x)         NO   -- divergence free, curl 2
    1  ( d_x,  d_y)         YES  -- grad of |d|^2 / 2
    2  ( d_y,  d_x)         YES  -- grad of d_x d_y
    3  ( 1, 0 )             YES  -- grad of x
    4  ( 0, 1 )             YES  -- grad of y

**The learner is already fitting a pure gradient field.**  Its potential
term is -grad(sum_i w_i phi_i), so anything in the library that is ITSELF a
gradient is competing for the same explanation.  Helmholtz splits a
velocity field into a curl-free part and a divergence-free part, and
exactly one of these five candidates lies in the second.

So the prediction is not "the true coefficient is recovered and the rest go
to zero".  It is sharper and it is only half that:

    the ROTATION is identifiable because nothing else in the model can
    produce curl; candidates 1 to 4 are DEGENERATE with the potential the
    learner is already free to reshape

The degeneracy is PARTIAL rather than exact, and that matters.  Nine
isotropic Gaussians of sigma .22 on a 3x3 lattice over [.25,.75] cannot
reproduce a global linear ramp across the sampled [{LO},{HI}] square exactly.
So the split between "potential" and "candidate 3" is constrained but
under-determined, and its resting place is set by initialisation and the
optimiser's path rather than by the observations.

(2) THE UNITS, SO THE COEFFICIENTS CAN BE COMPARED AT ALL

A raw coefficient is not comparable across operators of different shape.
Each is reported as the RMS VELOCITY it contributes over the sampled
region, theta_k * rms|V_k|, which is derived and not chosen:

    rms |d| over the square            {u:.4f}
    unit for k = 0, 1, 2 (all ~ |d|)   {u:.4f}
    unit for k = 3, 4 (uniform)        1.0000

    so the truth's rotation contributes  omega * {u:.4f} = {OMEGA * u:.4f}

For scale: the potential's own velocity is order .1 (weights .015 to .045
against a peak |grad phi| of 1/(sigma sqrt e) = {1 / (0.22 * math.sqrt(math.e)):.3f}), so the
hidden rotation is a comparable term and not a perturbation.
""")

print(f"""(3) THE FOUR REGISTERED NUMBERS

  (a) RECOVERY.  |omega_hat - omega| / omega <= 0.10, pooled over seeds
      7/19/41.  This is §27's first half and it should hold cleanly,
      because the rotation is the one candidate the potential cannot
      imitate.

  (b) THE NULL, and §27's second half.  Re-run with a truth containing NO
      rotation.  The recovered rotation must come back near zero, or the
      library is merely soaking up fit error:

          |omega_hat| * unit  <=  0.10 * {OMEGA * u:.4f}  =  {0.1 * OMEGA * u:.5f}

      Registered as a separate arm rather than inferred from (a), because
      "recovers what is there" and "does not invent what is not" are
      different claims and only the second is a null.

  (c) IDENTIFIABILITY CONTRAST.  Across the three seeds, the coefficient
      of variation of the curl-free candidates' contributions must be at
      least 5x the rotation's:

          mean CV(k = 1..4)  >=  5 * CV(k = 0)

      This is the phase's real finding if it holds, and it is a PREDICTED
      FAILURE of §27's stated success criterion: four of the five
      irrelevant coefficients will not approach zero, for a reason that
      has nothing to do with the optimiser and everything to do with what
      the model class already spans.

  (d) PREDICTION SURVIVES NON-IDENTIFIABILITY.  §33's distinction, and
      the reason (c) is not a disaster.  Held-out endpoint RMS with the
      library, against the same fit with the law left incomplete (no
      library at all, which is OBS-3's wrong-dynamics arm):

          RMS(library) / RMS(incomplete)  <=  0.25

      The SPLIT between potential and candidates is under-determined; the
      SUM is not.  A model can be unidentifiable in its parameters and
      perfectly determined in its predictions, and this measures both on
      one run.

(4) WHAT WOULD MAKE THIS INTERESTING RATHER THAN TIDY

  (i)  (a), (b) and (d) hold and (c) holds.  Level 3 works for operators
       outside the span of what is already being learned, and fails for
       operators inside it.  That is a design rule for level 4: a library
       is only well posed against a model class it is not already inside.

  (ii) (c) FAILS -- the curl-free candidates do go to zero and stay there
       across seeds.  Then the nine-Gaussian potential is far less able to
       imitate a linear ramp than the argument assumes, the degeneracy is
       nominal rather than real at this basis, and the interesting
       follow-up is how fine a potential basis has to be before level 3
       stops working.  That would be a better phase than this one.

  (iii) (a) fails.  Then trajectory observations do not determine the curl
       even in principle here -- most likely because the paths are short
       and stay near their starts, so the sampled region is much smaller
       than the square this is derived over.  Measurable directly, and it
       would be a statement about the sensor design rather than the
       algebra.

(5) WHAT IS NOT BEING CLAIMED

This is level 3 with a library that CONTAINS the missing term, which §27
says explicitly ("whether the MARL algebra can recover a missing physical
term when that term already exists within its operator vocabulary").
Nothing here bears on level 4.  The fixture is one 2-D first-order flow,
the potential basis is frozen, and allocation is not adaptive -- OBS-6's
recalibrated birth signal is what would drive a level-4 search and is
deliberately not used here, so that operator recovery and capacity
acquisition are measured apart.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
