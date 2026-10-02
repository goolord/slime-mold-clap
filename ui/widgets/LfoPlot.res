// Two cycles of an LFO's shape from its reset:
// starting at its phase, read at the start of each sample & hold step, and for a one-shot, holding
// its end once the cycle is over. The random shapes draw made-up values (the same each time): a new
// one each cycle, glided to across it (smooth) or held (stepping).
//
// The plugin names the parameters (ids): shape, a list in this order (sine, saw, square,
// triangle, smooth random, stepping random); and if it has them phase (0 .. 1, the reset's start),
// steps (sample & hold: a list in stepCounts' order, off, 2, 3, 4, 6, 8, 12, 16, 24, 32, or
// the count itself) and oneShot (a switch). Plain values throughout. ~seed varies the random
// shapes' made-up values between plots.

open! Web

type ids = {
  shape: string,
  phase?: string,
  steps?: string,
  oneShot?: string,
}

// the sample & hold step menu: off, then steps per cycle
let stepCounts = [0, 2, 3, 4, 6, 8, 12, 16, 24, 32]

// the one-shot's end, where it holds (0xfffe0000 / 2^32, a uint32 phase's last step)
let oneShotEnd = 4294836224. / 4294967296.

// made-up random values, 0..1, the same for the same k and seed
let random = (k: float, seed: float) => {
  let x = Math.sin(k * 12.9898 + seed * 78.233) * 43758.5453
  x - Math.floor(x)
}

// The LFO's value (0..1) at time t cycles after its reset (lfoShapeAt after Lfo.step).
let valueAt = (~shape, ~phase, ~steps, ~oneShot, ~seed, t: float) => {
  let run = phase + t
  // a one-shot stops at the end of its cycle; otherwise the phase wraps, drawing new random values
  let (ph, wraps) = oneShot && run >= 1. ? (1. - 1. / 4294967296., 0.) : (run - Math.floor(run), Math.floor(run))
  let ph = steps > 0 ? Math.floor(ph * Int.toFloat(steps)) / Int.toFloat(steps) : ph
  let x = oneShot ? Math.min(ph, oneShotEnd) : ph
  switch shape {
  | 1 => x
  | 2 => x < 0.5 ? 0. : 1.
  | 3 => x < 0.5 ? 2. * x : 2. - 2. * x
  | 4 =>
    let (a, b) = (random(wraps, seed), random(wraps + 1., seed))
    a + (b - a) * ph
  | 5 => random(wraps + 1., seed)
  | _ => (Math.sin(2. * Math.Constants.pi * x) + 1.) * 0.5
  }
}

// The plot, in a box of the parent. Returns its redraw.
let make = (ctx: Ctx.t, parent, box: box, ids: ids, ~seed=0.) => {
  let model = ctx.model
  let plain = id => (model->ParamModel.def(id)).plain(model->ParamModel.get(id))
  let s = Plots.svg(parent, box)
  Plots.background(s, box)
  let (w, h) = (box.w - 6., box.h - 7.)
  let mid = 3. + h / 2.
  Plots.line(s, ~cls="axis faint", 3., mid, 3. + w, mid)->ignore
  Plots.line(s, ~cls="axis faint", 3. + w / 2., 3., 3. + w / 2., 3. + h)->ignore
  let curve = s->svgEl("path", [("class", Str("curve"))])
  let status = () => {
    let parts = [Some(ids.shape), ids.phase, ids.steps, ids.oneShot]->Array.filterMap(x => x)
    "Two cycles of the LFO from its reset: " ++ model->ParamModel.statusText(parts)
  }
  ctx.status->Status.live(s, status)->ignore

  let draw = () => {
    let shape = Float.toInt(model->ParamModel.get(ids.shape))
    let phase = ids.phase->Option.mapOr(0., plain)
    let steps = switch ids.steps {
    | Some(id) =>
      switch (model->ParamModel.def(id)).names {
      | Some(_) => stepCounts[Float.toInt(model->ParamModel.get(id))]->Option.getOr(0)
      | None => Float.toInt(Math.round(plain(id)))
      }
    | None => 0
    }
    let oneShot = ids.oneShot->Option.mapOr(false, id => model->ParamModel.get(id) != 0.)
    let n = Float.toInt(w * 2.)
    let points = Array.fromInitializer(~length=n + 1, k => {
      let f = Int.toFloat(k) / Int.toFloat(n)
      // (the last point just short of the end, so it stays in the second cycle)
      let v = valueAt(~shape, ~phase, ~steps, ~oneShot, ~seed, Math.min(f, 0.99999) * 2.)
      (3. + f * w, 3. + (1. - Float.clamp(v, ~min=0., ~max=1.)) * h)
    })
    curve->setAttribute("d", Str(Plots.pathFrom(points)))
  }

  model->ParamModel.listenEach([Some(ids.shape), ids.phase, ids.steps, ids.oneShot]->Array.filterMap(x => x), draw)
  draw()
  draw
}
