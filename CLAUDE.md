# Arbeitsregeln für Claude Code – Handslice

Du arbeitest hier oft **unbeaufsichtigt** (Klaus ist tagsüber nicht am Rechner).
Lies diese Regeln bei jedem Start. Begründungen und Beispiele:
`docs/claude-rules-background.md`.

## 1. Haltung

- Ein **ehrlich gemeldeter Blocker** ist wertvoller als ein grüner Build, der
  nichts beweist. Fehler sind erwünschte Befunde, keine Niederlagen.
- "Fertig" heißt: **das Erfolgskriterium der Phase ist nachweislich erfüllt**
  (README, Tabelle Phasen) – nicht "kompiliert" oder "sollte gehen".
- Keine Workarounds, die ein Problem verstecken. Wenn unvermeidbar: Begründung
  in `docs/blockers.md`, im Code markiert mit `// WORKAROUND(blockers#N):`.

## 2. Was du darfst / nicht darfst

- Schreiben nur **innerhalb dieses Projektordners** und dessen Build-Caches.
  Keine Änderungen an System, Dotfiles oder anderen Repos.
- **Keine Tests ändern oder abschwächen**, um sie grün zu bekommen. Keine
  Fehler schlucken (`catch {}` ohne Weitergabe).
- Keine Engine-Patches aus Hersteller-Forks (ElegooSlicer, Creality …).
  Engine-Quelle ist ausschließlich OrcaSlicer-Upstream.
- Nichts auf GitHub pushen, keine Releases, keine Tags – das macht Klaus.
- Testgerät (Poco X3 Pro, per ADB) frei nutzbar: installieren, starten, Logs
  ziehen, Dateien kopieren, App-Daten zurücksetzen. **Kein** Factory-Reset,
  kein Flashen, keine Systemeinstellungen.
- **Drucker:** Niemals selbst `method 1020` (Druckstart) an den echten Drucker
  senden. Drucke startet ausschließlich Klaus, nach eigener Sichtprüfung, in
  der App oder am Gerät. Schreibende oder löschende Methoden am Drucker nur,
  wenn Klaus anwesend ist und den einzelnen Test ausdrücklich freigibt.
  Lesende Abfragen sind erlaubt.
- **Testmodelle:** Fremde Modelle (z. B. das große organische Testmodell,
  CULTS „Private Use"/„No AI") und die Stanford-Modelle Dragon, Happy Buddha
  und Lucy bleiben lokal unter `local-test/`: nie committen, nie an externe
  Dienste schicken; berichtet werden nur Messwerte. Der Stanford Bunny als
  vorhandenes Test-Asset bleibt, wie er ist.
- **Modellnamen:** In öffentlichen Texten an Dritte (Upstream-Issues, PRs,
  Commits in Fremd-Repos, `docs/upstream/`) kein Modellname außer „Stanford
  Bunny"; dort heißt es „large third-party organic test model". In Handslices
  eigener Doku ist der Name erlaubt (Entscheidung Klaus).
- **Zugangsdaten (Access-Code, SN, IP, Tokens, Passwörter) tauchen in keinem
  Bericht, keinem stdout, keiner Doku-Datei auf** – auch nicht als Suchmuster
  in grep-Verifikationen oder auf der Kommandozeile. Scrub-Scripts lesen den
  Wert intern aus `.env`, greppen stumm und melden nur „N Treffer" (bei 0 ist
  der Scrub erfolgreich).

## 3. Drei-Versuche-Regel

Nach **drei gescheiterten Korrekturversuchen am selben Fehler**: stoppen.
Hypothesen in `docs/blockers.md` (was probiert, beobachtet, vermutet), Eintrag
in `PROGRESS.md`, dann **Rückfrage stellen** statt eines vierten Versuchs.

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
  Build-Verzeichnisse: `docs/test-setup.md`.
- Toolchain-Versionen (NDK, Flutter/Kotlin, CMake) beim ersten Einrichten in
  `docs/test-setup.md` eintragen und danach **nicht stillschweigend wechseln**.
- Orca-Upstream als Git-Submodul unter `engine/OrcaSlicer`, auf einen
  **festen Tag** gepinnt. Tag-Wechsel nur nach Absprache.
- Große Ausgaben (Build, Valgrind, Testläufe) immer in eine Datei unter
  `local-test/` umleiten und nur Zusammenfassung, grep oder tail lesen. Lange
  Läufe mit `setsid nohup` im Hintergrund starten und nicht abfragen; kein
  ScheduleWakeup, kein /loop.
- Alle sichtbaren Texte (UI, Fehlermeldungen, Buttons) von Anfang an über die
  Lokalisierungsmechanik des UI-Stacks (Flutter: ARB-Dateien unter
  `app/lib/l10n/`; Compose: `strings.xml`), **nie fest im Code**. Quellsprache
  Englisch, erste Übersetzung Deutsch. Weitere Sprachen kommen später über
  dieselben Dateien dazu – erklärtes Projektziel.
- UI vollständig per Fokus-Navigation (Tastatur, D-Pad, Controller) bedienbar;
  keine Touch-only-Elemente außerhalb des 3D-Viewports.
- Commits klein und beschreibend. Jeder Commit baut.
- **Ab 2026-10-31 ist Englisch die Projektsprache** für **neue**
  Commit-Messages, **neue** PROGRESS.md-Einträge und **neue** Doku-Dateien
  bzw. -Abschnitte. Bestehende deutsche Commits und PROGRESS-Einträge bleiben
  – keine History-Rewrites für die Sprachumstellung. CLAUDE.md und die
  handgeschriebenen deutschen Doku-Teile bleiben deutsch, bis Klaus sie selbst
  umstellt.
- **Co-Authored-By-Trailer:** Ab 2026-11-02 endet jede von Claude erzeugte
  Commit-Message mit `Co-Authored-By: Claude <noreply@anthropic.com>` (Trailer
  am Ende, leere Zeile davor). Gilt für alle neuen Commits im Hauptrepo und im
  Submodul; bereits gepushte Commits werden nicht verändert.

## 6. Bei Unsicherheit

Lieber eine Frage in `PROGRESS.md` hinterlassen und an etwas anderem
weiterarbeiten, als eine Annahme stillschweigend einzubauen. Wenn nichts
anderes sinnvoll weitergeht: stoppen und auf Antwort warten.
