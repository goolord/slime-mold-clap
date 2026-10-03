// The patch's network state, typed: the output endpoints dsp/PhysarumFdn.cmajor sends about 30
// times a second, decoded from the JSON Cmajor delivers into arrays of the right length, and kept
// for whatever draws them. One bridge per view; listeners hear of each message as it comes.
//
//   matrixState     float[64]  W[i * 8 + j]: the effective conductance of tube i -> j
//   feedbackMatrix  float[64]  A[r * 8 + c]: line c into line r, after the unitary projection
//   nodeEnergy      float[8]   each line's pressure, 0..1 (its level above -72 dB)
//   nodeDelayMs     float[8]   each line's length, ms
//   networkStats    float[4]   the largest singular value of A, ||A^T A - I||_F, the mean
//                              conductance, and the projection's iterations

type stats = {
  sigmaMax: float,
  unitarityError: float,
  meanConductance: float,
  iterations: int,
}

type t = {
  mutable conductance: option<array<float>>,
  mutable matrix: option<array<float>>,
  mutable pressure: option<array<float>>,
  mutable delayMs: option<array<float>>,
  mutable stats: option<stats>,
  // when the last message came (performance.now), 0 for never
  mutable received: float,
  listeners: array<unit => unit>,
}

// A JSON array of exactly n numbers.
let floats = (json: JSON.t, n) =>
  switch json {
  | Array(xs) if Array.length(xs) == n =>
    let out = xs->Array.filterMap(x =>
      switch x {
      | JSON.Number(v) => Some(v)
      | _ => None
      }
    )
    Array.length(out) == n ? Some(out) : None
  | _ => None
  }

let decodeStats = json =>
  floats(json, 4)->Option.map(s => {
    sigmaMax: s->Array.getUnsafe(0),
    unitarityError: s->Array.getUnsafe(1),
    meanConductance: s->Array.getUnsafe(2),
    iterations: Float.toInt(s->Array.getUnsafe(3)),
  })

let connect = pc => {
  let t = {
    conductance: None,
    matrix: None,
    pressure: None,
    delayMs: None,
    stats: None,
    received: 0.,
    listeners: [],
  }
  // the stats come last in each batch, so listeners run once the batch is in
  let on = (endpoint, decode, store, ~notify=false) =>
    pc->PatchConnection.addEndpointListener(endpoint, json =>
      decode(json)->Option.forEach(v => {
        store(v)
        t.received = Web.performanceNow()
        if notify {
          t.listeners->Array.forEach(f => f())
        }
      })
    )
  on("matrixState", floats(_, FdnModel.cells), v => t.conductance = Some(v))
  on("feedbackMatrix", floats(_, FdnModel.cells), v => t.matrix = Some(v))
  on("nodeEnergy", floats(_, FdnModel.size), v => t.pressure = Some(v))
  on("nodeDelayMs", floats(_, FdnModel.size), v => t.delayMs = Some(v))
  on("networkStats", decodeStats, v => t.stats = Some(v), ~notify=true)
  t
}

let listen = (t, f) => t.listeners->Array.push(f)

// Whether the patch has spoken lately.
let isLive = t => t.received > 0. && Web.performanceNow() - t.received < 600.

// One value of an 8 x 8 array, or the fallback.
let at = (xs: option<array<float>>, i, ~fallback) => xs->Option.flatMap(a => a[i])->Option.getOr(fallback)
