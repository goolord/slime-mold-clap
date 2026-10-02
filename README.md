# Physarum

A CLAP reverb whose feedback delay network rewires itself like a slime mould. The DSP is Cmajor
and the UI is ReScript. The feedback matrix stays lossless however it rewires, so the reverb can't
run away (proof in [docs/STABILITY.md](docs/STABILITY.md)).

## Building

Needs cmaj, node, just, cmake and a C++17 compiler.

```
just              build dist/Physarum.clap
just install      build and copy it to the CLAP folder
just play         run it in the Cmajor player
just preview      the UI in a browser at localhost:8123/tools/ui-preview/
just test         render the DSP tests
```
