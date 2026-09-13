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
import {hooks as colocatedHooks} from "phoenix-colocated/svc_web"
import topbar from "../vendor/topbar"

// Kanban drag-drop (E4-B): нативный HTML5 DnD без внешних зависимостей.
// Используем on*-свойства (не addEventListener) — идемпотентно при LiveView-патчах.
const Hooks = {
  Kanban: {
    mounted() { this.setupDnd() },
    updated() { this.setupDnd() },
    setupDnd() {
      let dragId = null

      this.el.querySelectorAll("[data-task-id]").forEach(card => {
        card.ondragstart = e => {
          dragId = card.dataset.taskId
          e.dataTransfer.effectAllowed = "move"
          e.dataTransfer.setData("text/plain", dragId)
          card.classList.add("opacity-40")
        }
        card.ondragend = () => { dragId = null; card.classList.remove("opacity-40") }
      })

      this.el.querySelectorAll("[data-status]").forEach(col => {
        col.ondragover = e => {
          e.preventDefault()
          e.dataTransfer.dropEffect = "move"
          col.classList.add("ring-2", "ring-primary/40")
        }
        col.ondragleave = () => col.classList.remove("ring-2", "ring-primary/40")
        col.ondrop = e => {
          e.preventDefault()
          col.classList.remove("ring-2", "ring-primary/40")
          const id = e.dataTransfer.getData("text/plain") || dragId
          const status = col.dataset.status
          if (id && status) this.pushEvent("move_task", {id, status})
        }
      })
    }
  },

  // Встроенный помощник (S37). Ходит в тот же REST API, что Android и Tauri —
  // одна реализация поведения на три клиента.
  Assistant: {
    mounted() {
      this.panel = this.el.querySelector("#svc-assistant-panel")
      this.log = this.el.querySelector("[data-log]")
      this.input = this.el.querySelector("[data-input]")
      this.locale = this.el.dataset.locale || "uz"
      this.loaded = false

      this.el.querySelector("[data-toggle]").onclick = () => this.toggle()
      this.el.querySelector("[data-form]").onsubmit = e => {
        e.preventDefault()
        const q = this.input.value.trim()
        if (q) { this.input.value = ""; this.ask(q) }
      }
    },

    toggle() {
      const btn = this.el.querySelector("[data-toggle]")
      const open = this.panel.hidden
      this.panel.hidden = !open
      btn.setAttribute("aria-expanded", String(open))
      this.el.querySelector("[data-icon-open]").classList.toggle("hidden", open)
      this.el.querySelector("[data-icon-close]").classList.toggle("hidden", !open)

      // Подсказки тянем один раз и только при первом открытии — до него панель
      // никому не нужна, а запрос уходил бы на каждой загрузке страницы.
      if (open && !this.loaded) { this.loaded = true; this.loadSuggestions() }
      if (open) this.input.focus()
    },

    async loadSuggestions() {
      const data = await this.get(`/api/assistant/suggestions?locale=${this.locale}`)
      if (data) this.showChips(data.suggestions)
    },

    async ask(question) {
      this.bubble(question, "me")
      const thinking = this.bubble(this.t("thinking"), "bot muted")

      const data = await this.post("/api/assistant/ask", {question, locale: this.locale})
      thinking.remove()
      if (!data) { this.bubble(this.t("error"), "bot"); return }

      if (data.status === "ok") {
        this.bubble(data.answer.answer, "bot")
        this.showChips(data.related)
      } else if (data.status === "unsure") {
        this.bubble(this.t("unsure"), "bot")
        this.showChips(data.candidates)
      } else if (data.status === "restricted") {
        this.bubble(`${this.t("restricted")} ${(data.allowed_role_labels || data.allowed_roles).join(", ")}`, "bot")
      } else {
        this.bubble(this.t("nomatch"), "bot")
        this.showChips(data.suggestions)
      }
    },

    // Клик по подсказке берёт готовый ответ по id: незачем прогонять
    // собственный вопрос помощника через поиск ещё раз.
    async openEntry(entry) {
      this.bubble(entry.question, "me")
      const data = await this.get(`/api/assistant/${entry.id}?locale=${this.locale}`)
      this.bubble(data ? data.answer.answer : this.t("error"), "bot")
    },

    bubble(text, kind) {
      const mine = kind.startsWith("me")
      const el = document.createElement("div")
      el.className = mine
        ? "ml-auto max-w-[85%] rounded-2xl rounded-br-sm bg-primary text-primary-content px-3 py-2"
        : "mr-auto max-w-[90%] rounded-2xl rounded-bl-sm bg-base-200 px-3 py-2" +
          (kind.includes("muted") ? " opacity-60 italic" : "")
      el.textContent = text
      this.log.appendChild(el)
      this.log.scrollTop = this.log.scrollHeight
      return el
    },

    showChips(entries) {
      if (!entries || entries.length === 0) return
      const box = document.createElement("div")
      box.className = "flex flex-wrap gap-1.5"
      entries.forEach(entry => {
        const chip = document.createElement("button")
        chip.type = "button"
        chip.className = "btn btn-xs btn-outline normal-case font-normal"
        chip.textContent = entry.question
        chip.onclick = () => { box.remove(); this.openEntry(entry) }
        box.appendChild(chip)
      })
      this.log.appendChild(box)
      this.log.scrollTop = this.log.scrollHeight
    },

    t(key) { return this.el.dataset[`t${key.charAt(0).toUpperCase()}${key.slice(1)}`] || "" },

    async get(url) { return this.request(url, {headers: {accept: "application/json"}}) },

    async post(url, body) {
      return this.request(url, {
        method: "POST",
        headers: {"content-type": "application/json", accept: "application/json"},
        body: JSON.stringify(body),
      })
    },

    // Сетевая ошибка не должна ронять страницу — помощник вторичен по отношению
    // к тому, зачем человек вообще открыл систему.
    async request(url, opts) {
      try {
        const res = await fetch(url, {credentials: "same-origin", ...opts})
        return res.ok ? await res.json() : null
      } catch (_) {
        return null
      }
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
topbar.config({barColors: {0: "#34d399"}, shadowColor: "rgba(0, 0, 0, .3)"})
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

