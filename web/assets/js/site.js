// site.js — comportamento mínimo do site do msbos.
// Sem dependências: menu móvel, estado do cabeçalho, botões de copiar do código
// e destaque do sumário conforme a rolagem.

(() => {
  "use strict";

  const header = document.querySelector("[data-header]");
  const menuBtn = document.querySelector("[data-menu]");
  const nav = document.getElementById("menu");

  // ─── menu móvel ─────────────────────────────────────────────────────────
  if (menuBtn && nav) {
    const close = () => {
      nav.classList.remove("is-open");
      menuBtn.setAttribute("aria-expanded", "false");
    };
    menuBtn.addEventListener("click", () => {
      const open = nav.classList.toggle("is-open");
      menuBtn.setAttribute("aria-expanded", String(open));
    });
    nav.addEventListener("click", (e) => {
      if (e.target.closest("a")) close();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") close();
    });
    document.addEventListener("click", (e) => {
      if (!nav.contains(e.target) && !menuBtn.contains(e.target)) close();
    });
  }

  // ─── cabeçalho com sombra ao rolar ──────────────────────────────────────
  if (header) {
    const sync = () => header.classList.toggle("is-scrolled", window.scrollY > 4);
    sync();
    window.addEventListener("scroll", sync, { passive: true });
  }

  // ─── copiar código ──────────────────────────────────────────────────────
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const block = btn.closest(".codeblock");
      const code = block && block.querySelector("pre code");
      if (!code) return;
      const text = code.innerText;
      const label = btn.dataset.label || btn.textContent.trim();
      if (!btn.dataset.label) btn.dataset.label = label;
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = btn.dataset.done || "ok";
        btn.classList.add("is-done");
      } catch {
        // clipboard bloqueado (contexto não seguro): seleciona o texto
        const range = document.createRange();
        range.selectNodeContents(code);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
      setTimeout(() => {
        btn.textContent = label;
        btn.classList.remove("is-done");
      }, 1600);
    });
  });

  // ─── sumário ativo conforme a seção visível ─────────────────────────────
  const toc = document.querySelector(".toc");
  if (toc) {
    const links = Array.from(toc.querySelectorAll('a[href^="#"]'));
    const targets = links
      .map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))))
      .filter(Boolean);
    if (targets.length) {
      let active = null;
      const setActive = (id) => {
        if (id === active) return;
        active = id;
        links.forEach((a) => {
          a.classList.toggle("is-active", decodeURIComponent(a.hash.slice(1)) === id);
        });
      };
      const observer = new IntersectionObserver(
        (entries) => {
          const visible = entries
            .filter((e) => e.isIntersecting)
            .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
          if (visible.length) setActive(visible[0].target.id);
        },
        { rootMargin: "-80px 0px -70% 0px", threshold: 0 }
      );
      targets.forEach((t) => observer.observe(t));
    }
  }
})();
