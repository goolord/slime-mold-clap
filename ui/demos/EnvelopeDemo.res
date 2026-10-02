// The envelope editors' and the LFO plot's gallery: an amp envelope drawn in dB (EnvEditor,
// the #amp model), a filter envelope with its amount drawn the #block way, a
// plain ADSR, and an LFO's shape (LfoPlot), each over its raw parameter rows. The
// parameters are in plain units: times in ms on a square law, levels in dB (-60: silence) or
// 0..1, curves -1..1.
//
// bundle: npx esbuild ui/demos/EnvelopeDemo.res.mjs --bundle --format=esm --platform=browser --outfile=bundle/demo-envelope.js
// view:   http://localhost:8123/tools/ui-preview/?view=demo-envelope   (&page=adsr)

open! Web

let margin = 6.
let width = Style.designWidth - 2. * margin
let height = Style.pageHeight - 2. * margin
let half = (width - Grid.gap) / 2.

//==============================================================================
// Parameters

let ms = (id, name, ~min, ~max, ~init) => Param.number(id, name, ~min, ~max, ~init, ~law=Power(2.), ~unit="ms")
let db = (id, name, ~init) => Param.number(id, name, ~min=-60., ~max=0., ~init, ~unit="dB")
let curve = (id, name) => Param.number(id, name, ~min=-1., ~max=1., ~init=0., ~digits=2)

// the usual ranges; the sustain in dB, or 0..1 for a block envelope
let envelopeSpecs = (prefix, name, ~sustain) => [
  ms(prefix ++ "Attack", name ++ " attack", ~min=0.2, ~max=10000., ~init=5.),
  ms(prefix ++ "Hold", name ++ " hold", ~min=0., ~max=10000., ~init=0.),
  ms(prefix ++ "Decay1", name ++ " decay 1", ~min=10., ~max=20000., ~init=120.),
  db(prefix ++ "Breakpoint", name ++ " breakpoint", ~init=-6.),
  ms(prefix ++ "Decay2", name ++ " decay 2", ~min=10., ~max=20000., ~init=900.),
  sustain,
  ms(prefix ++ "Release", name ++ " release", ~min=10., ~max=20000., ~init=400.),
  curve(prefix ++ "AttackCurve", name ++ " attack curve"),
  curve(prefix ++ "Decay1Curve", name ++ " decay 1 curve"),
  curve(prefix ++ "Decay2Curve", name ++ " decay 2 curve"),
  curve(prefix ++ "ReleaseCurve", name ++ " release curve"),
]

let envelopeIds = (prefix): EnvEditor.ids => {
  attack: prefix ++ "Attack",
  hold: prefix ++ "Hold",
  decay1: prefix ++ "Decay1",
  breakpoint: prefix ++ "Breakpoint",
  decay: prefix ++ "Decay2",
  sustain: prefix ++ "Sustain",
  release: prefix ++ "Release",
  attackCurve: prefix ++ "AttackCurve",
  decay1Curve: prefix ++ "Decay1Curve",
  decayCurve: prefix ++ "Decay2Curve",
  releaseCurve: prefix ++ "ReleaseCurve",
}

let adsrIds: EnvEditor.ids = {attack: "adsrAttack", decay: "adsrDecay", sustain: "adsrSustain", release: "adsrRelease"}

let lfoIds: LfoPlot.ids = {shape: "lfoShape", phase: "lfoPhase", steps: "lfoSteps", oneShot: "lfoOneShot"}

let specs = [
  ...envelopeSpecs("amp", "Amp", ~sustain=db("ampSustain", "Amp sustain", ~init=-12.)),
  ...envelopeSpecs("fenv", "Filter env", ~sustain=Param.percent("fenvSustain", "Filter env sustain", ~init=0.3)),
  Param.number("fenvAmount", "Filter env amount", ~min=-8., ~max=8., ~init=3., ~unit="oct", ~digits=2),
  Param.toggle("fenvOn", "Filter env on", ~init=true),
  ms("adsrAttack", "ADSR attack", ~min=0.2, ~max=10000., ~init=40.),
  ms("adsrDecay", "ADSR decay", ~min=10., ~max=20000., ~init=600.),
  Param.percent("adsrSustain", "ADSR sustain", ~init=0.5),
  ms("adsrRelease", "ADSR release", ~min=10., ~max=20000., ~init=800.),
  Param.choice("lfoShape", "LFO shape", ["sine", "saw", "square", "triangle", "smooth random", "stepping random"]),
  Param.percent("lfoPhase", "LFO phase", ~init=0.),
  Param.choice("lfoSteps", "LFO steps", ["off", "2", "3", "4", "6", "8", "12", "16", "24", "32"]),
  Param.toggle("lfoOneShot", "LFO one-shot"),
]

//==============================================================================
// Pages

// An envelope editor over its raw parameter rows, in a panel.
let envelope = (ctx: Ctx.t, page, ~title, ~x, ids: EnvEditor.ids, ~extra=[], editor) => {
  let fields = Array.concat(EnvEditor.fields(ids), extra)
  let rows = (Array.length(fields) + 3) / 4
  let p = Panel.make(page, ~title, ~x, ~y=margin, ~w=half, ~h=height)
  let graphH = height - 25. - Int.toFloat(rows) * Grid.rowHeight - 12.
  editor(p.el, {x: 8., y: 25., w: half - 18., h: graphH})
  let g = Grid.make(ctx, p.el, ~y=25. + graphH + 6., ~cw=Grid.fitColumns(half, 4))
  fields->Array.forEachWithIndex(((id, label), i) => g->Grid.auto(id, mod(i, 4), i / 4, label))
}

let envelopesPage = (ctx: Ctx.t, page) => {
  envelope(ctx, page, ~title="amp envelope (#amp, in dB)", ~x=margin, envelopeIds("amp"), (parent, box) =>
    EnvEditor.make(ctx, parent, box, envelopeIds("amp"), ~name="Amp envelope")
  )
  envelope(
    ctx,
    page,
    ~title="filter envelope (#block, with its amount)",
    ~x=margin + half + Grid.gap,
    envelopeIds("fenv"),
    ~extra=[("fenvAmount", "amount"), ("fenvOn", "on")],
    (parent, box) =>
      EnvEditor.make(
        ctx,
        parent,
        box,
        envelopeIds("fenv"),
        ~name="Filter envelope",
        ~kind=#block,
        ~depth="fenvAmount",
        ~depthLabel="amount",
        ~enabled="fenvOn",
      ),
  )
}

let adsrPage = (ctx: Ctx.t, page) => {
  envelope(ctx, page, ~title="plain ADSR (#amp, drawn linearly)", ~x=margin, adsrIds, (parent, box) =>
    EnvEditor.make(ctx, parent, box, adsrIds, ~name="ADSR", ~decibels=false)
  )
  let x = margin + half + Grid.gap
  let p = Panel.make(page, ~title="LFO (two cycles from its reset)", ~x, ~y=margin, ~w=half, ~h=height)
  let plotH = height - 27. - 3. * Grid.rowHeight - 22.
  LfoPlot.make(ctx, p.el, {x: 8., y: 27., w: half - 18., h: plotH}, lfoIds)->ignore
  let g = Grid.make(ctx, p.el, ~y=27. + plotH + 8., ~cw=Grid.fitColumns(half, 4))
  g->Grid.choice("lfoShape", 0, 0, "shape", ~span=2)
  g->Grid.param("lfoPhase", 2, 0, "phase")
  g->Grid.choice("lfoSteps", 3, 0, "s&h steps")
  g->Grid.toggle("lfoOneShot", 0, 1, "one-shot")
  g->Grid.note("The phase is where a reset starts the cycle; one-shot runs one cycle from there and holds its end.", 1, 1, ~span=3, ~rows=2)->ignore
}

let pages: array<Shell.page> = [
  {
    id: "envelopes",
    label: "Envelopes",
    title: "EnvEditor",
    hint: "Envelope editors, the #amp model and the #block one",
    build: envelopesPage,
  },
  {
    id: "adsr",
    label: "ADSR & LFO",
    title: "EnvEditor and LfoPlot",
    hint: "A plain ADSR, and an LFO's shape",
    build: adsrPage,
  },
]

let default = pc => Shell.mount(pc, ~specs, ~pages)
