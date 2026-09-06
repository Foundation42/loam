import React, { useEffect, useRef, useState, useCallback } from "react";
import * as THREE from "three";

// ---------------------------------------------------------------
// LOOP LOFT — single-spine growth machine
// Spine + parallel-transport frames + N fixed slots of
// (r, dz, dθ) driven by a leaky integrator toward a morphogen
// envelope. Residuals ride the bus; heat view shows them.
// ---------------------------------------------------------------

const SLOTS = 56; // fixed vertex count — the invariant
const SPACING = 0.16; // ring spacing along arc length

// deterministic PRNG
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const lerp = (a, b, t) => a + (b - a) * t;

// heat ramp: quiet verdigris -> bone -> ember
function heatColor(v) {
  v = clamp(v, 0, 1);
  const c = [0, 0, 0];
  const lo = [0.16, 0.28, 0.26];
  const mid = [0.78, 0.73, 0.62];
  const hi = [1.0, 0.52, 0.28];
  if (v < 0.5) {
    const t = v / 0.5;
    for (let k = 0; k < 3; k++) c[k] = lerp(lo[k], mid[k], t);
  } else {
    const t = (v - 0.5) / 0.5;
    for (let k = 0; k < 3; k++) c[k] = lerp(mid[k], hi[k], t);
  }
  return c;
}
const CLAY = [0.80, 0.77, 0.70];

// -------------------- build the creature --------------------
function buildGeometry(p) {
  const rings = p.rings | 0;
  const rand = mulberry32(p.seed);
  const grand = () => (rand() + rand() + rand()) * 2 - 3; // ~gaussian, ±3

  // --- spine: constant-curvature planar arc, arc-length stepped
  const bendRad = (p.bend * Math.PI) / 180;
  const spine = [];
  const tangents = [];
  {
    const pos = new THREE.Vector3(0, 0, 0);
    for (let n = 0; n < rings; n++) {
      const t = rings > 1 ? n / (rings - 1) : 0;
      const phi = bendRad * t;
      const dir = new THREE.Vector3(Math.sin(phi), Math.cos(phi), 0);
      spine.push(pos.clone());
      tangents.push(dir.clone());
      pos.addScaledVector(dir, SPACING);
    }
  }

  // --- parallel-transport frames
  const normals = [new THREE.Vector3(0, 0, 1)];
  const q = new THREE.Quaternion();
  for (let n = 1; n < rings; n++) {
    q.setFromUnitVectors(tangents[n - 1], tangents[n]);
    normals.push(normals[n - 1].clone().applyQuaternion(q).normalize());
  }

  // --- ring CA state on the bus
  const res = new Float32Array(SLOTS); // radial residual
  const dz = new Float32Array(SLOTS); // vertical jitter
  const tmp = new Float32Array(SLOTS);

  const R0 = 1.35;
  const positions = new Float32Array(rings * SLOTS * 3 + 6);
  const colors = new Float32Array(rings * SLOTS * 3 + 6);
  const resAtVert = new Float32Array(rings * SLOTS);

  const bin = new THREE.Vector3();
  const vv = new THREE.Vector3();
  let maxAbs = 1e-4;

  for (let n = 0; n < rings; n++) {
    const t = rings > 1 ? n / (rings - 1) : 0;

    // morphogen envelope
    const envelope =
      R0 *
      (1 - p.taper * t) *
      (1 + p.bulge * Math.sin(2 * Math.PI * p.waves * t));

    if (n > 0) {
      // leak toward envelope (residual decays to 0)
      for (let i = 0; i < SLOTS; i++) {
        res[i] *= 1 - p.k;
        dz[i] *= 1 - p.k;
      }
      // ring diffusion
      for (let i = 0; i < SLOTS; i++) {
        const a = res[(i + SLOTS - 1) % SLOTS];
        const b = res[(i + 1) % SLOTS];
        tmp[i] = lerp(res[i], (a + b) * 0.5, p.diffuse);
      }
      res.set(tmp);
      // noise drive
      for (let i = 0; i < SLOTS; i++) {
        res[i] += grand() * p.noise * 0.08;
        dz[i] += grand() * p.noise * 0.05;
      }
      // impulse events: a bump kernel lands on the ring
      if (rand() < p.impulse) {
        const c = Math.floor(rand() * SLOTS);
        const w = 3 + Math.floor(rand() * 5);
        const s = (rand() < 0.5 ? -0.6 : 1) * (0.25 + rand() * 0.5) * R0 * 0.6;
        for (let d = -w; d <= w; d++) {
          const i = (c + d + SLOTS) % SLOTS;
          res[i] += s * (0.5 + 0.5 * Math.cos((Math.PI * d) / w));
        }
      }
    }

    // place vertices
    const P = spine[n];
    const T = tangents[n];
    const N = normals[n];
    bin.crossVectors(T, N).normalize();
    const jz = p.jitter * SPACING;

    for (let i = 0; i < SLOTS; i++) {
      const theta = (i / SLOTS) * Math.PI * 2 + p.drift * n;
      const r = Math.max(0.06, envelope + res[i]);
      const z = clamp(dz[i], -jz, jz);
      vv.copy(P)
        .addScaledVector(N, Math.cos(theta) * r)
        .addScaledVector(bin, Math.sin(theta) * r)
        .addScaledVector(T, z);
      const o = (n * SLOTS + i) * 3;
      positions[o] = vv.x;
      positions[o + 1] = vv.y;
      positions[o + 2] = vv.z;
      const a = Math.abs(res[i]);
      resAtVert[n * SLOTS + i] = a;
      if (a > maxAbs) maxAbs = a;
    }
  }

  // caps: centroid vertices at both ends
  const baseIdx = rings * SLOTS;
  const capB = spine[0], capT = spine[rings - 1];
  positions[baseIdx * 3] = capB.x;
  positions[baseIdx * 3 + 1] = capB.y;
  positions[baseIdx * 3 + 2] = capB.z;
  positions[baseIdx * 3 + 3] = capT.x;
  positions[baseIdx * 3 + 4] = capT.y;
  positions[baseIdx * 3 + 5] = capT.z;

  // colors
  for (let n = 0; n < rings; n++) {
    for (let i = 0; i < SLOTS; i++) {
      const idx = n * SLOTS + i;
      const c = p.heat ? heatColor(resAtVert[idx] / maxAbs) : CLAY;
      colors[idx * 3] = c[0];
      colors[idx * 3 + 1] = c[1];
      colors[idx * 3 + 2] = c[2];
    }
  }
  const capC = p.heat ? heatColor(0) : CLAY;
  for (let k = 0; k < 2; k++) {
    colors[(baseIdx + k) * 3] = capC[0];
    colors[(baseIdx + k) * 3 + 1] = capC[1];
    colors[(baseIdx + k) * 3 + 2] = capC[2];
  }

  // indices: bottom cap, then bands in growth order, then top cap
  const indices = [];
  for (let i = 0; i < SLOTS; i++) {
    indices.push(baseIdx, (i + 1) % SLOTS, i);
  }
  for (let n = 1; n < rings; n++) {
    for (let i = 0; i < SLOTS; i++) {
      const a = (n - 1) * SLOTS + i;
      const b = (n - 1) * SLOTS + ((i + 1) % SLOTS);
      const c = n * SLOTS + i;
      const d = n * SLOTS + ((i + 1) % SLOTS);
      indices.push(a, b, c, b, d, c);
    }
  }
  for (let i = 0; i < SLOTS; i++) {
    indices.push(baseIdx + 1, rings * SLOTS - SLOTS + i, rings * SLOTS - SLOTS + ((i + 1) % SLOTS));
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  // camera framing info
  const mid = new THREE.Vector3();
  spine.forEach((s) => mid.add(s));
  mid.multiplyScalar(1 / rings);
  const height = spine[0].distanceTo(spine[rings - 1]) + R0 * 2;

  return { geo, mid, height, capCount: SLOTS * 3, bandCount: SLOTS * 6, rings };
}

// -------------------- component --------------------
export default function LoopLoft() {
  const mountRef = useRef(null);
  const threeRef = useRef({});
  const growRef = useRef({ active: false, t: 0 });
  const [params, setParams] = useState({
    k: 0.06,
    noise: 0.14,
    impulse: 0.14,
    diffuse: 0.35,
    drift: 0.03,
    jitter: 0.25,
    taper: 0.35,
    bulge: 0.1,
    waves: 3,
    bend: 0,
    rings: 90,
    seed: 7,
    heat: true,
    wire: false,
  });

  // --- scene setup (once)
  useEffect(() => {
    const mount = mountRef.current;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x11171a);
    scene.fog = new THREE.Fog(0x11171a, 30, 90);

    const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 200);
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.outputEncoding = THREE.sRGBEncoding;
    mount.appendChild(renderer.domElement);

    const hemi = new THREE.HemisphereLight(0xcfe8e2, 0x1c2320, 0.85);
    scene.add(hemi);
    const key = new THREE.DirectionalLight(0xfff2df, 0.9);
    key.position.set(6, 10, 8);
    scene.add(key);
    const rim = new THREE.DirectionalLight(0x9fd8c8, 0.35);
    rim.position.set(-8, 4, -6);
    scene.add(rim);

    const grid = new THREE.GridHelper(60, 30, 0x2a3a36, 0x1c2724);
    grid.position.y = -0.01;
    scene.add(grid);

    const orbit = {
      az: 0.6, el: 0.35, dist: 22,
      target: new THREE.Vector3(0, 6, 0),
      lastInput: 0,
    };

    threeRef.current = { scene, camera, renderer, orbit, mesh: null, wireMesh: null };

    // pointer orbit + wheel zoom (mouse and touch)
    let dragging = false, px = 0, py = 0, pinch = 0;
    const el = renderer.domElement;
    el.style.touchAction = "none";
    const down = (e) => { dragging = true; px = e.clientX; py = e.clientY; orbit.lastInput = performance.now(); };
    const move = (e) => {
      if (!dragging) return;
      orbit.az -= (e.clientX - px) * 0.007;
      orbit.el = clamp(orbit.el + (e.clientY - py) * 0.005, -0.2, 1.35);
      px = e.clientX; py = e.clientY;
      orbit.lastInput = performance.now();
    };
    const up = () => { dragging = false; };
    const wheel = (e) => {
      e.preventDefault();
      orbit.dist = clamp(orbit.dist * (1 + e.deltaY * 0.001), 6, 70);
      orbit.lastInput = performance.now();
    };
    el.addEventListener("pointerdown", down);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    el.addEventListener("wheel", wheel, { passive: false });
    const touchStart = (e) => { if (e.touches.length === 2) pinch = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY); };
    const touchMove = (e) => {
      if (e.touches.length === 2) {
        const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY);
        orbit.dist = clamp(orbit.dist * (pinch / d), 6, 70);
        pinch = d;
        orbit.lastInput = performance.now();
      }
    };
    el.addEventListener("touchstart", touchStart, { passive: true });
    el.addEventListener("touchmove", touchMove, { passive: true });

    const resize = () => {
      const w = mount.clientWidth, h = mount.clientHeight;
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(mount);

    let raf;
    const tick = () => {
      raf = requestAnimationFrame(tick);
      const idle = performance.now() - orbit.lastInput > 3000;
      if (idle && !dragging) orbit.az += 0.0022;

      // growth replay
      const g = growRef.current;
      const t = threeRef.current;
      if (g.active && t.mesh) {
        g.t += 0.9; // rings per frame
        const grown = Math.min(Math.floor(g.t), t.ringsTotal - 1);
        const count = t.capCount + grown * t.bandCount;
        t.mesh.geometry.setDrawRange(0, count);
        if (t.wireMesh) t.wireMesh.geometry.setDrawRange(0, count);
        if (grown >= t.ringsTotal - 1) {
          t.mesh.geometry.setDrawRange(0, Infinity);
          if (t.wireMesh) t.wireMesh.geometry.setDrawRange(0, Infinity);
          g.active = false;
        }
      }

      camera.position.set(
        orbit.target.x + orbit.dist * Math.cos(orbit.el) * Math.sin(orbit.az),
        orbit.target.y + orbit.dist * Math.sin(orbit.el),
        orbit.target.z + orbit.dist * Math.cos(orbit.el) * Math.cos(orbit.az)
      );
      camera.lookAt(orbit.target);
      renderer.render(scene, camera);
    };
    tick();

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      el.removeEventListener("pointerdown", down);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      el.removeEventListener("wheel", wheel);
      el.removeEventListener("touchstart", touchStart);
      el.removeEventListener("touchmove", touchMove);
      renderer.dispose();
      mount.removeChild(renderer.domElement);
    };
  }, []);

  // --- rebuild creature on param change
  useEffect(() => {
    const t = threeRef.current;
    if (!t.scene) return;
    const { geo, mid, height, capCount, bandCount, rings } = buildGeometry(params);

    if (t.mesh) {
      t.scene.remove(t.mesh);
      t.mesh.geometry.dispose();
      t.mesh.material.dispose();
    }
    if (t.wireMesh) {
      t.scene.remove(t.wireMesh);
      t.wireMesh.geometry.dispose();
      t.wireMesh.material.dispose();
      t.wireMesh = null;
    }

    const mat = new THREE.MeshStandardMaterial({
      vertexColors: true,
      flatShading: true,
      roughness: 0.72,
      metalness: 0.05,
    });
    t.mesh = new THREE.Mesh(geo, mat);
    t.scene.add(t.mesh);

    if (params.wire) {
      const wmat = new THREE.MeshBasicMaterial({
        color: 0x0e1412, wireframe: true, transparent: true, opacity: 0.35,
      });
      t.wireMesh = new THREE.Mesh(geo.clone(), wmat);
      t.scene.add(t.wireMesh);
    }

    t.capCount = capCount;
    t.bandCount = bandCount;
    t.ringsTotal = rings;
    t.orbit.target.lerp(new THREE.Vector3(mid.x, mid.y, mid.z), 1);
    t.orbit.dist = clamp(height * 1.35, 10, 60);

    if (growRef.current.active) {
      growRef.current.t = 0;
    }
  }, [params]);

  const set = useCallback((key) => (e) => {
    const v = parseFloat(e.target.value);
    setParams((p) => ({ ...p, [key]: v }));
  }, []);

  const regrow = () => {
    growRef.current = { active: true, t: 0 };
  };
  const reseed = () => {
    setParams((p) => ({ ...p, seed: (p.seed * 1664525 + 1013904223) % 2147483647 }));
    growRef.current = { active: true, t: 0 };
  };

  const Knob = ({ label, path, k, min, max, step }) => (
    <div className="knob">
      <div className="krow">
        <span className="klabel">{label}</span>
        <span className="kpath">{path}</span>
        <span className="kval">{typeof params[k] === "number" ? params[k].toFixed(step >= 1 ? 0 : 3) : ""}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={params[k]} onChange={set(k)} />
    </div>
  );

  return (
    <div className="ll-root">
      <style>{`
        .ll-root {
          display: flex; flex-direction: column; height: 100vh; width: 100%;
          background: #0d1215; color: #d8e2dc;
          font-family: ui-monospace, "Cascadia Code", "SF Mono", Menlo, Consolas, monospace;
          overflow: hidden;
        }
        .ll-head {
          display: flex; align-items: baseline; gap: 12px;
          padding: 10px 14px 8px; border-bottom: 1px solid #1e2a26;
          flex-wrap: wrap;
        }
        .ll-title { font-size: 14px; letter-spacing: 0.14em; color: #8fd0bd; font-weight: 600; }
        .ll-sub { font-size: 11px; color: #5d6f68; }
        .ll-view { flex: 0 0 52vh; position: relative; min-height: 260px; }
        .ll-view > canvas { display: block; }
        .ll-badge {
          position: absolute; left: 10px; bottom: 10px;
          font-size: 10px; color: #6f857d; background: rgba(13,18,21,0.65);
          border: 1px solid #22312c; padding: 3px 7px; border-radius: 3px;
        }
        .ll-panel {
          flex: 1; overflow-y: auto; padding: 10px 14px 24px;
          display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
          gap: 8px 22px; align-content: start;
        }
        .ll-actions {
          grid-column: 1 / -1; display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 4px;
        }
        button {
          background: #16221e; color: #a9d8c8; border: 1px solid #2b423a;
          font: inherit; font-size: 12px; padding: 7px 14px; border-radius: 4px;
          cursor: pointer; letter-spacing: 0.05em;
        }
        button:hover { background: #1d2e28; }
        button.toggled { background: #23453a; color: #d9f2e7; border-color: #3f6a59; }
        .knob { display: flex; flex-direction: column; gap: 2px; }
        .krow { display: flex; align-items: baseline; gap: 8px; font-size: 11px; }
        .klabel { color: #c3d2cb; }
        .kpath { color: #55655f; font-size: 10px; }
        .kval { margin-left: auto; color: #8fd0bd; font-variant-numeric: tabular-nums; }
        input[type=range] {
          -webkit-appearance: none; appearance: none; width: 100%; height: 22px;
          background: transparent; cursor: pointer;
        }
        input[type=range]::-webkit-slider-runnable-track {
          height: 3px; background: #24352f; border-radius: 2px;
        }
        input[type=range]::-webkit-slider-thumb {
          -webkit-appearance: none; appearance: none; margin-top: -6px;
          width: 15px; height: 15px; border-radius: 50%;
          background: #79c7ae; border: 2px solid #0d1215;
        }
        input[type=range]::-moz-range-track { height: 3px; background: #24352f; border-radius: 2px; }
        input[type=range]::-moz-range-thumb {
          width: 13px; height: 13px; border-radius: 50%;
          background: #79c7ae; border: 2px solid #0d1215;
        }
        .sect {
          grid-column: 1 / -1; font-size: 10px; letter-spacing: 0.18em;
          color: #57736a; margin-top: 8px; border-bottom: 1px solid #1a2622; padding-bottom: 3px;
        }
        @media (min-width: 900px) {
          .ll-root { flex-direction: row; }
          .ll-view { flex: 1 1 auto; height: 100vh; }
          .ll-panel { flex: 0 0 340px; height: 100vh; display: block; }
          .knob { margin-bottom: 10px; }
        }
      `}</style>

      <div className="ll-view" ref={mountRef}>
        <div className="ll-badge">N = {SLOTS} slots · fixed · drag to orbit</div>
      </div>

      <div className="ll-panelwrap" style={{ display: "contents" }}>
        <div className="ll-panel">
          <div className="ll-head" style={{ gridColumn: "1 / -1", padding: "0 0 8px", border: "none" }}>
            <span className="ll-title">LOOP LOFT</span>
            <span className="ll-sub">single-spine growth machine · leaky integrator on the ring</span>
          </div>

          <div className="ll-actions">
            <button onClick={regrow}>regrow ▸</button>
            <button onClick={reseed}>new seed ⚄</button>
            <button className={params.heat ? "toggled" : ""} onClick={() => setParams((p) => ({ ...p, heat: !p.heat }))}>
              {params.heat ? "residual heat" : "clay"}
            </button>
            <button className={params.wire ? "toggled" : ""} onClick={() => setParams((p) => ({ ...p, wire: !p.wire }))}>
              wire
            </button>
          </div>

          <div className="sect">GROWTH</div>
          <Knob label="heal (leak)" path="growth.k" k="k" min={0} max={0.4} step={0.005} />
          <Knob label="noise drive" path="growth.noise" k="noise" min={0} max={0.6} step={0.01} />
          <Knob label="impulse rate" path="growth.impulse" k="impulse" min={0} max={0.6} step={0.01} />
          <Knob label="ring diffusion" path="ring.diffuse" k="diffuse" min={0} max={1} step={0.01} />

          <div className="sect">RING</div>
          <Knob label="drift dθ" path="ring.drift" k="drift" min={-0.15} max={0.15} step={0.002} />
          <Knob label="vertical jitter" path="ring.jitter_z" k="jitter" min={0} max={0.45} step={0.01} />

          <div className="sect">MORPHOGENS</div>
          <Knob label="taper" path="env.taper" k="taper" min={0} max={0.95} step={0.01} />
          <Knob label="bulge amp" path="env.bulge" k="bulge" min={0} max={0.4} step={0.01} />
          <Knob label="bulge waves" path="env.waves" k="waves" min={0} max={8} step={1} />

          <div className="sect">SPINE</div>
          <Knob label="bend" path="spine.bend" k="bend" min={0} max={230} step={1} />
          <Knob label="rings" path="spine.rings" k="rings" min={24} max={150} step={1} />
        </div>
      </div>
    </div>
  );
}
