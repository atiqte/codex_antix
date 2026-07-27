(() => {
  "use strict";

  const root = document.documentElement;
  const sidebarKey = "notmuch-browser.sidebar-collapsed";
  const splitKey = "notmuch-browser.result-pane-height-percent";
  const clamp = (value, low, high) => Math.min(high, Math.max(low, value));
  const notice = document.querySelector("#app-notice");
  let noticeTimer;

  const hideNotice = () => {
    if (!notice) return;
    notice.hidden = true;
    notice.textContent = "";
    clearTimeout(noticeTimer);
  };

  const showNotice = (message) => {
    if (!notice) return;
    notice.textContent = message;
    notice.hidden = false;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(hideNotice, 8000);
  };

  const setSidebarCollapsed = (collapsed) => {
    root.classList.toggle("sidebar-collapsed", collapsed);
    try {
      localStorage.setItem(sidebarKey, collapsed ? "1" : "0");
    } catch (_) {}
    document.querySelectorAll("[data-sidebar-toggle]").forEach((button) => {
      button.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
      button.setAttribute("title", collapsed ? "Expand sidebar" : "Collapse sidebar");
    });
  };

  try {
    setSidebarCollapsed(localStorage.getItem(sidebarKey) === "1");
  } catch (_) {}

  document.addEventListener("click", (event) => {
    const toggle = event.target.closest("[data-sidebar-toggle]");
    if (toggle) setSidebarCollapsed(!root.classList.contains("sidebar-collapsed"));
    if (event.target.closest("[data-sidebar-open]")) root.classList.add("sidebar-open");
    if (event.target.closest("[data-sidebar-close]")) root.classList.remove("sidebar-open");

    const copyButton = event.target.closest("[data-copy-target], [data-copy-text]");
    if (copyButton) copyText(copyButton);

    const messageLink = event.target.closest("[data-message-row] .subject");
    if (messageLink) {
      document.querySelectorAll("[data-message-row].selected").forEach((row) => {
        row.classList.remove("selected");
        row.querySelector(".subject")?.removeAttribute("aria-current");
      });
      messageLink.closest("[data-message-row]").classList.add("selected");
      messageLink.setAttribute("aria-current", "true");
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && root.classList.contains("sidebar-open")) {
      root.classList.remove("sidebar-open");
      document.querySelector("[data-sidebar-open]")?.focus();
      return;
    }
    if (event.key !== "/" || event.ctrlKey || event.metaKey || event.altKey) return;
    const tag = document.activeElement && document.activeElement.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    const query = document.querySelector("#query");
    if (query) {
      event.preventDefault();
      query.focus();
    }
  });

  document.addEventListener("change", (event) => {
    const folder = event.target.closest("[data-search-folder]");
    if (!folder) return;
    const form = folder.closest("form");
    if (form) form.requestSubmit();
  });

  document.body.addEventListener("htmx:afterSwap", (event) => {
    hideNotice();
    if (event.detail.target && event.detail.target.id === "reading-pane-content") {
      const pane = event.detail.target.closest(".reading-pane");
      if (pane) pane.scrollTop = 0;
      if (matchMedia("(max-width: 860px)").matches) {
        const behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
        event.detail.target.scrollIntoView({ block: "start", behavior });
      }
    } else if (event.detail.target && event.detail.target.id === "results") {
      const readingPane = document.querySelector("#reading-pane-content");
      const emptyTemplate = document.querySelector("#reader-empty-template");
      if (readingPane && emptyTemplate) readingPane.replaceChildren(emptyTemplate.content.cloneNode(true));
    }
  });

  document.body.addEventListener("htmx:beforeRequest", (event) => {
    hideNotice();
    event.detail.target?.setAttribute("aria-busy", "true");
  });

  document.body.addEventListener("htmx:afterRequest", (event) => {
    event.detail.target?.removeAttribute("aria-busy");
    if (event.detail.failed) showNotice("The request could not be completed. Your mail was not changed.");
  });

  document.body.addEventListener("htmx:sendError", () => {
    showNotice("The local notmuch browser is unreachable. Check the service or SSH tunnel.");
  });

  document.body.addEventListener("htmx:timeout", () => {
    showNotice("The request timed out. Try again after the current mail refresh finishes.");
  });

  document.querySelectorAll("[data-split-workspace]").forEach(setupSplitter);

  function setupSplitter(workspace) {
    const divider = workspace.querySelector("[data-pane-divider]");
    if (!divider) return;
    let percent = 35;
    try {
      percent = clamp(Number(localStorage.getItem(splitKey)) || 35, 25, 70);
    } catch (_) {}

    const apply = (value, persist) => {
      percent = clamp(value, 25, 70);
      workspace.style.setProperty("--result-pane-height", `${percent}%`);
      divider.setAttribute("aria-valuenow", String(Math.round(percent)));
      if (persist) {
        try {
          localStorage.setItem(splitKey, String(percent));
        } catch (_) {}
      }
    };
    apply(percent, false);

    divider.addEventListener("pointerdown", (event) => {
      if (matchMedia("(max-width: 860px)").matches) return;
      divider.setPointerCapture(event.pointerId);
      root.classList.add("resizing-panes");
    });
    divider.addEventListener("pointermove", (event) => {
      if (!divider.hasPointerCapture(event.pointerId)) return;
      const bounds = workspace.getBoundingClientRect();
      apply(((event.clientY - bounds.top) / bounds.height) * 100, false);
    });
    const finish = (event) => {
      if (divider.hasPointerCapture(event.pointerId)) divider.releasePointerCapture(event.pointerId);
      root.classList.remove("resizing-panes");
      apply(percent, true);
    };
    divider.addEventListener("pointerup", finish);
    divider.addEventListener("pointercancel", finish);
    divider.addEventListener("keydown", (event) => {
      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        event.preventDefault();
        apply(percent + (event.key === "ArrowUp" ? -2 : 2), true);
      } else if (event.key === "Home" || event.key === "End") {
        event.preventDefault();
        apply(event.key === "Home" ? 25 : 70, true);
      }
    });
  }

  async function copyText(button) {
    let value = button.dataset.copyText;
    if (value === undefined) {
      const target = document.querySelector(button.dataset.copyTarget);
      if (!target) return;
      value = target.textContent.trim();
    }
    try {
      await navigator.clipboard.writeText(value);
    } catch (_) {
      const area = document.createElement("textarea");
      area.value = value;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      document.execCommand("copy");
      area.remove();
    }
    button.classList.add("copied");
    const requestedDuration = Number(button.dataset.copyFeedbackMs) || 1200;
    const feedbackDuration = Math.min(5000, Math.max(1200, requestedDuration));
    setTimeout(() => button.classList.remove("copied"), feedbackDuration);
  }
})();
