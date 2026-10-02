// Small inline icons for list values (waveforms, voice modes, effects...), drawn as
// strokes in the current text colour.
//
// An icon is drawn on a grid 16 units tall. A list parameter shows icons when the plugin registers
// how to find the icon of each of its values (register, in App.res); a value without one simply
// has none.

open! Web

type mark =
  // a stroked path
  | Line(string)
  // a dashed stroked path
  | Dash(string)
  // a filled path
  | Fill(string)
  // a filled dot
  | Dot(float, float, float)
  // a small label (a digit)
  | Text(float, float, string)

// (mirrored: drawn right to left)
type icon = {width: float, marks: array<mark>, mirrored?: bool}

// The icon as an <svg>, 1em tall by default (CSS sets the size).
let render = (icon, ~cls="ic") => {
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str(cls))
  s->setAttribute("viewBox", Str(`0 0 ${Float.toString(icon.width)} 16`))
  s->setAttribute("width", Num(icon.width))
  s->setAttribute("height", Num(16.))
  let marks = s->svgEl(
    "g",
    icon.mirrored == Some(true)
      ? [("transform", Str(`matrix(-1 0 0 1 ${Float.toString(icon.width)} 0)`))]
      : [],
  )
  icon.marks->Array.forEach(mark =>
    switch mark {
    | Line(d) => marks->svgEl("path", [("d", Str(d))])->ignore
    | Dash(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("dash"))])->ignore
    | Fill(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("f"))])->ignore
    | Dot(x, y, r) =>
      marks->svgEl("circle", [("cx", Num(x)), ("cy", Num(y)), ("r", Num(r)), ("class", Str("f"))])->ignore
    | Text(x, y, text) =>
      let t = marks->svgEl("text", [("x", Num(x)), ("y", Num(y))])
      t->setTextContent(text)
    }
  )
  s
}

let wide = marks => {width: 22., marks}

//==============================================================================
// waveforms and LFO shapes: one cycle around the middle line

let sine = wide([Line("M1 8 C4.3 1.3 7.7 1.3 11 8 S17.7 14.7 21 8")])
let saw = wide([Line("M1 13 L11 3 V13 L21 3")])
let pulse = wide([Line("M1 13 V3 H11 V13 H21 V3")])
let triangle = wide([Line("M1 8 L6 3 L16 13 L21 8")])
let drawn = [Line("M1 9 C3 1.5 5.5 3 7 8 S10 14.5 12 9.5 S15.5 2 18 6 L21 5")]
let user = wide(drawn)
let userPwm = wide([...drawn, Dash("M14.5 1.5 V14.5")])
let smoothRandom = wide([Line("M1 10 C4 1.5 6 3 8 9 S12 13 14 6 S19 4 21 10")])
let steppingRandom = wide([Line("M1 10 H5 V4 H9 V12 H13 V6 H17 V11 H21")])
let flat = wide([Line("M1 8 H21")])
let fmWave = wide([Line("M1 8 C2 3 3 3 4 8 S5.5 13 6.5 8 S9 3 10.5 8 S14 13 16 8 S19.5 3 21 8")])

let waveformByName = name =>
  switch name {
  | "sine" => Some(sine)
  | "saw" => Some(saw)
  | "pulse" | "square" => Some(pulse)
  | "triangle" => Some(triangle)
  | "user" => Some(user)
  | "user pwm" => Some(userPwm)
  | "smooth random" => Some(smoothRandom)
  | "stepping random" => Some(steppingRandom)
  | _ => None
  }

//==============================================================================
// voice modes: notes

let head = (x, y) => Fill(
  `M${Float.toString(x - 2.6)} ${Float.toString(y)} a2.6 1.9 -20 1 0 5.2 0 a2.6 1.9 -20 1 0 -5.2 0`,
)
let stem = (x, y1, y2) => Line(`M${Float.toString(x)} ${Float.toString(y1)} V${Float.toString(y2)}`)

let voiceModes = [
  // mono
  wide([head(10., 12.), stem(12.4, 11.5, 2.)]),
  // poly
  wide([head(10., 13.), head(10., 9.), head(10., 5.), stem(12.4, 12.5, 1.)]),
  // mono legato: two notes under a slur
  wide([head(5., 12.), stem(7.4, 11.5, 4.), head(15., 9.), stem(17.4, 8.5, 1.), Line("M4 15 Q11 18.5 16 12.5")]),
]

//==============================================================================
// effects, by a key, for tabs and menus (FxStrip)

let phaser = notches => {
  let step = 20. / Int.toFloat(notches)
  let half = Math.min(2.2, step / 2.6)
  let f = x => Float.toFixed(x, ~digits=2)
  let d =
    Array.fromInitializer(~length=notches, i => {
      let c = 1. + (Int.toFloat(i) + 0.5) * step
      `L${f(c - half)} 5 L${f(c)} 13 L${f(c + half)} 5`
    })->Array.join(" ")
  wide([Line(`M1 5 ${d} L21 5`)])
}

let effect = key =>
  switch key {
  | "distortion" => Some(wide([Line("M1 8 C2 5 3 3 5 3 H7.5 C9 3 10 5 11 8 S13 13 14.5 13 H17 C19 13 20 11 21 8")]))
  | "chorus" =>
    Some(wide([Line("M1 8 C4.3 1.3 7.7 1.3 11 8 S17.7 14.7 21 8"), Dash("M3 8 C6.3 3.3 9.7 3.3 13 8 S19 12 21 10")]))
  | "flanger" => Some(wide([Line("M1 5 L2.5 13 L4 5 L6 13 L8.5 5 L11.5 13 L15.5 5 L21 5")]))
  | "phaser" => Some(phaser(4))
  | "bode" => Some(wide([Line("M2 14 V5 M5.5 14 V8 M9 14 V10"), Line("M12 7 H20 M17.5 4.5 L20 7 L17.5 9.5")]))
  | "delay" => Some(wide([Line("M1 13.5 H21 M3 13.5 V3 M8.5 13.5 V6.5 M14 13.5 V9 M19.5 13.5 V11")]))
  | "reverb" => Some(wide([Line("M1 13 H21 M3 13 V3 M6 13 V6 M8.5 13 V7.5 M11 13 V9 M13.5 13 V10 M16 13 V11 M18.5 13 V12")]))
  | "space" => Some(wide([Line("M2 14.5 V6 L11 2 L20 6 V14.5"), Line("M7 14.5 A4 4 0 0 1 15 14.5 M4.5 14.5 A6.5 6.5 0 0 1 17.5 14.5")]))
  | "ambience" => Some(wide([Line("M4 3.5 H18 V13.5 H4 Z"), Dot(8.5, 9.5, 1.3), Line("M8.5 9.5 L13 6 L16 9 M8.5 9.5 L14 11.5")]))
  | "convolve" => Some(wide([Line("M1 13 H21 M4 13 V2.5"), Line("M6 13 C7.5 13 7.5 8 9 9.5 S11.5 12 13 11 S16.5 12.5 20 12.5")]))
  | "eq" => Some(wide([Line("M1 10 H4.5 C6.5 10 7 3.5 8.5 3.5 S10.5 10 12.5 10 C15.5 10 15.5 5.5 21 5.5")]))
  | "filter" => Some(wide([Line("M1 5 H9 C13 5 14.5 9 17.5 14")]))
  | "air" => Some(wide([Line("M1 11.5 H9 C12.5 11.5 12.5 6 16 6 H21"), Line("M17.5 0.5 V4 M15.75 2.25 H19.25"), Dot(13., 2.5, 0.8), Dot(20.5, 2., 0.8)]))
  | "compressor" => Some(wide([Line("M2 14.5 L10.5 6 C13 3.5 16 3 20 2.6"), Dash("M10.5 6 L15 1.5")]))
  | "utility" => Some(wide([Line("M2 3.5 H20 M2 8 H20 M2 12.5 H20"), Fill("M12.5 1.5 h3 v4 h-3 Z"), Fill("M5 6 h3 v4 h-3 Z"), Fill("M9.5 10.5 h3 v4 h-3 Z")]))
  | _ => None
  }

//==============================================================================
// which parameters show icons

// How a parameter finds the icon of a value from its index and its lower-case name.
let registry: Map.t<string, (int, string) => option<icon>> = Map.make()

let register = (id, find) => registry->Map.set(id, find)

let byIndex = icons => (index, _) => icons[index]

// Whether any value of the parameter has an icon.
let has = id => registry->Map.has(id)

// The icon for value `index` (named `name`) of a list parameter, in its wrapper.
let forValue = (id, index, name) =>
  registry
  ->Map.get(id)
  ->Option.flatMap(find => find(index, String.toLowerCase(name)))
  ->Option.map(icon => {
    let wrap = el("span", ~cls="icw")
    wrap->appendChild(render(icon))
    wrap
  })
