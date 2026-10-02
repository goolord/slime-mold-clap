// The plugin's parameters: the one list the view, the host and the DSP share. tools/gen.mjs turns it
// into dsp/Params.cmajor (the endpoints, and a params::Values struct the DSP reads by name), so
// after changing it run `just gen` (every build does).
//
// Ids are Cmajor identifiers and are how hosts and presets know a parameter: append, and rename
// with care. Ranges and defaults are plain values (Hz, ms, dB). A `logarithmic` knob hands the DSP
// its frequency or time but keeps its position for hosts to automate.
//
// The Physarum FDN (dsp/PhysarumFdn.cmajor): four tube-plasticity parameters that drive how the
// feedback matrix grows and prunes itself, four reverb parameters, and the eight "food" switches
// that say which delay lines the input is fed into (clicked on the network graph rather than
// automated, so hidden from the host's list).

open Param

// "γ 1.50"
let gammaText = x => "γ " ++ Float.toFixed(x, ~digits=2)

let all = [
  // tube plasticity: dD/dt = growthRate * f(|Q|) - decayRate * D
  logarithmic("growthRate", "Adaptation Speed", ~min=0.02, ~max=20., ~init=1.5, ~unit="/s"),
  logarithmic("decayRate", "Pruning Rate", ~min=0.01, ~max=10., ~init=0.4, ~unit="/s"),
  // the share of the regular lattice every tube keeps however little flows through it
  percent("memory", "Harmonic Memory", ~init=0.3),
  // f(|Q|) = |Q|^γ / (1 + |Q|^γ)
  number("gamma", "Flux Exponent", ~min=1., ~max=2., ~init=1.5, ~text=gammaText),
  // the reverb
  logarithmic("decayTime", "Decay Time", ~min=0.3, ~max=30., ~init=3., ~unit="s"),
  percent("damping", "Damping", ~init=0.35),
  number("roomSize", "Room Size", ~min=0.25, ~max=2., ~init=1., ~digits=2, ~unit="x"),
  percent("mix", "Dry/Wet", ~init=0.35),
  // food: the delay lines the input feeds (oat flakes on the graph)
  toggle("food1", "Food 1", ~init=true, ~hidden=true),
  toggle("food2", "Food 2", ~hidden=true),
  toggle("food3", "Food 3", ~hidden=true),
  toggle("food4", "Food 4", ~init=true, ~hidden=true),
  toggle("food5", "Food 5", ~hidden=true),
  toggle("food6", "Food 6", ~init=true, ~hidden=true),
  toggle("food7", "Food 7", ~hidden=true),
  toggle("food8", "Food 8", ~hidden=true),
]
