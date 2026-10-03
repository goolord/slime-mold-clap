// Envelope editors, FL Studio style: drag the points to shape the envelope, and the small
// points in the middle of the attack, decays and release up or down to bend them. A "values"
// switch in the corner swaps the graph for the raw parameter fields.
//
// Time runs left to right on a compressed (square-root) axis. Each segment is measured
// from the point before it, so dragging a point changes only its own segment. The axis is
// refitted when a drag ends, never during one, so the point stays under the pointer.
//
// It draws one of two envelope models (~kind); a DSP envelope that follows the same formulas sounds
// as drawn:
// - #amp (for a level): the attack is (2 - a) a of its curved progress a, the decays are eased
//   between their end levels (envCubic below), the release falls 60 dB in its time to 0.001 and is
//   scaled to end at 0. Drawn in dB by default, -60 dB at the bottom.
// - #block (for a filter or modulation amount): a linear attack, and exponential decays and
//   release on their curved paths. Drawn linearly by default.
// A stage's curve c warps its progress p into k p / (1 + (k - 1) p), k = 8^c.
//
// The plugin names the parameters (ids): attack, decay (decay 2: to the sustain level), sustain
// and release, and if it has them hold, decay1 with its breakpoint (from the top to the
// breakpoint level, before decay 2; a breakpoint at the top skips it, above 0.998)
// and the four stages' curves (-1 .. 1). A plain ADSR names just the first four.
// - Times: their plain values are ms (e.g. attack 0.2 .. 10000, hold 0 .. 10000, the others
//   10 .. 20000), whatever their knob law: read through the def's plain, set through ofPlain.
// - Levels (breakpoint, sustain): ~levelOf turns a level parameter's value into the linear level
//   0 .. 1, ~levelTo back. By default a dB parameter (unit "dB") is 10^(dB/20), its minimum
//   silence, and any other its plain value.
// - ~depth: a parameter that scales what the envelope does (a filter envelope's amount), drawn as
//   the envelope at that depth (its plain value over the largest of its range's ends: rising from
//   the bottom, or for a negative depth hanging from the top), with a label for it.
// - ~enabled: a switch that turns the envelope on; the graph is dimmed while it is off.

open! Web

let margin = 7. // keeps points at the edges grabbable
let axisHeight = 12. // the time axis labels, under the curve
let bottomOf = h => h - margin - axisHeight
let segmentGap = 12. // minimum segment width, so that points never sit on top of each other

let hintFor = name =>
  name ++ ": drag the points to shape it, and the small middle points up or down to bend a stage; shift for fine steps. Scroll over a point to change it, right-click to reset it."

// compressed seconds
let units = ms => Math.sqrt(Math.max(0., ms) / 1000.)
let msOf = u => 1000. * u * u

// A round axis length (in compressed seconds) that leaves room to drag into.
let niceSpan = total =>
  [1.5, 2., 3., 4., 6., 8., 12., 16., 24., 32.]
  ->Array.find(s => s >= total * 1.15)
  ->Option.getOr(32.)

// time axis ticks, 1 ms to 500 s: the roundest first, so they win the room
let tickTimes = [1., 5., 2.]->Array.flatMap(m =>
  [1., 10., 100., 1000., 10000., 100000.]->Array.map(d => m * d)
)
let tickText = ms => ms < 1000. ? `${Float.toString(ms)} ms` : `${Float.toString(ms / 1000.)} s`

// The envelope's parameters.
type ids = {
  attack: string,
  hold?: string,
  // decay 1, from the top to the breakpoint level (both or neither)
  decay1?: string,
  breakpoint?: string,
  // decay 2, to the sustain level
  decay: string,
  sustain: string,
  release: string,
  attackCurve?: string,
  decay1Curve?: string,
  decayCurve?: string,
  releaseCurve?: string,
}

// Which model it draws (see the top).
type kind = [#amp | #block]

// The raw parameter fields an envelope's "values" switch shows, with their labels.
let fields = (ids: ids) =>
  [
    Some((ids.attack, "attack")),
    ids.hold->Option.map(id => (id, "hold")),
    ids.decay1->Option.map(id => (id, "decay 1")),
    ids.breakpoint->Option.map(id => (id, "breakpoint")),
    Some((ids.decay, ids.decay1 == None ? "decay" : "decay 2")),
    Some((ids.sustain, "sustain")),
    Some((ids.release, "release")),
    ids.attackCurve->Option.map(id => (id, "attack curve")),
    ids.decay1Curve->Option.map(id => (id, "decay 1 curve")),
    ids.decayCurve->Option.map(id => (id, ids.decay1 == None ? "decay curve" : "decay 2 curve")),
    ids.releaseCurve->Option.map(id => (id, "release curve")),
  ]->Array.filterMap(x => x)

// A level parameter's value as the linear level, and back (see the header).
let defaultLevelOf = (def: Param.t, value) => {
  let x = def.plain(value)
  def.unit == Some("dB") ? x <= def.plain(def.min) ? 0. : Math.pow(10., ~exp=x / 20.) : x
}
let defaultLevelTo = (def: Param.t, level) =>
  def.unit == Some("dB")
    ? level <= 0. ? def.min : def.ofPlain(20. * Math.log10(level))
    : def.ofPlain(level)

// A draggable point. Dragging it sideways sets `time` from the width of its segment (which
// starts at x0); dragging it up and down sets `level`, or for a bend point, `curve`.
type handle = {
  time: option<string>,
  level: option<string>,
  x0: float,
  x: float,
  y: float,
  // drawn hollow when the stage it ends is skipped
  hollow: bool,
  // not shown, for a bend point whose stage is skipped or flat
  hidden: bool,
  // a stage's curve, and which way up bends it positive
  curve: option<string>,
  bendSign: float,
}

let point = (~time=?, ~level=?, ~hollow=false, x0, x, y) => {
  time,
  level,
  x0,
  x,
  y,
  hollow,
  hidden: false,
  curve: None,
  bendSign: 0.,
}

// A stage's bend point, at the middle of its segment.
let bendPoint = (~hidden=false, curve, (x, y), ~rising) => {
  ...point(x, x, y),
  hidden,
  curve: Some(curve),
  bendSign: rising ? 1. : -1.,
}

// Scales held for the length of a drag.
type frame = {
  // pixels per compressed second
  unitPx: float,
}

// A stretch of the time axis: xFrom to xTo covers msFrom to msTo, timed from the note-on,
// or for a release, from the note-off. Time is linear within a stretch, as the curve is.
type stretch = {
  xFrom: float,
  xTo: float,
  msFrom: float,
  msTo: float,
  release: bool,
}

let stretch = (~release=false, xFrom, xTo, msFrom, msTo) => {xFrom, xTo, msFrom, msTo, release}

type shape = {
  ids: array<string>,
  fit: unit => frame,
  // the curve, the points and the time axis for the current values
  layout: frame => (array<(float, float)>, array<handle>, array<stretch>),
  // sets a handle's time from its segment width in pixels
  setTime: (handle, float, frame) => unit,
  // sets a handle's level from a y position
  setLevel: (handle, float, frame) => unit,
  dimmed: unit => bool,
  // the parameter that scales what the envelope does, and its label
  depth: option<(string, unit => string)>,
}

let handleIds = h => [h.time, h.level, h.curve]->Array.filterMap(id => id)

//==============================================================================
// the models' maths

// The decays' easing (#amp): L on its way between lo and hi moved along a cubic that keeps
// the end levels and leaves and reaches them flat.
let envCubic = (l: float, lo: float, hi: float) =>
  Math.abs(hi - lo) < 1e-6
    ? l
    : (-2. * l * l * l +
      3. * (lo + hi) * l * l -
      6. * lo * hi * l +
      (lo + hi) * lo * hi) / ((hi - lo) * (hi - lo))

// A stage's progress p warped by its curve: k p / (1 + (k - 1) p), k = 8^curve. The inverse is
// the warp by -curve.
let warp = (p: float, curve: float) => {
  let k = Math.pow(8., ~exp=Math.max(-1., Math.min(1., curve)))
  k * p / (1. + (k - 1.) * p)
}

// A level on the dB scale the amp envelope is drawn in: -60 dB (and silence) at 0, 0 dB at 1
// (envLevelKnob).
let levelKnob = (l: float) => l <= 0. ? 0. : Math.max(0., Math.min(1., 1. + Math.log10(l) / 3.))
let knobLevel = (f: float) => f <= 0. ? 0. : Math.pow(10., ~exp=3. * (Math.min(f, 1.) - 1.))

//==============================================================================
// The shape

// Attack, hold, decay 1 to the breakpoint, decay 2 to sustain, release.
let adsr = (
  ctx: Ctx.t,
  ids: ids,
  ~kind: kind,
  ~decibels,
  ~levelOf,
  ~levelTo,
  ~depth: option<string>,
  ~depthLabel: option<string>,
  ~enabled: option<string>,
  ~w,
  ~h,
): shape => {
  let model = ctx.model
  let amp = kind == #amp
  let def = id => model->ParamModel.def(id)
  let ms = ParamModel.plain(model, _)
  let optMs = id => id->Option.mapOr(0., ms)
  let level = id => levelOf(def(id), model->ParamModel.get(id))
  let curve = id => id->Option.mapOr(0., ParamModel.plain(model, _))
  // decay 1 is there with both its time and its breakpoint
  let decay1 = switch (ids.decay1, ids.breakpoint) {
  | (Some(t), Some(l)) => Some((t, l))
  | _ => None
  }
  let (top, bottom) = (margin, bottomOf(h))
  let yOf = v => {
    let f = decibels ? levelKnob(v) : v
    bottom - Float.clamp(f, ~min=0., ~max=1.) * (bottom - top)
  }
  let fractionAt = y => Float.clamp((bottom - y) / (bottom - top), ~min=0., ~max=1.)
  let levelAt = y => decibels ? knobLevel(fractionAt(y)) : fractionAt(y)
  // the lib skips decay 1 when the breakpoint is above 0.998
  let skipped = () => decay1->Option.mapOr(true, ((_, l)) => level(l) > 0.998)
  // the sustain level, held to 1 above 0.998
  let sustain = () => {
    let s = Math.max(0., Math.min(1., level(ids.sustain)))
    s > 0.998 ? 1. : s
  }
  let stages = () =>
    [
      Some(ms(ids.attack)),
      ids.hold->Option.map(ms),
      decay1->Option.map(((t, _)) => skipped() ? 0. : ms(t)),
      Some(ms(ids.decay)),
      Some(ms(ids.release)),
    ]->Array.filterMap(x => x)

  let fit = () => {
    let st = stages()
    let total = st->Array.reduce(0., (a, t) => a + units(t))
    {unitPx: (w - 2. * margin - Int.toFloat(Array.length(st)) * segmentGap) / niceSpan(total)}
  }

  let layout = f => {
    let after = (x0, t) => x0 + segmentGap + units(t) * f.unitPx
    let skip = skipped()
    let bp = skip ? 1. : Math.max(0., Math.min(1., decay1->Option.mapOr(1., ((_, l)) => level(l))))
    let sus = sustain()
    let x0 = margin
    let xa = after(x0, ms(ids.attack))
    let xh = ids.hold->Option.mapOr(xa, id => after(xa, ms(id)))
    let xb = switch decay1 {
    | Some(_) if skip => xh + segmentGap
    | Some((t, _)) => after(xh, ms(t))
    | None => xh
    }
    // the release starts at the sustain point: the time a note is held has no width
    let xs = after(xb, ms(ids.decay))
    let xr = after(xs, ms(ids.release))

    let points = [(x0, yOf(0.))]
    // each sampled segment, and its middle point
    let sample = (xFrom: float, xTo: float, level) => {
      points->Plots.trace(t => (xFrom + (xTo - xFrom) * t, yOf(level(t))))
      ((xFrom + xTo) / 2., yOf(level(0.5)))
    }
    let (ca, cd1, cd2, cr) = (curve(ids.attackCurve), curve(ids.decay1Curve), curve(ids.decayCurve), curve(ids.releaseCurve))
    let ease = (l, lo, hi) => amp ? envCubic(l, lo, hi) : l
    let attackMid = sample(x0, xa, t => {
      let a = warp(t, ca)
      amp ? (2. - a) * a : a
    })
    points->Array.push((xh, yOf(1.)))
    // the levels the decays run between: #amp holds them above 1e-4, #block the
    // breakpoint above 1e-6 and the sustain above a millionth of it
    let bpRun = Math.max(bp, amp ? 1e-4 : 1e-6)
    let susRun = amp ? Math.max(sus, 1e-4) : Math.max(sus, bpRun * 1e-6)
    let decay1Mid = if skip {
      // decay 2 starts from the top, at the hollow breakpoint
      points->Array.push((xb, yOf(1.)))
      ((xh + xb) / 2., yOf(1.))
    } else {
      sample(xh, xb, t => ease(Math.pow(bpRun, ~exp=warp(t, cd1)), bpRun, 1.))
    }
    let decay2Mid = sample(xb, xs, t =>
      ease(bpRun * Math.pow(susRun / bpRun, ~exp=warp(t, cd2)), susRun, bpRun)
    )
    // a sustain level below 0.001 ends the envelope
    let held = susRun < 0.001 ? 0. : susRun
    points->Array.push((xs, yOf(held)))
    // The release falls 60 dB in its time, from the held level to 0.001, where it ends: this
    // fraction of its time. Its curve warps its progress along that path, and it reaches the
    // bottom of the graph at progress `bottom`. The curve is stretched to end there, and the
    // time axis says when that is.
    let k = held / (held - 0.001)
    let (path, bottom) = if held <= 0.001 {
      (1., 1.)
    } else {
      let path = Math.log10(held / 0.001) / 3.
      let floor = decibels ? 0.001 : 0.
      let reach = amp ? Math.log10(held / (floor / k + 0.001)) / 3. / path : 1.
      (path, warp(reach, -.cr))
    }
    let fall = Math.min(1., path * bottom)
    let releaseMid = sample(xs, xr, t =>
      if held <= 0.001 {
        0.
      } else {
        let l = held * Math.pow(10., ~exp=-3. * path * warp(t * bottom, cr))
        amp ? (l - 0.001) * k : l
      }
    )
    let ta = ms(ids.attack)
    let th = ta + optMs(ids.hold)
    let tb = th + (skip ? 0. : decay1->Option.mapOr(0., ((t, _)) => ms(t)))
    let times = [
      stretch(x0, xa, 0., ta),
      stretch(xa, xh, ta, th),
      stretch(xh, xb, th, tb),
      stretch(xb, xs, tb, tb + ms(ids.decay)),
      stretch(~release=true, xs, xr, 0., ms(ids.release) * fall),
    ]

    let top = yOf(1.)
    let handles = [
      Some(point(~time=ids.attack, x0, xa, top)),
      ids.hold->Option.map(id => point(~time=id, xa, xh, top)),
      decay1->Option.map(((t, l)) => point(~time=t, ~level=l, ~hollow=skip, xh, xb, yOf(bp))),
      Some(point(~time=ids.decay, ~level=ids.sustain, xb, xs, yOf(sus))),
      Some(point(~time=ids.release, xs, xr, yOf(0.))),
      ids.attackCurve->Option.map(c => bendPoint(c, attackMid, ~rising=true)),
      decay1->Option.flatMap(_ => ids.decay1Curve)->Option.map(c => bendPoint(~hidden=skip, c, decay1Mid, ~rising=false)),
      ids.decayCurve->Option.map(c => bendPoint(~hidden=Math.abs(bp - sus) < 0.02, c, decay2Mid, ~rising=sus > bp)),
      ids.releaseCurve->Option.map(c => bendPoint(c, releaseMid, ~rising=false)),
    ]->Array.filterMap(x => x)
    (points, handles, times)
  }

  let setTime = (h, width, f) =>
    h.time->Option.forEach(t =>
      // a skipped decay 1 keeps its time until the breakpoint is pulled down
      if !(Some(t) == ids.decay1 && skipped()) {
        model->ParamModel.set(t, (def(t)).ofPlain(msOf(Math.max(0., width) / f.unitPx)))
      }
    )

  let setLevel = (h, y, _) =>
    h.level->Option.forEach(l =>
      // the top edge is "skip decay 1" for the breakpoint
      model->ParamModel.set(
        l,
        levelTo(def(l), Some(l) == ids.breakpoint && fractionAt(y) > 0.985 ? 1. : levelAt(y)),
      )
    )

  let depth = depth->Option.map(id => {
    let d = def(id)
    let label = depthLabel->Option.getOr(String.toLowerCase(d.name))
    (
      id,
      () =>
        d.plain(model->ParamModel.get(id)) == 0.
          ? label ++ " 0: no effect"
          : label ++ " " ++ model->ParamModel.shortText(id),
    )
  })

  {
    ids: [
      ...fields(ids)->Array.map(((id, _)) => id),
      ...depth->Option.mapOr([], ((id, _)) => [id]),
      ...enabled->Option.mapOr([], id => [id]),
    ],
    fit,
    layout,
    setTime,
    setLevel,
    dimmed: () => enabled->Option.mapOr(false, id => model->ParamModel.get(id) == 0.),
    depth,
  }
}

//==============================================================================
// The editor

// The graph of a shape: fields are the raw parameters shown by the "values" switch, four to a row.
let editor = (ctx: Ctx.t, parent, box: box, shape: shape, ~fields: array<(string, string)>, ~name) => {
  let model = ctx.model
  let ed = NodeEditor.make(ctx, parent, box, ~hint=hintFor(name), ~columns=4)
  let fill = Graph.path(ed.g.under, ~cls="fill")
  let ticks = Graph.group(ed.g.under)
  let curve = Graph.path(ed.g.under, ~cls="curve")
  // the envelope at its depth: rising from the bottom, or for a negative depth hanging from the top
  let depthCurve = Graph.path(ed.g.under, ~cls="curve depth")
  let depthLabel = svgEl(ed.g.under, "text", [("class", Str("tick depth")), ("text-anchor", Str("end"))])
  fields->Array.forEachWithIndex(((id, label), i) => ed.values->Grid.param(id, mod(i, 4), i / 4, label))

  let frame = ref(shape.fit())
  let handles = ref([])

  let statusFor = h => model->ParamModel.statusText(handleIds(h))
  let readoutFor = h => h->handleIds->Array.map(id => model->ParamModel.shortText(id))->Array.join("  ·  ")

  // a faint line and a label at each tick time that has room, the release's counted from
  // the note-off
  let drawTicks = (times: array<stretch>) => {
    ticks->setTextContent("")
    // the room each tick takes, line and label; the note-on and note-off keep a little
    let taken = times->Array.filterMap(t => t.msFrom == 0. ? Some((t.xFrom - 6., t.xFrom + 16.)) : None)
    tickTimes->Array.forEach(ms =>
      times->Array.forEach(t =>
        if ms > t.msFrom && ms <= t.msTo {
          let x = t.xFrom + (t.xTo - t.xFrom) * (ms - t.msFrom) / (t.msTo - t.msFrom)
          let text = (t.release ? "+" : "") ++ tickText(ms)
          let width = 5. * Int.toFloat(String.length(text))
          // near the right edge, the label sits left of its line
          let flip = x + 3. + width > box.w - 4.
          let (left, right) = flip ? (x - 3. - width, x) : (x, x + 3. + width)
          if left > 2. && taken->Array.every(((l, r)) => right + 8. < l || left - 8. > r) {
            taken->Array.push((left, right))
            Graph.line(ticks, ~cls="axis faint", x, 1., x, box.h - 1.)
            Graph.text(ticks, ~anchor=flip ? "end" : "start", flip ? x - 3. : x + 3., box.h - 4., text)
          }
        }
      )
    )
  }

  let startDrag = (i, hit, ev) =>
    handles.contents[i]->Option.forEach(h => {
      let x = ref(h.x)
      let y = ref(h.y)
      let curve0 = h.curve->Option.map(c => model->ParamModel.get(c))->Option.getOr(0.)
      ed->NodeEditor.drag(i, hit, ev, ~ids=handleIds(h), ~onMove=(dx, dy) => {
        x := Float.clamp(x.contents + dx, ~min=h.x0 + segmentGap, ~max=box.w * 4.)
        y := Float.clamp(y.contents + dy, ~min=margin, ~max=bottomOf(box.h))
        // the level first: it decides whether decay 1 is skipped
        shape.setLevel(h, y.contents, frame.contents)
        shape.setTime(h, x.contents - h.x0 - segmentGap, frame.contents)
        // a bend point: up or down bends its stage, a full bend per 60 pixels
        h.curve->Option.forEach(c =>
          model->ParamModel.set(
            c,
            Float.clamp(curve0 + h.bendSign * (h.y - y.contents) / 60., ~min=-1., ~max=1.),
          )
        )
      })
    })

  // every hit area above every dot, so a dot never hides a neighbour's hit area
  let (_, initial, _) = shape.layout(frame.contents)
  let nodes = initial->Array.mapWithIndex((h, i) =>
    ed->NodeEditor.node(
      i,
      ~dot=[("class", Str("node")), ("r", Num(4.))],
      ~hitR=h.curve != None ? 6. : 8.,
      ~cursor=switch (h.time, h.level) {
      | (Some(_), Some(_)) => "move"
      | (Some(_), None) => "ew-resize"
      | _ => "ns-resize"
      },
      ~onDrag=startDrag(i, ...),
      ~onRightClick=() =>
        handles.contents[i]->Option.forEach(h =>
          h->handleIds->Array.forEach(id => model->ParamModel.gestureSet(id, (model->ParamModel.def(id)).init))
        ),
      ~wheel=() => handles.contents[i]->Option.flatMap(h => h.time->Option.orElse(h.level)->Option.orElse(h.curve)),
    )
  )

  let draw = () => {
    let (points, hs, times) = shape.layout(frame.contents)
    handles := hs
    drawTicks(times)
    let d = Plots.pathFrom(points)
    curve->setAttribute("d", Str(d))
    switch (points[0], points[Array.length(points) - 1]) {
    | (Some((xa, _)), Some((xb, _))) =>
      let base = Float.toString(bottomOf(box.h))
      fill->setAttribute("d", Str(`${d}L${Float.toString(xb)} ${base}L${Float.toString(xa)} ${base}Z`))
    | _ => fill->setAttribute("d", Str(""))
    }
    switch shape.depth {
    | Some((id, label)) =>
      let def = model->ParamModel.def(id)
      let reach = Math.max(Math.abs(def.plain(def.min)), Math.abs(def.plain(def.max)))
      let amount = Float.clamp(reach > 0. ? def.plain(model->ParamModel.get(id)) / reach : 0., ~min=-1., ~max=1.)
      let (top, bottom) = (margin, bottomOf(box.h))
      let scaled = points->Array.map(((x, y)) => {
        let f = (bottom - y) / (bottom - top) * Math.abs(amount)
        (x, amount >= 0. ? bottom - f * (bottom - top) : top + f * (bottom - top))
      })
      depthCurve->setAttribute("d", Str(Plots.pathFrom(scaled)))
      // (at the top, left of the "values" switch)
      depthLabel->setAttribute("x", Num(amount < 0. ? box.w - 6. : box.w - 58.))
      depthLabel->setAttribute("y", Num(amount < 0. ? bottomOf(box.h) - 4. : margin + 9.))
      depthLabel->setTextContent(label())
    | None => ()
    }
    ed.g.svg->toggleClass("off", shape.dimmed())

    nodes->Array.forEachWithIndex((node, i) =>
      hs[i]->Option.forEach(h => {
        node->NodeEditor.place(h.x, h.y)
        [node.dot, node.hit]->Array.forEach(e => e->setAttribute("display", Str(h.hidden ? "none" : "inline")))
        let hot = ed.hover == Some(i) || ed.dragging == Some(i)
        let isBend = h.curve != None
        node.dot->setAttribute(
          "class",
          Str("node" ++ (h.hollow ? " hollow" : "") ++ (isBend ? " bend" : "") ++ (hot ? " hot" : "")),
        )
        node.dot->setAttribute("r", Num(isBend ? (hot ? 4.5 : 3.) : hot ? 5.5 : 4.))
      })
    )

    switch NodeEditor.focus(ed)->Option.flatMap(i => hs[i]) {
    | Some(h) =>
      ctx.status->Status.show(statusFor(h))
      if ed.dragging != None {
        ed.g->Graph.readout(~x=h.x, ~y=h.y, ~dx=10., ~above=9., ~below=18., ~nearTop=24., readoutFor(h))
      }
    | None => ()
    }
    if ed.dragging == None {
      ed.g->Graph.hideReadout
    }
  }

  // the axis is refitted when a drag ends, never during one
  let refresh = () => {
    if ed.dragging == None {
      frame := shape.fit()
    }
    draw()
  }

  ed->NodeEditor.start(shape.ids, refresh)
}

// An envelope editor on these parameters (see the header). name: what the hint calls it
// ("Amp envelope"); fields: the raw values' fields and labels (by default every parameter in ids).
let make = (
  ctx: Ctx.t,
  parent,
  box: box,
  ids: ids,
  ~name,
  ~kind: kind=#amp,
  ~decibels=?,
  ~levelOf=defaultLevelOf,
  ~levelTo=defaultLevelTo,
  ~depth=?,
  ~depthLabel=?,
  ~enabled=?,
  ~fields as fs=?,
) => {
  let decibels = decibels->Option.getOr(kind == #amp)
  let shape = adsr(ctx, ids, ~kind, ~decibels, ~levelOf, ~levelTo, ~depth, ~depthLabel, ~enabled, ~w=box.w, ~h=box.h)
  editor(ctx, parent, box, shape, ~fields=fs->Option.getOr(fields(ids)), ~name)
}
