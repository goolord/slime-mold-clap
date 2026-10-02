// The preset browser's demo: a page of parameters, the shell's Browse button (ctrl+F), and a
// "Sample bank" button that loads a made-up bank (it becomes the list the header's arrows step
// through, and a source in the browser). Drop preset files on the window with the browser open to
// browse them; in the UI preview the stand-in bank library keeps them, and a preset folder added in
// the browser "holds" the files in presets/.

open Param

let specs = [
  number("gain", "Gain", ~min=-60., ~max=12., ~init=0., ~unit="dB"),
  logarithmic("cutoff", "Cutoff", ~min=20., ~max=20000., ~init=2000., ~unit="Hz"),
  percent("drive", "Drive", ~init=0.2),
  percent("mix", "Mix", ~init=1.),
  choice("mode", "Mode", ["clean", "warm", "hot"]),
  toggle("bypass", "Bypass"),
]

// the plugin's formats (registering them is Formats.res's side effect)
let formats = Formats.all

let sample = (name, ~category, ~tags, ~author="demo", ~description="", values) =>
  Preset.make(~name, ~category, ~tags, ~author, ~description, Dict.fromArray(values))

let sampleBank = [
  sample("Soft Pad", ~category="pad", ~tags=["warm", "wide"], ~description="Low cutoff, a little drive.", [
    ("gain", -6.),
    ("cutoff", 0.35),
    ("drive", 0.1),
    ("mode", 1.),
  ]),
  sample("Glass Keys", ~category="keys", ~tags=["bright", "clean"], [("cutoff", 0.85), ("mode", 0.)]),
  sample("Fuzz Lead", ~category="lead", ~tags=["hot", "mono"], ~author="someone else", [
    ("drive", 0.9),
    ("mode", 2.),
    ("gain", -3.),
  ]),
  sample("Dark Drone", ~category="pad", ~tags=["dark", "wide"], ~description="For long notes.", [
    ("cutoff", 0.15),
    ("mix", 0.6),
  ]),
  sample("Init", ~category="", ~tags=[], []),
  sample("Bypassed", ~category="utility", ~tags=["clean"], [("bypass", 1.)]),
  sample("Warm Bass", ~category="bass", ~tags=["warm", "mono"], ~author="someone else", [
    ("cutoff", 0.3),
    ("drive", 0.4),
    ("mode", 1.),
  ]),
  sample("Per-voice Shimmer", ~category="pad", ~tags=["bright", "per-voice pan"], [
    ("cutoff", 0.7),
    ("mix", 0.8),
  ]),
]

let loadSampleBank = (ctx: Ctx.t) =>
  PresetFormat.primary()->Option.forEach(format =>
    format.write->Option.forEach(write =>
      ctx.presets
      ->PresetStore.loadBytes(~fileName="Sample bank" ++ PresetStore.extension(format), write(~bankName="Sample bank", sampleBank))
      ->ignore
    )
  )

let page = (ctx: Ctx.t, el) => {
  let p = Panel.make(el, ~title="parameters", ~x=6., ~y=6., ~w=540., ~h=Grid.panelHeight(4))
  let g = Grid.make(ctx, p.el, ~cw=Grid.fitColumns(540., 3))
  g->Grid.param("gain", 0, 0, "gain")
  g->Grid.param("cutoff", 1, 0, "cutoff")
  g->Grid.param("drive", 2, 0, "drive")
  g->Grid.param("mix", 0, 1, "mix")
  g->Grid.choice("mode", 1, 1, "mode")
  g->Grid.toggle("bypass", 2, 1, "bypass")
  g->Grid.note(
    "Browse (ctrl+F) to search the presets; Sample bank loads a made-up one. Drop preset files on the browser to add them.",
    0,
    2,
    ~span=3,
    ~rows=2,
  )->ignore
}

let default = pc =>
  Shell.mount(
    pc,
    ~specs,
    ~pages=[{id: "main", label: "Main", title: "Parameters", hint: "Browse the presets (ctrl+F)", build: page}],
    ~buttons=ctx => [("Sample bank", "Load a made-up bank of presets, to browse", () => loadSampleBank(ctx))],
  )
