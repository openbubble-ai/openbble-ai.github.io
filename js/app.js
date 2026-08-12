// OpenBubble Clone — minimal interactivity

(function () {
  // ---------- Auto theme: follows the user's OS color scheme ----------
  // The site uses CSS custom properties keyed off [data-theme="dark"].
  // We set/remove that attribute based on the prefers-color-scheme media query.
  const root = document.documentElement;
  const mql = window.matchMedia("(prefers-color-scheme: dark)");

  const applyTheme = (isDark) => {
    if (isDark) root.setAttribute("data-theme", "dark");
    else root.removeAttribute("data-theme");
  };

  applyTheme(mql.matches);
  // Modern browsers
  if (mql.addEventListener) mql.addEventListener("change", (e) => applyTheme(e.matches));
  // Safari < 14 fallback
  else if (mql.addListener) mql.addListener((e) => applyTheme(e.matches));

  // ---------- Tabs (install commands) ----------
  document.querySelectorAll("[data-tabs]").forEach((group) => {
    const tabs = group.querySelectorAll(".tab");
    const panels = group.querySelectorAll(".tab-panel");
    tabs.forEach((tab, i) => {
      tab.addEventListener("click", () => {
        tabs.forEach((t) => t.classList.remove("is-active"));
        panels.forEach((p) => p.classList.remove("is-active"));
        tab.classList.add("is-active");
        panels[i].classList.add("is-active");
      });
    });
  });

  // ---------- Copy buttons ----------
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.getAttribute("data-copy");
      try {
        await navigator.clipboard.writeText(text);
        const original = btn.textContent;
        btn.textContent = "copied";
        setTimeout(() => (btn.textContent = original), 1200);
      } catch (_) {
        // no-op
      }
    });
  });

  // ---------- Waitlist form ----------
  const form = document.querySelector("[data-waitlist]");
  if (form) {
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const input = form.querySelector("input[type=email]");
      const status = form.querySelector("[data-status]");
      if (!input.value) return;
      status.textContent = "You're on the list. We'll be in touch.";
      input.value = "";
    });
  }

  // ---------- Docs TOC scrollspy ----------
  const tocLinks = document.querySelectorAll(".docs-toc a");
  if (tocLinks.length) {
    const map = new Map();
    tocLinks.forEach((a) => {
      const id = a.getAttribute("href").slice(1);
      const el = document.getElementById(id);
      if (el) map.set(el, a);
    });
    const onScroll = () => {
      let current = null;
      map.forEach((_, el) => {
        if (el.getBoundingClientRect().top < 120) current = el;
      });
      tocLinks.forEach((a) => a.classList.remove("is-active"));
      if (current && map.get(current)) map.get(current).classList.add("is-active");
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }
})();
