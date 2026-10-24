# Build-Rechner & Testgerät

## Build-Rechner: AMR5

- Ryzen 7 5800U (8C/16T), 32 GB DDR4, CachyOS (Triple-Boot – nur CachyOS
  wird genutzt).
- Dauerhaft am Strom und im LAN. Standby/Suspend aus, Festplatten-Schlaf aus.
- Mindestens 60–80 GB frei auf der CachyOS-Partition (SDK, NDK, Orca-Quellen
  mit Deps, Build-Verzeichnisse).
- Fernzugriff fürs Reinschauen tagsüber: SSH über Tailscale oder WireGuard
  (vom Handy aus `cat PROGRESS.md`).

### Toolchain (beim Einrichten eintragen, danach nicht stillschweigend ändern)

| Komponente | Version | Pfad |
|---|---|---|
| Android SDK | – | – |
| Android NDK | – | – |
| CMake | – | – |
| Flutter / Kotlin | – (nach UI-Entscheidung) | – |
| OrcaSlicer-Tag (Submodul) | – | `engine/OrcaSlicer` |
| Desktop-Orca (Referenz, AppImage) | – muss zum Tag passen | – |

## Testgerät: Poco X3 Pro

- Snapdragon 860 (4× Cortex-A76 + 4× A55, ARM64), 6/8 GB RAM.
- Stock-MIUI, Originalzustand. Android-Version: _eintragen_.
- SIM entfernt. Wird nach Projektende zurückgesetzt – App-Daten dürfen frei
  angelegt und gelöscht werden.

### Vorbereitung (Klaus, einmalig)

1. Einstellungen → Über das Telefon → 7× auf „MIUI-Version" tippen.
2. Zusätzliche Einstellungen → Entwickleroptionen → **USB-Debugging** an,
   **Bildschirm bleibt aktiv beim Laden** an, **USB-Debugging (Sicherheits-
   einstellungen)** an (MIUI-spezifisch, sonst keine Eingabe per ADB).
3. Akku & Leistung → App-Akkusparen → Handslice-App später auf „Keine
   Einschränkungen".
4. Per USB an den AMR5, Debugging-Abfrage am Handy mit „Immer erlauben"
   bestätigen.
5. Prüfen: `adb devices` zeigt das Gerät als `device` (nicht `unauthorized`).

### Was Claude Code darf

Installieren, starten, stoppen, Logs (`adb logcat`), Dateien kopieren
(`adb push/pull`), App-Daten löschen (`adb shell pm clear`), Screenshots.
**Nicht:** Factory-Reset, Flashen, Systemeinstellungen, Konten.
