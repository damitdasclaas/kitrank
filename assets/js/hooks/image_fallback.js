// Ein abgeleitetes Vorschaubild kann fehlen: Shopware legt nicht für jedes
// Produkt jede Größenstufe an, und ein Shop kann seine Adressen umbauen. Dann
// einmal auf die Original-Adresse zurückfallen — und wenn die auch nicht kommt,
// das Bild ausblenden, damit die gezeichnete Silhouette dahinter sichtbar wird.
// Ein kaputtes Bildsymbol ist das schlechteste der drei Ergebnisse.
//
// Das ist der Grund, warum Kitrank.Kits.ImageVariant kein srcset benutzt: dort
// wählt der Browser eine Adresse und scheitert still, ohne Rückfall.
export default {
  mounted() {
    this.onError = () => {
      const original = this.el.dataset.original

      if (original && this.el.getAttribute("src") !== original) {
        this.el.setAttribute("src", original)
      } else {
        this.el.style.display = "none"
      }
    }

    this.el.addEventListener("error", this.onError)

    // Schon fehlgeschlagen, bevor der Hook lief — passiert bei Bildern aus dem
    // Cache und beim ersten Rendern nach dem Verbinden. Ohne diese Zeile
    // bleibt so ein Bild kaputt, weil das error-Ereignis längst durch ist.
    if (this.el.complete && this.el.naturalWidth === 0) this.onError()
  },

  destroyed() {
    this.el.removeEventListener("error", this.onError)
  },
}
