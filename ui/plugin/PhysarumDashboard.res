// The Physarum FDN's page: the petri dish on the left (NetworkGraph, edited where it's drawn), and on
// the right what each group of settings does, drawn beside its test tubes: the tube plasticity and
// the conductance it settles tubes at, the reverb and its decay, and the loop matrix the DSP is
// running with the numbers that show it stays lossless.

open! Web

let hint = "Click a node in the dish to feed it the input, drag it to stretch the room. Drag a test tube up or down, double-click it to type a value, right-click to reset it."

// The slime's chrome: rounded display type for the names, a glossy gooey panel, drips under the
// header. Only the theme's properties, so the agar theme gets the same shapes in its own colours.
Style.register(`
:host, plugin-view {
    --display: ui-rounded, "SF Pro Rounded", "Arial Rounded MT Bold", "Nunito", "Varela Round", "Segoe UI", sans-serif;
}
.pv-stage { background: radial-gradient(ellipse 120% 90% at 30% 20%, rgba(var(--paper-rgb), 0.12), transparent 60%), var(--ground); }
.pv-head { z-index: 5; border-bottom: none; background: linear-gradient(to bottom, var(--panel-hi), var(--panel)); }
.pv-head .brand { font-family: var(--display); font-size: 23px; letter-spacing: -0.01em; color: var(--signal); padding: 0 10px 2px 6px; }
/* goo hanging off the header */
.pv-head::after {
    content: ""; position: absolute; left: 0; right: 0; top: 100%; height: 11px; pointer-events: none;
    background:
        radial-gradient(circle 5px at 4% 2px, var(--panel) 98%, transparent),
        radial-gradient(circle 3px at 9% 6px, var(--panel) 98%, transparent),
        radial-gradient(ellipse 9px 7px at 23% 0, var(--panel) 98%, transparent),
        radial-gradient(circle 4px at 31% 4px, var(--panel) 98%, transparent),
        radial-gradient(ellipse 6px 9px at 47% 0, var(--panel) 98%, transparent),
        radial-gradient(circle 3px at 53% 3px, var(--panel) 98%, transparent),
        radial-gradient(ellipse 10px 5px at 66% 0, var(--panel) 98%, transparent),
        radial-gradient(circle 4px at 79% 6px, var(--panel) 98%, transparent),
        radial-gradient(ellipse 7px 8px at 88% 0, var(--panel) 98%, transparent),
        radial-gradient(circle 3px at 96% 3px, var(--panel) 98%, transparent);
}
.blk {
    background: linear-gradient(to bottom, var(--panel-hi), var(--panel) 60px);
    box-shadow: inset 0 1px 0 rgba(var(--ink-rgb), 0.1), 0 2px 0 rgba(0, 0, 0, 0.18);
}
.blk > .ttl { font-family: var(--display); font-size: 15px; letter-spacing: 0; top: 4px; left: 10px; }
.pv-status { border-top: none; background: linear-gradient(to top, var(--panel-hi), var(--panel)); }
.dish { cursor: grab; }
.vitals { position: absolute; display: flex; flex-direction: column; justify-content: space-between; font-size: 12.5px; color: var(--ink-soft); }
.vitals b { font-weight: var(--title-weight); color: var(--ink); font-variant-numeric: tabular-nums; }
.vitals .ok { color: var(--signal); }
`)

@set external setInnerHtml: (element, string) => unit = "innerHTML"

let fmt = (x, digits) => Float.toFixed(x, ~digits)

// The numbers under the matrix: its largest singular value (never above 1), how far it is from
// lossless and how many iterations that took, and how much of the network is open.
let vitals = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box) => {
  let root = el("div", ~cls="vitals", ~parent)->placeBox(box)
  let lines = [el("div", ~parent=root), el("div", ~parent=root), el("div", ~parent=root)]
  let set = (i, html) => lines[i]->Option.forEach(e => e->setInnerHtml(html))
  let update = () =>
    switch bridge.stats {
    | Some(s) =>
      let memory = ParamModel.def(ctx.model, "memory").plain(ParamModel.get(ctx.model, "memory"))
      let threshold = memory + 0.1 * (1. - memory)
      let openTubes =
        bridge.conductance->Option.mapOr(0, ws =>
          ws->Array.reduceWithIndex(0, (n, w, k) =>
            k / FdnModel.size != mod(k, FdnModel.size) && w > threshold ? n + 1 : n
          )
        )
      let bounded = s.sigmaMax <= 1.0000005
      set(
        0,
        `Loop gain <b class="${bounded ? "ok" : ""}">${fmt(s.sigmaMax, 6)}</b>, ${bounded ? "never above 1" : "above 1!"}`,
      )
      set(
        1,
        `Lossless to <b>${s.unitarityError->Float.toExponential(~digits=1)}</b> after <b>${Int.toString(s.iterations)}</b> iterations`,
      )
      set(2, `<b>${Int.toString(openTubes)}</b> of 56 tubes open, mean conductance <b>${fmt(s.meanConductance, 2)}</b>`)
    | None =>
      set(0, "Waiting for the DSP")
      set(1, "")
      set(2, "")
    }
  bridge->PatchBridge.listen(update)
  update()
  ctx.status->Status.hover(root, () =>
    "The matrix is projected to the nearest lossless matrix every 64 samples; its gain can never exceed 1, so the loop can't run away"
  )
}

let build = (ctx: Ctx.t, page) => {
  let bridge = PatchBridge.connect(ctx.pc)
  let margin = 6.

  // the dish
  let dish = Panel.make(page, ~title="petri dish", ~x=margin, ~y=margin, ~w=492., ~h=492.)
  NetworkGraph.make(ctx, bridge, dish.el, {x: 5., y: 22., w: 480., h: 464.})->ignore

  // a panel with its plot on the left and four test tubes on the right
  let column = Panel.right(dish)
  let width = 1000. - margin - column
  let group = (~title, ~y, ~h, ~plot, tubes) => {
    let panel = Panel.make(page, ~title, ~x=column, ~y, ~w=width, ~h)
    let plotWidth = 210.
    plot(ctx, bridge, panel.el, {x: 7., y: 26., w: plotWidth, h: h - 34.})
    let x0 = plotWidth + 13.
    let cw = (width - 2. - x0 - 5.) / Int.toFloat(Array.length(tubes))
    tubes->Array.forEachWithIndex(((id, label), i) =>
      TubeSlider.make(ctx, panel.el, id, {x: x0 + Int.toFloat(i) * cw, y: 24., w: cw - 4., h: h - 30.}, ~label)->ignore
    )
    panel
  }

  let plasticity = group(
    ~title="tube plasticity",
    ~y=margin,
    ~h=190.,
    ~plot=SlimePlots.plasticity,
    [("growthRate", "adaptation"), ("decayRate", "pruning"), ("memory", "memory"), ("gamma", "flux shape")],
  )
  let reverb = group(
    ~title="reverb",
    ~y=Panel.bottom(plasticity),
    ~h=190.,
    ~plot=SlimePlots.decay,
    [("decayTime", "decay time"), ("damping", "damping"), ("roomSize", "room size"), ("mix", "dry/wet")],
  )

  // the loop matrix, and the output level
  let outWidth = 70.
  let y = Panel.bottom(reverb)
  let h = Style.pageHeight - y - margin
  let loopPanel = Panel.make(page, ~title="loop matrix", ~x=column, ~y, ~w=width - outWidth - Grid.gap, ~h)
  SlimePlots.matrix(ctx, bridge, loopPanel.el, {x: 9., y: 25., w: h - 32., h: h - 32.})
  vitals(ctx, bridge, loopPanel.el, {x: h - 8., y: 26., w: loopPanel.w - h, h: h - 34.})

  let out = Panel.make(page, ~title="out", ~x=Panel.right(loopPanel), ~y, ~w=outWidth, ~h)
  let mw = 30.
  Meter.make(ctx, out.el, {x: (outWidth - mw) / 2., y: 26., w: mw, h: h - 34.}, ~endpoint="meterOut", ~name="Output")->ignore
}
