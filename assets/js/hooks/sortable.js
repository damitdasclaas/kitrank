import Sortable from "../../vendor/sortable"

// Drag-Sortierung der Rangliste.
//
// Der Hook schickt nach dem Loslassen die komplette neue Reihenfolge an den
// Server – nicht "Element X von 3 nach 1". Der Server kann die Liste damit
// gegen seinen Stand prüfen und im Zweifel ablehnen, statt eine Verschiebung
// auf einen Stand anzuwenden, den der Browser vielleicht gar nicht mehr hat.
export default {
  mounted() {
    this.sortable = new Sortable(this.el, {
      animation: 150,
      handle: "[data-drag-handle]",
      draggable: "[data-kit-id]",
      ghostClass: "opacity-40",
      dragClass: "shadow-xl",
      // Auf dem Handy soll ein normaler Wisch die Seite scrollen und nicht
      // versehentlich die Rangliste umsortieren.
      delay: 120,
      delayOnTouchOnly: true,
      touchStartThreshold: 4,
      onEnd: () => {
        const ids = Array.from(this.el.querySelectorAll("[data-kit-id]"))
          .map((el) => el.dataset.kitId)

        this.pushEvent("reorder", { kit_ids: ids })
      },
    })
  },

  destroyed() {
    this.sortable?.destroy()
  },
}
