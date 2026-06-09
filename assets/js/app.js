// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/cherry"
import Sortable from "../vendor/sortable.min"
import topbar from "../vendor/topbar"

const setTheme = theme => {
  if(theme === "system") {
    localStorage.removeItem("phx:theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("phx:theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
  }
}

if(!document.documentElement.hasAttribute("data-theme")) {
  setTheme(localStorage.getItem("phx:theme") || "system")
}

window.addEventListener("storage", event => {
  if(event.key === "phx:theme") setTheme(event.newValue || "system")
})

window.addEventListener("phx:set-theme", event => setTheme(event.target.dataset.phxTheme))
window.addEventListener("click", event => {
  const themeButton = event.target.closest("[data-phx-theme]")
  if(themeButton) setTheme(themeButton.dataset.phxTheme)
})

const Hooks = {
  TagEditor: {
    mounted() {
      this.valueInput = this.el.querySelector("[data-tag-editor-value]")
      this.textInput = this.el.querySelector("[data-tag-input]")
      this.colorSelect = this.el.querySelector("[data-tag-color-select]")
      this.tagList = this.el.querySelector("[data-tag-list]")
      this.tags = this.parseTags(this.valueInput?.value || this.el.dataset.initialTags)

      this.handleKeyDown = event => {
        if(event.key === "Enter" || event.key === " ") {
          event.preventDefault()
          this.addTag(this.textInput.value)
        } else if(event.key === "Backspace" && this.textInput.value === "" && this.tags.length > 0) {
          this.tags.pop()
          this.renderTags()
        }
      }

      this.handlePaste = event => {
        const pasted = event.clipboardData?.getData("text")
        if(!pasted || !/[\s,]/.test(pasted)) return

        event.preventDefault()
        pasted.split(/[\s,]+/).forEach(name => this.addTag(name, false))
        this.renderTags()
      }

      this.handleEvent("reset-task-form", () => {
        if(!this.el.closest("#task-form")) return

        this.tags = []
        if(this.textInput) this.textInput.value = ""
        if(this.colorSelect) this.colorSelect.value = "neutral"
        this.renderTags()
      })

      this.textInput?.addEventListener("keydown", this.handleKeyDown)
      this.textInput?.addEventListener("paste", this.handlePaste)
      this.renderTags()
    },
    destroyed() {
      this.textInput?.removeEventListener("keydown", this.handleKeyDown)
      this.textInput?.removeEventListener("paste", this.handlePaste)
    },
    parseTags(value) {
      try {
        const tags = JSON.parse(value || "[]")
        if(!Array.isArray(tags)) return []

        return tags
          .map(tag => ({
            name: String(tag.name || "").trim().toLowerCase(),
            color: this.validColor(tag.color) ? tag.color : "neutral",
          }))
          .filter(tag => tag.name)
      } catch(_error) {
        return []
      }
    },
    addTag(value, render = true) {
      const name = String(value || "").trim().toLowerCase()
      if(!name) return

      const existing = this.tags.find(tag => tag.name === name)
      const color = this.validColor(this.colorSelect?.value) ? this.colorSelect.value : "neutral"

      if(existing) {
        existing.color = color
      } else {
        this.tags.push({name, color})
      }

      if(this.textInput) this.textInput.value = ""
      if(render) this.renderTags()
    },
    removeTag(name) {
      this.tags = this.tags.filter(tag => tag.name !== name)
      this.renderTags()
    },
    updateColor(name, color) {
      const tag = this.tags.find(tag => tag.name === name)
      if(!tag || !this.validColor(color)) return

      tag.color = color
      this.renderTags()
    },
    renderTags() {
      if(!this.tagList || !this.valueInput) return

      this.tagList.innerHTML = ""
      this.tagList.classList.toggle("hidden", this.tags.length === 0)
      this.tagList.classList.toggle("flex", this.tags.length > 0)

      this.tags.forEach(tag => {
        const chip = document.createElement("span")
        chip.className = `cherry-tag-chip cherry-tag-chip-${tag.color}`

        const name = document.createElement("span")
        name.textContent = tag.name

        const color = document.createElement("select")
        color.className = "cherry-tag-color-select"
        color.setAttribute("aria-label", `Color for ${tag.name}`)
        this.colorOptions().forEach(([label, value]) => {
          const option = document.createElement("option")
          option.value = value
          option.textContent = label
          option.selected = tag.color === value
          color.appendChild(option)
        })
        color.addEventListener("change", event => this.updateColor(tag.name, event.target.value))

        const remove = document.createElement("button")
        remove.type = "button"
        remove.className = "cherry-tag-remove"
        remove.setAttribute("aria-label", `Remove ${tag.name}`)
        remove.textContent = "×"
        remove.addEventListener("click", () => this.removeTag(tag.name))

        chip.appendChild(name)
        chip.appendChild(color)
        chip.appendChild(remove)
        this.tagList.appendChild(chip)
      })

      this.valueInput.value = JSON.stringify(this.tags)
    },
    colorOptions() {
      return [
        ["Stone", "neutral"],
        ["Rose", "rose"],
        ["Amber", "amber"],
        ["Emerald", "emerald"],
        ["Sky", "sky"],
        ["Violet", "violet"],
      ]
    },
    validColor(color) {
      return ["neutral", "rose", "amber", "emerald", "sky", "violet"].includes(color)
    },
  },
  TaskForm: {
    mounted() {
      this.handleEvent("reset-task-form", () => this.el.reset())
    },
  },
  TaskBoard: {
    mounted() {
      this.sortables = []
      this.handleCardDoubleClick = event => {
        const card = event.target.closest("[data-task-card]")

        if(!card || !this.el.contains(card) || event.target.closest("button, input, textarea, select, a, [data-no-drag]")) return

        event.preventDefault()
        this.pushEvent("edit_task", {task_id: card.dataset.taskId})
      }

      this.el.addEventListener("dblclick", this.handleCardDoubleClick)
      this.initSortables()
    },
    updated() {
      this.destroySortables()
      this.initSortables()
    },
    destroyed() {
      this.el.removeEventListener("dblclick", this.handleCardDoubleClick)
      this.destroySortables()
    },
    initSortables() {
      const columnSortable = new Sortable(this.el, {
        animation: 150,
        draggable: "[data-board-column]",
        filter: "button, input, textarea, select, a, [data-no-drag], [data-task-list], [data-task-list] *",
        preventOnFilter: false,
        ghostClass: "task-column-ghost",
        chosenClass: "task-column-chosen",
        dragClass: "task-column-drag",
        onEnd: event => {
          const columnId = event.item?.dataset.columnId

          if(!columnId) return

          this.pushEvent("move_column", {
            column_id: columnId,
            position: event.newDraggableIndex,
          })
        },
      })

      this.sortables.push(columnSortable)

      this.el.querySelectorAll("[data-task-list]").forEach(list => {
        const sortable = new Sortable(list, {
          group: "project-tasks",
          animation: 150,
          draggable: "[data-task-card]",
          filter: "button, input, textarea, select, a, [data-no-drag]",
          preventOnFilter: false,
          ghostClass: "task-card-ghost",
          chosenClass: "task-card-chosen",
          dragClass: "task-card-drag",
          onEnd: event => {
            const taskId = event.item?.dataset.taskId
            const columnId = event.to?.dataset.columnId

            if(!taskId || !columnId) return

            this.pushEvent("move_task", {
              task_id: taskId,
              column_id: columnId,
              position: event.newDraggableIndex,
            })
          },
        })

        this.sortables.push(sortable)
      })
    },
    destroySortables() {
      ;(this.sortables || []).forEach(sortable => sortable.destroy())
      this.sortables = []
    },
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
