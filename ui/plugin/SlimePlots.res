// The plots beside the dish, each drawn from the same formulas as the DSP (FdnModel) so that a
// setting shows what it does as it's turned:
//
//  - plasticity: the conductance a tube settles at for each flux through it, under the four tube
//    parameters, with every tube in the network as a dot where it is now;
//  - decay: the reverb's level over time on a log time axis, low and high frequencies, with the
//    dry level, the room's first echoes and the decay times;
//  - matrix: the feedback matrix the DSP is running, signed.

open! Web
module G = Web.Context2d
module C = Canvas2d

let rgba = Theme.rgba
let tau = 2. * Math.Constants.pi
let fmt = Param.fixed

type plot = {
  canvas: element,
  g: Web.context2d,
  w: float,
  h: float,
}

let makePlot = (parent, box: box) => {
  let canvas = CanvasStyle.make(parent, box)
  canvas->setStyle("cursor", "default")
  {canvas, g: canvas->getContext2d, w: box.w, h: box.h}
}

// Clears to the plot's paper, at design scale.
let begin = p => {
  let theme = Theme.current.contents
  C.setTransform(p.g, 2., 0., 0., 2., 0., 0.)
  G.clearRect(p.g, 0., 0., p.w, p.h)
  G.setFillStyle(p.g, rgba(theme.paper, 0.55))
  G.beginPath(p.g)
  G.fillRect(p.g, 0., 0., p.w, p.h)
  theme
}

let text = (p, ~align="left", ~size=10.5, ~colour, s, x, y) => {
  C.setFont(p.g, `${fmt(size, 1)}px ${Theme.current.contents.font}`)
  C.setTextAlign(p.g, align)
  C.setTextBaseline(p.g, "middle")
  G.setFillStyle(p.g, colour)
  C.fillText(p.g, s, x, y)
}

let polyline = (p, points: array<(float, float)>) => {
  G.beginPath(p.g)
  points->Array.forEachWithIndex(((x, y), i) => i == 0 ? G.moveTo(p.g, x, y) : G.lineTo(p.g, x, y))
}

// Redraws once a frame at most, and whenever these parameters change or the theme does.
let redrawOn = (ctx: Ctx.t, ids, draw) => {
  let redraw = perFrame(draw)
  ctx.model->ParamModel.listenEach(ids, redraw)
  CanvasStyle.onThemeChange(redraw)
  redraw()
  redraw
}

//==============================================================================
// plasticity

let plasticity = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box) => {
  let p = makePlot(parent, box)
  let model = ctx.model
  let plain = ParamModel.plain(model, _)
  let maxFlux = 3.
  let (left, right, top, bottom) = (24., p.w - 6., 22., p.h - 18.)
  let xAt = q => left + (right - left) * q / maxFlux
  let yAt = w => bottom - (bottom - top) * w

  let draw = () => {
    let theme = begin(p)
    let (alpha, mu, gamma, memory) = (plain("growthRate"), plain("decayRate"), plain("gamma"), plain("memory"))
    let settled = q => FdnModel.effective(memory, FdnModel.equilibrium(q, ~alpha, ~mu, ~gamma))

    // grid: conductance quarters, flux units
    for k in 0 to 4 {
      let y = CanvasStyle.snap(yAt(Int.toFloat(k) / 4.))
      CanvasStyle.line(p.g, (left, y), (right, y), rgba(theme.ink, k == 0 ? 0.35 : 0.1))
    }
    for k in 0 to 3 {
      let x = CanvasStyle.snap(xAt(Int.toFloat(k)))
      CanvasStyle.line(p.g, (x, top), (x, bottom), rgba(theme.ink, k == 0 ? 0.35 : 0.1))
      k < 3
        ? text(p, ~align="center", ~colour=rgba(theme.ink, 0.5), Int.toString(k), x, bottom + 8.)
        : text(p, ~align="right", ~colour=rgba(theme.ink, 0.55), "flux", right, bottom + 8.)
    }
    text(p, ~align="right", ~colour=rgba(theme.ink, 0.5), "1", left - 5., yAt(1.))
    text(p, ~align="right", ~colour=rgba(theme.ink, 0.5), "0", left - 5., yAt(0.))

    // the memory floor
    G.setStrokeStyle(p.g, rgba(theme.mod, 0.9))
    C.setLineDash(p.g, [3., 3.])
    G.beginPath(p.g)
    G.moveTo(p.g, left, yAt(memory) + 0.5)
    G.lineTo(p.g, right, yAt(memory) + 0.5)
    G.stroke(p.g)
    C.setLineDash(p.g, [])
    let floorLabelY = memory > 0.85 ? yAt(memory) + 8. : yAt(memory) - 7.
    text(p, ~align="right", ~size=10., ~colour=rgba(theme.mod, 1.), `memory ${fmt(memory * 100., 0)} %`, right - 2., floorLabelY)

    // the settled conductance, filled under
    let curve = Array.fromInitializer(~length=121, k => {
      let q = maxFlux * Int.toFloat(k) / 120.
      (xAt(q), yAt(settled(q)))
    })
    polyline(p, [(left, bottom), ...curve, (right, bottom)])
    G.closePath(p.g)
    G.setFillStyle(p.g, rgba(theme.signal, 0.16))
    G.fill(p.g)
    polyline(p, curve)
    G.setStrokeStyle(p.g, Theme.rgb(theme.signal))
    G.setLineWidth(p.g, 2.)
    C.setLineJoin(p.g, "round")
    G.stroke(p.g)

    // every tube where it is: its flux now, its conductance now (drifting to the curve)
    switch (bridge.conductance, bridge.pressure) {
    | (Some(ws), Some(ps)) =>
      G.setFillStyle(p.g, rgba(theme.ink, 0.75))
      for i in 0 to FdnModel.size - 1 {
        for j in 0 to FdnModel.size - 1 {
          if i != j {
            let wij = ws[FdnModel.cell(i, j)]->Option.getOr(0.)
            let pi = ps[i]->Option.getOr(0.)
            let pj = ps[j]->Option.getOr(0.)
            let q = Math.max(0., Math.min(maxFlux, FdnModel.flux(wij, i, j, pi, pj)))
            G.beginPath(p.g)
            C.arc(p.g, xAt(q), yAt(wij), 2., 0., tau)
            G.fill(p.g)
          }
        }
      }
    | _ => ()
    }

    // how fast tubes settle
    let settle = 1. / mu
    text(
      p,
      ~colour=rgba(theme.ink, 0.8),
      ~size=11.,
      `tubes settle in ${settle < 10. ? fmt(settle, 1) : fmt(settle, 0)} s`,
      left + 2.,
      9.,
    )
  }

  let redraw = redrawOn(ctx, ["growthRate", "decayRate", "memory", "gamma"], draw)
  bridge->PatchBridge.listen(redraw)
  ctx.status->Status.hover(p.canvas, () =>
    "The conductance a tube settles at for a steady flux through it (the line), the lattice it never drops below (dashed), and every tube in the network now (dots)"
  )
}

//==============================================================================
// decay

let decay = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box) => {
  let p = makePlot(parent, box)
  let model = ctx.model
  let plain = ParamModel.plain(model, _)
  let (tMin, tMax, floorDb) = (0.005, 40., -66.)
  let (left, right, top, bottom) = (26., p.w - 6., 22., p.h - 18.)
  let xAt = Graph.logX(~lo=tMin, ~hi=tMax, ~left, ~right, ...)
  let yAt = db => top + (bottom - top) * Math.max(0., Math.min(1., db / floorDb))

  let draw = () => {
    let theme = begin(p)
    let (t60, damping, mix, room) = (plain("decayTime"), plain("damping"), plain("mix"), plain("roomSize"))
    let lengths = FdnModel.delayLengths(~roomSize=room)
    let delays = switch bridge.delayMs {
    | Some(ms) => ms
    | None => lengths->Array.map(n => FdnModel.lengthMs(n))
    }
    let meanLength = lengths->Array.reduce(0., (s, n) => s + Int.toFloat(n)) / Int.toFloat(FdnModel.size)
    let (dry, wet) = FdnModel.mixLevels(mix)
    let wetDb = Graph.gainDb(wet * FdnModel.wetGain(lengths, ~t60))
    let dryDb = Graph.gainDb(dry)
    let low = FdnModel.decayTimeAt(100., ~t60, ~damping, ~meanLength)
    let high = FdnModel.decayTimeAt(6000., ~t60, ~damping, ~meanLength)
    let first = (delays[0]->Option.getOr(18.)) / 1000.

    // grid: 20 dB steps, decades of time
    [0., -20., -40., -60.]->Array.forEach(db => {
      let y = CanvasStyle.snap(yAt(db))
      CanvasStyle.line(p.g, (left, y), (right, y), rgba(theme.ink, db == 0. ? 0.3 : 0.1))
      text(p, ~align="right", ~colour=rgba(theme.ink, 0.5), fmt(db, 0), left - 4., y)
    })
    [(0.01, "10 ms"), (0.1, "0.1 s"), (1., "1 s"), (10., "10 s")]->Array.forEach(((t, label)) => {
      let x = CanvasStyle.snap(xAt(t))
      CanvasStyle.line(p.g, (x, top), (x, bottom), rgba(theme.ink, 0.1))
      text(p, ~align="center", ~colour=rgba(theme.ink, 0.5), label, x, bottom + 8.)
    })

    // the room's first echoes: one tick per delay line
    G.setStrokeStyle(p.g, rgba(theme.signal, 0.75))
    G.setLineWidth(p.g, 1.5)
    delays->Array.forEach(ms => {
      let x = xAt(ms / 1000.)
      G.beginPath(p.g)
      G.moveTo(p.g, x, bottom)
      G.lineTo(p.g, x, bottom - 7.)
      G.stroke(p.g)
    })

    // the tail: from the first echo, down at each frequency's rate
    let tail = rate =>
      Array.fromInitializer(~length=161, k => {
        let t = first * Math.pow(tMax / first, ~exp=Int.toFloat(k) / 160.)
        (xAt(t), yAt(wetDb - 60. * (t - first) / rate))
      })
    let lows = tail(low)
    let highs = tail(high)
    polyline(p, [...lows, ...highs->Array.toReversed])
    G.closePath(p.g)
    G.setFillStyle(p.g, rgba(theme.signal, 0.16))
    G.fill(p.g)
    C.setLineJoin(p.g, "round")
    polyline(p, lows)
    G.setStrokeStyle(p.g, Theme.rgb(theme.signal))
    G.setLineWidth(p.g, 2.)
    G.stroke(p.g)
    polyline(p, highs)
    G.setStrokeStyle(p.g, rgba(theme.signal, 0.7))
    G.setLineWidth(p.g, 1.2)
    C.setLineDash(p.g, [4., 3.])
    G.stroke(p.g)
    C.setLineDash(p.g, [])

    // the dry sound: a bar at the start
    let x = xAt(tMin) + 3.
    G.setFillStyle(p.g, rgba(theme.mod, 0.95))
    G.fillRect(p.g, x - 2., yAt(dryDb), 4., bottom - yAt(dryDb))
    if dryDb > floorDb {
      text(p, ~size=10., ~colour=rgba(theme.mod, 1.), "dry", x + 5., yAt(dryDb) + 6.)
    }

    let seconds = t => t >= 100. ? "long" : t < 10. ? fmt(t, 1) ++ " s" : fmt(t, 0) ++ " s"
    text(p, ~colour=rgba(theme.ink, 0.8), ~size=11., `decays in ${seconds(low)} low, ${seconds(high)} high`, left + 2., 9.)
  }

  let redraw = redrawOn(ctx, ["decayTime", "damping", "mix", "roomSize"], draw)
  // the line lengths come from the DSP (at its sample rate) once a room change has crossfaded
  let lastDelays = ref("")
  bridge->PatchBridge.listen(() => {
    let key = bridge.delayMs->Option.mapOr("", ms => ms->Array.map(x => fmt(x, 2))->Array.join(","))
    if key != lastDelays.contents {
      lastDelays := key
      redraw()
    }
  })
  ctx.status->Status.hover(p.canvas, () =>
    "The reverb's level over time: low frequencies (solid) and high (dashed) dying away from the first echo, one tick per delay line, and the dry level (bar)"
  )
}

//==============================================================================
// the matrix

let matrix = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box) => {
  let p = makePlot(parent, box)
  let n = FdnModel.size
  let cellSize = Math.min(p.w, p.h) / Int.toFloat(n)
  let hover = ref(None)

  let draw = () => {
    let theme = begin(p)
    switch bridge.matrix {
    | Some(a) =>
      for r in 0 to n - 1 {
        for c in 0 to n - 1 {
          let v = a[FdnModel.cell(r, c)]->Option.getOr(0.)
          let colour = v >= 0. ? theme.signal : theme.mod
          G.setFillStyle(p.g, rgba(colour, Math.min(1., Math.pow(Math.abs(v), ~exp=0.7) * 1.1)))
          G.fillRect(p.g, Int.toFloat(c) * cellSize + 0.5, Int.toFloat(r) * cellSize + 0.5, cellSize - 1., cellSize - 1.)
        }
      }
    | None => text(p, ~align="center", ~colour=rgba(theme.ink, 0.5), "no data", p.w / 2., p.h / 2.)
    }
    hover.contents->Option.forEach(((r, c)) => {
      G.setStrokeStyle(p.g, Theme.rgb(theme.ink))
      G.setLineWidth(p.g, 1.)
      G.strokeRect(p.g, Int.toFloat(c) * cellSize + 0.5, Int.toFloat(r) * cellSize + 0.5, cellSize - 1., cellSize - 1.)
    })
  }

  let redraw = redrawOn(ctx, [], draw)
  bridge->PatchBridge.listen(redraw)

  let describe = () =>
    switch (hover.contents, bridge.matrix) {
    | (Some((r, c)), Some(a)) =>
      `Line ${Int.toString(c + 1)} into line ${Int.toString(r + 1)}: ${fmt(a[FdnModel.cell(r, c)]->Option.getOr(0.), 3)} (green positive, yellow negative)`
    | _ => "The feedback matrix in use, after the projection that keeps it lossless: each row is where a line's input comes from"
    }
  p.canvas->onPointer(#pointermove, ev => {
    let (fx, fy) = pointerFraction(p.canvas, ev)
    let (c, r) = (Float.toInt(fx * p.w / cellSize), Float.toInt(fy * p.h / cellSize))
    hover := (r >= 0 && r < n && c >= 0 && c < n ? Some((r, c)) : None)
    ctx.status->Status.show(describe())
    redraw()
  })
  p.canvas->onMouse(#mouseleave, _ => {
    hover := None
    ctx.status->Status.clear
    redraw()
  })
}
