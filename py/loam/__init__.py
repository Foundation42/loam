"""loam — sparse field dynamics, from Python.

A pure-stdlib ctypes binding over ``libloam.so`` (``zig build`` puts it in
``zig-out/lib``). Every call is one of the seedbed's authoring verbs or a
read of the published snapshot; the world underneath is the Zig one, so a
run driven from here and a run driven from ``loam-run`` with the same inputs
print the same hash.

    import loam
    w = loam.World(seed=7)
    w.blob("growth", (0, 24, 0), 56, 1.0)
    w.blob("light", (40, 60, 0), 64, 1.0)
    w.plant((0, 0, 0), (0, 1, 0), tropism_light=0.6)
    w.apply()
    for t in range(60):
        w.step(t, t * 1_000_000_000)
    print(w.root_hash().hex(), w.stats())
"""

from __future__ import annotations

import ctypes
import os
import sys
from dataclasses import dataclass
from typing import Iterable, Sequence

_HERE = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.environ.get("LOAM_LIB"),
    os.path.join(_HERE, "..", "..", "zig-out", "lib", "libloam.so"),
    os.path.join(_HERE, "..", "..", "zig-out", "lib", "libloam.dylib"),
]


def _load() -> ctypes.CDLL:
    for c in _CANDIDATES:
        if c and os.path.exists(c):
            return ctypes.CDLL(os.path.abspath(c))
    raise OSError("libloam not found: run `zig build` in the loam repo, or set LOAM_LIB")


_lib = None


def lib() -> ctypes.CDLL:
    global _lib
    if _lib is None:
        _lib = _load()
        _declare(_lib)
    return _lib


class Stats(ctypes.Structure):
    _fields_ = [
        ("vid", ctypes.c_uint64),
        ("epoch", ctypes.c_uint64),
        ("bricks", ctypes.c_uint32),
        ("nodes", ctypes.c_uint32),
        ("fronts", ctypes.c_uint32),
        ("fronts_live", ctypes.c_uint32),
        ("active", ctypes.c_uint32),
        ("dirty", ctypes.c_uint32),
        ("region_evals", ctypes.c_uint64),
        ("front_steps", ctypes.c_uint64),
        ("bricks_changed", ctypes.c_uint64),
        ("bricks_materialised", ctypes.c_uint64),
        ("spawns", ctypes.c_uint64),
    ]

    def as_dict(self) -> dict:
        return {name: getattr(self, name) for name, _ in self._fields_}


def _declare(L: ctypes.CDLL) -> None:
    P = ctypes.c_void_p
    d = ctypes.c_double
    f = ctypes.c_float
    u32 = ctypes.c_uint32
    u64 = ctypes.c_uint64
    L.loam_version.restype = u32
    L.loam_world_new.restype = P
    L.loam_world_new.argtypes = [u64, d, d, d, d, u32]
    L.loam_world_free.argtypes = [P]
    L.loam_error_name.restype = ctypes.c_char_p
    L.loam_error_name.argtypes = [P]
    L.loam_channel.restype = ctypes.c_int
    L.loam_channel.argtypes = [P, ctypes.c_char_p]
    L.loam_channel_register.restype = ctypes.c_int
    L.loam_channel_register.argtypes = [P, ctypes.c_char_p, f, f]
    L.loam_blob.restype = ctypes.c_int
    L.loam_blob.argtypes = [P, u32, d, d, d, d, f, u32]
    L.loam_plant.restype = ctypes.c_int
    L.loam_plant.argtypes = [P, d, d, d, d, d, d, f, f, f, f, f, f]
    L.loam_damage.restype = ctypes.c_int
    L.loam_damage.argtypes = [P, d, d, d, d, d, d]
    L.loam_clear.restype = ctypes.c_int
    L.loam_clear.argtypes = [P, u32]
    L.loam_apply.restype = ctypes.c_int
    L.loam_apply.argtypes = [P]
    L.loam_add_diffusion.restype = ctypes.c_int
    L.loam_add_diffusion.argtypes = [P, u32, f]
    L.loam_add_decay.restype = ctypes.c_int
    L.loam_add_decay.argtypes = [P, u32, f]
    L.loam_add_advection.restype = ctypes.c_int
    L.loam_add_advection.argtypes = [P, u32, d, d, d]
    L.loam_add_healing.restype = ctypes.c_int
    L.loam_add_healing.argtypes = [P, f, f, f]
    L.loam_step.restype = ctypes.c_int
    L.loam_step.argtypes = [P, u64, u64]
    L.loam_sample.restype = f
    L.loam_sample.argtypes = [P, u32, d, d, d]
    L.loam_sample_many.restype = ctypes.c_int
    L.loam_sample_many.argtypes = [P, u32, ctypes.c_size_t, ctypes.POINTER(d), ctypes.POINTER(f)]
    L.loam_slice.restype = ctypes.c_int
    L.loam_slice.argtypes = [P, u32, u32, d, d, d, d, d, u32, ctypes.POINTER(f)]
    L.loam_project.restype = ctypes.c_int
    L.loam_project.argtypes = [P, u32, u32, d, d, d, d, d, d, u32, u32, ctypes.POINTER(f)]
    L.loam_root_hash.restype = ctypes.c_int
    L.loam_root_hash.argtypes = [P, ctypes.c_char_p]
    L.loam_content_hash.restype = ctypes.c_int
    L.loam_content_hash.argtypes = [P, ctypes.c_char_p]
    L.loam_stats.restype = ctypes.c_int
    L.loam_stats.argtypes = [P, ctypes.POINTER(Stats)]
    L.loam_total.restype = d
    L.loam_total.argtypes = [P, u32]
    L.loam_inside_count.restype = u64
    L.loam_inside_count.argtypes = [P]
    L.loam_capsule.restype = ctypes.c_int
    L.loam_capsule.argtypes = [P, d, d, d, d, d, d, d, f, u32]
    L.loam_fronts.restype = ctypes.c_size_t
    L.loam_fronts.argtypes = [P, ctypes.c_size_t, ctypes.POINTER(d)]
    L.loam_ray_count.restype = ctypes.c_int
    L.loam_ray_count.argtypes = [P, u32, d, d, d, d, d, d, ctypes.POINTER(u64), ctypes.POINTER(u64)]
    L.loam_dump.restype = ctypes.c_int
    L.loam_dump.argtypes = [P, ctypes.c_char_p]


class LoamError(RuntimeError):
    pass


def version() -> int:
    return lib().loam_version()


class World:
    """A loam world. World units; the default frame is one unit per
    lattice cell with the world origin at the lattice centre."""

    def __init__(self, seed: int = 0, extent: float = 0.0, origin=(0.0, 0.0, 0.0), default_gauge: int = 0):
        self._L = lib()
        self._h = self._L.loam_world_new(seed, extent, *origin, default_gauge)
        if not self._h:
            raise LoamError("loam_world_new failed")

    def close(self) -> None:
        if self._h:
            self._L.loam_world_free(self._h)
            self._h = None

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def _check(self, rc: int) -> None:
        if rc < 0:
            raise LoamError(self._L.loam_error_name(self._h).decode())

    # ── channels ──────────────────────────────────────────────────────
    def channel(self, name: str) -> int:
        bit = self._L.loam_channel(self._h, name.encode())
        if bit < 0:
            raise LoamError(f"unknown channel {name!r}")
        return bit

    def register(self, name: str, lo: float = float("-inf"), hi: float = float("inf")) -> int:
        bit = self._L.loam_channel_register(self._h, name.encode(), lo, hi)
        self._check(bit)
        return bit

    # ── authoring (queued; apply commits) ─────────────────────────────
    def blob(self, channel: str, centre, radius: float, amplitude: float = 1.0, gauge: int = 0) -> None:
        self._check(self._L.loam_blob(self._h, self.channel(channel), *centre, radius, amplitude, gauge))

    def plant(self, pos, direction=(0, 1, 0), radius: float = 0, length: float = 0, deposit: float = 1.0,
              tropism_light: float = 0.0, tropism_stimulus: float = 0.0, consume: float = -1.0) -> None:
        self._check(self._L.loam_plant(self._h, *pos, *direction, radius, length, deposit, tropism_light, tropism_stimulus, consume))

    def damage(self, lo, hi) -> None:
        self._check(self._L.loam_damage(self._h, *lo, *hi))

    def capsule(self, p0, p1, radius: float, k: float = 0.0, gauge: int = 0) -> None:
        """A straight capsule into the carrier (`surface`): signed distance, smooth-unioned with collar k."""
        self._check(self._L.loam_capsule(self._h, *p0, *p1, radius, k, gauge))

    def clear(self, channel: str) -> None:
        self._check(self._L.loam_clear(self._h, self.channel(channel)))

    def apply(self) -> None:
        self._check(self._L.loam_apply(self._h))

    # ── operators ─────────────────────────────────────────────────────
    def add_diffusion(self, channel: str, rate: float) -> None:
        self._check(self._L.loam_add_diffusion(self._h, self.channel(channel), rate))

    def add_decay(self, channel: str, tau: float) -> None:
        self._check(self._L.loam_add_decay(self._h, self.channel(channel), tau))

    def add_advection(self, channel: str, velocity) -> None:
        self._check(self._L.loam_add_advection(self._h, self.channel(channel), *velocity))

    def add_healing(self, rate: float = 1.0, front_radius: float = 2.0, front_length: float = 12.0) -> None:
        self._check(self._L.loam_add_healing(self._h, rate, front_radius, front_length))

    # ── time ──────────────────────────────────────────────────────────
    def step(self, frame: int, time_ns: int) -> None:
        self._check(self._L.loam_step(self._h, frame, time_ns))

    def run(self, steps: int, dt_ns: int = 1_000_000_000, start_frame: int = 0) -> None:
        for i in range(steps + 1):
            self.step(start_frame + i, (start_frame + i) * dt_ns)

    # ── reading ───────────────────────────────────────────────────────
    def sample(self, channel: str, p) -> float:
        return self._L.loam_sample(self._h, self.channel(channel), *p)

    def sample_many(self, channel: str, points: Sequence[Sequence[float]]) -> list:
        n = len(points)
        xyz = (ctypes.c_double * (3 * n))(*[c for p in points for c in p])
        out = (ctypes.c_float * n)()
        self._check(self._L.loam_sample_many(self._h, self.channel(channel), n, xyz, out))
        return list(out)

    def slice(self, channel: str, axis: str, coord: float, lo, hi, res: int) -> list:
        ax = "xyz".index(axis)
        out = (ctypes.c_float * (res * res))()
        self._check(self._L.loam_slice(self._h, self.channel(channel), ax, coord, lo[0], lo[1], hi[0], hi[1], res, out))
        return list(out)

    def project(self, channel: str, axis: str, lo, hi, res: int, depth: int | None = None) -> list:
        ax = "xyz".index(axis)
        out = (ctypes.c_float * (res * res))()
        self._check(self._L.loam_project(self._h, self.channel(channel), ax, *lo, *hi, res, depth or res, out))
        return list(out)

    def root_hash(self) -> bytes:
        buf = ctypes.create_string_buffer(32)
        self._check(self._L.loam_root_hash(self._h, buf))
        return buf.raw

    def content_hash(self) -> bytes:
        buf = ctypes.create_string_buffer(32)
        self._check(self._L.loam_content_hash(self._h, buf))
        return buf.raw

    def stats(self) -> dict:
        s = Stats()
        self._check(self._L.loam_stats(self._h, ctypes.byref(s)))
        return s.as_dict()

    def total(self, channel: str) -> float:
        return self._L.loam_total(self._h, self.channel(channel))

    def inside_count(self) -> int:
        """Samples of the carrier that are inside (φ < 0): the amount of tissue."""
        return self._L.loam_inside_count(self._h)

    def fronts(self) -> list:
        cap = 1024
        out = (ctypes.c_double * (3 * cap))()
        n = self._L.loam_fronts(self._h, cap, out)
        n = min(n, cap)
        return [(out[i * 3], out[i * 3 + 1], out[i * 3 + 2]) for i in range(n)]

    def ray_count(self, channel: str, origin, direction) -> tuple:
        sampled = ctypes.c_uint64()
        crossed = ctypes.c_uint64()
        self._check(self._L.loam_ray_count(self._h, self.channel(channel), *origin, *direction, ctypes.byref(sampled), ctypes.byref(crossed)))
        return sampled.value, crossed.value

    def dump(self, path: str) -> None:
        self._check(self._L.loam_dump(self._h, path.encode()))


def write_pgm(path: str, res: int, values: Iterable[float], scale: float = 1.0) -> None:
    """An 8-bit PGM of a res×res field, top row first."""
    vals = list(values)
    rows = [vals[v * res:(v + 1) * res] for v in range(res)]
    with open(path, "wb") as f:
        f.write(f"P5\n{res} {res}\n255\n".encode())
        for row in reversed(rows):
            f.write(bytes(int(max(0.0, min(255.0, x * scale * 255.0))) for x in row))
