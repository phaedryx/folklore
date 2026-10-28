// Buttons with data-clipboard-source="<selector>" copy that element's text.
function wireClipboardButtons() {
  document.querySelectorAll("[data-clipboard-source]").forEach((btn) => {
    if (btn.dataset.clipboardWired === "1") return;
    btn.dataset.clipboardWired = "1";

    btn.addEventListener("click", async () => {
      const target = document.querySelector(btn.dataset.clipboardSource);
      if (!target) return;

      const text = (target.innerText || target.textContent || "").trim();
      const originalLabel = btn.dataset.clipboardLabel || btn.textContent;
      btn.dataset.clipboardLabel = originalLabel;

      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = "Copied!";
      } catch (_err) {
        btn.textContent = "Copy failed, select manually";
      }

      setTimeout(() => { btn.textContent = originalLabel; }, 1800);
    });
  });
}

document.addEventListener("turbo:load", wireClipboardButtons);
document.addEventListener("DOMContentLoaded", wireClipboardButtons);
