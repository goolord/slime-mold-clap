# Why the Physarum FDN can't blow up

`dsp/PhysarumFdn.cmajor` rebuilds its feedback matrix from a slime-mould model every 64 samples,
crossfades line lengths when the room changes, and glides its damping and decay gains. This note
proves that none of that can make the loop run away. The output stays bounded for every bounded
input, whatever the input's amplitude and whatever the parameters do, including automation that
slams them between extremes. The proof needs four facts about the loop, each enforced in the code,
and a small-gain argument to combine them.

## The loop

Per sample `n`, with `N = 8` lines:

```
x_i(n) = R_i[s_i](n)                  the taps: line i read back (a delay, or a crossfade of two)
y_i(n) = g_i(n) · F_i[x_i](n)         damping lowpass F, then the loop gain g
s(n)   = A(n) y(n) + B u(n)           mixed by the feedback matrix, plus the input
out(n) = d(n) u(n) + w(n) C x(n)      dry and wet
```

`u` is the stereo input, `B` (8×2) and `C` (2×8) are fixed routing gains, and `d`, `w` are mix
levels in [0, 1]. Everything else depends on time, and the matrix `A(n)` also depends on the signal
through the conductances.

(Strictly, the loop hears `v = D[h · u]` rather than `u`: the input ducked by the attack softener's
gain `h(n)` in [0, 1], then through the diffuser `D`, a chain of allpasses
`w(n) = x(n) + g w(n − L)`, `y(n) = w(n − L) − g w(n)` with `0 ≤ g ≤ 0.72`. Each has
`sup|w| ≤ sup|x| / (1 − g)` and so `sup|y| ≤ sup|x| (1 + g) / (1 − g)`, whatever `g` does over time,
so `sup|v| ≤ K sup|u|` for a fixed `K`. Both are outside the loop: everything below holds with
`sup|v|` in place of `sup|u|`.)

Notation: `‖v‖` is the Euclidean norm of a vector, `‖M‖₂` the spectral norm of a matrix (its
largest singular value), and `‖e‖_ℓ2` the energy norm of a signal, `√Σₙ ‖e(n)‖²`.

## Fact 1: ‖A(n)‖₂ ≤ 1 at every sample

The conductances `W` give a matrix `M` with `M[r][c] = ±√(W_cr · L_min / L_cr)` (and a constant
diagonal). `project()` turns it into `A` in two steps.

**Scaling.** `X₀ = M / β` with `β = min(‖M‖_F, √(‖M‖₁ ‖M‖_∞))`. Both are upper bounds on `‖M‖₂`.
The Frobenius norm bounds it because `‖M‖₂² = σ_max² ≤ Σσᵢ² = ‖M‖_F²`. The other bound is the Schur
test, or Riesz–Thorin interpolation between the 1- and ∞-norms. So every singular value of `X₀`
lies in [0, 1].

**Newton–Schulz.** `X_{k+1} = X_k (3I − X_kᵀX_k) / 2`. Write `X_k = U Σ Vᵀ`, so
`X_kᵀX_k = V Σ² Vᵀ` and

```
X_{k+1} = U · Σ (3I − Σ²)/2 · Vᵀ
```

The singular vectors stay put, and each singular value maps through `f(σ) = σ(3 − σ²)/2`. On [0, 1],
`f′(σ) = 3(1 − σ²)/2 ≥ 0`, `f(0) = 0` and `f(1) = 1`, so `f` maps [0, 1] into [0, 1]. Above 0 it
draws values towards 1: `f(σ) > σ` for `0 < σ < 1`. By induction, **`‖X_k‖₂ ≤ 1` for every `k`**, and
not only in the limit. The iteration stops when `‖XᵀX − I‖_F < 10⁻⁷`, which takes at most 24
iterations and typically 6 to 9. A singular value that hasn't reached 1 yet can only lose energy.
The limit is the polar factor `M (MᵀM)^(-1/2)`, the orthogonal matrix nearest `M`.

**The ramp.** Within each 64-sample block the audio uses `A(n) = (1 − t) A_old + t A_new` with
`t ∈ [0, 1]`. By the triangle inequality, `‖A(n)‖₂ ≤ (1 − t) + t = 1`.

**Rounding.** The projection runs in float64 and the audio matrix is float32. Let `η` bound the
rounding excess, so `‖A(n)‖₂ ≤ 1 + η` with `η ≈ 10⁻⁶`. The DSP measures this: `networkStats[0]`
is the largest singular value of the matrix in use, and the dashboard shows it.

A depends on the signal, but that doesn't matter here: the bound holds pointwise for any
`A(n)`. Then `‖A(n) y(n)‖ ≤ (1 + η) ‖y(n)‖` at every `n`, so as an operator on signals, `y ↦ A y` has
gain at most `1 + η` in ℓ2 and in any weighted ℓ2.

## Fact 2: the delay reads never amplify, even while crossfading

Without a fade, `x_i(n) = s_i(n − a)` is a pure delay with gain 1. When the length changes from `a`
to `b`, `readTap` reads

```
x(n) = α(n) s(n − a) + β(n) s(n − b),   α ramps 1 → 0 over T samples,
                                         β(n) = 1 − α(n − λ),  λ = max(b − a, 0)
```

Think of this as a matrix from stored samples `s(k)` to reads `x(n)`, with non-negative entries.
Schur's test gives `‖R‖ ≤ √(max row sum · max column sum)`.

- **Rows** (one read): `α(n) + 1 − α(n − λ) ≤ 1`, because `α` never increases and `λ ≥ 0`.
- **Columns** (one stored sample `s(k)`, read with weight `α` at `n = k + a` and `β` at `n = k + b`):
  - When lengthening (`λ = b − a`), the column sum is `α(k + a) + 1 − α(k + b − λ) = 1` exactly.
  - When shortening (`λ = 0`, `b < a`), it is `α(k + a) + 1 − α(k + b) ≤ 1`, because `k + a > k + b`.

So `‖R‖ ≤ 1`. The obvious alternative, sliding the read point, has gain up to `√(1 + 2ε)` at
slide speed `ε`: when the delay grows, samples get read twice. That would need a loop-gain margin
that grows with the speed. The crossfade needs no margin at all.

## Fact 3: the damping filter is a contraction, even while it changes

The lowpass is `a / (1 − p z⁻¹)` with `p = 1 − a`, `a ∈ (0, 1]`. Its gain is at most 1 at every
frequency, but that only holds for a fixed `a`. The common form `l += a (x − l)` can gain energy
when `a` drops quickly: an impulse caught at `a = 1` and then held with a small `a` rings far
longer than it should.

So the code uses this state-space form instead:

```
[ z(n+1) ]   [ p   c ] [ z(n) ]
[ y(n)   ] = [ c   a ] [ x(n) ],      c = √(a p)
```

Its transfer function is `a + c²z⁻¹/(1 − p z⁻¹) = a / (1 − p z⁻¹)`, the same filter. The matrix
`Θ` is symmetric with trace `p + a = 1` and determinant `pa − c² = 0`, so its eigenvalues are 1 and
0. It is an orthogonal projection with `‖Θ‖₂ = 1` for every `a`. At each sample,
`z(n+1)² + y(n)² ≤ z(n)² + x(n)²`, even as `a(n)` changes. Summing over time gives
`‖y‖²_ℓ2 ≤ ‖x‖²_ℓ2 + z(0)²`.

## Fact 4: the loop gain stays below a ceiling

`g_i(n) = min(10^(−3 Lᵢ / (T60 · sr)), 0.9995)`, then smoothed. A convex blend of values below the
ceiling stays below it, so `0 ≤ g_i(n) ≤ ĝ = 0.9995` for every decay time, including the longest.

## Putting it together: exponentially weighted small gain

Take any `ρ` with

```
ĝ (1 + η) < ρ^(L_max + 1) < 1        (L_max ≤ 16382 samples, the longest line)
```

Such a `ρ` exists because `ĝ (1 + η) ≈ 0.9995 < 1`. Weight every signal by `ρ^(−n)`:
`ŝ(n) = ρ^(−n) s(n)`, and so on. Each part of the loop in turn:

| part | weighted gain |
|---|---|
| matrix `A(n)` (pointwise) | `≤ 1 + η` |
| loop gain `g(n)` (pointwise) | `≤ ĝ` |
| damping filter: weighted, `Θ` becomes `diag(ρ⁻¹, 1) Θ` | `≤ ρ⁻¹` |
| delay read: each weight is multiplied by `ρ^(−a)` or `ρ^(−b)` | `≤ ρ^(−L_max)` |

The product is `γ = ĝ (1 + η) ρ^(−L_max − 1) < 1`. Every line is at least 200 samples long, so the
loop is causal with no algebraic loop. The small-gain theorem, applied to the signals truncated at
any time `N`, then gives

```
‖ŝ‖_ℓ2[0,N]  ≤  ( ‖B û‖_ℓ2[0,N] + c₀ ) / (1 − γ)
```

Here `c₀` collects the initial state: the buffers start at zero and so do the filters. Since
`|ŝ(N)| ≤ ‖ŝ‖_ℓ2[0,N]` and `Σ_{n≤N} ρ^(−2n) ≤ ρ^(−2N) / (1 − ρ²)`, multiplying back by `ρ^N` gives

```
‖s(N)‖  ≤  ‖B‖₂ · sup|u| / ((1 − γ) √(1 − ρ²))     for every N
```

The taps `x` are reads of `s` with weights at most 1, so they are bounded the same way, and
`out = d u + w C x` is bounded too. **Bounded input gives bounded output.** The bound doesn't
depend on the tube dynamics, the growth, pruning, memory or γ settings, the room-size changes or the
damping changes. It also shows that with no input the state dies away exponentially, at least as
fast as `ρⁿ`.

The constant is very loose: `ρ` is within about `3·10⁻⁸` of 1, because the argument budgets for
the longest line at the worst moment. It is a guarantee, not an estimate. The decay time measured
on the real thing is what the decay time is set to.

## The tube dynamics are bounded too

This isn't needed for the audio bound, but it keeps the matrix well defined. Pressures are clamped
to [0, 1] and `W ∈ [0, 1]`, so the flux `Q = 4 W (pᵢ − pⱼ) / L ≤ 4 / 0.765` is finite. Over a step
`Δt = 64 / sr`, `dD/dt = α f(Q⁺) − μ D` is integrated exactly for the flux held over the step:

```
D ← D* + (D − D*) e^(−μ Δt),    D* = α f / μ
```

That is a contraction towards `D*` with factor `e^(−μΔt) ∈ (0, 1)`, which can't overshoot for any
`α`, `μ` or `Δt`. The result is then clamped to `[0.002, 1]`. No setting can make `D` diverge or
oscillate numerically, and the 0.002 floor means a starved tube can always regrow.

## What is checked

- `tools/test/dsp/PhysarumStress.cmajor` uses the most plastic tubes and the longest decay. It slams
  damping between none and full, jumps the room between its extremes ten times a second, and drives
  the bursts 50 times too loud. The test passes with a peak of 0.23 after scaling back down by 50.
- Measured on the default patch: the largest singular value is at most 1 to float precision,
  `‖AᵀA − I‖_F ≤ 7.3·10⁻⁸`, and Newton–Schulz takes at most 7 iterations.

Out of scope: NaN or infinite input samples propagate like in any linear filter, and no bound
covers them.
