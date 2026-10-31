// M8-Nachbesserung: zentraler Uebersetzer fuer die control.*-
// Fehlerschluessel, die `PrinterState.lastError` setzt. Fruehere
// Fassung reichte den rohen Schluessel in `l.printControlFailed*`-
// Platzhalter weiter – dann stand bei einem Timeout die Zeile
// "Abbruch vom Drucker abgelehnt: control.cancel.timeout" in der
// UI. Jetzt wird jeder bekannte Schluessel in einen echten
// Satzsatz umgewandelt.
//
// Unterstuetzte Form:
//   control.<verb>.error_code.<n>   → "<Verb> vom Drucker abgelehnt (error_code=<n>)"
//   control.<verb>.timeout          → "<Verb>: keine Antwort in der erwarteten Zeit"
//
// `<verb>` ist aktuell `pause`, `cancel` oder `light`. Fuer die
// Guard-Test: known_verbs sichtbar.

import '../l10n/app_localizations.dart';

const List<String> controlErrorVerbs = ['pause', 'cancel', 'light'];
const List<String> controlErrorKinds = ['error_code', 'timeout'];

String? mapControlErrorToText(AppLocalizations l, String? key) {
  if (key == null || key.isEmpty) return null;
  final m = RegExp(r'^control\.([a-z]+)\.(error_code|timeout)(?:\.(-?\d+))?$')
      .firstMatch(key);
  if (m == null) return null;
  final verb = m.group(1)!;
  final kind = m.group(2)!;
  final code = m.group(3);
  final verbLabel = switch (verb) {
    'pause'  => l.controlVerbPause,
    'cancel' => l.controlVerbCancel,
    'light'  => l.controlVerbLight,
    _ => verb,
  };
  if (kind == 'timeout') return l.controlFailedTimeout(verbLabel);
  // error_code benoetigt den konkreten Code
  if (code == null) return null;
  return l.controlFailedWithCode(verbLabel, code);
}
