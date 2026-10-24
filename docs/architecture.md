# Architektur

## Schichten

```
┌─────────────────────────────┐
│   UI  (Flutter oder Compose)│   Scroll-Menüs, 3D-Preview, Slot-Mapping
├─────────────────────────────┤
│   App-Logik / Profilverwalt.│   lädt Orca-Profile (machine/process/filament)
├─────────────────────────────┤
│   Engine-Bridge (JNI/FFI)   │   ruft die Slicing-Engine auf
├─────────────────────────────┤
│   Slicing-Engine (C++, ARM) │   OrcaSlicer-Engine, per NDK gebaut
├─────────────────────────────┤
│   Netzwerk (LAN-Senden)     │   Elegoo-Protokoll / Moonraker
└─────────────────────────────┘
```

Die beiden Elegoo-spezifischen Teile – Profile und Netzwerk – liegen
**außerhalb der Engine**. Sie werden als Schichten draufgesetzt, die Engine
bleibt Orca-Upstream. Siehe `elegoo-integration.md`.

## Komponenten

1. **UI** – mobil-nativ, Touch-first. Gruppierte, ausklappbare Einstellungen
   (Qualität, Struktur, Speed, Supports, Multimaterial); Werte als
   Slider/Eingabe/Toggle. 3D-Viewport (Drehen/Zoomen, nach dem Slicen
   Layer-/Farbvorschau). Preset-Auswahl und Slot-Mapping als Dropdowns.
   **Vollständige Fokus-Navigation**: jedes bedienbare Element außerhalb
   des 3D-Viewports ist per Tastatur, D-Pad und Controller erreichbar
   (Tab/Shift+Tab zum Blättern, Pfeiltasten zum Fokus-Verschieben,
   Enter/Space zum Aktivieren). Keine Touch-only-Interaktionen in Menüs,
   Dialogen oder Listen. Grund: Barrierefreiheit; Nebeneffekt ist, dass
   die App auf Android TV und auf Tablets mit angeschlossener Tastatur
   komplett nutzbar bleibt.
2. **App-Logik / Profilverwaltung** – lädt die Orca-Profil-JSONs 1:1 vom
   Desktop-Format (inkl. `inherits`-Ketten) und baut daraus die Menüs
   dynamisch.
3. **Engine-Bridge** – übergibt Modell + zusammengebaute Config an die Engine,
   holt G-Code + Kennzahlen zurück. JNI (Kotlin) bzw. dart:ffi (Flutter).
   In Phase 0 ist die "Bridge" ein HTTP-Client gegen `server/`.
4. **Slicing-Engine** – siehe `engine-integration.md`.
5. **Netzwerk** – siehe `networking-cc2.md`.

## UI-Stack: Flutter vs. Kotlin/Compose (OFFEN)

| Kriterium | Flutter (Dart) | Kotlin + Jetpack Compose |
|---|---|---|
| Plattform | Android **+ iOS** aus einer Basis | Android nativ |
| Native-C++-Anbindung | dart:ffi (sauber) | JNI (mehr Boilerplate) |
| 3D-View | three_dart / filament / Platform-View | OpenGL/Vulkan nativ, SceneView |
| Iterationsgeschwindigkeit | sehr hoch (Hot Reload) | hoch |
| „fühlt sich nativ an" | gut | am besten |
| Claude-Code-Erfahrung | sehr gut | sehr gut |

**Empfehlung:** Flutter – schnelles UI, spätere iOS-Option, saubere FFI.
Compose nur, wenn tiefste Android-Integration wichtiger ist als Plattform-
Reichweite. Entscheidung in `PROGRESS.md` festhalten, bevor `app/` befüllt wird.

## Datenfluss (MVP)

```
[3mf/STL] ──▶ App-Logik ──(Modell + Config)──▶ Engine-Bridge ──▶ Engine
                                                                    │
   UI ◀── Kennzahlen + Preview ◀── G-Code + Stats ◀──────────────────┘
                                                                    │
                                        Netzwerk ──(G-Code)──▶ Drucker (LAN)
```
