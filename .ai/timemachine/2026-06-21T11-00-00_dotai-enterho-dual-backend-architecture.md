# Timemachine: .ai + .enterHo — Dual-Backend-Architektur

**Zeitpunkt:** 2026-06-21T11:00 CEST
**Status:** Konzept, noch nicht implementiert — NICHT VERLIEREN

---

## Die Kernidee: Zwei Backends, ein Pattern

Beide Ordner (`.ai/` und `.enterHo/`) sollen **zwei austauschbare Backends**
unterstützen, die denselben inhaltlichen Job machen — aber für verschiedene
Zielgruppen und Reifegrade:

```
Backend A: "Timemachined Dated Folders"
  → Verzeichnisse mit Zeitstempel-Namen
  → Kein git nötig
  → Menschlich lesbar, auch für KI-Modelle ohne git-Verständnis
  → Einstieg für Anfänger
  → Brücke zur Versionierungswelt

Backend B: "Git-Server" (Forgejo/Gitea lokal)
  → Vollständige Versionierung
  → Kurzgedächtnis via Commits (täglich/sessionweise)
  → Übergang zur "Traumwelt" via Tags/Milestones
  → Bessere "Traumhygiene" (saubere, reflektierbare Geschichte)
```

---

## Backend A: Timemachined Dated Folders

### Struktur

```
.ai/
├── context.md                          # Aktueller Stand (immer überschreiben)
└── timemachine/
    ├── 2026-06-15T14-30-00_thema.md    # Session-Snapshot
    ├── 2026-06-18T09-00-00_thema.md
    └── 2026-06-21T11-00-00_thema.md    # ← heute

.enterHo/
└── timemachine/
    ├── 2026-06-15T14-30-00_cache-state.md  # Was war gecacht, warum
    └── 2026-06-21T11-00-00_cache-state.md
```

### Warum dieses Backend wichtig bleibt (auch nach git-Umstieg)

1. **Zugänglichkeit:** Verzeichnisse + Dateien verstehen alle —
   Menschen, KI-Modelle, Skripte — ohne git-Wissen.

2. **Einstiegspunkt:** Wer git noch nicht kennt, kann trotzdem
   mit Zeitstempel-Ordnern arbeiten und seine Arbeit strukturieren.
   Dated Folders sind die "Fahrradstabilisatoren" vor dem git-Fahrrad.

3. **Sanfte Annäherung:** Das Pattern *erklärt git* ohne es vorauszusetzen:
   - "Was wir hier machen, macht git automatisch"
   - "Jeder Commit ist wie ein Timemachine-Folder — aber komprimiert"

4. **Meilenstein-Reflexion:** Auch nach git-Umstieg bleiben große Würfe
   als dated Snapshots erhalten — *und* als git-Tag gespiegelt.
   Man kann sehen: "Was hatte ich am 2026-06-15 schon alles erreicht?"
   ohne git log zu verstehen.

5. **Verlust-Detektion:** Wenn Errungenschaften in einem späteren
   git-State fehlen, sieht man im Timemachine-Folder was es mal gab.

---

## Backend B: Lokaler Git-Server (Forgejo/Gitea)

### Rolle

```
Lokaler Forgejo (NAS)
  ├── .ai/ als eigenes Repo oder Branch
  │   ├── Commits = Session-Grenzen
  │   ├── Tags = Meilensteine / große Würfe
  │   └── main = aktueller Kontext
  └── .enterHo/ als eigenes Repo
      ├── Commits = Cache-State-Wechsel
      └── Kein Sync nach GitHub
```

### Traumhygiene mit git

"Traumhygiene" = die Fähigkeit, die eigene Arbeitsgeschichte klar
zu sehen, zu reflektieren und bewusst weiterzuführen.

Git-Server ermöglicht bessere Traumhygiene als dated Folders weil:
- **Kurzgedächtnis:** Commits der letzten Sessions direkt sichtbar
- **Übergang in die Traumwelt:** Ein Tag markiert "das war ein großer
  Meilenstein" — wie ein Kapitel-Ende
- **Diff-fähig:** Was hat sich seit letzter Woche verändert?
- **Wiederherstellbar:** `git checkout <tag>` zeigt exakten Zustand

---

## Zusammenspiel beider Backends

```
Dated Folder (immer)          Git-Server (wenn vorhanden)
─────────────────────         ────────────────────────────
Snapshot schreiben      ──→   git commit -m "session: <thema>"
                              (oder: Skript synct Folder → Commit)

Großer Wurf erkannt     ──→   git tag v1.0-meilenstein-<name>
                         UND  Folder bleibt als Referenz erhalten

Rückblick               ──→   git log --oneline ODER
                              ls .ai/timemachine/ | sort

Verlust-Detektion       ──→   diff zwischen Timemachine-Folder
                         UND  git diff <alter-tag> HEAD
```

### Sync-Skript (Idee, nicht implementiert)

```sh
# .ai/timemachine → git commit
# Läuft am Ende jeder Session oder via Cron
kl_ai_commit_session() {
    local msg="${1:-session: $(date +%Y-%m-%d)}"
    cd "$(git -C ~/.ai rev-parse --show-toplevel 2>/dev/null || echo '')"
    [ -z "$(git status --porcelain)" ] && return 0
    git add -A
    git commit -m "$msg"
    git push forgejo main 2>/dev/null || true  # lokal, kein GitHub
}
```

---

## Zielgruppen-Matrix

| Zielgruppe | Backend | Was sie sehen |
|---|---|---|
| Anfänger (kein git) | Dated Folders | Zeitgestempelte Ordner, plain Markdown |
| KI-Modell ohne git | Dated Folders | Verzeichnislisting + Dateiinhalt |
| Entwickler mit git | Git-Server | `git log`, `git diff`, Tags |
| KI-Modell mit git | Beide | Folder als Quick-Context, git für Details |
| Reflexion / Review | Beide | Folder für "was war damals", git für Diff |

---

## Namens-Entscheidungen (noch offen)

- `.ai/timemachine/` — klar, sprechend, kein Konflikt mit Apple Time Machine
- `.enterHo/timemachine/` — analog, aber: braucht `.enterHo/` ein timemachine?
  Oder reicht der XDG_CACHE-Pfad + git-Versionierung?
- **Alternativ:** `.enterHo/` heißt eigentlich
  `~/.cache/kl-input-cache/<repo-hash>/` — vielleicht ist das dated-Folder-
  Backend hier weniger relevant als bei `.ai/`?

---

## Offene Fragen

- [ ] Soll `.enterHo/timemachine/` automatisch nach jedem `kl_read_cached`-Call
  einen Snapshot schreiben? (Wäre sehr viel Output)
- [ ] Soll der Sync Folder→git-Commit automatisch laufen (Cron, post-commit
  Hook) oder manuell getriggert werden?
- [ ] Wie groß darf ein Timemachine-Folder werden, bevor wir archivieren?
  (Oder: git-Tags als natürliche Archivgrenze nutzen)
- [ ] Soll ein git-Tag automatisch erstellt werden wenn ein Timemachine-
  Snapshot "als Meilenstein" markiert wird? (Frontmatter-Flag: `milestone: true`)
