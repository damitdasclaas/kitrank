// Rückfall für Bilder, die nicht kommen.
//
// Ein abgeleitetes Vorschaubild kann fehlen: Shops legen nicht für jedes
// Produkt jede Größenstufe an, und Adressen ändern sich. Dann einmal auf das
// Original zurückfallen — und wenn das auch nicht kommt, das Bild ausblenden,
// damit die gezeichnete Silhouette dahinter sichtbar wird. Ein kaputtes
// Bildsymbol ist das schlechteste der drei Ergebnisse.
//
// Ein Hook für die ganze Seite, nicht einer pro Bild. Der erste Versuch hatte
// ein phx-hook am <img> und brauchte dafür eine ID — die war mit
// System.unique_integer bei jedem Rendern anders, also schickte LiveView bei
// jeder Eingabe achtzehn geänderte IDs, ersetzte jedes Bild im DOM und
// montierte jeden Hook neu. Das Diffing war damit ausgeschaltet und jede
// Eingabe teuer.
//
// error-Ereignisse von Bildern steigen nicht auf, laufen aber durch die
// Capture-Phase. Ein Zuhörer am Container erreicht sie deshalb alle, ohne dass
// ein einzelnes Bild etwas davon wissen muss.
export default {
  mounted() {
    this.onError = (ereignis) => {
      const el = ereignis.target

      if (!el || el.tagName !== "IMG") return

      const original = el.dataset.original

      if (original && el.getAttribute("src") !== original) {
        el.setAttribute("src", original)
      } else {
        el.style.display = "none"
      }
    }

    this.el.addEventListener("error", this.onError, true)
  },

  destroyed() {
    this.el.removeEventListener("error", this.onError, true)
  },
}
