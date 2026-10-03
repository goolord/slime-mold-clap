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

// The glow layer's blur (CSS px), the least of the glows it stands in for; the rest is made up by
// drawing a glow wider (tubes) or as a halo already soft (nodes).
let glowBlur = 4.

// How many straight pieces a tube's outline is drawn with.
let steps = 16

let make = (ctx: Ctx.t, bridge: PatchBridge.t, parent, box: box) => {
  let model = ctx.model
  let (w, h) = (box.w, box.h)
  let (cx, cy) = (w / 2., h / 2.)
  let dishR = Math.min(w, h) / 2. - 7.

  // The layers, bottom to top: the dish, the room and the tubes; the glow, at half resolution,
  // blurred and blended on by the compositor (one blur a frame, where a canvas shadow per shape
  // was dozens); the oat flakes, the nodes and their labels, which take the pointer.
  let base = CanvasStyle.make(parent, box)
  let glowCanvas = el("canvas", ~cls="draw", ~parent)->placeBox(box)
  glowCanvas->setCanvasWidth(w)
  glowCanvas->setCanvasHeight(h)
  glowCanvas->setStyle("filter", `blur(${Float.toString(glowBlur)}px)`)
  glowCanvas->setStyle("mix-blend-mode", "screen")
  glowCanvas->setStyle("pointer-events", "none")
  let canvas = CanvasStyle.make(parent, box)
  canvas->addClass("dish")
  let g = base->getContext2d
  let glow = glowCanvas->getContext2d
  let top = canvas->getContext2d

  // the dish itself, drawn once for each theme it is shown in
  let dishLayer = el("canvas")
  dishLayer->setCanvasWidth(w * 2.)
  dishLayer->setCanvasHeight(h * 2.)
  let dishTheme = ref("")
  let glowShown = ref(true)

  let plain = ParamModel.plain(model, _)
  let foodId = i => "food" ++ Int.toString(i + 1)
  let isFed = i => model->ParamModel.get(foodId(i)) != 0.
  let room = () => plain("roomSize")

  // the ring's radius for a room size, and back
  let {min: roomMin, max: roomMax} = ParamModel.def(model, "roomSize")
  let ringRadius = room => dishR * (0.32 + 0.4 * (room - roomMin) / (roomMax - roomMin))
  let roomForRadius = r => roomMin + (roomMax - roomMin) * (r / dishR - 0.32) / 0.4

  //==============================================================================
  // the state drawn: the DSP's, or the starting network

  let startingConductance = () => FdnModel.effective(plain("memory"), 0.5)
  let conductance = (i, j) =>
    switch bridge.conductance->Option.flatMap(ws => ws[FdnModel.cell(i, j)]) {
    | Some(w) => w
    | None => startingConductance()
    }
  let pressure = i => bridge.pressure->PatchBridge.at(i, ~fallback=0.)
  let matrix = (r, c) => bridge.matrix->PatchBridge.at(FdnModel.cell(r, c), ~fallback=0.)
  // net flux from i towards j
  let netFlux = (i, j) => {
    let (pi, pj) = (pressure(i), pressure(j))
    0.5 * (FdnModel.flux(conductance(i, j), i, j, pi, pj) - FdnModel.flux(conductance(j, i), j, i, pj, pi))
  }

  //==============================================================================
  // what the last frame drew, for the next and for hit testing

  let n = FdnModel.size
  // each node's place, radius and line length (ms)
  let nodeX = Array.make(~length=n, 0.)
  let nodeY = Array.make(~length=n, 0.)
  let nodeR = Array.make(~length=n, 0.)
  let delays = Array.make(~length=n, 0.)
  // each tube's curve (x0, y0, qx, qy, x1, y1), its widest, and where its grains are
  let curves = Array.make(~length=Array.length(pairs) * 6, 0.)
  let tubeWidths = Array.make(~length=Array.length(pairs), 0.)
  let phases = Array.make(~length=Array.length(pairs), 0.)

  // Where the nodes are, from the room size and the line lengths (the DSP's, or the starting ones).
  let layout = () => {
    let roomSize = room()
    let ring = ringRadius(roomSize)
    let starting = bridge.delayMs == None ? FdnModel.delayLengths(~roomSize) : []
    for i in 0 to n - 1 {
      let ms = switch bridge.delayMs {
      | Some(ms) => ms[i]->Option.getOr(0.)
      | None => starting[i]->Option.mapOr(0., n => FdnModel.lengthMs(n))
      }
      let a = FdnModel.angle(i)
      delays->Array.setUnsafe(i, ms)
      nodeR->Array.setUnsafe(i, 5.5 + 8. * Math.sqrt(Math.max(0., ms) / 73.))
      nodeX->Array.setUnsafe(i, cx + Math.cos(a) * ring)
      nodeY->Array.setUnsafe(i, cy + Math.sin(a) * ring)
    }
  }
  layout()

  let delayMs = i => delays->Array.getUnsafe(i)
  let nodeAt = i => (nodeX->Array.getUnsafe(i), nodeY->Array.getUnsafe(i))

  // A point t (0..1) along tube k's curve.
  let curveX = (k, t) => {
    let u = 1. - t
    let o = k * 6
    u * u * curves->Array.getUnsafe(o) + 2. * u * t * curves->Array.getUnsafe(o + 2) + t * t * curves->Array.getUnsafe(o + 4)
  }
  let curveY = (k, t) => {
    let u = 1. - t
    let o = k * 6
    u * u * curves->Array.getUnsafe(o + 1) + 2. * u * t * curves->Array.getUnsafe(o + 3) + t * t * curves->Array.getUnsafe(o + 5)
  }

  //==============================================================================
  // interaction state

  let hover = ref(Outside)
  let dragging = ref(false)
  let lastTime = ref(None)

  //==============================================================================
  // drawing

  let widthOf = w => 0.5 + 11. * Math.pow(Math.max(0., w), ~exp=1.8)

  let blobPath = (x, y, r, seed, time) => {
    G.beginPath(top)
    for k in 0 to 31 {
      let th = tau * Int.toFloat(k) / 32.
      let wobble = 1. + 0.075 * Math.sin(3. * th + time * 0.9 + seed) + 0.045 * Math.sin(5. * th - time * 1.3 + 2. * seed)
      let (px, py) = (x + Math.cos(th) * r * wobble, y + Math.sin(th) * r * wobble)
      k == 0 ? G.moveTo(top, px, py) : G.lineTo(top, px, py)
    }
    G.closePath(top)
  }

  let renderDish = (pal: palette) => {
    let g = dishLayer->getContext2d
    C.setTransform(g, 2., 0., 0., 2., 0., 0.)
    G.clearRect(g, 0., 0., w, h)
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

  // Tube k's outline into c's path: out along one side and back along the other, its width
  // running from w0 at its start to w1 at its end.
  let outline = (c, k, w0: float, w1: float) => {
    let o = k * 6
    let (x0, y0) = (curves->Array.getUnsafe(o), curves->Array.getUnsafe(o + 1))
    let (qx, qy) = (curves->Array.getUnsafe(o + 2), curves->Array.getUnsafe(o + 3))
    let (x1, y1) = (curves->Array.getUnsafe(o + 4), curves->Array.getUnsafe(o + 5))
    G.beginPath(c)
    for m in 0 to 2 * steps + 1 {
      let s = m <= steps ? m : 2 * steps + 1 - m
      let side = m <= steps ? 0.5 : -0.5
      let t = Int.toFloat(s) / Int.toFloat(steps)
      let u = 1. - t
      // the point, and the curve's direction there
      let px = u * u * x0 + 2. * u * t * qx + t * t * x1
      let py = u * u * y0 + 2. * u * t * qy + t * t * y1
      let tx = u * (qx - x0) + t * (x1 - qx)
      let ty = u * (qy - y0) + t * (y1 - qy)
      let half = (w0 + (w1 - w0) * t) * side / Math.max(1e-6, Math.sqrt(tx * tx + ty * ty))
      m == 0 ? G.moveTo(c, px - ty * half, py + tx * half) : G.lineTo(c, px - ty * half, py + tx * half)
    }
    G.closePath(c)
  }

  let drawTubes = (pal: palette, time, dt, still) => {
    pairs->Array.forEachWithIndex(((i, j), k) => {
      let (wij, wji) = (conductance(i, j), conductance(j, i))
      let (x0, y0) = (nodeX->Array.getUnsafe(i), nodeY->Array.getUnsafe(i))
      let (x1, y1) = (nodeX->Array.getUnsafe(j), nodeY->Array.getUnsafe(j))
      // the tube bows towards the centre, and drifts a little
      let (mx, my) = ((x0 + x1) / 2., (y0 + y1) / 2.)
      let (dx, dy) = (x1 - x0, y1 - y0)
      let len = Math.max(1., Math.sqrt(dx * dx + dy * dy))
      let drift = still ? 0. : Math.sin(time * 0.33 + Int.toFloat(i) * 1.7 + Int.toFloat(j) * 2.9) * 6.
      let qx = mx + (cx - mx) * 0.22 - dy / len * drift
      let qy = my + (cy - my) * 0.22 + dx / len * drift
      let o = k * 6
      curves->Array.setUnsafe(o, x0)
      curves->Array.setUnsafe(o + 1, y0)
      curves->Array.setUnsafe(o + 2, qx)
      curves->Array.setUnsafe(o + 3, qy)
      curves->Array.setUnsafe(o + 4, x1)
      curves->Array.setUnsafe(o + 5, y1)

      // the body: a strip whose width runs from the conductance out of i to the one out of j
      let (w0, w1) = (widthOf(wij), widthOf(wji))
      tubeWidths->Array.setUnsafe(k, Math.max(w0, w1))
      let strength = Math.max(wij, wji)
      let isHot = switch hover.contents {
      | Tube(a, b) => a == i && b == j
      | _ => false
      }
      let opacity = isHot ? 1. : 0.12 + 0.8 * strength * strength
      outline(g, k, w0, w1)
      G.setFillStyle(g, rgba(pal.slime, opacity))
      G.fill(g)
      // its glow, wider as the tube is stronger (a shadow blurred by 4 + 14 strength)
      if pal.glow {
        let spread = 2. * Math.max(0., 2. + 7. * strength - glowBlur)
        outline(glow, k, w0 + spread, w1 + spread)
        G.setFillStyle(glow, rgba(pal.slime, 0.8 * opacity))
        G.fill(glow)
      }

      // the cytoplasm down the middle
      G.setStrokeStyle(g, rgba(pal.core, isHot ? 0.9 : 0.1 + 0.7 * strength * strength))
      G.setLineWidth(g, Math.max(0.6, Math.min(w0, w1) * 0.32))
      C.setLineCap(g, "round")
      G.beginPath(g)
      G.moveTo(g, x0, y0)
      C.quadraticCurveTo(g, qx, qy, x1, y1)
      G.stroke(g)

      // grains streaming with the flux, shuttling when there is none
      let shuttle = 0.1 * Math.sin(time * 0.7 + Int.toFloat(k) * 0.61)
      let speed = Math.max(-1.4, Math.min(1.4, netFlux(i, j) * 0.45)) + shuttle
      if !still {
        phases->Array.setUnsafe(k, fract(phases->Array.getUnsafe(k) + dt * speed * 140. / len))
      }
      let grains = 1 + Float.toInt(strength * 4.)
      let radius = 0.9 + 1.3 * strength
      G.setFillStyle(g, rgba(pal.core, 0.35 + 0.6 * strength))
      G.beginPath(g)
      for m in 0 to grains - 1 {
        let t = fract(phases->Array.getUnsafe(k) + Int.toFloat(m) / Int.toFloat(grains))
        let (px, py) = (curveX(k, t), curveY(k, t))
        G.moveTo(g, px + radius, py)
        C.arc(g, px, py, radius, 0., tau)
      }
      G.fill(g)
    })
  }

  let drawOat = (pal: palette, i, x, y, r) => {
    let a0 = flakes->Array.getUnsafe(i * 16) * tau
    let (rx, ry) = (r * 1.85 + 4., r * 1.3 + 3.)
    G.beginPath(top)
    for k in 0 to 13 {
      let th = tau * Int.toFloat(k) / 14.
      let jag = 0.88 + 0.2 * flakes->Array.getUnsafe(i * 16 + 1 + k)
      let (ex, ey) = (Math.cos(th) * rx * jag, Math.sin(th) * ry * jag)
      let (px, py) = (x + ex * Math.cos(a0) - ey * Math.sin(a0), y + ex * Math.sin(a0) + ey * Math.cos(a0))
      k == 0 ? G.moveTo(top, px, py) : G.lineTo(top, px, py)
    }
    G.closePath(top)
    G.setFillStyle(top, rgba(pal.oat, 0.95))
    G.fill(top)
    G.setStrokeStyle(top, rgba(pal.oatEdge, 0.9))
    G.setLineWidth(top, 1.)
    G.stroke(top)
    // its ridge
    G.setStrokeStyle(top, rgba(pal.oatEdge, 0.45))
    G.beginPath(top)
    G.moveTo(top, x - Math.cos(a0) * rx * 0.6, y - Math.sin(a0) * rx * 0.6)
    G.lineTo(top, x + Math.cos(a0) * rx * 0.6, y + Math.sin(a0) * rx * 0.6)
    G.stroke(top)
  }

  // A node's glow: a soft halo, as a shadow blurred by 6 + 26 pressure would be (the layer's own
  // blur taken off), a little stronger than half at the blob's edge.
  let drawHalo = (pal: palette, x, y, r, p) => {
    let sigma = 3. + 13. * p
    let s = Math.sqrt(Math.max(1., sigma * sigma - glowBlur * glowBlur))
    let outer = r + 2.5 * s
    let at = d => Math.max(0., Math.min(1., d / outer))
    let halo = C.createRadialGradient(glow, x, y, 0., x, y, outer)
    halo->C.addColorStop(0., rgba(pal.slime, 0.9))
    halo->C.addColorStop(at(r - s), rgba(pal.slime, 0.75))
    halo->C.addColorStop(at(r), rgba(pal.slime, 0.45))
    halo->C.addColorStop(at(r + s), rgba(pal.slime, 0.14))
    halo->C.addColorStop(1., rgba(pal.slime, 0.))
    C.setFillGradient(glow, halo)
    G.beginPath(glow)
    C.arc(glow, x, y, outer, 0., tau)
    G.fill(glow)
  }

  let drawNodes = (pal: palette, time, still) => {
    let theme = Theme.current.contents
    C.setFont(top, `11px ${theme.font}`)
    C.setTextAlign(top, "center")
    C.setTextBaseline(top, "middle")
    for i in 0 to n - 1 {
      let (x, y) = nodeAt(i)
      let r = nodeR->Array.getUnsafe(i)
      let p = pressure(i)
      if isFed(i) {
        drawOat(pal, i, x, y, r)
      }
      let swollen = r * (1. + 0.3 * p)
      if pal.glow {
        drawHalo(pal, x, y, swollen, p)
      }
      blobPath(x, y, swollen, Int.toFloat(i) * 1.3, still ? 0. : time)
      let body = C.createRadialGradient(top, x - swollen * 0.3, y - swollen * 0.3, 0., x, y, swollen * 1.1)
      body->C.addColorStop(0., rgba(pal.core, 1.))
      body->C.addColorStop(0.55, rgba(pal.slime, 1.))
      body->C.addColorStop(1., rgba(pal.slime, 0.85))
      C.setFillGradient(top, body)
      G.fill(top)
      switch hover.contents {
      | Node(m) if m == i =>
        G.setStrokeStyle(top, rgba(pal.rim, 0.9))
        G.setLineWidth(top, 1.5)
        G.beginPath(top)
        C.arc(top, x, y, swollen + 5., 0., tau)
        G.stroke(top)
      | _ => ()
      }
      // the line's length, outside the ring
      let a = FdnModel.angle(i)
      let out = r * 1.3 + 14. + 16. * Math.abs(Math.cos(a))
      G.setFillStyle(top, rgba(pal.text, 0.85))
      let lx = Math.max(24., Math.min(w - 24., x + Math.cos(a) * out))
      C.fillText(top, Param.msText(~digits=1, delayMs(i)), lx, y + Math.sin(a) * out)
    }
  }

  let draw = now => {
    let theme = Theme.current.contents
    let pal = paletteFor(theme)
    let still = C.reducedMotion()
    let time = now / 1000.
    let dt = switch lastTime.contents {
    | Some(t) => Math.min(0.1, (now - t) / 1000.)
    | None => 0.
    }
    lastTime := Some(now)
    layout()

    // the dish, and the room: a faint ring the nodes sit on, brighter while it's being stretched
    if dishTheme.contents != theme.name {
      dishTheme := theme.name
      renderDish(pal)
    }
    C.setTransform(g, 1., 0., 0., 1., 0., 0.)
    G.clearRect(g, 0., 0., w * 2., h * 2.)
    C.drawImage(g, dishLayer, 0., 0.)
    C.setTransform(g, 2., 0., 0., 2., 0., 0.)
    G.setStrokeStyle(g, rgba(pal.rim, dragging.contents ? 0.45 : 0.1))
    G.setLineWidth(g, 1.)
    C.setLineDash(g, [3., 4.])
    G.beginPath(g)
    C.arc(g, cx, cy, ringRadius(room()), 0., tau)
    G.stroke(g)
    C.setLineDash(g, [])

    // light adds up on a dark plate, not on a pale one
    if glowShown.contents != pal.glow {
      glowShown := pal.glow
      glowCanvas->setStyle("display", pal.glow ? "" : "none")
    }
    if pal.glow {
      G.clearRect(glow, 0., 0., w, h)
      C.setCompositeOperation(g, "lighter")
      C.setCompositeOperation(glow, "lighter")
    }
    drawTubes(pal, time, dt, still)
    C.setCompositeOperation(g, "source-over")
    C.setCompositeOperation(glow, "source-over")

    C.setTransform(top, 2., 0., 0., 2., 0., 0.)
    G.clearRect(top, 0., 0., w, h)
    drawNodes(pal, time, still)

    if bridge.received == 0. {
      C.setFont(top, `12px ${theme.font}`)
      G.setFillStyle(top, rgba(pal.text, 0.7))
      C.fillText(top, "Waiting for the DSP: the network shows its starting state", cx, cy + dishR * 0.86)
    }
  }

  //==============================================================================
  // the loop: every frame while the dish is on screen (and moves: held still, it draws only when
  // something changes)

  let running = ref(false)
  let rec frame = now => {
    draw(now)
    if canvas->offsetParent->Option.isSome && !C.reducedMotion() {
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
    let node = Array.fromInitializer(~length=n, i => i)->Array.find(i => distance(p, nodeAt(i)) < nodeR->Array.getUnsafe(i) + 6.)
    switch node {
    | Some(i) => Node(i)
    | None if distance(p, (cx, cy)) > dishR => Outside
    | None =>
      let best = ref((Dish, 1e9))
      pairs->Array.forEachWithIndex(((i, j), k) => {
        let reach = tubeWidths->Array.getUnsafe(k) / 2. + 3.
        for s in 0 to steps {
          let t = Int.toFloat(s) / Int.toFloat(steps)
          let d = distance(p, (curveX(k, t), curveY(k, t)))
          if d < reach && d < Pair.second(best.contents) {
            best := (Tube(i, j), d)
          }
        }
      })
      Pair.first(best.contents)
    }
  }

  let fmt = Param.fixed
  let describe = hit =>
    switch hit {
    | Node(i) =>
      let samples = Math.round(delayMs(i) * FdnModel.referenceRate / 1000.)
      let pressureText = bridge.pressure == None ? "" : `, at ${Param.dbText(~digits=0, FdnModel.pressureDb(pressure(i)))}`
      let foodText = isFed(i) ? "fed with the input: click to starve it" : "not fed: click to feed it the input"
      `Line ${Int.toString(i + 1)}: ${Param.msText(~digits=1, delayMs(i))} (${fmt(samples, 0)} samples at 48 kHz)${pressureText}; ${foodText}. Drag to stretch the room.`
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
