// A test tube for a slider: the parameter's knob travel is how full of slime the tube is. It
// behaves like every other control (Controls.valueInput): drag up or down (shift and ctrl for finer
// steps), scroll, double-click or Enter to type a value, right-click to reset, a double
// right-click for the host's menu. The label sits over the tube, the value under it.

open! Web

Style.register(`
/* a test tube slider (TubeSlider.res): label, the glass with its slime, the value */
.tube {
    position: absolute; box-sizing: border-box; display: flex; flex-direction: column; align-items: center;
    cursor: ns-resize; border-radius: var(--radius-sm); padding: 3px 0 2px;
}
.tube:hover, .tube.drag { background: var(--tile); box-shadow: inset 0 0 0 1px var(--tile-edge); }
.tube .l { font-size: 11.5px; line-height: 13px; color: var(--ink-soft); white-space: nowrap; text-align: center; }
.tube .v { font-size: 12.5px; line-height: 15px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.tube .glass {
    position: relative; flex: 1; width: 26px; margin: 5px 0 4px; box-sizing: border-box;
    border: 1.5px solid rgba(var(--ink-rgb), 0.55); border-top: none; border-radius: 0 0 13px 13px;
    background:
        repeating-linear-gradient(to top, transparent 0 9px, rgba(var(--ink-rgb), 0.18) 9px 10px) right 0 bottom 8px / 6px calc(100% - 8px) no-repeat,
        rgba(var(--paper-rgb), 0.6);
    overflow: hidden;
}
/* the lip */
.tube .glass::before {
    content: ""; position: absolute; left: -4px; right: -4px; top: 0; height: 3px; z-index: 2;
    border-radius: 2px; background: rgba(var(--ink-rgb), 0.55);
}
/* a highlight down the glass */
.tube .glass::after {
    content: ""; position: absolute; left: 4px; top: 6px; bottom: 10px; width: 3px; z-index: 2;
    border-radius: 2px; background: rgba(var(--ink-rgb), 0.22);
}
.tube .goo {
    position: absolute; left: 0; right: 0; bottom: 0;
    background: linear-gradient(to right, rgba(var(--signal-rgb), 0.85), var(--signal) 45%, rgba(var(--signal-rgb), 0.8));
}
/* the meniscus: the slime clings to the glass */
.tube .goo::before {
    content: ""; position: absolute; left: 0; right: 0; top: -4px; height: 8px;
    background: radial-gradient(ellipse 60% 100% at 50% 100%, var(--signal) 55%, transparent 58%),
                linear-gradient(to right, var(--signal) 18%, transparent 18% 82%, var(--signal) 82%);
    border-radius: 6px 6px 0 0;
}
.tube .goo i {
    position: absolute; bottom: 0; width: 4px; height: 4px; border-radius: 50%;
    background: rgba(var(--paper-rgb), 0.7); animation: tube-bubble 3.2s linear infinite; opacity: 0;
}
.tube .goo i:nth-child(1) { left: 6px; animation-delay: -0.4s; }
.tube .goo i:nth-child(2) { left: 13px; width: 3px; height: 3px; animation-delay: -1.7s; animation-duration: 2.6s; }
.tube .goo i:nth-child(3) { left: 9px; width: 5px; height: 5px; animation-delay: -2.5s; animation-duration: 4.1s; }
@keyframes tube-bubble {
    0% { transform: translateY(0); opacity: 0; }
    15% { opacity: 1; }
    100% { transform: translateY(-120px); opacity: 0; }
}
.tube .goo.low i { display: none; }
.tube:hover .glass, .tube.drag .glass, .tube:focus-visible .glass { border-color: var(--signal); }
.tube:focus-visible { outline: 2px solid var(--signal); outline-offset: 1px; }
@media (prefers-reduced-motion: reduce) { .tube .goo i { display: none; } }
`)

let make = (ctx: Ctx.t, parent, id, box: box, ~label=?) => {
  let (c, e) = Controls.frame(ctx, parent, id, ~cls="tube", ~x=box.x, ~y=box.y, ~w=box.w, ~label?, ~labelCls="l")
  e->setStyle("height", px(box.h))
  let glass = el("div", ~cls="glass", ~parent=e)
  let goo = el("div", ~cls="goo", ~parent=glass)
  for _ in 1 to 3 {
    el("i", ~parent=goo)->ignore
  }
  let v = el("span", ~cls="v", ~parent=e)

  let update = () => {
    let x = Controls.current(c)
    v->setTextContent(c.def.shortText(x))
    let n = Controls.clamp01(c.def.toNorm(x))
    // the meniscus shows even when empty, so the tube never looks broken
    goo->setStyle("height", `calc(${Float.toString(n * 100.)}% - ${Float.toString(n * 4.)}px + 3px)`)
    goo->toggleClass("low", n < 0.08)
    Controls.refreshStatus(c)
  }

  Controls.valueInput(c, e)
  Controls.bind(c, update)
  e
}
