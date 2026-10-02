// A chain of effects as a strip of tabs, in the order they run, each with a light that switches the
// effect on and off, and a page per tab under the strip. Drag a tab
// sideways to move its effect in the chain (Reorder); click it to show its page.
//
// The order is kept in parameters, so that it is saved with the session and in presets: one list
// parameter per place in the chain, each holding the index of the effect there, which the DSP
// reads to run them in that order. Without ~order the strip keeps the order it's given.

open! Web

type effect = {
  // what the tab says, and the status line's text over it
  label: string,
  title: string,
  // the effect's on switch (a toggle parameter), if it has one
  on: option<string>,
  // builds the effect's page in the element it gets (the size of the strip's page area)
  build: element => unit,
  // shown each time the page is shown (redraw a graph that skipped drawing while hidden...)
  onShow?: unit => unit,
}

type t = {
  select: int => unit,
  // the effects in the order they run, by index
  order: unit => array<int>,
}

// ~order: the place parameters (one per effect); area: the strip and the pages under it
let make = (ctx: Ctx.t, parent, area: box, ~effects: array<effect>, ~order=?, ~stripHeight=26.) => {
  let model = ctx.model
  let get = id => model->ParamModel.get(id)
  let count = Array.length(effects)

  let strip = el("div", ~cls="fxstrip", ~parent)->place(area.x, area.y, ~w=area.w, ~h=stripHeight)
  let pageBox = {x: area.x, y: area.y + stripHeight + 4., w: area.w, h: area.h - stripHeight - 4.}
  let pages = effects->Array.map(e => {
    let page = el("div", ~cls="fxbody", ~parent)->placeBox(pageBox)
    e.build(page)
    page
  })

  // the order: from the place parameters if there are any (an effect missing from them, or there
  // twice, is put right: every effect appears once)
  let current = () =>
    switch order {
    | Some(ids) =>
      let listed = ids->Array.map(id => Float.toInt(get(id)))->Array.filter(i => i >= 0 && i < count)
      let unique = listed->Array.reduce([], (acc, i) => acc->Array.includes(i) ? acc : [...acc, i])
      [...unique, ...Array.fromInitializer(~length=count, i => i)->Array.filter(i => !(unique->Array.includes(i)))]
    | None => Array.fromInitializer(~length=count, i => i)
    }
  let setOrder = (list: array<int>) =>
    order->Option.forEach(ids =>
      ids->Array.forEachWithIndex((id, place) =>
        list[place]->Option.forEach(i => model->ParamModel.gestureSet(id, Int.toFloat(i)))
      )
    )

  // lays the tabs out in the chain's order (set below, once the tabs are made)
  let layout = ref(() => ())
  let selected = ref(0)
  let select = i => {
    selected := i
    pages->Array.forEachWithIndex((page, k) => page->toggleClass("on", k == i))
    effects[i]->Option.forEach(e => e.onShow->Option.forEach(f => f()))
    layout.contents()
  }

  // the tabs, made once, laid out in the chain's order
  let tabs = effects->Array.map(e => {
    let tab = el("div", ~cls="fxtab")
    e.on->Option.forEach(id => {
      let led = el("i", ~cls="led", ~parent=tab)
      led->onPointer(#pointerdown, ev =>
        if ev->button == 0 {
          ev->stopPropagation
          ev->preventDefault
          model->ParamModel.gestureSet(id, get(id) != 0. ? 0. : 1.)
        }
      )
      led->onMouse(#mouseenter, ev => {
        ev->stopPropagation
        ctx.status->Status.show(`${model->ParamModel.longText(id)}: click to switch it`)
      })
      led->onMouse(#mouseleave, _ => ctx.status->Status.show(e.title))
      model->ParamModel.listen(id, () => led->toggleClass("lit", get(id) != 0.))
      led->toggleClass("lit", get(id) != 0.)
    })
    el("span", ~cls="lbl", ~text=e.label, ~parent=tab)->ignore
    ctx.status->Status.hover(tab, () =>
      order == None ? e.title : `${e.title}: click to open, drag sideways to move it in the chain`
    )
    tab->suppressContextMenu
    tab
  })

  layout :=
    () => {
      let list = current()
      strip->setTextContent("")
      list->Array.forEachWithIndex((i, place) => {
        if place > 0 {
          el("span", ~cls="fxsep", ~text="›", ~parent=strip)->ignore
        }
        tabs[i]->Option.forEach(tab => {
          tab->toggleClass("on", i == selected.contents)
          strip->appendChild(tab)
        })
      })
    }

  tabs->Array.forEachWithIndex((tab, i) =>
    tab->onPointer(#pointerdown, ev => {
      ev->preventDefault
      if ev->button == 0 {
        switch order {
        | Some(_) =>
          let list = current()
          let others = list->Array.filter(o => o != i)->Array.filterMap(o => tabs[o])
          Reorder.start(
            ev,
            tab,
            ~others,
            ~onDrop=pos => {
              let rest = list->Array.filter(o => o != i)
              setOrder([...rest->Array.slice(~start=0, ~end=pos), i, ...rest->Array.slice(~start=pos)])
            },
            ~onClick=() => select(i),
          )
        | None => select(i)
        }
      }
    })
  )

  order->Option.forEach(ids => model->ParamModel.listenEach(ids, perFrame(() => layout.contents())))
  select(0)
  {select, order: current}
}
