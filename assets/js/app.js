// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/ash_phoenix_starter"
import { SVGInject } from '../vendor/svg-inject';
import ReusableMapHook from "./hooks/reusable_map_hook"
import TusUploader from "./hooks/tus_uploader";
import topbar from "../vendor/topbar"
import "phoenix_live_head"
import 'altcha'
import { AthanorHooks } from "athanor"
import PhiaHooks from './phia_hooks/index.js'

import "../../deps/phoenix_live_calendar/priv/static/assets/phoenix_live_calendar.js"

let Hooks = {};

Hooks.AltchaHook = {
  mounted() {
    const widget = this.el.querySelector("altcha-widget");
    const input = this.el.querySelector("#altcha-token-input");

    if (widget && input) {
      widget.addEventListener("statechange", (event) => {
        const { state, payload } = event.detail || {};
        console.log(`[Altcha] State: ${state}, Payload:`, payload);

        if (state === "verified" && payload) {
          input.value = payload;
        } else if (state === "error") {
          input.value = "";
        }
      });
    }
  }
};

Hooks.DelayedDropdown = {
  mounted() {
    let timeout = null;
    const dropdown = this.el.querySelector("div[id^='dropdown-']");
    const button = this.el.querySelector("button");

    if (!dropdown || !button) return;

    // Toggle dropdown open/closed when clicking the 3-dots button
    button.addEventListener("click", (e) => {
      e.stopPropagation();
      if (dropdown.classList.contains("hidden")) {
        dropdown.classList.remove("hidden");
        requestAnimationFrame(() => {
          dropdown.classList.remove("opacity-0");
        });
      } else {
        dropdown.classList.add("opacity-0");
        setTimeout(() => dropdown.classList.add("hidden"), 300);
      }
    });

    // When the mouse leaves the wrapper area
    this.el.addEventListener("mouseleave", () => {
      if (dropdown.classList.contains("hidden")) return;

      timeout = setTimeout(() => {
        dropdown.classList.add("opacity-0");
        setTimeout(() => {
          dropdown.classList.add("hidden");
        }, 300);
      }, 1000); // 1-second delay before disappearing
    });

    // Cancel fade out if the mouse enters back
    this.el.addEventListener("mouseenter", () => {
      if (timeout) {
        clearTimeout(timeout);
        timeout = null;
      }
      if (!dropdown.classList.contains("hidden")) {
        dropdown.classList.remove("opacity-0");
      }
    });
  }
};

Hooks.Map = ReusableMapHook;
Hooks.TusUploader = TusUploader;

let Uploaders = {};

Uploaders.S3 = function(entries, onViewError) {
  entries.forEach((entry) => {
    let xhr = new XMLHttpRequest();
    onViewError(() => xhr.abort());

    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300
        ? entry.progress(100)
        : entry.error();

    xhr.onerror = () => entry.error();

    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) {
        let percent = Math.round((event.loaded / event.total) * 100);
        if (percent < 100) entry.progress(percent);
      }
    });

    xhr.open("PUT", entry.meta.url, true);
    xhr.setRequestHeader("Content-Type", entry.file.type);
    xhr.send(entry.file);
  });
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...window.PhoenixLiveCalendarHooks, ...colocatedHooks, ...Hooks, ...AthanorHooks },
  uploaders: Uploaders,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

window.liveSocket = liveSocket
window.SVGInject = SVGInject;

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
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
