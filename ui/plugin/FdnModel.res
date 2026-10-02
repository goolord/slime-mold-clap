// The network's shape and laws as the view draws them: the same constants and formulas as
// dsp/PhysarumFdn.cmajor (keep the two in step), so that the graphs show what the DSP does with a
// setting before it has even sent anything back.

let size = 8
let cells = size * size
let pi = Math.Constants.pi

// line lengths at room size 1 and 48 kHz (fdn::basePrimes)
let basePrimes = [887, 1093, 1327, 1601, 1913, 2357, 2903, 3511]
let referenceRate = 48000.
let maxLength = 16384 - 2

let gainCeiling = 0.9995
let fluxGain = 4.
let minConductance = 0.002
let pressureFloorDb = -72.

let cell = (r, c) => r * size + c

// where a node sits: clockwise from the top
let angle = i => -.pi / 2. + 2. * pi * Int.toFloat(i) / Int.toFloat(size)

// the tube between two nodes: their chord on the unit circle
let tubeLength = (i, j) => i == j ? 1. : 2. * Math.sin(pi * Int.toFloat(Math.Int.abs(i - j)) / Int.toFloat(size))

// f(q) = q^gamma / (1 + q^gamma)
let growth = (q: float, gamma) =>
  if q <= 0. {
    0.
  } else {
    let qg = Math.pow(q, ~exp=gamma)
    qg / (1. + qg)
  }

// the conductance a tube settles at under a steady flux: alpha f / mu, kept in range
let equilibrium = (q, ~alpha, ~mu, ~gamma) =>
  Math.max(minConductance, Math.min(1., alpha / Math.max(mu, 1e-4) * growth(q, gamma)))

// a tube's effective conductance: the lattice it remembers, and what it has grown
let effective = (memory: float, d) => memory + (1. - memory) * d

// the flux down tube i -> j at conductance w, from the two pressures
let flux = (w: float, i, j, pi: float, pj: float) => fluxGain * w / tubeLength(i, j) * (pi - pj)

// a pressure (0..1) as the level it stands for
let pressureDb = (p: float) => pressureFloorDb * (1. - p)

let isPrime = n =>
  if n < 2 {
    false
  } else if mod(n, 2) == 0 {
    n == 2
  } else {
    let rec go = d => d * d > n ? true : mod(n, d) == 0 ? false : go(d + 2)
    go(3)
  }

let rec primeAtLeast = n => isPrime(n) ? n : primeAtLeast(n + 1)

// the line lengths (samples) for a room size, at a sample rate
let delayLengths = (~roomSize, ~rate=referenceRate) => {
  let longest = Int.toFloat(basePrimes[size - 1]->Option.getOr(3511))
  let scale = Math.min(Math.max(0.25, Math.min(2., roomSize)) * rate / referenceRate, Int.toFloat(maxLength - 64) / longest)
  let previous = ref(1)
  basePrimes->Array.map(base => {
    let n = primeAtLeast(Math.Int.max(Float.toInt(Int.toFloat(base) * scale + 0.5), previous.contents + 1))
    previous := n
    n
  })
}

let lengthMs = (samples: int, ~rate=referenceRate) => 1000. * Int.toFloat(samples) / rate

// the loop gain that takes a line of this length down 60 dB in t60 seconds
let loopGain = (samples: float, ~t60: float, ~rate=referenceRate) =>
  Math.min(gainCeiling, Math.pow(10., ~exp=-3. * samples / (Math.max(t60, 0.05) * rate)))

// the damping lowpass's coefficient, and its gain at a frequency
let dampCoef = (damping: float, ~rate=referenceRate) =>
  damping <= 0.
    ? 1.
    : {
        let hz = Math.min(500. * Math.pow(40., ~exp=1. - damping), 0.45 * rate)
        1. - Math.exp(-2. * pi * hz / rate)
      }
let lowpassGain = (a: float, hz: float, ~rate=referenceRate) => {
  let w = 2. * pi * hz / rate
  let b = 1. - a
  a / Math.sqrt(1. - 2. * b * Math.cos(w) + b * b)
}

// dry and wet levels (equal power)
let mixLevels = (mix: float) => (Math.cos(mix * pi / 2.), Math.sin(mix * pi / 2.))

// the wet level's lean against long decays: (1 - mean g^2)^(1/4)
let wetGain = (lengths: array<int>, ~t60) => {
  let squares =
    lengths->Array.reduce(0., (s, n) => {
      let g = loopGain(Int.toFloat(n), ~t60)
      s + g * g
    })
  Math.sqrt(Math.sqrt(Math.max(0., 1. - squares / Int.toFloat(size))))
}

// The decay time at a frequency: each pass through a line of mean length loses the loop gain and
// the lowpass's gain there.
let decayTimeAt = (hz: float, ~t60: float, ~damping: float, ~meanLength: float) => {
  let g = loopGain(meanLength, ~t60)
  let h = lowpassGain(dampCoef(damping), hz)
  let lossDb = -20. * Math.log10(Math.max(1e-9, g * h))
  let passes = referenceRate / meanLength
  lossDb <= 0. ? 1e9 : 60. / (lossDb * passes)
}
