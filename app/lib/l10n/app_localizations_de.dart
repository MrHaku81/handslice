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
  String get pairDialogIp => 'Drucker-IP oder Hostname';

  @override
  String get pairDialogIpInvalid =>
      'IPv4-Adresse oder Hostname eintragen (keine Leerzeichen, kein Modellname).';

  @override
  String get pairDialogCode => 'Zugangscode (Drucker-Display)';

  @override
  String get pairDialogSave => 'Speichern';

  @override
  String get pairDialogCancel => 'Abbrechen';

  @override
  String get projectFilaments => 'Filamente / Slot-Zuordnung';

  @override
  String get projectZOffset =>
      'Z-Offset pro Seite (wird beim Slicen angewendet)';

  @override
  String get projectZOffsetDecrement => 'Z-Offset um 0,01 mm verringern';

  @override
  String get projectZOffsetIncrement => 'Z-Offset um 0,01 mm erhöhen';

  @override
  String get projectZOffsetHint =>
      '±0,50 mm, Schritte 0,01 mm — wird beim Slicen angewendet.';

  @override
  String get projectSliceButton => 'Auf dem Gerät slicen';

  @override
  String sliceInProgress(String mm, String ss) {
    return 'Slice läuft… $mm:$ss';
  }

  @override
  String get sliceCancelling =>
      'Wird abgebrochen – warte, bis die Engine stoppt…';

  @override
  String get sliceCancel => 'Abbrechen';

  @override
  String get sliceErrorOom =>
      'Nicht genug Arbeitsspeicher — der Slicer wurde vom System beendet. Modell mit weniger Dreiecken, dickere Schicht oder andere Apps schließen.';

  @override
  String sliceErrorExit(String code, String msg) {
    return 'Slicer fehlgeschlagen (Exit $code): $msg';
  }

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
  String get printPreflightNoUpload => 'Zuerst einen G-Code hochladen.';

  @override
  String get printPreflightNotConnected => 'Drucker nicht verbunden.';

  @override
  String get printPreflightBoundsFailed =>
      'Grenztest fehlgeschlagen – siehe Projekt-Bildschirm.';

  @override
  String printPreflightNotIdle(String status) {
    return 'Drucker ist nicht im Leerlauf – aktuell: $status.';
  }

  @override
  String printPreflightTrayEmpty(int slot) {
    return 'Gewähltes Fach (A$slot) ist leer.';
  }

  @override
  String get printTimelapseNotSupported =>
      'Dieser Drucker meldet keine Kamera – Zeitraffer deaktiviert.';

  @override
  String get printReconnecting => 'Verbindung verloren – wird neu aufgebaut…';

  @override
  String get printStatusLabel => 'Zustand';

  @override
  String get printBedLabel => 'Bett';

  @override
  String get printNozzleLabel => 'Düse';

  @override
  String get printExceptionLabel => 'Drucker-Alarme';

  @override
  String printTempFormat(String cur, String tgt) {
    return '$cur / $tgt °C';
  }

  @override
  String printLayerProgress(int cur, int tot, int pct) {
    return 'Schicht $cur/$tot  ($pct %)';
  }

  @override
  String printRemainingTime(String text) {
    return 'Restzeit ≈ $text';
  }

  @override
  String get settingsHeading => 'Einstellungen';

  @override
  String get settingsPlaceholder =>
      'Der generierte Einstellungsbaum kommt in einer späteren Phase.';

  @override
  String settingsSourceCaption(String version) {
    return 'Prozess-Einstellungen — erzeugt aus OrcaSlicer $version.';
  }

  @override
  String get settingsTierBasis => 'Basis';

  @override
  String get settingsTierAdvanced => 'Fortgeschritten';

  @override
  String get settingsTierExpert => 'Experte';

  @override
  String get settingsSearchHint => 'Suchen (Option, Beschriftung, Hilfe)…';

  @override
  String get settingsResetTooltip => 'Auf Profil-Standard zurücksetzen';

  @override
  String get settingsNoMatches =>
      'Keine Einstellungen passen zum aktuellen Filter.';

  @override
  String settingsOverridesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Überschreibungen',
      one: '1 Überschreibung',
      zero: 'Keine Überschreibungen',
    );
    return '$_temp0';
  }

  @override
  String get settingsSaveAsProfile => 'Als Profil speichern';

  @override
  String get settingsSaveAsNewProfile => 'Als neues Profil…';

  @override
  String get settingsUpdateProfile => 'Profil aktualisieren';

  @override
  String get settingsSaveDialogTitle => 'Prozess-Profil speichern';

  @override
  String get settingsSaveDialogHint =>
      'Speichert die aktuellen Überschreibungen als Orca-Preset mit inherits auf das aktive Basisprofil. Lokal auf dem Gerät.';

  @override
  String get settingsSaveFilamentDialogTitle => 'Filament-Profil speichern';

  @override
  String get settingsSaveFilamentDialogHint =>
      'Speichert die Überschreibungen des aktiven Fachs als Filament-Preset mit inherits auf das Basisprofil des Materials. Beim Laden wird das Profil Fächern mit demselben Material angeboten.';

  @override
  String get settingsProfileName => 'Profilname';

  @override
  String settingsProfileSaved(String file) {
    return 'Gespeichert: $file';
  }

  @override
  String settingsProfileSaveFailed(String msg) {
    return 'Speichern fehlgeschlagen: $msg';
  }

  @override
  String settingsSourceCaptionFilament(String version) {
    return 'Filament-Einstellungen — erzeugt aus OrcaSlicer $version.';
  }

  @override
  String get settingsFilamentActiveProfile => 'Filament-Profil';

  @override
  String get settingsFilamentActiveProfileNone => 'Standard (Basisprofil)';

  @override
  String settingsFilamentPickTitle(int tray) {
    return 'Filament-Profil für A$tray';
  }

  @override
  String settingsFilamentPickDefault(String name) {
    return 'Material-Basisprofil ($name)';
  }

  @override
  String get settingsFilamentPickEmpty =>
      'Noch keine Filament-Profile gespeichert. Über »Als Profil speichern« im Filament-Bereich anlegen.';

  @override
  String get settingsFilamentNoMatch =>
      'Keine Profile mit passendem Material zu diesem Fach.';

  @override
  String get focusHintDpad =>
      'D-Pad / Tab bewegen den Fokus, Enter / Leertaste aktivieren.';

  @override
  String get sampleBannerPlaceholder =>
      'Meilenstein 1 – Grundgerüst mit Beispieldaten, nichts ist verdrahtet.';

  @override
  String get settingsAreaProcess => 'Prozess';

  @override
  String get settingsAreaFilament => 'Filament';

  @override
  String settingsFilamentBase(String name) {
    return 'Basisprofil: $name';
  }

  @override
  String get settingsFilamentNoSlot =>
      'Keine Fach-Zuordnung bekannt. Mit dem Drucker verbinden und Fächer neu laden.';

  @override
  String get projectProfilePickTitle => 'Profil laden';

  @override
  String get projectProfileStandard => 'Orca-Standard (0.20mm Standard)';

  @override
  String get projectProfilePickEmpty =>
      'Noch keine eigenen Profile gespeichert. Unter Einstellungen → Als Profil speichern anlegen.';

  @override
  String projectProfileMissing(String slug) {
    return 'Gespeichertes Profil fehlt: $slug';
  }

  @override
  String get tabPrinter => 'Drucker';

  @override
  String get printerHistoryHeading => 'Druckhistorie';

  @override
  String get printerHistoryEmpty => 'Noch keine Drucke.';

  @override
  String get printerHistoryRefresh => 'Aktualisieren';

  @override
  String get printerHistoryClock =>
      'Zeitstempel stammen aus der Druckeruhr (aktuell UTC+8) und werden nur als Reihenfolge genutzt.';

  @override
  String get printerTaskStatusCompleted => 'Fertig';

  @override
  String get printerTaskStatusCancelled => 'Abgebrochen';

  @override
  String get printerTaskStatusFailed => 'Fehlgeschlagen';

  @override
  String printerTaskStatusUnknown(int code) {
    return 'Unbekannt ($code)';
  }

  @override
  String get printerVideoNone => 'Kein Zeitraffer';

  @override
  String get printerVideoRenderable => 'Zeitraffer-Rohdaten vorhanden';

  @override
  String get printerVideoReady => 'Zeitraffer-Video verfügbar';

  @override
  String get printerVideoNotRenderable => 'Zeitraffer nicht erzeugbar';

  @override
  String printerVideoDurationBytes(int seconds, int kib) {
    return '${seconds}s · $kib KiB';
  }

  @override
  String printerDurationShort(int minutes) {
    return '${minutes}m';
  }

  @override
  String get printerDownloadCheck => 'Prüfe Verfügbarkeit…';

  @override
  String get printerDownloadButton => 'Herunterladen';

  @override
  String get printerDownloadUnavailable =>
      'Nicht mehr verfügbar (am Drucker gelöscht?)';

  @override
  String get printerDownloadStarted => 'Lädt…';

  @override
  String printerDownloadDone(String path) {
    return 'Gespeichert: $path';
  }

  @override
  String get printerDownloadDoneGallery =>
      'In Movies/Handslice gespeichert (in der Galerie sichtbar)';

  @override
  String printerDownloadFailed(String msg) {
    return 'Download fehlgeschlagen: $msg';
  }

  @override
  String get printerShareButton => 'Teilen';

  @override
  String get printerRenderButton => 'Video erzeugen';

  @override
  String get printerRenderStarted => 'Erzeugt Video…';

  @override
  String get printerRenderNoFrames => 'Keine Rohdaten mehr vorhanden.';

  @override
  String printerRenderFailed(String msg) {
    return 'Erzeugung fehlgeschlagen: $msg';
  }

  @override
  String get printerRenderNotPossible =>
      'Nicht erzeugbar (keine Rohdaten am Drucker)';

  @override
  String get printStatusVideoComposing => 'Zeitraffer wird erzeugt/exportiert';

  @override
  String get printStatusException1243 =>
      'Filamentzufuhr-Fehler – PTFE-Schläuche prüfen';

  @override
  String get substatePausing => 'Pausiert gerade';

  @override
  String get substatePaused => 'Pausiert';

  @override
  String get substateResuming => 'Setzt fort';

  @override
  String get substateResumed => 'Fortgesetzt';

  @override
  String get printerNotConnected => 'Drucker nicht verbunden.';

  @override
  String get printerConnectHint => 'Im Projekt-Reiter koppeln und verbinden.';

  @override
  String get printControlSectionLabel => 'Druck-Steuerung';

  @override
  String get printControlPause => 'Pausieren';

  @override
  String get printControlResume => 'Fortsetzen';

  @override
  String get printControlCancel => 'Druck abbrechen';

  @override
  String get printControlCancelConfirmTitle =>
      'Laufenden Druck wirklich abbrechen?';

  @override
  String get printControlCancelConfirmBody =>
      'Stoppt den Druck sofort. Kann aus der App nicht rückgängig gemacht werden.';

  @override
  String get printControlCancelConfirmYes => 'Ja, abbrechen';

  @override
  String get printControlCancelConfirmNo => 'Weiterdrucken';

  @override
  String get printControlLightLabel => 'Kammerlicht';

  @override
  String get printControlLightUnknown =>
      'unbekannt (Drucker meldet den Zustand nicht)';

  @override
  String get printControlResumeHint =>
      'Fortsetzen gesendet – der Drucker antwortet erst nach Abschluss der Bewegung (bis ~2 min).';

  @override
  String printControlFailedPause(String detail) {
    return 'Pause vom Drucker abgelehnt: $detail';
  }

  @override
  String printControlFailedCancel(String detail) {
    return 'Abbruch vom Drucker abgelehnt: $detail';
  }

  @override
  String printControlFailedLight(String detail) {
    return 'Licht-Befehl fehlgeschlagen: $detail';
  }

  @override
  String get printPhaseCancelling => 'Bricht ab …';

  @override
  String get printPhaseCancelled => 'Abgebrochen';

  @override
  String get printPhasePreparing => 'Vorbereitung';

  @override
  String get machineStatusUnknown => 'unbekannt';

  @override
  String get machineStatusInitializing => 'Initialisierung';

  @override
  String get machineStatusIdle => 'Leerlauf';

  @override
  String get machineStatusPrinting => 'Druck läuft';

  @override
  String get machineStatusFilamentOp => 'Filamentwechsel';

  @override
  String get machineStatusAutoLeveling => 'Auto-Nivellierung';

  @override
  String get machineStatusPidCalibrating => 'PID-Kalibrierung';

  @override
  String get machineStatusResonanceTesting => 'Resonanz-Test';

  @override
  String get machineStatusSelfChecking => 'Selbsttest';

  @override
  String get machineStatusUpdating => 'Firmware-Update';

  @override
  String get machineStatusHoming => 'Homing';

  @override
  String get machineStatusFileTransferring => 'Dateiübertragung';

  @override
  String get machineStatusVideoComposing => 'Zeitraffer wird erzeugt';

  @override
  String get machineStatusExtruderOp => 'Extruder arbeitet';

  @override
  String get machineStatusEmergencyStop => 'Not-Halt';

  @override
  String get machineStatusPowerLossRecovery => 'Stromausfall-Wiederherstellung';

  @override
  String machineStatusOther(int code) {
    return 'Status $code';
  }

  @override
  String get printerErrorBannerTitle => 'Druckerfehler';

  @override
  String printerErrorsBannerTitle(int count) {
    return 'Druckerfehler ($count)';
  }

  @override
  String exceptionCodeUnknown(int code) {
    return 'Druckerfehler $code';
  }

  @override
  String get reconnectBannerLost => 'Verbindung verloren – verbinde neu …';

  @override
  String reconnectBannerRetrying(int seconds) {
    return 'Erneuter Verbindungsversuch in $seconds s …';
  }

  @override
  String reconnectBannerBackoff(int seconds) {
    return 'Verbindung fehlgeschlagen – nächster Versuch in $seconds s.';
  }

  @override
  String get printerSectionFiles => 'Dateien';

  @override
  String get printerSectionHistory => 'Historie';

  @override
  String get printerSectionCamera => 'Kamera';

  @override
  String get printerFilesEmpty => 'Noch keine Dateien am Drucker.';

  @override
  String get printerFilesRefresh => 'Neu laden';

  @override
  String get printerFilesSizeLabel => 'Größe';

  @override
  String get printerFilesLayersLabel => 'Schichten';

  @override
  String get printerFilesPrintTimeLabel => 'Druckzeit';

  @override
  String get printerFilesCurrentPrint =>
      'Wird gerade gedruckt – nicht löschbar';

  @override
  String get printerFilesPrintButton => 'Drucken';

  @override
  String get printerFilesDownloadButton => 'Herunterladen';

  @override
  String get printerFilesDeleteButton => 'Löschen';

  @override
  String get printerFilesDeleteBlockedRunning =>
      'Datei des laufenden Drucks kann nicht gelöscht werden';

  @override
  String get printerFilesDeleteConfirmTitle => 'Datei vom Drucker löschen?';

  @override
  String printerFilesDeleteConfirmBody(String name) {
    return 'Entfernt $name vom Drucker. Kann aus der App nicht rückgängig gemacht werden.';
  }

  @override
  String get printerFilesDeleteConfirmYes => 'Ja, löschen';

  @override
  String get printerFilesDeleteConfirmNo => 'Behalten';

  @override
  String printerFilesDownloadDone(String path) {
    return 'Gespeichert unter $path';
  }

  @override
  String printerFilesDownloadFailed(String msg) {
    return 'Download fehlgeschlagen: $msg';
  }

  @override
  String get printerFilesDownloadUnavailable =>
      'Datei gerade nicht abrufbar (Head-Probe fehlgeschlagen).';

  @override
  String get printerFilesPrintTitle => 'Diese Datei drucken?';

  @override
  String get printerFilesPrintSlot => 'Aktuelles Fach';

  @override
  String get printerFilesPrintStart => 'Druck starten';

  @override
  String get printerFilesPrintCancel => 'Abbrechen';

  @override
  String get printerFilesVisualCheckHint =>
      'Erste Schicht am Drucker im Auge behalten.';

  @override
  String get printerCameraHeading => 'Live-Kamera';

  @override
  String get printerCameraLoading => 'Verbindung zur Kamera …';

  @override
  String get printerCameraPaused =>
      'Kamera aus (Bereich nicht sichtbar oder App im Hintergrund).';

  @override
  String get printerCameraNoUrl =>
      'Konnte die Stream-URL vom Drucker nicht laden.';

  @override
  String printerCameraNoUrlDetail(String detail) {
    return 'method 1042 fehlgeschlagen: $detail';
  }

  @override
  String printerCameraStreamError(String detail) {
    return 'Stream-Fehler: $detail';
  }

  @override
  String get printerCameraTapHint => 'Bild antippen für Vollbild';

  @override
  String get printerCameraFullscreenClose => 'Vollbild schließen';

  @override
  String get printerFilesHeading => 'Dateien am Drucker';

  @override
  String get printerFilesDownloadDoneDownloads =>
      'Gespeichert unter Download/Handslice (sichtbar im Datei-Manager)';

  @override
  String get printerFilesDownloadOpen => 'Öffnen';

  @override
  String get printerFilesDownloadShare => 'Teilen';

  @override
  String get printerFilesPrintPickSlot => 'Fach wählen';

  @override
  String get printerFilesPrintSlotsUnknown =>
      'Fach-Informationen nicht verfügbar (nicht verbunden?).';

  @override
  String printerFilesFilamentIndex(int idx) {
    return 'Filament $idx';
  }

  @override
  String get printLevelBed => 'Bett vor dem Druck nivellieren (ca. 200 s)';

  @override
  String get startPrintForcedLevelHint =>
      'Drucker hat keine Mesh-Daten – Nivellierung wird erzwungen';

  @override
  String get controlVerbPause => 'Pause';

  @override
  String get controlVerbCancel => 'Abbruch';

  @override
  String get controlVerbLight => 'Licht';

  @override
  String controlFailedTimeout(String verb) {
    return '$verb: keine Antwort vom Drucker in der erwarteten Zeit';
  }

  @override
  String controlFailedWithCode(String verb, String code) {
    return '$verb vom Drucker abgelehnt (error_code=$code)';
  }
}
