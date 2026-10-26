// Zuordnung: CANVAS-Fach-Material (aus method 2005 `filament_name` +
// `filament_type`) → Orca-Filamentprofil-Datei unter
// assets/profiles/Elegoo/filament/ECC2/. Fallback: Generic-Profil des
// gleichen Typs mit sichtbarem Hinweis in der UI.
//
// Quellen (Belege im Repo):
// - CANVAS-Fach-Felder: engine/test/mock-cc2/mock_cc2.py (CANVAS_FIXTURE)
//   und docs/networking-cc2.md "CANVAS-Slot-Belegung".
// - Elegoo-Filamentprofile: engine/OrcaSlicer/resources/profiles/Elegoo/
//   filament/ECC2/*.json (im App-Bundle unter assets/profiles/...).

class FilamentProfileRef {
  const FilamentProfileRef({
    required this.assetName,
    required this.generic,
    this.fallbackReason,
  });

  /// Dateiname ohne Verzeichnis, z. B. "Elegoo PETG @ECC2.json".
  final String assetName;

  /// true = Generic/Fallback (nicht die konkrete Material-Variante), z. B.
  /// weil die Zuordnung aus dem Material-String nicht eindeutig war.
  final bool generic;

  /// User-sichtbarer Hinweis, warum das Fallback gewaehlt wurde.
  /// Beispiel: 'Material "ELEGOO ABS" nicht erkannt, generischer PLA'.
  final String? fallbackReason;
}

class FilamentMapping {
  const FilamentMapping();

  /// Zuordnung belegt aus beobachteten 2005-Antworten
  /// (`filament_name` + `filament_type` → ECC2-Profilname).
  ///
  /// Fuer die Haupt-Materialien laut `docs/networking-cc2.md`:
  /// - A1 PETG     → Elegoo PETG @ECC2
  /// - A2 Rapid PETG → Elegoo Rapid PETG @ECC2
  /// - A3 PLA Pro  → Elegoo PLA PRO @ECC2
  /// - A4 Rapid PLA+ → Elegoo Rapid PLA+ @ECC2
  FilamentProfileRef resolve({
    required String filamentName,
    required String filamentType,
  }) {
    final nm = filamentName.toUpperCase();
    final tp = filamentType.toUpperCase();

    // Exakte Namens-Treffer zuerst (robust gegen Casing).
    if (nm.contains('RAPID PLA')) return _ok('Elegoo Rapid PLA+ @ECC2.json');
    if (nm.contains('RAPID PETG')) return _ok('Elegoo Rapid PETG @ECC2.json');
    if (nm.contains('PLA PRO') || nm.contains('ELEGOO PLA PRO')) {
      return _ok('Elegoo PLA PRO @ECC2.json');
    }
    if (nm.contains('PLA PLUS') || nm == 'ELEGOO PLA+') {
      return _ok('Elegoo PLA+ @ECC2.json');
    }
    if (nm.contains('PETG PRO')) return _ok('Elegoo PETG PRO @ECC2.json');
    if (nm.contains('PLA MATTE')) return _ok('Elegoo PLA Matte @ECC2.json');
    if (nm.contains('PETG HF')) return _ok('Elegoo PETG HF @ECC2.json');

    // Dann Basis-Materialien aus filament_type (PETG/PLA/ABS/...).
    if (tp == 'PETG') return _ok('Elegoo PETG @ECC2.json');
    if (tp == 'PLA') return _ok('Elegoo PLA @ECC2.json');
    if (tp == 'ABS') return _ok('Elegoo ABS @ECC2.json');

    // Fallback: generisch nach Grob-Typ. Hinweis fuer die UI.
    if (nm.contains('PETG') || tp.contains('PETG')) {
      return FilamentProfileRef(
        assetName: 'Elegoo PETG @ECC2.json',
        generic: true,
        fallbackReason:
            'Material "$filamentName" nicht exakt zugeordnet; "Elegoo PETG @ECC2" als generische PETG-Vorlage.',
      );
    }
    // Default-Fallback: PLA (sichert sinnvolle Temperaturen und Grenzen).
    return FilamentProfileRef(
      assetName: 'Elegoo PLA @ECC2.json',
      generic: true,
      fallbackReason:
          'Material "$filamentName" (${filamentType.isEmpty ? "ohne Typ" : filamentType}) nicht erkannt; "Elegoo PLA @ECC2" als generische PLA-Vorlage.',
    );
  }

  FilamentProfileRef _ok(String name) =>
      FilamentProfileRef(assetName: name, generic: false);
}
