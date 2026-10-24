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

Stand: 2026-10-24 (Erstaufnahme durch Umgebungscheck).

| Komponente | Version | Pfad |
|---|---|---|
| git | 2.56.0 | `/usr/bin/git` |
| CMake | 4.4.4 | `/usr/bin/cmake` |
| Ninja | 1.13.2 | `/usr/bin/ninja` |
| GCC | 16.2.1 (20260810) | `/usr/bin/gcc` |
| Clang / LLVM | 23.1.3 | `/usr/bin/clang` |
| lld (LLVM-Linker, aarch64-fähig) | 23.1.3 | `/usr/bin/ld.lld` |
| Python | 3.14.8 | `/usr/bin/python3` |
| adb (platform-tools) | 1.0.41 / 37.0.0p1 | `/usr/bin/adb` |
| Android SDK | **nicht installiert** | – |
| Android NDK | **nicht installiert** | – |
| aarch64-linux-gnu-gcc (System-Cross-Toolchain) | **nicht installiert** | – |
| Flutter | **nicht installiert** | – |
| Kotlin (kotlinc) | **nicht installiert** | – |
| OrcaSlicer-Tag (Submodul) | – (Submodul noch nicht eingerichtet) | `engine/OrcaSlicer` |
| Desktop-Orca (Referenz, AppImage) | – muss zum Tag passen | – |

Hinweis: Clang+lld können aarch64-ELFs erzeugen (freistehend, direkte
Linux-Syscalls), siehe ADB-Rundlauf unten. Für echtes NDK/Bionic-Linking
muss das NDK installiert werden – noch offen (abhängig von UI-Entscheidung).

## Testgerät: Poco X3 Pro

- Snapdragon 860 (4× Cortex-A76 + 4× A55, ARM64), 6/8 GB RAM.
- Stock-MIUI, Originalzustand. Android-Version: _eintragen_.
- SIM entfernt. Wird nach Projektende zurückgesetzt – App-Daten dürfen frei
  angelegt und gelöscht werden.

### Fakten vom Gerät (Stand 2026-10-24, per adb erfasst)

| Feld | Wert |
|---|---|
| ADB-Seriennummer | `9ed86ce3` |
| Hersteller / Modell | Xiaomi / `M2102J20SG` (Poco X3 Pro, Codename `vayu`) |
| Produktname | `vayu_eea` |
| Android-Version | 12 (API 31) |
| MIUI-Version | `V13.0.1.0.SJUEUXM` (V130) |
| Primäre ABI | `arm64-v8a` |
| ABI-Liste | `arm64-v8a,armeabi-v7a,armeabi` |
| RAM (MemTotal) | 7 678 948 kB (≈ 7,32 GiB → 8-GB-Variante) |
| MemAvailable | 4 821 164 kB (≈ 4,6 GiB frei nutzbar) |
| /data (= /data/local/tmp) | 226 GB gesamt, 144 GB frei (37 % belegt) |

### ADB-Rundlauf (Stand 2026-10-24, bestanden)

- 10 MiB `/dev/urandom`-Blob erzeugt, per `adb push` nach
  `/data/local/tmp/blob.bin` geschoben, auf dem Gerät `sha256sum` gelaufen,
  per `adb pull` zurückgeholt und erneut gehasht.
- Alle drei SHA-256 identisch:
  `90156b83892d6516b2b952d5a5a702d5d31cb8609b8b025c9ccb93216f4c355d`.
- Transferraten (USB): push 44,1 MB/s, pull 37,4 MB/s.
- ARM64-Hello-World (freistehend, direkte Linux-Syscalls, mit Clang+lld
  gebaut: `clang --target=aarch64-linux -ffreestanding -nostdlib -fuse-ld=lld
  -static -O2`) nach `/data/local/tmp` gepusht, `chmod 755`, direkt
  ausgeführt → Ausgabe `hello from arm64`, Exit 0.
- Kein echtes NDK/Bionic-Binary getestet (NDK nicht installiert) – das
  freistehende Syscall-Binary beweist nur, dass ADB-Rundlauf,
  `/data/local/tmp`-Execute-Rechte und arm64-Userspace-Ausführung an sich
  funktionieren.

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
