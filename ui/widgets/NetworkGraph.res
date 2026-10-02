// The petri dish: the delay network as the slime mould it is, drawn live from what the DSP sends
// (PatchBridge), and edited where it is drawn.
//
//  - Each delay line is a node on a ring, clockwise from the top, its size the line's length.
//    It swells and glows with its pressure (the line's level).
//  - Each pair of nodes is joined by a tube whose thickness at each end is the conductance out of
//    that end (W i -> j at node i): thick where the tube carries energy away, thin where it doesn't.
//  - Grains stream along a tube with the flux through it, and shuttle gently back and forth when
//    there is none, as Physarum's cytoplasm does.
//  - An oat flake marks a line the input feeds. Click a node to feed it or starve it.
//  - The ring's radius is the room size: drag a node (or anywhere in the dish) outwards or inwards
//    to stretch the room, or scroll over the dish.
//
// Until the DSP has sent anything (the UI preview, say), it draws the network as it starts: every
// tube at the lattice its harmonic memory keeps, the lines at the room size's lengths at 48 kHz.

open! Web
module G = Web.Context2d
module C = Canvas2d

// The dish's colours for a theme: the agar, the glass, the slime, the oat flakes, the labels, and
// whether the slime glows (light adds up on a dark plate, not on a pale one).
type palette = {
  agarInner: string,
  agarOuter: string,
  rim: string,
  slime: string,
  core: string,
  oat: string,
  oatEdge: string,
  text: string,
  glow: bool,
}

let paletteFor = (theme: Theme.t) =>
  switch theme.name {
  | "agar" => {
      agarInner: "246, 232, 176",
      agarOuter: "226, 204, 132",
      rim: "120, 104, 52",
      slime: "58, 164, 14",
      core: "176, 236, 96",
      oat: "252, 242, 214",
      oatEdge: "176, 146, 84",
      text: "64, 72, 22",
      glow: false,
    }
  | _ => {
      agarInner: "40, 62, 28",
      agarOuter: "16, 26, 12",
      rim: "220, 255, 170",
      slime: "150, 236, 72",
      core: "240, 255, 206",
      oat: "242, 226, 176",
      oatEdge: "170, 140, 80",
      text: "206, 246, 168",
      glow: true,
    }
  }

let rgba = Theme.rgba
let tau = 2. * Math.Constants.pi

type hit = Node(int) | Tube(int, int) | Dish | Outside

// the unordered pairs of nodes, each tube once
let pairs = {
  let out = []
  for i in 0 to FdnModel.size - 2 {
    for j in i + 1 to FdnModel.size - 1 {
      out->Array.push((i, j))
    }
  }
  out
}

// A deterministic scatter of numbers 0..1, for the agar's specks and the oat flakes' edges.
let scatter = n => {
  let s = ref(20240917)
  Array.fromInitializer(~length=n, _ => {
    s := mod(s.contents * 1103515245 + 12345, 2147483647)->Math.Int.abs
    Int.toFloat(mod(s.contents, 100000)) / 100000.
  })
}
let specks = scatter(420)
let flakes = scatter(FdnModel.size * 16)

let fract = x => x - Math.floor(x)

let make = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box: box) => {
  let canvas = CanvasStyle.make(parent, box)
  canvas->addClass("dish")
  let g = canvas->getContext2d
  let model = ctx.model
  let (w, h) = (box.w, box.h)
  let (cx, cy) = (w / 2., h / 2.)
  let dishR = Math.min(w, h) / 2. - 7.

  let plain = id => ParamModel.def(model, id).plain(ParamModel.get(model, id))
  let foodId = i => "food" ++ Int.toString(i + 1)
  let isFed = i => model->ParamModel.get(foodId(i)) != 0.
  let room = () => plain("roomSize")

  // the ring's radius for a room size, and back
  let ringRadius = room => dishR * (0.32 + 0.4 * (room - 0.25) / 1.75)
  let roomForRadius = r => 0.25 + 1.75 * (r / dishR - 0.32) / 0.4

  //==============================================================================
  // the state drawn: the DSP's, or the starting network

  let startingConductance = () => FdnModel.effective(plain("memory"), 0.5)
  let conductance = (i, j) =>
    bridge.conductance->PatchBridge.at(FdnModel.cell(i, j), ~fallback=startingConductance())
  let pressure = i => bridge.pressure->PatchBridge.at(i, ~fallback=0.)
  let delayMs = i =>
    switch bridge.delayMs {
    | Some(ms) => ms[i]->Option.getOr(0.)
    | None =>
      FdnModel.delayLengths(~roomSize=room())[i]->Option.mapOr(0., n => FdnModel.lengthMs(n))
    }
  let matrix = (r, c) => bridge.matrix->PatchBridge.at(FdnModel.cell(r, c), ~fallback=0.)
  // net flux from i towards j
  let netFlux = (i, j) => {
    let (pi, pj) = (pressure(i), pressure(j))
    0.5 * (FdnModel.flux(conductance(i, j), i, j, pi, pj) - FdnModel.flux(conductance(j, i), j, i, pj, pi))
  }

  let nodeAt = i => {
    let a = FdnModel.angle(i)
    let r = ringRadius(room())
    (cx + Math.cos(a) * r, cy + Math.sin(a) * r)
  }
  let nodeRadius = i => 5.5 + 8. * Math.sqrt(Math.max(0., delayMs(i)) / 73.)

  //==============================================================================
  // interaction state, and what the last frame drew (for hit testing)

  let hover = ref(Outside)
  let dragging = ref(false)
  let tubePoints: array<array<(float, float)>> = pairs->Array.map(_ => [])
  let tubeWidths: array<float> = pairs->Array.map(_ => 0.)
  let phases = pairs->Array.map(_ => 0.)
  let lastTime = ref(None)

  //==============================================================================
  // drawing

  let widthOf = w => 0.5 + 11. * Math.pow(Math.max(0., w), ~exp=1.8)

  let bezier = ((x0, y0), (qx, qy), (x1, y1), t) => {
    let u = 1. - t
    (u * u * x0 + 2. * u * t * qx + t * t * x1, u * u * y0 + 2. * u * t * qy + t * t * y1)
  }

  let blobPath = (x, y, r, seed, time) => {
    G.beginPath(g)
    for k in 0 to 31 {
      let th = tau * Int.toFloat(k) / 32.
      let wobble = 1. + 0.075 * Math.sin(3. * th + time * 0.9 + seed) + 0.045 * Math.sin(5. * th - time * 1.3 + 2. * seed)
      let (px, py) = (x + Math.cos(th) * r * wobble, y + Math.sin(th) * r * wobble)
      k == 0 ? G.moveTo(g, px, py) : G.lineTo(g, px, py)
    }
    G.closePath(g)
  }

  let drawDish = (pal: palette) => {
    let agar = C.createRadialGradient(g, cx - dishR * 0.25, cy - dishR * 0.3, 0., cx, cy, dishR)
    agar->C.addColorStop(0., rgba(pal.agarInner, 1.))
    agar->C.addColorStop(1., rgba(pal.agarOuter, 1.))
    G.beginPath(g)
    C.arc(g, cx, cy, dishR, 0., tau)
    C.setFillGradient(g, agar)
    G.fill(g)
    // specks in the agar
    G.setFillStyle(g, rgba(pal.rim, 0.07))
    for k in 0 to Array.length(specks) / 2 - 1 {
      let a = specks->Array.getUnsafe(2 * k) * tau
      let r = Math.sqrt(specks->Array.getUnsafe(2 * k + 1)) * (dishR - 4.)
      G.fillRect(g, cx + Math.cos(a) * r, cy + Math.sin(a) * r, 1.2, 1.2)
    }
    // the glass: the wall, its inner edge, and a highlight
    G.setStrokeStyle(g, rgba(pal.rim, 0.35))
    G.setLineWidth(g, 3.)
    G.beginPath(g)
    C.arc(g, cx, cy, dishR + 2., 0., tau)
    G.stroke(g)
    G.setStrokeStyle(g, rgba(pal.rim, 0.14))
    G.setLineWidth(g, 1.)
    G.beginPath(g)
    C.arc(g, cx, cy, dishR - 5., 0., tau)
    G.stroke(g)
    G.setStrokeStyle(g, "rgba(255, 255, 255, 0.4)")
    G.setLineWidth(g, 2.)
    C.setLineCap(g, "round")
    G.beginPath(g)
    C.arc(g, cx, cy, dishR - 1., 3.55, 4.25)
    G.stroke(g)
  }

  let drawTubes = (pal: palette, time, dt, still) => {
    pairs->Array.forEachWithIndex(((i, j), k) => {
      let (wij, wji) = (conductance(i, j), conductance(j, i))
      let p0 = nodeAt(i)
      let p1 = nodeAt(j)
      let ((x0, y0), (x1, y1)) = (p0, p1)
      // the tube bows towards the centre, and drifts a little
      let (mx, my) = ((x0 + x1) / 2., (y0 + y1) / 2.)
      let (dx, dy) = (x1 - x0, y1 - y0)
      let len = Math.max(1., Math.sqrt(dx * dx + dy * dy))
      let drift = still ? 0. : Math.sin(time * 0.33 + Int.toFloat(i) * 1.7 + Int.toFloat(j) * 2.9) * 6.
      let q = (mx + (cx - mx) * 0.22 - dy / len * drift, my + (cy - my) * 0.22 + dx / len * drift)

      // the body: a strip whose width runs from the conductance out of i to the one out of j
      let steps = 16
      let points = Array.fromInitializer(~length=steps + 1, s => bezier(p0, q, p1, Int.toFloat(s) / Int.toFloat(steps)))
      let (w0, w1) = (widthOf(wij), widthOf(wji))
      tubePoints->Array.setUnsafe(k, points)
      tubeWidths->Array.setUnsafe(k, Math.max(w0, w1))
      let side = (sign: float) =>
        points->Array.mapWithIndex(((px, py), s) => {
          let (ax, ay) = points[Math.Int.max(0, s - 1)]->Option.getOr((px, py))
          let (bx, by) = points[Math.Int.min(steps, s + 1)]->Option.getOr((px, py))
          let (tx, ty) = (bx - ax, by - ay)
          let tl = Math.max(1e-6, Math.sqrt(tx * tx + ty * ty))
          let half = (w0 + (w1 - w0) * Int.toFloat(s) / Int.toFloat(steps)) / 2.
          (px - ty / tl * half * sign, py + tx / tl * half * sign)
        })
      let left = side(1.)
      let right = side(-1.)->Array.toReversed
      let strength = Math.max(wij, wji)
      let isHot = switch hover.contents {
      | Tube(a, b) => a == i && b == j
      | _ => false
      }

      G.beginPath(g)
      [...left, ...right]->Array.forEachWithIndex(((px, py), n) => n == 0 ? G.moveTo(g, px, py) : G.lineTo(g, px, py))
      G.closePath(g)
      if pal.glow {
        C.setShadowColor(g, rgba(pal.slime, 0.8))
        C.setShadowBlur(g, 4. + 14. * strength)
      }
      G.setFillStyle(g, rgba(pal.slime, isHot ? 1. : 0.12 + 0.8 * strength * strength))
      G.fill(g)
      C.setShadowBlur(g, 0.)

      // the cytoplasm down the middle
      G.setStrokeStyle(g, rgba(pal.core, isHot ? 0.9 : 0.1 + 0.7 * strength * strength))
      G.setLineWidth(g, Math.max(0.6, Math.min(w0, w1) * 0.32))
      C.setLineCap(g, "round")
      G.beginPath(g)
      points->Array.forEachWithIndex(((px, py), n) => n == 0 ? G.moveTo(g, px, py) : G.lineTo(g, px, py))
      G.stroke(g)

      // grains streaming with the flux, shuttling when there is none
      let shuttle = 0.1 * Math.sin(time * 0.7 + Int.toFloat(k) * 0.61)
      let speed = Math.max(-1.4, Math.min(1.4, netFlux(i, j) * 0.45)) + shuttle
      if !still {
        phases->Array.setUnsafe(k, fract(phases->Array.getUnsafe(k) + dt * speed * 140. / len))
      }
      let grains = 1 + Float.toInt(strength * 4.)
      G.setFillStyle(g, rgba(pal.core, 0.35 + 0.6 * strength))
      for n in 0 to grains - 1 {
        let t = fract(phases->Array.getUnsafe(k) + Int.toFloat(n) / Int.toFloat(grains))
        let (px, py) = bezier(p0, q, p1, t)
        G.beginPath(g)
        C.arc(g, px, py, 0.9 + 1.3 * strength, 0., tau)
        G.fill(g)
      }
    })
  }

  let drawOat = (pal: palette, i, x, y, r) => {
    let a0 = flakes->Array.getUnsafe(i * 16) * tau
    let (rx, ry) = (r * 1.85 + 4., r * 1.3 + 3.)
    G.beginPath(g)
    for k in 0 to 13 {
      let th = tau * Int.toFloat(k) / 14.
      let jag = 0.88 + 0.2 * flakes->Array.getUnsafe(i * 16 + 1 + k)
      let (ex, ey) = (Math.cos(th) * rx * jag, Math.sin(th) * ry * jag)
      let (px, py) = (x + ex * Math.cos(a0) - ey * Math.sin(a0), y + ex * Math.sin(a0) + ey * Math.cos(a0))
      k == 0 ? G.moveTo(g, px, py) : G.lineTo(g, px, py)
    }
    G.closePath(g)
    G.setFillStyle(g, rgba(pal.oat, 0.95))
    G.fill(g)
    G.setStrokeStyle(g, rgba(pal.oatEdge, 0.9))
    G.setLineWidth(g, 1.)
    G.stroke(g)
    // its ridge
    G.setStrokeStyle(g, rgba(pal.oatEdge, 0.45))
    G.beginPath(g)
    G.moveTo(g, x - Math.cos(a0) * rx * 0.6, y - Math.sin(a0) * rx * 0.6)
    G.lineTo(g, x + Math.cos(a0) * rx * 0.6, y + Math.sin(a0) * rx * 0.6)
    G.stroke(g)
  }

  let drawNodes = (pal: palette, time, still) => {
    let theme = Theme.current.contents
    C.setFont(g, `11px ${theme.font}`)
    C.setTextAlign(g, "center")
    C.setTextBaseline(g, "middle")
    for i in 0 to FdnModel.size - 1 {
      let (x, y) = nodeAt(i)
      let r = nodeRadius(i)
      let p = pressure(i)
      if isFed(i) {
        drawOat(pal, i, x, y, r)
      }
      let swollen = r * (1. + 0.3 * p)
      blobPath(x, y, swollen, Int.toFloat(i) * 1.3, still ? 0. : time)
      let body = C.createRadialGradient(g, x - swollen * 0.3, y - swollen * 0.3, 0., x, y, swollen * 1.1)
      body->C.addColorStop(0., rgba(pal.core, 1.))
      body->C.addColorStop(0.55, rgba(pal.slime, 1.))
      body->C.addColorStop(1., rgba(pal.slime, 0.85))
      if pal.glow {
        C.setShadowColor(g, rgba(pal.slime, 0.9))
        C.setShadowBlur(g, 6. + 26. * p)
      }
      C.setFillGradient(g, body)
      G.fill(g)
      C.setShadowBlur(g, 0.)
      switch hover.contents {
      | Node(n) if n == i =>
        G.setStrokeStyle(g, rgba(pal.rim, 0.9))
        G.setLineWidth(g, 1.5)
        G.beginPath(g)
        C.arc(g, x, y, swollen + 5., 0., tau)
        G.stroke(g)
      | _ => ()
      }
      // the line's length, outside the ring
      let a = FdnModel.angle(i)
      let out = r * 1.3 + 14. + 16. * Math.abs(Math.cos(a))
      G.setFillStyle(g, rgba(pal.text, 0.85))
      let lx = Math.max(24., Math.min(w - 24., x + Math.cos(a) * out))
      C.fillText(g, Float.toFixed(delayMs(i), ~digits=1) ++ " ms", lx, y + Math.sin(a) * out)
    }
  }

  let draw = now => {
    let pal = paletteFor(Theme.current.contents)
    let still = C.reducedMotion()
    let time = now / 1000.
    let dt = switch lastTime.contents {
    | Some(t) => Math.min(0.1, (now - t) / 1000.)
    | None => 0.
    }
    lastTime := Some(now)

    C.setTransform(g, 2., 0., 0., 2., 0., 0.)
    G.clearRect(g, 0., 0., w, h)
    drawDish(pal)

    // the room: a faint ring the nodes sit on, brighter while it's being stretched
    G.setStrokeStyle(g, rgba(pal.rim, dragging.contents ? 0.45 : 0.1))
    G.setLineWidth(g, 1.)
    C.setLineDash(g, [3., 4.])
    G.beginPath(g)
    C.arc(g, cx, cy, ringRadius(room()), 0., tau)
    G.stroke(g)
    C.setLineDash(g, [])

    if pal.glow {
      C.setCompositeOperation(g, "lighter")
    }
    drawTubes(pal, time, dt, still)
    C.setCompositeOperation(g, "source-over")
    drawNodes(pal, time, still)

    if bridge.received == 0. {
      C.setFont(g, `12px ${Theme.current.contents.font}`)
      G.setFillStyle(g, rgba(pal.text, 0.7))
      C.fillText(g, "Waiting for the DSP: the network shows its starting state", cx, cy + dishR * 0.86)
    }
  }

  //==============================================================================
  // the loop: every frame while the dish is on screen

  let running = ref(false)
  let rec frame = now => {
    draw(now)
    if canvas->offsetParent->Option.isSome {
      requestAnimationFrame(frame)
    } else {
      running := false
      lastTime := None
    }
  }
  let wake = () =>
    if !running.contents {
      running := true
      requestAnimationFrame(frame)
    }

  //==============================================================================
  // pointing

  let local = ev => {
    let (fx, fy) = pointerFraction(canvas, ev)
    (fx * w, fy * h)
  }
  let distance = ((ax: float, ay: float), (bx: float, by: float)) => Math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))

  let hitAt = p => {
    let node = Array.fromInitializer(~length=FdnModel.size, i => i)->Array.find(i => distance(p, nodeAt(i)) < nodeRadius(i) + 6.)
    switch node {
    | Some(i) => Node(i)
    | None if distance(p, (cx, cy)) > dishR => Outside
    | None =>
      let best = ref((Dish, 1e9))
      pairs->Array.forEachWithIndex(((i, j), k) => {
        let reach = tubeWidths->Array.getUnsafe(k) / 2. + 3.
        tubePoints
        ->Array.getUnsafe(k)
        ->Array.forEach(q => {
          let d = distance(p, q)
          if d < reach && d < Pair.second(best.contents) {
            best := (Tube(i, j), d)
          }
        })
      })
      Pair.first(best.contents)
    }
  }

  let fmt = (x, digits) => Float.toFixed(x, ~digits)
  let describe = hit =>
    switch hit {
    | Node(i) =>
      let samples = Math.round(delayMs(i) * FdnModel.referenceRate / 1000.)
      let pressureText = bridge.pressure == None ? "" : `, at ${fmt(FdnModel.pressureDb(pressure(i)), 0)} dB`
      let foodText = isFed(i) ? "fed with the input: click to starve it" : "not fed: click to feed it the input"
      `Line ${Int.toString(i + 1)}: ${fmt(delayMs(i), 1)} ms (${fmt(samples, 0)} samples at 48 kHz)${pressureText}; ${foodText}. Drag to stretch the room.`
    | Tube(i, j) =>
      let (a, b) = (Int.toString(i + 1), Int.toString(j + 1))
      let matrixText =
        bridge.matrix == None
          ? ""
          : `; in the matrix ${fmt(matrix(j, i), 3)} and ${fmt(matrix(i, j), 3)}`
      `Tube ${a}–${b}: conductance ${fmt(conductance(i, j), 2)} out of ${a}, ${fmt(conductance(j, i), 2)} out of ${b}${matrixText}`
    | Dish =>
      `Room size ${fmt(room(), 2)}x: drag outwards to grow the room, inwards to shrink it, or scroll`
    | Outside => ""
    }

  let showHover = () =>
    switch hover.contents {
    | Outside => ctx.status->Status.clear
    | hit => ctx.status->Status.show(describe(hit))
    }

  let setHover = hit => {
    hover := hit
    canvas->setStyle(
      "cursor",
      switch hit {
      | Node(_) => "pointer"
      | Dish | Tube(_) => dragging.contents ? "grabbing" : "grab"
      | Outside => "default"
      },
    )
    showHover()
    wake()
  }

  canvas->onPointer(#pointermove, ev =>
    if !dragging.contents {
      setHover(hitAt(local(ev)))
    }
  )
  canvas->onMouse(#mouseleave, _ =>
    if !dragging.contents {
      setHover(Outside)
    }
  )
  canvas->suppressContextMenu

  canvas->onPointer(#pointerdown, ev =>
    if ev->button == 0 {
      let start = local(ev)
      let hit = hitAt(start)
      if hit != Outside {
        ev->preventDefault
        let startDistance = Math.max(12., distance(start, (cx, cy)))
        let startRadius = ringRadius(room())
        let moved = ref(false)
        Controls.capturePointer(
          canvas,
          ev,
          ~onMove=mv => {
            let p = local(mv)
            if !moved.contents && distance(p, start) > 3. {
              moved := true
              dragging := true
              model->ParamModel.beginGesture("roomSize")
            }
            if moved.contents {
              let r = startRadius * distance(p, (cx, cy)) / startDistance
              model->ParamModel.set("roomSize", roomForRadius(r))
              ctx.status->Status.show(describe(Dish))
              wake()
            }
          },
          ~onUp=() =>
            if moved.contents {
              dragging := false
              model->ParamModel.endGesture("roomSize")
              setHover(hit)
            } else {
              switch hit {
              | Node(i) =>
                model->ParamModel.gestureSet(foodId(i), isFed(i) ? 0. : 1.)
                setHover(hit)
              | _ => ()
              }
            },
        )
      }
    }
  )
  canvas->onWheel(ev => Controls.wheelParam(model, "roomSize", ev))

  bridge->PatchBridge.listen(() => {
    if hover.contents != Outside && !dragging.contents {
      showHover()
    }
    wake()
  })
  model->ParamModel.listenAny(_ => wake())
  CanvasStyle.onThemeChange(wake)
  wake()
  canvas
}
