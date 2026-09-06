# Working in loam

## Running tests — the default is to run NOTHING

Pick a gate because the change can break the thing it watches, never to
feel reassured. Chris has asked for this in every sibling repo; a suite
run per edit makes the harness the activity rather than the work.

    zig build test -Dtest-filter=straddling   # one gate, seconds
    zig build test                            # 48 gates, ~3 min Debug — before a commit
    zig build test -Doptimize=ReleaseFast     # the same in ~20 s; know the delta, don't lean on it
    zig build verify-dump                     # loam-run writes a dump, the struple PYTHON port reads it
    zig build py-test                         # the ctypes binding, and G1 across two PROCESSES
    zig build run -- --help                   # loam-run, the seedbed

The suite is CPU-only and deterministic, so the calculus is spindrift's:
run a gate when you have changed what it watches, the lot once before a
commit. What is NOT cheap is downstream — matryoshka will read the tree,
the summaries and the sampling contract the way it reads spindrift's
population, and once it does, anything a host reads (`Snapshot`,
`Summary`, `Brick` layout, the C seam, the dump) puts its GPU sweep in
the blast radius.

Rules that hold whatever you picked:

- A gate that passed stays passed until the code changes.
- Debug builds while iterating. `loam-run --phases` prints wall-clock
  per phase; the numbers in the ledger state which build they came from.
- One GPU gate at a time, when a sibling repo's are involved.

## The ledger

`docs/implementation-notes.md` — every decision made while building, with
the mutation that paid for each gate. Same rules as rill's ledger, restated
at its head. Docs ride the same commit as the code they describe.

## House style

Write the reasoning into the code. A gate's comment should name the bug it
was paid for. A gate that cannot fail is decoration: check it fails against
the old behaviour before believing it — every gate in `src/tests.zig` has a
named mutation, executable where cheap, by hand where not, and the ledger
records which bit and which survived (a survived mutation is a finding:
either the gate does not vary on that axis, or the code is decoration).

Prose approves plausible semantics; execution approves actual semantics.
Read-aloud before naming; record rejected names. Recorded-not-built needs
a trigger. Loud, never a guess — a refusal lands on the node that refused.

## The sim's rules

- **Time is fed, never read.** `step(now)` carries `{frame, time_ns}`; dt
  is the fed delta; no wall clock reaches the sim. A regression is
  `error.TimeRegression`, never a clamp. The first tick is the epoch and
  moves nothing.
- **Addresses are integers; values are f32; movers are f64.** Lattice
  points and Morton keys are integers on the 20-bit lattice (R2). Channel
  values are f32 with a fixed evaluation order. Front positions are f64
  lattice units. Bit-identity (G1) is claimed per BINARY on ONE MACHINE:
  two processes of the same build agree, and Debug and ReleaseFast of one
  source agree here; f64 front positions pass through exp/sin/cos, and a
  different libm is unmeasured. A GPU twin is D3's problem and the
  integer lattice is the path there.
- **Operators write deltas, never bricks.** Region-local update entries,
  applied at commit in key order. No parallel phase can reach the result
  in a different order; G1 runs serial and over common's JobSystem and
  compares the bytes against a frozen reference.
- **What runs in parallel** when a world has `jobs` (or `step` is handed
  a system): the operate phase, applying deltas, finalize (summary and
  hash), blob authoring, the seam pass's collect phase, and the front
  pass into per-front sinks — all order-free; seam writes are sorted and
  applied in key order, sinks are merged in id order (Age set-once: the
  first in id order wins). The G3 ensemble runs its worlds one per core
  on plain threads. `loam-run --threads N` sets all of it, and the hash
  must not move — and "serial equals parallel" is not enough: G1's
  frozen reference is what caught the front pass summing two birth
  times while agreeing with itself at every thread count.
- **Randomness is counter-based.** `rng.Stream` hashes (seed, who, epoch,
  counter); nothing draws sequentially, so parallel order cannot leak in.
- **Snapshots are immutable and refcounted.** A published brick is never
  handed out as `*Brick`. The commit clones what it changes; untouched
  subtrees are shared by identity (G4 checks identity, not equality).
  Readers `acquire` through a hazard slot, lock-free (G8).

## The seam contract

Every brick stores its own faces, so two bricks sharing a face both hold
it. At commit, over every changed brick's surface: a shared point takes
the finest holder's value (ties: the holder that wrote deltas this
commit, then the lowest key); a fine sample on a face shared with a
coarser brick, off the coarse lattice, takes the coarse interpolant. The
guard (`guards.zig`) reconstructs every shared face from both sides by
the slow general path; the commit collects writes in parallel through a
neighbourhood cache and applies them sorted. They must agree, and the
guard is the witness, not the cache.

## Thresholds are Christian's

`src/thresholds.zig` holds every ⟨…⟩ from the brief's gate table as a
PROPOSED value. Do not tune a threshold to make a gate pass; change the
code, or record the finding and ask.
