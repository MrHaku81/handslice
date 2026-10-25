// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Handslice';

  @override
  String get tabProject => 'Project';

  @override
  String get tabPrint => 'Print';

  @override
  String get tabSettings => 'Settings';

  @override
  String get projectHeading => 'Project';

  @override
  String get projectEmptyModel => 'No model loaded';

  @override
  String get projectOpenModel => 'Open model (STL / 3MF)';

  @override
  String get projectModelFile => 'Model';

  @override
  String get projectPrinter => 'Printer';

  @override
  String get projectPlate => 'Build plate';

  @override
  String get projectPlateTextured => 'A — Textured';

  @override
  String get projectPlateSmooth => 'B — Smooth';

  @override
  String get projectProfile => 'Profile';

  @override
  String get projectPrinterSection => 'Printer';

  @override
  String get projectPrinterNotPaired => 'No printer paired.';

  @override
  String get projectPrinterPair => 'Pair printer…';

  @override
  String get projectPrinterConnect => 'Connect & load slots';

  @override
  String get projectPrinterConnecting => 'Connecting…';

  @override
  String projectPrinterConnected(String host) {
    return 'Connected ($host).';
  }

  @override
  String get projectPrinterAuthError => 'Access-code rejected. Re-pair.';

  @override
  String projectPrinterNetError(String msg) {
    return 'Network / discovery error: $msg';
  }

  @override
  String get projectPrinterLanOffHint =>
      'The printer rejects LAN connections. Enable \'LAN only\' at the printer display.';

  @override
  String get pairDialogTitle => 'Pair with CC2';

  @override
  String get pairDialogIp => 'Printer IP or hostname';

  @override
  String get pairDialogIpInvalid =>
      'Enter an IPv4 address or hostname (no spaces, no model name).';

  @override
  String get pairDialogCode => 'Access code (printer display)';

  @override
  String get pairDialogSave => 'Save';

  @override
  String get pairDialogCancel => 'Cancel';

  @override
  String get projectFilaments => 'Filaments / Slot assignment';

  @override
  String get projectZOffset => 'Z-offset per plate (applied at slice time)';

  @override
  String get projectZOffsetDecrement => 'Decrease Z-offset by 0.01 mm';

  @override
  String get projectZOffsetIncrement => 'Increase Z-offset by 0.01 mm';

  @override
  String get projectZOffsetHint =>
      '±0.50 mm, 0.01 mm steps — applied when slicing.';

  @override
  String get projectSliceButton => 'Slice on device';

  @override
  String get printHeading => 'Print';

  @override
  String get printNoGcode => 'No G-code — slice a project first';

  @override
  String get printFileLabel => 'File';

  @override
  String get printSizeLabel => 'Size';

  @override
  String get printLayersLabel => 'Layers';

  @override
  String get printTimeLabel => 'Estimated time';

  @override
  String get printFilamentLabel => 'Filament';

  @override
  String get printBedLeveling => 'Force bed leveling before this print';

  @override
  String get printPrinterCheck => 'Always level the bed (adds ~200 s)';

  @override
  String get printTimelapse => 'Record timelapse';

  @override
  String get printBoundsOk => 'Bounds-check: all moves within printable area.';

  @override
  String printBoundsFail(int count) {
    return 'Bounds-check failed: $count move(s) outside the printable area / height. Upload blocked.';
  }

  @override
  String get printUploadButton => 'Upload to printer';

  @override
  String get printStartButton => 'Print (requires visual check at printer)';

  @override
  String get printStatusHeading => 'Printer status';

  @override
  String get printStatusIdle => 'Idle';

  @override
  String get printStatusPrinting => 'Printing';

  @override
  String get printStatusLeveling => 'Leveling';

  @override
  String get printStatusHeating => 'Heating';

  @override
  String get printStatusComposing => 'Composing timelapse';

  @override
  String get printStatusUnknown => 'Unknown';

  @override
  String get printPreflightNoUpload => 'Upload a G-code first.';

  @override
  String get printPreflightNotConnected => 'Printer not connected.';

  @override
  String get printPreflightBoundsFailed =>
      'Bounds-check failed — see Project screen.';

  @override
  String printPreflightNotIdle(int status) {
    return 'Printer is not idle (status=$status).';
  }

  @override
  String printPreflightTrayEmpty(int slot) {
    return 'Selected tray (A$slot) is empty.';
  }

  @override
  String get printTimelapseNotSupported =>
      'This printer reports no camera — timelapse disabled.';

  @override
  String get printReconnecting => 'Connection lost — reconnecting…';

  @override
  String get printStatusLabel => 'State';

  @override
  String get printBedLabel => 'Bed';

  @override
  String get printNozzleLabel => 'Nozzle';

  @override
  String get printExceptionLabel => 'Printer alarms';

  @override
  String printTempFormat(String cur, String tgt) {
    return '$cur / $tgt °C';
  }

  @override
  String printLayerProgress(int cur, int tot, int pct) {
    return 'Layer $cur/$tot  ($pct%)';
  }

  @override
  String printRemainingTime(String text) {
    return 'Remaining ≈ $text';
  }

  @override
  String get settingsHeading => 'Settings';

  @override
  String get settingsPlaceholder =>
      'The generated settings tree comes in a later milestone.';

  @override
  String get focusHintDpad =>
      'Use D-pad / Tab to move focus, Enter / Space to activate.';

  @override
  String get sampleBannerPlaceholder =>
      'Milestone 1 scaffold with sample data — nothing is wired yet.';
}
