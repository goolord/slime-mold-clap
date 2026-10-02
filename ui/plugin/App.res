// The plugin's view: its page, and what else it gives the shell (Shell.res). Index.res mounts it.

// (the preset formats register themselves)
let formats = Formats.all

let pages: array<Shell.page> = [
  {
    id: "dish",
    label: "Dish",
    title: "The slime mould network and its settings",
    hint: PhysarumDashboard.hint,
    build: PhysarumDashboard.build,
  },
]

let mount = pc => Shell.mount(pc, ~specs=Params.all, ~pages)
