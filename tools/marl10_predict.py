#!/usr/bin/env python3
"""marl10_predict — MARL-10's gate numbers, before its run.

MARL-9 left exactly one thing twelve moves could not settle: on a fully
recurrent world the marginal cost of a revisit decays, but does it decay to
ZERO or to a small constant? Logarithmic growth is effectively bounded for
any practical horizon; linear growth at 160 kernels a move is not.

This is not a threshold plucked from a range. It is a LAW fitted to the
twelve points MARL-9 already produced, and the run is its test.
"""

K = [5233, 7373, 8344, 9089, 9616, 9984, 10355, 10660, 10882, 11098, 11327, 11497, 11656]


def main():
    d = [K[i + 1] - K[i] for i in range(len(K) - 1)]
    prod = [(i + 1) * x for i, x in enumerate(d)]
    A = sum(prod) / len(prod)
    print("MARL-10 — predictions, written before the run")
    print("=" * 70)
    print("\n0. The law, fitted to MARL-9's twelve moves")
    print("   n·ΔK, which is constant if and only if the decay is harmonic:")
    print("   " + "  ".join(f"{p:.0f}" for p in prod))
    print(f"   mean {A:.0f}, spread {min(prod):.0f}–{max(prod):.0f}, and no trend across")
    print("   twelve points. So ΔK ≈ A/n, and cumulative growth is LOGARITHMIC:")
    print("       K(N) ≈ K₀ + A·H(N)")
    print("   which is unbounded in principle and bounded in any practice.")

    print("\n1. The test, and it is a real discrimination")
    print("   Against the alternative that the decay has bottomed out and the")
    print(f"   tail is linear at {d[-1]} kernels a move:")
    print(f"   {'N':>5} {'harmonic':>10} {'linear tail':>12} {'apart':>7}")
    for N in (20, 40, 80):
        h = K[0] + A * sum(1.0 / n for n in range(1, N + 1))
        l = K[12] + (N - 12) * d[-1]
        print(f"   {N:>5} {h:>10.0f} {l:>12.0f} {100*(l/h-1):>6.0f}%")
    h80 = K[0] + A * sum(1.0 / n for n in range(1, 81))
    print(f"\n   → MARL10_LOGARITHMIC = 1.15: K(80) over the harmonic prediction")
    print(f"     of {h80:.0f}. That ceiling is {h80*1.15:.0f}, which is 79% of what a")
    print("     linear tail would reach — so the two hypotheses cannot both")
    print("     pass, which is the point of running eighty rather than twenty.")

    print("\n2. And the model must still be healthy at the end")
    print("   Eighty world-changes is far outside anything this campaign has")
    print("   run. Accuracy must not drift upward and the weights must stay in")
    print("   the convergent regime, or a bounded population is only bounded")
    print("   because the thing stopped working.")
    print("   → MARL10_STABLE = 1.25: RMS at move 80 over RMS at move 12.")
    print("   → MARL1_OVERRESPONSIBILITY unchanged, on both levels.")
    print()


if __name__ == "__main__":
    main()
