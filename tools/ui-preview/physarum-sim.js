// A stand-in for dsp/PhysarumFdn.cmajor's view endpoints in the UI preview, where no DSP runs: the
// same tube dynamics and unitary projection, driven by a rough model of the lines' levels (bursts
// fed into the fed lines, spread by the matrix, decaying at the decay time) instead of audio. It
// sends what the patch would, about 30 times a second. Not the DSP: for working on the view.
//
//   start(pc)   from tools/ui-preview/index.html (leave it out with ?sim=0)

const N = 8;
const primes = [887, 1093, 1327, 1601, 1913, 2357, 2903, 3511];
const cell = (r, c) => r * N + c;
const chord = (i, j) => (i === j ? 1 : 2 * Math.sin((Math.PI * Math.abs(i - j)) / N));
const hadamard = (i, j) => { let b = i & j, odd = false; while (b) { if (b & 1) odd = !odd; b >>= 1; } return odd ? -1 : 1; };
const exp = (lo, hi, v) => lo * Math.pow(hi / lo, v);

// the parameters' plain values from the mock connection's endpoint values (or the defaults)
function settings(pc) {
  const get = (id, init) => (pc.params.has(id) ? pc.params.get(id) : init);
  const pos = (lo, hi, x) => Math.log(x / lo) / Math.log(hi / lo);
  const food = [1, 0, 0, 1, 0, 1, 0, 0].map((init, i) => get("food" + (i + 1), init) >= 0.5);
  return {
    alpha: exp(0.02, 20, get("growthRate", pos(0.02, 20, 1.5))),
    mu: exp(0.01, 10, get("decayRate", pos(0.01, 10, 0.4))),
    memory: get("memory", 0.3),
    gamma: get("gamma", 1.5),
    t60: exp(0.3, 30, get("decayTime", pos(0.3, 30, 3))),
    room: get("roomSize", 1),
    food: food.some((f) => f) ? food : food.map(() => true),
  };
}

function project(m) {
  let frob = 0;
  for (const x of m) frob += x * x;
  let x = m.map((v) => v / Math.sqrt(frob)), err = 0, iterations = 0;
  for (; iterations < 24; iterations++) {
    const g = new Array(N * N).fill(0);
    for (let a = 0; a < N; a++) for (let b = 0; b < N; b++) for (let r = 0; r < N; r++) g[cell(a, b)] += x[cell(r, a)] * x[cell(r, b)];
    err = Math.sqrt(g.reduce((s, v, k) => s + (v - (k % (N + 1) === 0 ? 1 : 0)) ** 2, 0));
    if (err < 1e-7) break;
    const next = new Array(N * N).fill(0);
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      let s = 0;
      for (let k = 0; k < N; k++) s += x[cell(r, k)] * g[cell(k, c)];
      next[cell(r, c)] = 1.5 * x[cell(r, c)] - 0.5 * s;
    }
    x = next;
  }
  return { a: x, err, iterations };
}

export function start(pc) {
  const D = new Array(N * N).fill(0.5);
  const energy = new Array(N).fill(0);
  let a = project(D.map((_, k) => hadamard(Math.floor(k / N), k % N) * Math.sqrt(0.5))).a;
  let t = 0;
  const dt = 1 / 30;

  setInterval(() => {
    const s = settings(pc);
    t += dt;
    // the lines' levels: bursts into the fed lines (0.4 s in every 1.6 s), spread through the
    // matrix's energy couplings, and decaying at the decay time
    const burst = t % 1.6 < 0.4 ? 0.05 : 0;
    const meanLength = primes.reduce((x, y) => x + y, 0) / N * s.room / 48000;
    const keep = Math.pow(10, (-3 * dt) / s.t60);
    const spread = energy.map((_, r) => energy.reduce((sum, e, c) => sum + a[cell(r, c)] ** 2 * e, 0));
    for (let i = 0; i < N; i++) energy[i] = keep * (0.04 * spread[i] + 0.96 * energy[i]) + (s.food[i] ? burst : 0) * dt / meanLength;
    const p = energy.map((e) => Math.min(1, Math.max(0, (10 * Math.log10(e + 1e-12) + 72) / 72)));

    // the tubes, as the DSP integrates them
    const relax = Math.exp(-s.mu * dt);
    const w = (k) => s.memory + (1 - s.memory) * D[k];
    for (let i = 0; i < N; i++) for (let j = 0; j < N; j++) {
      if (i === j) continue;
      const k = cell(i, j);
      const q = (4 * w(k)) / chord(i, j) * (p[i] - p[j]);
      const f = q > 0 ? q ** s.gamma / (1 + q ** s.gamma) : 0;
      const eq = (s.alpha / s.mu) * f;
      D[k] = Math.min(1, Math.max(0.002, eq + (D[k] - eq) * relax));
    }
    const m = new Array(N * N).fill(0);
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++)
      m[cell(r, c)] = hadamard(r, c) * Math.sqrt(r === c ? 0.5 : (w(cell(c, r)) * chord(0, 1)) / chord(r, c));
    const projected = project(m);
    a = projected.a;

    const W = D.map((_, k) => (Math.floor(k / N) === k % N ? 0 : w(k)));
    const delays = primes.map((n) => (n * Math.min(2, Math.max(0.25, s.room)) / 48000) * 1000);
    pc.emit("matrixState", W);
    pc.emit("feedbackMatrix", a);
    pc.emit("nodeEnergy", p);
    pc.emit("nodeDelayMs", delays);
    pc.emit("meterOut", [Math.sqrt(energy[0]) * 0.8, Math.sqrt(energy[2]) * 0.8]);
    pc.emit("networkStats", [1 - projected.err / 4, projected.err, W.reduce((x, y) => x + y, 0) / (N * N - N), projected.iterations]);
  }, 1000 * dt);
}
