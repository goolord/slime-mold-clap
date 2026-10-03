// The widgets' gallery: XY pads with a level meter (XyPad, Meter), and a strip of reorderable tabs
// (FxStrip), each on a page of its own. The header's "test signal" makes up what a patch would send
// the meter and the pad's live position, when the connection can fake it (the UI preview's
// pc.emit); otherwise send them yourself, e.g. pc.emit("meterOut", [0.5, 0.4]).
//
// bundle: npx esbuild ui/demos/GraphsDemo.res.mjs --bundle --format=esm --platform=browser --outfile=bundle/demo-graphs.js
// view:   http://localhost:8123/tools/ui-preview/?view=demo-graphs   (&page=strip)

open! Web

let margin = 6.
let width = Style.designWidth - 2. * margin
let height = Style.pageHeight - 2. * margin

//==============================================================================
// Parameters

let xySpecs = [
  Param.number("xyX", "XY X", ~min=-1., ~max=1., ~init=0.),
  Param.number("xyY", "XY Y", ~min=-1., ~max=1., ~init=0.),
  Param.percent("xyRadius", "XY random radius", ~init=0.2),
  // a pad over any two parameters
  Param.logarithmic("cutoff", "Cutoff", ~min=20., ~max=20000., ~init=1000., ~unit="Hz"),
  Param.number("resonance", "Resonance", ~min=0., ~max=1., ~init=0.3, ~law=Power(2.)),
]

// the strip's effects: an on switch each, and a place parameter per slot
let stripNames = ["one", "two", "three"]
let stripSpecs = [
  ...stripNames->Array.map(n => Param.toggle(n ++ "On", "Strip " ++ n ++ " on", ~init=true)),
  ...stripNames->Array.mapWithIndex((_, k) => {
    let n = Int.toString(k + 1)
    Param.choice("slot" ++ n, "Slot " ++ n, stripNames, ~init=k, ~hidden=true)
  }),
]

let specs = [...xySpecs, ...stripSpecs]

//==============================================================================
// Pages

let xyPage = (ctx: Ctx.t, page) => {
  let panelH = height
  let padSide = 360.
  let a = Panel.make(page, ~title="xy", ~x=margin, ~y=margin, ~w=padSide + 16., ~h=panelH)
  XyPad.make(ctx, a.el, {x: 8., y: 27., w: padSide, h: padSide}, ~x="xyX", ~y="xyY", ~radius="xyRadius", ~position="xyOut")
  let g = Grid.make(ctx, a.el, ~y=27. + padSide + 10., ~cw=Grid.fitColumns(padSide + 16., 3))
  g->Grid.param("xyX", 0, 0, "x")
  g->Grid.param("xyY", 1, 0, "y")
  g->Grid.param("xyRadius", 2, 0, "radius")

  let bSide = 300.
  let b = Panel.make(page, ~title="any ranges", ~x=Panel.right(a), ~y=margin, ~w=bSide + 16., ~h=panelH)
  XyPad.make(ctx, b.el, {x: 8., y: 27., w: bSide, h: bSide}, ~x="cutoff", ~y="resonance", ~label="cutoff × resonance")
  let g = Grid.make(ctx, b.el, ~y=27. + bSide + 10., ~cw=Grid.fitColumns(bSide + 16., 2))
  g->Grid.param("cutoff", 0, 0, "cutoff")
  g->Grid.param("resonance", 1, 0, "resonance")
  g->Grid.note("Each axis spans its parameter's knob travel: cutoff on a log scale, resonance on a power law.", 0, 1, ~span=2, ~rows=2)->ignore

  let mx = Panel.right(b)
  let m = Panel.make(page, ~title="output", ~x=mx, ~y=margin, ~w=width + margin - mx, ~h=panelH)
  let mw = 34.
  Meter.make(ctx, m.el, {x: (m.w - mw) / 2., y: 27., w: mw, h: panelH - 37.}, ~endpoint="meterOut", ~name="Output")->ignore
}

let stripPage = (ctx: Ctx.t, page) => {
  let effects: array<FxStrip.effect> = stripNames->Array.map((n): FxStrip.effect => {
    label: n,
    title: "Effect " ++ n,
    on: Some(n ++ "On"),
    build: body => {
      let p = Panel.make(body, ~title=n, ~x=0., ~y=0., ~w=width, ~h=height - 30.)
      let g = Grid.make(ctx, p.el, ~cw=Grid.fitColumns(width, 6))
      g->Grid.note("Its editor goes here. Drag the tab sideways to move it in the chain; the slot parameters keep the order.", 0, 0, ~span=3, ~rows=2)->ignore
    },
  })
  let order = stripNames->Array.mapWithIndex((_, k) => "slot" ++ Int.toString(k + 1))
  FxStrip.make(ctx, page, {x: margin, y: margin, w: width, h: height}, ~effects, ~order)->ignore
}

let pages: array<Shell.page> = [
  {id: "xy", label: "XY", title: "XyPad and Meter", hint: "XY pads, and a level meter", build: xyPage},
  {id: "strip", label: "Strip", title: "FxStrip", hint: "A chain as a strip of tabs, each with an on light", build: stripPage},
]

//==============================================================================
// A made-up signal for the meter and the pad, through the UI preview's pc.emit

let canEmit: PatchConnection.t => bool = %raw(`pc => typeof pc.emit === "function"`)
@send external emit: (PatchConnection.t, string, 'value) => unit = "emit"

let testSignal = (ctx: Ctx.t) => {
  let timer = ref(None)
  () =>
    switch timer.contents {
    | Some(t) =>
      clearInterval(t)
      timer := None
      ctx.toast("Test signal off")
    | None if !canEmit(ctx.pc) => ctx.toast("This connection can't fake the patch's messages (try the UI preview)")
    | None =>
      let model = ctx.model
      let get = ParamModel.plain(model, _)
      let start = Date.now()
      ctx.toast("Test signal on")
      timer := Some(setInterval(() => {
            let t = (Date.now() - start) / 1000.
            // the output: a wobble, now and then over 0 dB
            let swell = 0.55 + 0.4 * Math.sin(t * 1.3)
            let burst = Math.sin(t * 0.37) > 0.93 ? 1.25 : 1.
            emit(ctx.pc, "meterOut", [swell * burst, (0.5 + 0.4 * Math.sin(t * 1.3 + 0.8)) * burst])
            // the pad's random walk around its point, within the radius
            let r = get("xyRadius")
            let clamp = v => Float.clamp(v, ~min=-1., ~max=1.)
            emit(
              ctx.pc,
              "xyOut",
              [clamp(get("xyX") + r * Math.cos(t * 2.3) * Math.sin(t * 0.7)), clamp(get("xyY") + r * Math.sin(t * 1.9))],
            )
          }, 33))
    }
}

let default = pc =>
  Shell.mount(pc, ~specs, ~pages, ~buttons=ctx => [
    ("test signal", "Fake the patch's meters and live positions (in the UI preview)", testSignal(ctx)),
  ])
