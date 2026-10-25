// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Handslice';

  @override
  String get tabProject => 'Projekt';

  @override
  String get tabPrint => 'Drucken';

  @override
  String get tabSettings => 'Einstellungen';

  @override
  String get projectHeading => 'Projekt';

  @override
  String get projectEmptyModel => 'Kein Modell geladen';

  @override
  String get projectOpenModel => 'Modell öffnen (STL / 3MF)';

  @override
  String get projectModelFile => 'Modell';

  @override
  String get projectPrinter => 'Drucker';

  @override
  String get projectPlate => 'Druckbett';

  @override
  String get projectPlateTextured => 'A – Strukturiert';

  @override
  String get projectPlateSmooth => 'B – Glatt';

  @override
  String get projectProfile => 'Profil';

  @override
  String get projectPrinterSection => 'Drucker';

  @override
  String get projectPrinterNotPaired => 'Kein Drucker gekoppelt.';

  @override
  String get projectPrinterPair => 'Drucker koppeln…';

  @override
  String get projectPrinterConnect => 'Verbinden & Fächer laden';

  @override
  String get projectPrinterConnecting => 'Verbinde…';

  @override
  String projectPrinterConnected(String host) {
    return 'Verbunden ($host).';
  }

  @override
  String get projectPrinterAuthError =>
      'Zugangscode abgelehnt. Erneut koppeln.';

  @override
  String projectPrinterNetError(String msg) {
    return 'Netz-/Discovery-Fehler: $msg';
  }

  @override
  String get projectPrinterLanOffHint =>
      'Der Drucker lehnt LAN-Verbindungen ab. »Nur LAN« am Display einschalten.';

  @override
  String get pairDialogTitle => 'Mit CC2 koppeln';

  @override
  String get pairDialogIp => 'Drucker-IP (z. B. <cc2-ip>)';

  @override
  String get pairDialogCode => 'Zugangscode (Drucker-Display)';

  @override
  String get pairDialogSave => 'Speichern';

  @override
  String get pairDialogCancel => 'Abbrechen';

  @override
  String get projectFilaments => 'Filamente / Slot-Zuordnung';

  @override
  String get projectZOffset => 'Z-Offset pro Seite (nur gespeichert)';

  @override
  String get projectZOffsetDecrement => 'Z-Offset um 0,01 mm verringern';

  @override
  String get projectZOffsetIncrement => 'Z-Offset um 0,01 mm erhöhen';

  @override
  String get projectZOffsetHint =>
      '±0,50 mm, Schritte 0,01 mm — noch nicht angewendet.';

  @override
  String get projectSliceButton => 'Auf dem Gerät slicen';

  @override
  String get printHeading => 'Drucken';

  @override
  String get printNoGcode => 'Kein G-Code – vorher ein Projekt slicen';

  @override
  String get printFileLabel => 'Datei';

  @override
  String get printSizeLabel => 'Größe';

  @override
  String get printLayersLabel => 'Layer';

  @override
  String get printTimeLabel => 'Geschätzte Zeit';

  @override
  String get printFilamentLabel => 'Filament';

  @override
  String get printBedLeveling => 'Bettnivellierung vor diesem Druck erzwingen';

  @override
  String get printPrinterCheck => 'Immer bettnivellieren (dauert ~200 s)';

  @override
  String get printTimelapse => 'Zeitraffer aufnehmen';

  @override
  String get printBoundsOk =>
      'Grenztest: alle Bewegungen innerhalb der Druckfläche.';

  @override
  String printBoundsFail(int count) {
    return 'Grenztest fehlgeschlagen: $count Bewegung(en) außerhalb der Druckfläche/-höhe. Upload gesperrt.';
  }

  @override
  String get printUploadButton => 'An den Drucker hochladen';

  @override
  String get printStartButton => 'Drucken (nach Sichtkontrolle am Gerät)';

  @override
  String get printStatusHeading => 'Druckerstatus';

  @override
  String get printStatusIdle => 'Bereit';

  @override
  String get printStatusPrinting => 'Druckt';

  @override
  String get printStatusLeveling => 'Nivelliert';

  @override
  String get printStatusHeating => 'Heizt';

  @override
  String get printStatusComposing => 'Erstellt Zeitraffer';

  @override
  String get printStatusUnknown => 'Unbekannt';

  @override
  String get settingsHeading => 'Einstellungen';

  @override
  String get settingsPlaceholder =>
      'Der generierte Einstellungsbaum kommt in einer späteren Phase.';

  @override
  String get focusHintDpad =>
      'D-Pad / Tab bewegen den Fokus, Enter / Leertaste aktivieren.';

  @override
  String get sampleBannerPlaceholder =>
      'Meilenstein 1 – Grundgerüst mit Beispieldaten, nichts ist verdrahtet.';
}
