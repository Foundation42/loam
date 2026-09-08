#!/usr/bin/env python3
"""edge_rbf — how tightly can a sum of anisotropic Gaussians hold an edge?

Christian's thread, pulled from Bresenham: "There comes a question about
drawing straight lines with RBFs and residuals and how tight you want them.
That seems to be an experiment for some simple Python outside of MARL, so we
can sweep it and play."

It is the right question to ask right now, because MARL-22 just found that
the occlusion cache's error is 77% REPRESENTATION and that a third of what
it was representing was the STEP at a surface. So: what does a step actually
cost a Gaussian basis, and what changes it?

This is deliberately OUTSIDE MARL. No learner, no births, no NLMS — centres
are placed analytically and the weights are least-squares. That isolates
what the BASIS can do from what the LEARNER finds, which are different
questions and were tangled together in every phase so far.

The kernel is MARL's, term for term, including the hard cutoff:

    g(q) = exp(-r²/2)  for r² <= CUTOFF, and EXACTLY 0 beyond

which is why a plateau is not free here either.

    python3 tools/edge_rbf.py                      # all three sweeps
    python3 tools/edge_rbf.py --sweep aspect       # the Bresenham one
    python3 tools/edge_rbf.py --sweep layers       # step against coarse+residual
    python3 tools/edge_rbf.py --sweep count        # RMS against kernel count
"""

from __future__ import annotations

import argparse
import math

import numpy as np

CUTOFF = 32.0          # MARL's, so the support is compact and a plateau costs
CUTOFF_R = math.sqrt(CUTOFF)
RIDGE = 1e-6           # only to keep the normal equations conditioned


# ── targets ──────────────────────────────────────────────────────────

def signed_distance(P, kind, R):
    """Signed distance to the edge, positive on the 'inside'.

    A straight edge has zero curvature; a circle of radius R has 1/R. The
    sweep is over R because curvature is the only thing that limits how far
    a kernel may run straight — which is Bresenham's question exactly.
    """
    if kind == "line":
        return 0.5 - P[:, 1]
    d = np.hypot(P[:, 0] - 0.5, P[:, 1] - 0.5)
    return R - d


def target(P, kind, R, form, width):
    """`step` is 1 inside and 0 outside — what ambient occlusion looks like
    across a surface, and what a single layer has to swallow whole.

    `ridge` is the same edge with NO plateau: nonzero only within `width` of
    it. This is what a RESIDUAL layer is handed once a coarse layer has
    taken the plateau, and MARL-16 is why the distinction matters — zero is
    what an empty model already predicts, so a compactly supported target
    costs nothing where it is zero.
    """
    phi = signed_distance(P, kind, R)
    if form == "step":
        return 0.5 * (1 + np.tanh(phi / width))
    # the step's derivative, normalised to peak at 1: a compact ridge.
    return 1.0 / np.cosh(phi / width) ** 2


# ── the basis ────────────────────────────────────────────────────────

def place(kind, R, n, sigma_n, aspect):
    """`n` kernels ON the edge, tangent-aligned, with the given aspect.

    Returns (centres, inverse-covariance factors). The major axis follows
    the edge and the minor axis is the normal, which is the orientation an
    anisotropic kernel WOULD take if a learner found it — the point of
    placing them analytically is to ask what the basis can do when it is
    oriented correctly, separately from whether descent gets there.
    """
    sigma_t = sigma_n * aspect
    cs, Ls = [], []
    if kind == "line":
        xs = (np.arange(n) + 0.5) / n
        for x in xs:
            cs.append((x, 0.5))
            # tangent is +x, normal is +y
            Ls.append(np.diag([1 / sigma_t, 1 / sigma_n]))
    else:
        for k in range(n):
            th = 2 * math.pi * (k + 0.5) / n
            c = (0.5 + R * math.cos(th), 0.5 + R * math.sin(th))
            t = np.array([-math.sin(th), math.cos(th)])   # tangent
            nrm = np.array([math.cos(th), math.sin(th)])  # normal
            # rows of L are the axes scaled by 1/sigma: L·d gives (t/σt, n/σn)
            Ls.append(np.vstack([t / sigma_t, nrm / sigma_n]))
            cs.append(c)
    return np.array(cs), np.array(Ls)


def design(P, cs, Ls):
    """The Gram matrix of the basis at the sample points, with MARL's hard
    cutoff — beyond √32 Mahalanobis widths a kernel contributes EXACTLY 0."""
    A = np.empty((P.shape[0], len(cs)), np.float64)
    for j, (c, L) in enumerate(zip(cs, Ls)):
        d = P - c
        v = d @ L.T
        r2 = np.einsum("ij,ij->i", v, v)
        g = np.exp(-0.5 * r2)
        g[r2 > CUTOFF] = 0.0
        A[:, j] = g
    return A


def fit_rms(P_fit, y_fit, P_ev, y_ev, cs, Ls):
    """Least squares by SVD, not by normal equations.

    `AᵀA` squares the condition number, and a basis whose kernels are
    narrower than the feature they are fitting is badly conditioned by
    nature — the first form of this program used normal equations and
    reported a fit getting FIFTY TIMES worse as the basis got finer, which
    would have been a spectacular claim about representation and was
    arithmetic. `lstsq` truncates the small singular values instead.
    """
    A = design(P_fit, cs, Ls)
    w, *_ = np.linalg.lstsq(A, y_fit, rcond=1e-8)
    rf = A @ w - y_fit
    r = design(P_ev, cs, Ls) @ w - y_ev
    return float(np.sqrt(np.mean(r * r))), float(np.sqrt(np.mean(rf * rf)))


def points(rng, n):
    return rng.random((n, 2))


def anchor(y):
    """MARL-17's rule, and it is not optional: an RMS without the constant
    predictor's score beside it is a number with no scale."""
    return float(np.std(y))


# ── the sweeps ───────────────────────────────────────────────────────

def sweep_aspect(a, rng):
    print("\n" + "=" * 74)
    print("THE BRESENHAM SWEEP — how many kernels per unit of edge?")
    print("=" * 74)
    print("""
An elongated kernel laid along a circle of radius R with tangent half-length
L departs from the curve by a sagitta of about L²/(2R). It stops hugging the
edge once that exceeds its own normal width, so

    L²/(2R) <~ σ_n   →   aspect = L/σ_n <~ sqrt(2R/σ_n)

That is Bresenham's question in continuous form: how far you may run before
the curve forces a step.

The first form of this sweep held the kernel COUNT fixed and swept aspect,
and found elongation worth 3.7% on a straight edge — because at 64 kernels
over a unit edge with σ_n = 0.01 the basis is already tiled 1.6σ apart and
there is nothing for a longer kernel to do. The question that has an answer
is the other way round: **at each aspect, how FEW kernels reach a given
accuracy?** That is what a longer kernel is supposed to buy.

Below: the smallest n on a doubling ladder whose RMS clears a fifth of the
constant predictor's, which is a fit rather than a gesture.
""")
    P_fit, P_ev = points(rng, a.fit), points(rng, a.eval)
    ns = [4, 8, 16, 32, 64, 128, 256]
    for kind, R in (("line", 0.0), ("circle", 0.40), ("circle", 0.30), ("circle", 0.20), ("circle", 0.10)):
        y_fit = target(P_fit, kind, R, "ridge", a.width)
        y_ev = target(P_ev, kind, R, "ridge", a.width)
        anc = anchor(y_ev)
        want = anc / 5
        lab = "straight edge" if kind == "line" else f"circle R = {R}"
        pred = "—" if kind == "line" else f"{math.sqrt(2 * R / a.sigma):.1f}"
        print(f"  {lab}   (constant {anc:.5f}, target RMS {want:.5f}; "
              f"σ_n = {a.sigma}; sagitta bound on aspect {pred})")
        print(f"    {'aspect':>8} {'σ_t':>9} {'kernels needed':>16} {'RMS there':>11} {'saving':>8}")
        base = None
        # A √2 ladder, because the sagitta bound scales as √R and a
        # doubling ladder cannot resolve a √2 difference — the first form
        # of this sweep put the cliff "between 2 and 4" for both R = 0.30
        # and R = 0.15, which is the ladder speaking, not the geometry.
        for asp in (1, 1.41, 2, 2.83, 4, 5.66, 8, 11.3, 16, 32, 64):
            hit = None
            for n in ns:
                cs, Ls = place(kind, R, n, a.sigma, asp)
                r = fit_rms(P_fit, y_fit, P_ev, y_ev, cs, Ls)[0]
                if r <= want:
                    hit = (n, r)
                    break
            if base is None and hit:
                base = hit[0]
            if hit is None:
                if last is not None:
                    print(f"    {asp:>8.2f} {a.sigma*asp:>9.4f} {'never (> 256)':>16}   ← THE CLIFF")
                    cliff = last
                    last = None
                continue
            last = asp
            sav = f"{base/hit[0]:.1f}x" if base else "—"
            print(f"    {asp:>8.2f} {a.sigma*asp:>9.4f} {hit[0]:>16} {hit[1]:>11.5f} {sav:>8}")
        if kind != "line" and cliff:
            bound = math.sqrt(2 * R / a.sigma)
            print(f"    → the last aspect that works is {cliff:.2f}; the sagitta bound is {bound:.1f}, so the usable fraction of it is {cliff/bound:.3f}")
        print()


def tiling(n_side, extra=2.0):
    """A uniform isotropic tiling of the unit square: `n_side²` kernels with
    σ set so the cutoff boxes just cover. This is what a learner with no
    knowledge of where the edge is would end up building."""
    gx, gy = np.meshgrid((np.arange(n_side) + 0.5) / n_side,
                         (np.arange(n_side) + 0.5) / n_side)
    cs = np.stack([gx.ravel(), gy.ravel()], 1)
    sig = extra / n_side / CUTOFF_R
    Ls = np.array([np.diag([1 / sig, 1 / sig])] * len(cs))
    return cs, Ls


def sweep_layers(a, rng):
    print("\n" + "=" * 74)
    print("THE RESIDUAL SWEEP — is a step cheaper as coarse + residual?")
    print("=" * 74)
    print("""
MARL-16: a Gaussian basis with a hard cutoff cannot cheaply represent a
plateau of ANY value, and zero is special only because it is what an empty
model already predicts. A STEP is half plateau. A RIDGE — the same edge with
the plateau taken away by a coarse layer — is compactly supported and free
wherever it is zero.

The first form of this sweep gave the one-layer arm kernels ON THE EDGE at
the residual's own σ, and it scored 1.407x a constant: it could not reach
the plateau at all. That is a straw man. A single layer that does not know
where the edge is tiles the DOMAIN, which is what a learner builds, so that
is what it gets here — and at equal total kernels.
""")
    P_fit, P_ev = points(rng, a.fit), points(rng, a.eval)
    for kind, R in (("line", 0.0), ("circle", 0.30)):
        lab = "straight edge" if kind == "line" else f"circle R = {R}"
        y_f = target(P_fit, kind, R, "step", a.width)
        y_e = target(P_ev, kind, R, "step", a.width)
        anc = anchor(y_e)
        print(f"  {lab}, target = STEP (a constant predictor scores {anc:.5f})")
        print(f"    {'total k':>8} {'arrangement':>36} {'RMS':>10} {'x constant':>11} {'vs 1-layer':>11}")
        for side in (6, 8, 11, 16):
            total = side * side
            # ONE LAYER: a uniform tiling, all of the budget.
            cs, Ls = tiling(side)
            one = fit_rms(P_fit, y_f, P_ev, y_e, cs, Ls)[0]
            print(f"    {total:>8} {f'one layer, {side}x{side} tiling':>36} {one:>10.5f} {one/anc:>11.3f} {'1.00':>11}")

            # TWO LAYERS: HALF the budget as a coarser tiling, the rest on
            # the edge. The coarse layer takes the plateau; the residual it
            # leaves is compactly supported, which is the half MARL-16 says
            # is free.
            cside = max(2, int(round(side / math.sqrt(2))))
            ccs, cLs = tiling(cside)
            Ac = design(P_fit, ccs, cLs)
            wc = np.linalg.solve(Ac.T @ Ac + RIDGE * np.eye(len(ccs)), Ac.T @ y_f)
            res_f = y_f - Ac @ wc
            res_e = y_e - design(P_ev, ccs, cLs) @ wc
            n_res = total - len(ccs)
            if n_res < 4:
                continue
            # HOW TIGHT DO YOU WANT THEM. The residual a coarse tiling
            # leaves is not as sharp as the original edge — it is as sharp
            # as the coarse layer's own σ, because that is the scale at
            # which the coarse fit stops following. Handing the residual
            # layer kernels matched to the ORIGINAL edge width makes them
            # far too narrow to cover what is actually left, and the first
            # form of this sweep did exactly that.
            csig = 2.0 / cside / CUTOFF_R
            best = (1e9, None)
            for mult in (0.25, 0.5, 1.0, 2.0):
                rsig = csig * mult
                rcs, rLs = place(kind, R, n_res, rsig, a.aspect)
                r = fit_rms(P_fit, res_f, P_ev, res_e, rcs, rLs)[0]
                if r < best[0]:
                    best = (r, mult)
            two, mult = best
            name = f"coarse {cside}x{cside} + {n_res} on the edge"
            print(f"    {total:>8} {name:>36} {two:>10.5f} {two/anc:>11.3f} {one/two:>10.2f}x"
                  f"   (residual σ = {mult:g}× the coarse layer's)")
        print()


def sweep_count(a, rng):
    print("\n" + "=" * 74)
    print("THE CAPACITY SWEEP — what does an edge cost, per kernel?")
    print("=" * 74)
    print("""
MARL-22 found that on the occlusion fixture MORE RESOLUTION MADE IT WORSE —
regions 6 → 12 gave 9 711 kernels against 1 989 and a 1.392× worse fit. That
was a statement about a LEARNER on finite evidence. This is the same axis
with the learner removed: least squares, analytic placement, unlimited
evidence. If the basis scales cleanly here, MARL-22's regression is squarely
the learner's and not the representation's.
""")
    P_fit, P_ev = points(rng, a.fit), points(rng, a.eval)
    for kind, R in (("circle", 0.30),):
        # The RIDGE again: edge-placed kernels cannot reach a plateau, and
        # asking them to is the straw man the layers sweep already retired.
        y_f = target(P_fit, kind, R, "ridge", a.width)
        y_e = target(P_ev, kind, R, "ridge", a.width)
        print(f"  circle R = {R}, target = ridge (a constant scores {anchor(y_e):.5f})")
        # BOTH errors, because they separate the two ways a fine basis can
        # fail. If the FIT error keeps falling while the EVAL error rises,
        # the basis can represent the target and the evidence is what ran
        # out — MARL-11's law. If both rise, the system is ill-conditioned
        # and the answer is arithmetic rather than representation.
        print(f"    {'kernels':>8} {'σ_n':>9} {'iso eval':>11} {'iso fit':>10} {'aniso eval':>12} {'aniso fit':>10} {'ratio':>8}")
        for n in (16, 32, 64, 128, 256):
            # σ scales with the spacing, which is what a finer basis means.
            # σ tracks the SPACING, which is what "a finer basis" means —
            # and it is floored at a quarter of the feature's own width,
            # because a kernel far narrower than the thing it is fitting
            # gives an ill-conditioned system rather than a better fit.
            sig = max(a.width / 4, a.sigma * 64 / n)
            ci, Li = place(kind, R, n, sig, 1)
            ca, La = place(kind, R, n, sig, a.aspect)
            ri, ri_f = fit_rms(P_fit, y_f, P_ev, y_e, ci, Li)
            ra, ra_f = fit_rms(P_fit, y_f, P_ev, y_e, ca, La)
            print(f"    {n:>8} {sig:>9.5f} {ri:>11.5f} {ri_f:>10.5f} {ra:>12.5f} {ra_f:>10.5f} {ri/ra:>8.2f}")
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sweep", default="all", choices=["all", "aspect", "layers", "count"])
    ap.add_argument("--n", type=int, default=64, help="kernels on the edge")
    ap.add_argument("--sigma", type=float, default=0.01, help="normal width")
    ap.add_argument("--aspect", type=float, default=8.0)
    ap.add_argument("--width", type=float, default=0.01, help="the edge's own softness")
    ap.add_argument("--form", default="step", choices=["step", "ridge"])
    ap.add_argument("--fit", type=int, default=20000)
    ap.add_argument("--eval", type=int, default=20000)
    ap.add_argument("--seed", type=int, default=22)
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    if a.sweep in ("all", "aspect"):
        sweep_aspect(a, rng)
    if a.sweep in ("all", "layers"):
        sweep_layers(a, rng)
    if a.sweep in ("all", "count"):
        sweep_count(a, rng)


if __name__ == "__main__":
    main()
