// Kopiert den Share-Link in die Zwischenablage und bestaetigt es kurz am
// Knopf selbst – ohne Flash-Nachricht, die man erst suchen muesste.
export default {
  mounted() {
    this.el.addEventListener("click", async () => {
      const value = this.el.dataset.copy
      if (!value) return

      try {
        await navigator.clipboard.writeText(value)
        this.confirm("Kopiert")
      } catch {
        // Ohne Clipboard-Recht (z. B. ueber http auf einem anderen Geraet)
        // bleibt der Link sichtbar daneben stehen – dann markiert man ihn eben.
        this.confirm("Kopieren nicht erlaubt")
      }
    })
  },

  confirm(message) {
    const label = this.el.querySelector("[data-copy-label]")
    if (!label) return

    const original = label.textContent
    label.textContent = message
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (label.textContent = original), 1800)
  },
}
