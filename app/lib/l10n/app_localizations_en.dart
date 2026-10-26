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
  String sliceInProgress(String mm, String ss) {
    return 'Slicing… $mm:$ss';
  }

  @override
  String get sliceCancelling => 'Cancelling — waiting for the engine to stop…';

  @override
  String get sliceCancel => 'Cancel';

  @override
  String get sliceErrorOom =>
      'Not enough memory — the slicer was stopped by the system. Try a lower resolution model, a thicker layer, or close other apps.';

  @override
  String sliceErrorExit(String code, String msg) {
    return 'Slicer failed (exit $code): $msg';
  }

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
  String settingsSourceCaption(String version) {
    return 'Process settings — generated from OrcaSlicer $version.';
  }

  @override
  String get settingsTierBasis => 'Basics';

  @override
  String get settingsTierAdvanced => 'Advanced';

  @override
  String get settingsTierExpert => 'Expert';

  @override
  String get settingsSearchHint => 'Search (option, label, help)…';

  @override
  String get settingsResetTooltip => 'Reset to profile default';

  @override
  String get settingsNoMatches => 'No settings match the current filter.';

  @override
  String settingsOverridesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count overrides',
      one: '1 override',
      zero: 'No overrides',
    );
    return '$_temp0';
  }

  @override
  String get settingsSaveAsProfile => 'Save as profile';

  @override
  String get settingsSaveDialogTitle => 'Save process profile';

  @override
  String get settingsSaveDialogHint =>
      'Saves your current overrides as an Orca-style preset with inherits onto the active base profile. Stored locally.';

  @override
  String get settingsProfileName => 'Profile name';

  @override
  String settingsProfileSaved(String file) {
    return 'Saved: $file';
  }

  @override
  String settingsProfileSaveFailed(String msg) {
    return 'Save failed: $msg';
  }

  @override
  String get focusHintDpad =>
      'Use D-pad / Tab to move focus, Enter / Space to activate.';

  @override
  String get sampleBannerPlaceholder =>
      'Milestone 1 scaffold with sample data — nothing is wired yet.';

  @override
  String get settingsAreaProcess => 'Process';

  @override
  String get settingsAreaFilament => 'Filament';

  @override
  String settingsFilamentBase(String name) {
    return 'Base profile: $name';
  }

  @override
  String get settingsFilamentNoSlot =>
      'No slot assignment known. Connect to the printer and reload Canvas.';

  @override
  String get projectProfilePickTitle => 'Load profile';

  @override
  String get projectProfileStandard => 'Orca default (0.20mm Standard)';

  @override
  String get projectProfilePickEmpty =>
      'No saved profiles yet. Save one from Settings → Save as profile.';

  @override
  String projectProfileMissing(String slug) {
    return 'Saved profile missing: $slug';
  }

  @override
  String get tabPrinter => 'Printer';

  @override
  String get printerHistoryHeading => 'Print history';

  @override
  String get printerHistoryEmpty => 'No prints yet.';

  @override
  String get printerHistoryRefresh => 'Refresh';

  @override
  String get printerHistoryClock =>
      'Timestamps are the printer\'s own clock (currently UTC+8), used only as an ordering key.';

  @override
  String get printerTaskStatusCompleted => 'Completed';

  @override
  String get printerTaskStatusCancelled => 'Cancelled';

  @override
  String get printerTaskStatusFailed => 'Failed';

  @override
  String printerTaskStatusUnknown(int code) {
    return 'Unknown ($code)';
  }

  @override
  String get printerVideoNone => 'No time-lapse';

  @override
  String get printerVideoRenderable => 'Time-lapse frames available';

  @override
  String get printerVideoReady => 'Time-lapse video ready';

  @override
  String get printerVideoNotRenderable => 'Time-lapse not renderable';

  @override
  String printerVideoDurationBytes(int seconds, int kib) {
    return '${seconds}s · $kib KiB';
  }

  @override
  String printerDurationShort(int minutes) {
    return '${minutes}m';
  }

  @override
  String get printerDownloadCheck => 'Checking availability…';

  @override
  String get printerDownloadButton => 'Download';

  @override
  String get printerDownloadUnavailable =>
      'No longer available (deleted on the printer?)';

  @override
  String get printerDownloadStarted => 'Downloading…';

  @override
  String printerDownloadDone(String path) {
    return 'Saved: $path';
  }

  @override
  String get printerDownloadDoneGallery =>
      'Saved to Movies/Handslice (visible in Gallery)';

  @override
  String printerDownloadFailed(String msg) {
    return 'Download failed: $msg';
  }

  @override
  String get printerShareButton => 'Share';

  @override
  String get printerRenderButton => 'Create video';

  @override
  String get printerRenderStarted => 'Rendering…';

  @override
  String get printerRenderNoFrames => 'No raw frames available for this print.';

  @override
  String printerRenderFailed(String msg) {
    return 'Render failed: $msg';
  }

  @override
  String get printerRenderNotPossible =>
      'Not renderable (no raw frames on the printer)';

  @override
  String get printStatusVideoComposing => 'Creating/exporting time-lapse';

  @override
  String get printStatusException1243 =>
      'Filament feed error — check PTFE tubes';

  @override
  String get substatePausing => 'Pausing';

  @override
  String get substatePaused => 'Paused';

  @override
  String get substateResuming => 'Resuming';

  @override
  String get substateResumed => 'Resumed';

  @override
  String get printerNotConnected => 'Printer not connected.';

  @override
  String get printerConnectHint => 'Pair and connect from the Project tab.';
}
