// XY pad: two parameters on one square, x across and y up. Drag to set both (shift or ctrl for
// fine steps, moving from where the point was rather than jumping to the pointer). Dragging with
// the right button keeps the distance to the centre (moves around a circle), a middle click
// centres. With a radius parameter, a dashed circle of that radius goes around the point (a random
// walk's reach, say); the small ring shows where the patch says it currently
// is, if it reports it.
//
// Any ranges: the pad spans each parameter's knob travel (toNorm/fromNorm), its centre being the
// middle of both. The radius is a fraction of the pad's half width (its knob position, so a 0..1
// parameter is that fraction).
//
// ~position names an output endpoint the patch reports the live position on, as float<2> (JSON
// [x, y], or {x, y}) in the parameters' plain units (what the DSP gets): send it every few blocks,
// and only when it has moved, e.g.
//   if (++blocks >= 8) { blocks = 0; if (x != sentX || y != sentY) xyOut <- float<2> (x, y); }
// It is drawn at most once a frame.

open! Web

let signal = Str("var(--signal)")

// The patch's position: a float<2>, or a struct {x, y}.
let decodePosition = (json: JSON.t) =>
  switch json {
  | Array([Number(x), Number(y)]) => Some((x, y))
  | Object(fields) =>
    switch (fields->Dict.get("x"), fields->Dict.get("y")) {
    | (Some(Number(x)), Some(Number(y))) => Some((x, y))
    | _ => None
    }
  | _ => None
  }

let make = (ctx: Ctx.t, parent, area: box, ~x as xId, ~y as yId, ~radius as radiusId=?, ~position=?, ~label="XY pad") => {
  let model = ctx.model
  let (xDef, yDef) = (model->ParamModel.def(xId), model->ParamModel.def(yId))
  // a parameter's place on the pad, -1 .. 1, and back
  let padOf = (d: Param.t, id) => 2. * Controls.clamp01(d.toNorm(model->ParamModel.get(id))) - 1.
  let valueAt = (d: Param.t, v) => d.fromNorm(Controls.clamp01((v + 1.) / 2.))
  let get = () => (padOf(xDef, xId), padOf(yDef, yId))
  let setBoth = ((x, y)) => {
    model->ParamModel.set(xId, valueAt(xDef, x))
    model->ParamModel.set(yId, valueAt(yDef, y))
  }

  let side = Math.min(area.w, area.h)
  let box = {x: area.x + (area.w - side) / 2., y: area.y + (area.h - side) / 2., w: side, h: side}
  let s = Plots.svg(parent, box)
  s->addClass("draw")
  let svgEl = svgEl(s, ...)
  Plots.background(s, box)
  s->Plots.line(side / 2., 1., side / 2., side - 1.)->ignore
  s->Plots.line(1., side / 2., side - 1., side / 2.)->ignore
  let radius = svgEl(
    "circle",
    [
      ("r", Num(0.)),
      ("fill", Str("none")),
      ("stroke", signal),
      ("stroke-width", Num(1.)),
      ("stroke-dasharray", Str("2 2")),
      ("opacity", Num(0.8)),
    ],
  )
  let live = svgEl(
    "circle",
    [("r", Num(3.)), ("fill", Str("none")), ("stroke", signal), ("stroke-width", Num(1.)), ("opacity", Num(0.))],
  )
  let hx = svgEl("line", [("stroke", signal), ("stroke-width", Num(1.4))])
  let hy = svgEl("line", [("stroke", signal), ("stroke-width", Num(1.4))])
  let dot = svgEl("circle", [("r", Num(3.2)), ("fill", signal)])

  // where the patch says it is, on the pad
  let livePosition = ref(None)

  let toPx = (x, y) => (side / 2. + x * (side / 2. - 3.), side / 2. - y * (side / 2. - 3.))

  // the pad's own coordinates and polar form, then the values when they aren't those
  let padRange = (d: Param.t) => d.plain(d.min) == -1. && d.plain(d.max) == 1. && d.toNorm(0.) == 0.5
  let status = ctx.status->Status.live(s, () => {
    let (x, y) = get()
    let r = Math.hypot(x, y)
    let a = Math.atan2(~y, ~x) * 180. / Math.Constants.pi
    let fixed = (v, digits) => Float.toFixed(v, ~digits)
    let pad = `${label} (${fixed(x, 3)}, ${fixed(y, 3)} / ${fixed(r, 3)}, ${fixed(a, 2)} degrees)`
    padRange(xDef) && padRange(yDef) ? pad : pad ++ "    " ++ model->ParamModel.statusText([xId, yId])
  })

  let radiusAmount = () =>
    radiusId->Option.mapOr(0., id => Controls.clamp01((model->ParamModel.def(id)).toNorm(model->ParamModel.get(id))))

  let draw = () => {
    let (px, py) = toPx(padOf(xDef, xId), padOf(yDef, yId))
    let set = (e, attrs) => attrs->Array.forEach(((name, v)) => e->setAttribute(name, Num(v)))
    dot->set([("cx", px), ("cy", py)])
    hx->set([("x1", px - 6.), ("x2", px + 6.), ("y1", py), ("y2", py)])
    hy->set([("y1", py - 6.), ("y2", py + 6.), ("x1", px), ("x2", px)])
    let r = radiusAmount() * (side / 2. - 3.)
    radius->set([("cx", px), ("cy", py), ("r", r)])

    // the live position shows while it can differ: always, or with a radius parameter, while
    // the radius is above 0
    switch livePosition.contents {
    | Some((x, y)) if radiusId == None || r > 0. =>
      let (lx, ly) = toPx(x, y)
      live->set([("cx", lx), ("cy", ly), ("opacity", 1.)])
    | _ => live->set([("opacity", 0.)])
    }
    status.refresh()
  }

  let onDown = ev => {
    ev->preventDefault
    if ev->button == 1 {
      model->ParamModel.gestureSet(xId, valueAt(xDef, 0.))
      model->ParamModel.gestureSet(yId, valueAt(yDef, 0.))
    } else {
      status.setDragging(true)
      model->ParamModel.beginGesture(xId)
      model->ParamModel.beginGesture(yId)
      let circular = ev->button == 2
      let (x0, y0) = get()
      let r0 = Math.hypot(x0, y0)
      let position = ref((x0, y0))
      let fine = ev => ev->shiftKey || ev->ctrlKey
      // the position under the pointer
      let under = ev => {
        let (fx, fy) = s->pointerFraction(ev)
        let k = 2. * (side / 2.) / (side / 2. - 3.)
        ((fx - 0.5) * k, (0.5 - fy) * k)
      }

      let apply = ((nx, ny)) => {
        let (nx, ny) = if circular && r0 > 0. {
          let a = Math.atan2(~y=ny, ~x=nx)
          (Math.cos(a) * r0, Math.sin(a) * r0)
        } else {
          (nx, ny)
        }
        let clamp = v => Float.clamp(v, ~min=-1., ~max=1.)
        let p = (clamp(nx), clamp(ny))
        position := p
        setBoth(p)
      }

      if !fine(ev) {
        apply(under(ev))
      }
      Controls.dragBy(
        ctx,
        s,
        ev,
        ~onMove=(dx, dy, mv) =>
          if fine(mv) {
            let (x, y) = position.contents
            apply((x + dx / (side / 2.) * 0.15, y - dy / (side / 2.) * 0.15))
          } else {
            apply(under(mv))
          },
        ~onUp=() => {
          model->ParamModel.endGesture(xId)
          model->ParamModel.endGesture(yId)
          status.setDragging(false)
        },
      )
    }
  }

  s->onPointer(#pointerdown, onDown)
  s->suppressContextMenu

  model->ParamModel.listenEach([xId, yId, ...radiusId->Option.mapOr([], id => [id])], draw)
  // (reported at the patch's rate: drawn once a frame, and only when it moves)
  let drawSoon = perFrame(draw)
  position->Option.forEach(endpoint =>
    ctx.pc->PatchConnection.addEndpointListener(endpoint, json => {
      let onPad = (d: Param.t, v) => 2. * Controls.clamp01(d.toNorm(d.ofPlain(v))) - 1.
      let p = decodePosition(json)->Option.map(((x, y)) => (onPad(xDef, x), onPad(yDef, y)))
      if p != livePosition.contents {
        livePosition := p
        drawSoon()
      }
    })
  )
  draw()
}
