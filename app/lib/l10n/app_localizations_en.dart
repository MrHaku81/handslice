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
  String get projectFilaments => 'Filaments / Slot assignment';

  @override
  String get projectZOffset => 'Z-offset per plate (saved only)';

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
  String get printBedLeveling => 'Force bed leveling before print';

  @override
  String get printAutoLevelCheck => 'Auto bed-level check';

  @override
  String get printTimelapse => 'Record timelapse';

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
