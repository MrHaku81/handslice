# Elegoo-Integration

ElegooSlicer (github.com/ELEGOO-3D/ElegooSlicer) ist ein AGPL-3.0-Fork von
OrcaSlicer mit Elegoo-Profilen, Branding und Gerätesteuerung. Wir nehmen
daraus gezielt zwei Dinge – und sonst nichts.

## Übernommen wird

### 1. Druckerprofile (Phase 1b)

Quelle: `resources/profiles/Elegoo/` im ElegooSlicer-Repo.
Ziel: `profiles/Elegoo/` hier, **mit Herkunftsvermerk** (Commit-Hash, Datum).

Das Format ist dasselbe Orca-JSON mit `inherits`-Ketten; Übernahme ist
weitgehend Kopieren. Zu prüfen:

- Felder, die Elegoo im Fork ergänzt hat und die Orca-Upstream nicht kennt →
  auflisten; ignorieren oder in der App-Logik nachbilden, **nicht** in die
  Engine patchen.
- Nachweis: CC2-Profile laden ohne Warnungen; G-Code aus unserer Engine mit
  Elegoo-Profil ist bytegleich zu ElegooSlicer-Desktop mit demselben Profil.
  Abweichungen zeigen, ob der Fork Engine-Änderungen enthält, die der CC2
  wirklich braucht – das ist die einzige Stelle, an der ein Engine-Patch
  diskutiert wird.

### 2. Netzwerkprotokoll (Phase 2)

Quelle: Code des „Device Assistant" in ElegooSlicer (Discovery, Upload,
Druck starten, Status/Monitoring).
Ziel: eigenes Modul in der App, das Protokoll **nachgebaut**, nicht der
C++-Code eingebettet.

Vorher klären (siehe `networking-cc2.md`): Spricht der CC2 Elegoo-eigenes
Protokoll oder Moonraker-kompatible Endpunkte? Das entscheidet über den
Aufwand.

## Nicht übernommen wird

- Engine-Änderungen jeglicher Art.
- Branding, Icons, Namen.
- Cloud-/Konto-Funktionen.

## Lizenz

Beides ist AGPL-3.0, Übernahme ist zulässig, solange Handslice AGPL-3.0 bleibt
und die Herkunft genannt wird. Herkunftsvermerk in `profiles/README.md` und
im Netzwerk-Modul pflegen.
