# Arbeitsregeln für Claude Code – Handslice

Du arbeitest hier oft **unbeaufsichtigt** (Klaus ist tagsüber nicht am Rechner).
Diese Regeln sind kurz, damit sie auch nach Stunden noch gelten. Lies sie bei
jedem Start.

## 1. Haltung

- Ein **ehrlich gemeldeter Blocker** ist ein wertvolleres Ergebnis als ein
  grüner Build, der nichts beweist. Fehler sind erwünschte Befunde, keine
  Niederlagen.
- "Fertig" heißt: **das Erfolgskriterium der Phase ist nachweislich erfüllt**
  (siehe README, Tabelle Phasen) – nicht "kompiliert" oder "sollte gehen".
- Keine Workarounds, die ein Problem verstecken. Wenn einer unvermeidbar ist:
  mit Begründung in `docs/blockers.md`, und im Code markiert mit
  `// WORKAROUND(blockers#N):`.

## 2. Was du darfst / nicht darfst

- Schreiben nur **innerhalb dieses Projektordners** und dessen Build-Caches.
  Keine Änderungen an System, Dotfiles oder anderen Repos.
- **Keine Tests ändern oder abschwächen**, um sie grün zu bekommen. Keine
  Fehler schlucken (`catch {}` ohne Weitergabe).
- Keine Engine-Patches aus Hersteller-Forks (ElegooSlicer, Creality …)
  übernehmen. Engine-Quelle ist ausschließlich OrcaSlicer-Upstream.
- Nichts auf GitHub pushen, keine Releases, keine Tags – das macht Klaus.
- Das Testgerät (Poco X3 Pro, per ADB) darfst du frei nutzen: installieren,
  starten, Logs ziehen, Dateien kopieren, zurücksetzen von App-Daten.
  **Kein** Factory-Reset, kein Flashen, keine Systemeinstellungen.

## 3. Drei-Versuche-Regel

Nach **drei gescheiterten Korrekturversuchen am selben Fehler**: stoppen.
Hypothesen in `docs/blockers.md` schreiben (was probiert, was beobachtet,
was vermutet), Eintrag in `PROGRESS.md`, dann **Rückfrage stellen** statt
eines vierten Versuchs.

## 4. Protokoll

- `PROGRESS.md` nach jedem größeren Schritt ergänzen (Datum, Uhrzeit, was
  gemacht, Ergebnis). Kurz. Das ist Klaus' einziges Fenster tagsüber.
- Jeder Abschlussbericht hat **genau drei Rubriken**:
  1. **Nachweislich funktioniert** – mit dem Befehl, der es beweist.
  2. **Ungeprüft** – gebaut, aber nicht auf dem Gerät/gegen das Kriterium
     getestet.
  3. **Geht nicht** – mit Verweis auf `docs/blockers.md`.

## 5. Technische Konventionen

- Build-Rechner: AMR5 (Ryzen 7 5800U, 32 GB, CachyOS). Arbeits- und
  Build-Verzeichnisse siehe `docs/test-setup.md`.
- Toolchain-Versionen (NDK, Flutter/Kotlin, CMake) beim ersten Einrichten in
  `docs/test-setup.md` eintragen und danach **nicht stillschweigend wechseln**.
- Orca-Upstream als Git-Submodul unter `engine/OrcaSlicer`, auf einen
  **festen Tag** gepinnt. Tag-Wechsel nur nach Absprache.
- Alle sichtbaren Texte (UI, Fehlermeldungen, Buttons) von Anfang an über
  die Lokalisierungsmechanik des UI-Stacks (Flutter: ARB-Dateien unter
  `app/lib/l10n/`; Compose: `strings.xml`), **nie fest im Code**.
  Quellsprache Englisch, erste Übersetzung Deutsch. Weitere Sprachen kommen
  später über dieselben Dateien dazu – das ist ein erklärtes Projektziel.
- UI vollständig per Fokus-Navigation (Tastatur, D-Pad, Controller)
  bedienbar; keine Touch-only-Elemente außerhalb des 3D-Viewports. Grund:
  Barrierefreiheit und Nebeneffekt Android TV / Tablets mit Tastatur.
- Commits klein und beschreibend, deutsch oder englisch – egal, aber
  konsistent pro Commit. Jeder Commit baut.

## 6. Bei Unsicherheit

Lieber eine Frage in `PROGRESS.md` hinterlassen und weiter an etwas anderem
arbeiten, als eine Annahme stillschweigend einzubauen. Wenn nichts anderes
sinnvoll weitergeht: stoppen und auf Antwort warten.
