// Ranglisten im Browser merken.
//
// Der Bearbeiten-Link ist der einzige Weg zurueck zu einer Rangliste. Wer den
// Tab schliesst, ohne ihn zu sichern, kommt nicht mehr an seine Liste. Deshalb
// merkt sich der Browser die Links – der Link bleibt aber der eigentliche
// Zugriffsweg, etwa beim Geraetewechsel.
//
// Bewusst nur localStorage und kein Cookie: der Token soll nicht bei jedem
// Request mitgeschickt werden.

const KEY = "kitrank:rankings"
const LIMIT = 20

function read() {
  try {
    const raw = localStorage.getItem(KEY)
    const list = raw ? JSON.parse(raw) : []
    return Array.isArray(list) ? list.filter((e) => e && e.token) : []
  } catch {
    return []
  }
}

function write(list) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list.slice(0, LIMIT)))
  } catch {
    // Privater Modus oder volles Kontingent – dann eben nicht merken.
  }
}

// Auf der Bearbeiten-Seite: Rangliste aufnehmen bzw. Namen aktualisieren.
export const RememberRanking = {
  mounted() { this.remember() },
  updated() { this.remember() },

  remember() {
    const { token, slug, name } = this.el.dataset
    if (!token) return

    const rest = read().filter((e) => e.token !== token)
    write([{ token, slug, name: name || "", seen: Date.now() }, ...rest])
  },
}

// Auf der Uebersichtsseite: gemerkte Ranglisten an den Server geben, damit er
// sie nachschlagen und anzeigen kann. Geloeschte fliegen dabei wieder raus.
export const RememberedRankings = {
  mounted() {
    this.pushEvent("remembered_rankings", { tokens: read().map((e) => e.token) })

    this.handleEvent("forget_ranking", ({ token }) => {
      write(read().filter((e) => e.token !== token))
    })

    this.handleEvent("prune_rankings", ({ keep }) => {
      const behalten = new Set(keep)
      write(read().filter((e) => behalten.has(e.token)))
    })
  },
}

// Host-Token eines Reveal-Raums.
//
// Steht bewusst nicht in der Adresse: geteilt wird der Raumcode, und wer eine
// URL mit Host-Token weitergibt, wuerde ungewollt die Steuerung mitgeben.
// Geraetewechsel loest stattdessen die Uebergabe im Raum.

const ROOMS = "kitrank:rooms"

function readRooms() {
  try {
    const raw = localStorage.getItem(ROOMS)
    const map = raw ? JSON.parse(raw) : {}
    return map && typeof map === "object" ? map : {}
  } catch {
    return {}
  }
}

function writeRooms(map) {
  try {
    localStorage.setItem(ROOMS, JSON.stringify(map))
  } catch {
    // Kein Speicher – dann bleibt der Host nur fuer diese Sitzung Host.
  }
}

export const RememberHost = {
  mounted() {
    const { code, hostToken } = this.el.dataset
    if (!code || !hostToken) return

    writeRooms({ ...readRooms(), [code]: hostToken })
  },
}

export const ClaimHost = {
  mounted() {
    const code = this.el.dataset.code
    const token = readRooms()[code]
    if (token) this.pushEvent("claim_host", { token })

    this.handleEvent("forget_host", ({ code }) => {
      const map = readRooms()
      delete map[code]
      writeRooms(map)
    })
  },
}
