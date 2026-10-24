# Engine-Anbindung

## Entscheidung

**OrcaSlicer-Upstream** (SoftFever) ist die Engine. Grund: exakte Treue zu den
CC2-/CANVAS-Profilen, identische Ergebnisse zum Desktop.
CuraEngine bleibt nur als Notfall-Fallback, falls der Android-Build sich als
nicht machbar erweist – dann müssten Profile übersetzt werden und CANVAS-
Mehrfarbe wäre nicht 1:1.

Keine Engine-Patches aus Hersteller-Forks. ElegooSlicer merged Orca-Upstream
nur periodisch und liegt zurück; zwei Codebasen zu verfolgen ist nicht
tragbar.

## Reihenfolge – jeder Schritt ein eigener Auftrag mit eigenem Nachweis

### Schritt A: Headless-Build auf x86 (CachyOS)

Orca ohne wxWidgets und ohne GUI-Abhängigkeiten bauen: nur `libslic3r` plus
CLI. Wenn das auf x86 nicht geht, geht es auf ARM auch nicht.

- Submodul `engine/OrcaSlicer` auf festen Tag pinnen.
- CMake-Optionen durchprobieren: `SLIC3R_GUI=OFF` (oder Äquivalent der
  gepinnten Version), nur CLI-Target.
- **Nachweis:** `orca-slicer --slice ... test.3mf` erzeugt G-Code, der
  bytegleich mit dem Desktop-AppImage derselben Version ist.
- Nebeneffekt: Dieses Binary ist der Server für Phase 0.

### Schritt B: Abhängigkeiten für Android ARM64 cross-compilen

Orca hängt an Boost, TBB, OpenVDB, CGAL, Eigen, nlohmann-json, Expat, libpng,
Cereal, GMP/MPFR (für CGAL) u. a. Orcas `deps/`-Build ist auf Desktop
ausgelegt; mit NDK-Toolchain-File durchgehen, Bibliothek für Bibliothek.

- Toolchain: NDK (Version in `test-setup.md` festhalten), `ANDROID_ABI=arm64-v8a`,
  `ANDROID_PLATFORM` ≥ 29 (Android 10, wegen Poco X3 Pro mind. Android 11).
- **Nachweis:** alle Deps liegen als `.a` unter `engine/deps-build/arm64/`;
  `file` zeigt `ELF 64-bit ... ARM aarch64`.

### Schritt C: libslic3r + CLI für ARM64

- Gleicher Headless-Build wie A, gegen die Deps aus B.
- Als **statisch gelinktes Kommandozeilen-Binary** bauen (einfacher als
  `.so` + JNI für den ersten Durchstich).
- **Nachweis:** per ADB auf das Poco kopiert, dort ausgeführt, G-Code zurück
  kopiert, `sha256sum` identisch zum Desktop.

### Schritt D: Einbettung in die App

- Erst CLI-Binary als Asset mitliefern und per `Process` aufrufen (schnell,
  robust, einfache Fehlersuche).
- Später optional `.so` + FFI/JNI für Fortschrittsmeldungen und Preview-Daten.

## Bekannte Stolpersteine

- CMake-Fehler in der Deps-Kette zeigen oft weit weg von der Ursache
  („Boost nicht gefunden" wegen falscher Toolchain-Variable). Drei-Versuche-
  Regel aus `CLAUDE.md` beachten.
- OpenVDB und CGAL sind die dicksten Brocken; wenn eine nicht baut, prüfen,
  ob Orca sie für reines Slicen (ohne Hollowing/Mesh-Boolean) überhaupt
  braucht, und ggf. per Build-Option abschalten – **dokumentiert**.
- Scoped Storage (Android 11): CLI darf nur in den App-eigenen Ordner
  schreiben; Modelle vorher dorthin kopieren.
- MIUI killt Hintergrundprozesse aggressiv: Slicen in einem Foreground-
  Service laufen lassen, Akku-Optimierung für die App deaktivieren.
