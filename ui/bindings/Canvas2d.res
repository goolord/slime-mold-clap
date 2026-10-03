// More of the canvas 2D context than Web.Context2d binds: arcs and curves, gradients, shadows,
// compositing, text and transforms, for the drawings that glow (NetworkGraph, SlimePlots).

type context2d = Web.context2d
type gradient

@send external arc: (context2d, float, float, float, float, float) => unit = "arc"
@send external quadraticCurveTo: (context2d, float, float, float, float) => unit = "quadraticCurveTo"
@send external ellipse: (context2d, float, float, float, float, float, float, float) => unit = "ellipse"
@send external rect: (context2d, float, float, float, float) => unit = "rect"
@send external clip: context2d => unit = "clip"
@send external drawImage: (context2d, Web.element, float, float) => unit = "drawImage"

@set external setShadowBlur: (context2d, float) => unit = "shadowBlur"
@set external setShadowColor: (context2d, string) => unit = "shadowColor"
@set external setGlobalAlpha: (context2d, float) => unit = "globalAlpha"
@set external setCompositeOperation: (context2d, string) => unit = "globalCompositeOperation"
@set external setLineCap: (context2d, string) => unit = "lineCap"
@set external setLineJoin: (context2d, string) => unit = "lineJoin"
@send external setLineDash: (context2d, array<float>) => unit = "setLineDash"

@send
external createRadialGradient: (context2d, float, float, float, float, float, float) => gradient =
  "createRadialGradient"
@send
external createLinearGradient: (context2d, float, float, float, float) => gradient =
  "createLinearGradient"
@send external addColorStop: (gradient, float, string) => unit = "addColorStop"
@set external setFillGradient: (context2d, gradient) => unit = "fillStyle"

@set external setFont: (context2d, string) => unit = "font"
@set external setTextAlign: (context2d, string) => unit = "textAlign"
@set external setTextBaseline: (context2d, string) => unit = "textBaseline"
@send external fillText: (context2d, string, float, float) => unit = "fillText"

@send external save: context2d => unit = "save"
@send external restore: context2d => unit = "restore"
@send external setTransform: (context2d, float, float, float, float, float, float) => unit = "setTransform"
@send external translate: (context2d, float, float) => unit = "translate"
@send external rotate: (context2d, float) => unit = "rotate"

// Whether the user asked for less motion.
type mediaQuery
@val external matchMedia: string => mediaQuery = "matchMedia"
@get external matches: mediaQuery => bool = "matches"
// (the query is made once; its `matches` follows the setting)
let reducedMotionQuery = try Some(matchMedia("(prefers-reduced-motion: reduce)")) catch {
| _ => None
}
let reducedMotion = () => reducedMotionQuery->Option.mapOr(false, matches)
