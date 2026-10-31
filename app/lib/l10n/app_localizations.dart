import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Handslice'**
  String get appTitle;

  /// Bottom-nav label for the project screen
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get tabProject;

  /// Bottom-nav label for the print screen
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get tabPrint;

  /// Bottom-nav label for the settings placeholder
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @projectHeading.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectHeading;

  /// No description provided for @projectEmptyModel.
  ///
  /// In en, this message translates to:
  /// **'No model loaded'**
  String get projectEmptyModel;

  /// No description provided for @projectOpenModel.
  ///
  /// In en, this message translates to:
  /// **'Open model (STL / 3MF)'**
  String get projectOpenModel;

  /// No description provided for @projectModelFile.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get projectModelFile;

  /// No description provided for @projectPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get projectPrinter;

  /// No description provided for @projectPlate.
  ///
  /// In en, this message translates to:
  /// **'Build plate'**
  String get projectPlate;

  /// No description provided for @projectPlateTextured.
  ///
  /// In en, this message translates to:
  /// **'A — Textured'**
  String get projectPlateTextured;

  /// No description provided for @projectPlateSmooth.
  ///
  /// In en, this message translates to:
  /// **'B — Smooth'**
  String get projectPlateSmooth;

  /// No description provided for @projectProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get projectProfile;

  /// No description provided for @projectPrinterSection.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get projectPrinterSection;

  /// No description provided for @projectPrinterNotPaired.
  ///
  /// In en, this message translates to:
  /// **'No printer paired.'**
  String get projectPrinterNotPaired;

  /// No description provided for @projectPrinterPair.
  ///
  /// In en, this message translates to:
  /// **'Pair printer…'**
  String get projectPrinterPair;

  /// No description provided for @projectPrinterConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect & load slots'**
  String get projectPrinterConnect;

  /// No description provided for @projectPrinterConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get projectPrinterConnecting;

  /// No description provided for @projectPrinterConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected ({host}).'**
  String projectPrinterConnected(String host);

  /// No description provided for @projectPrinterAuthError.
  ///
  /// In en, this message translates to:
  /// **'Access-code rejected. Re-pair.'**
  String get projectPrinterAuthError;

  /// No description provided for @projectPrinterNetError.
  ///
  /// In en, this message translates to:
  /// **'Network / discovery error: {msg}'**
  String projectPrinterNetError(String msg);

  /// No description provided for @projectPrinterLanOffHint.
  ///
  /// In en, this message translates to:
  /// **'The printer rejects LAN connections. Enable \'LAN only\' at the printer display.'**
  String get projectPrinterLanOffHint;

  /// No description provided for @pairDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with CC2'**
  String get pairDialogTitle;

  /// No description provided for @pairDialogIp.
  ///
  /// In en, this message translates to:
  /// **'Printer IP or hostname'**
  String get pairDialogIp;

  /// No description provided for @pairDialogIpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an IPv4 address or hostname (no spaces, no model name).'**
  String get pairDialogIpInvalid;

  /// No description provided for @pairDialogCode.
  ///
  /// In en, this message translates to:
  /// **'Access code (printer display)'**
  String get pairDialogCode;

  /// No description provided for @pairDialogSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get pairDialogSave;

  /// No description provided for @pairDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get pairDialogCancel;

  /// No description provided for @projectFilaments.
  ///
  /// In en, this message translates to:
  /// **'Filaments / Slot assignment'**
  String get projectFilaments;

  /// No description provided for @projectZOffset.
  ///
  /// In en, this message translates to:
  /// **'Z-offset per plate (applied at slice time)'**
  String get projectZOffset;

  /// No description provided for @projectZOffsetDecrement.
  ///
  /// In en, this message translates to:
  /// **'Decrease Z-offset by 0.01 mm'**
  String get projectZOffsetDecrement;

  /// No description provided for @projectZOffsetIncrement.
  ///
  /// In en, this message translates to:
  /// **'Increase Z-offset by 0.01 mm'**
  String get projectZOffsetIncrement;

  /// No description provided for @projectZOffsetHint.
  ///
  /// In en, this message translates to:
  /// **'±0.50 mm, 0.01 mm steps — applied when slicing.'**
  String get projectZOffsetHint;

  /// No description provided for @projectSliceButton.
  ///
  /// In en, this message translates to:
  /// **'Slice on device'**
  String get projectSliceButton;

  /// No description provided for @sliceInProgress.
  ///
  /// In en, this message translates to:
  /// **'Slicing… {mm}:{ss}'**
  String sliceInProgress(String mm, String ss);

  /// No description provided for @sliceCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling — waiting for the engine to stop…'**
  String get sliceCancelling;

  /// No description provided for @sliceCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sliceCancel;

  /// No description provided for @sliceErrorOom.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory — the slicer was stopped by the system. Try a lower resolution model, a thicker layer, or close other apps.'**
  String get sliceErrorOom;

  /// No description provided for @sliceErrorExit.
  ///
  /// In en, this message translates to:
  /// **'Slicer failed (exit {code}): {msg}'**
  String sliceErrorExit(String code, String msg);

  /// No description provided for @printHeading.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printHeading;

  /// No description provided for @printNoGcode.
  ///
  /// In en, this message translates to:
  /// **'No G-code — slice a project first'**
  String get printNoGcode;

  /// No description provided for @printFileLabel.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get printFileLabel;

  /// No description provided for @printSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get printSizeLabel;

  /// No description provided for @printLayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get printLayersLabel;

  /// No description provided for @printTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get printTimeLabel;

  /// No description provided for @printFilamentLabel.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get printFilamentLabel;

  /// config.bedlevel_force
  ///
  /// In en, this message translates to:
  /// **'Force bed leveling before this print'**
  String get printBedLeveling;

  /// config.printer_check — per CC2_PROTOCOL.md: true always levels (~200 s), false never does, omitting the key lets the firmware decide.
  ///
  /// In en, this message translates to:
  /// **'Always level the bed (adds ~200 s)'**
  String get printPrinterCheck;

  /// No description provided for @printTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Record timelapse'**
  String get printTimelapse;

  /// No description provided for @printBoundsOk.
  ///
  /// In en, this message translates to:
  /// **'Bounds-check: all moves within printable area.'**
  String get printBoundsOk;

  /// No description provided for @printBoundsFail.
  ///
  /// In en, this message translates to:
  /// **'Bounds-check failed: {count} move(s) outside the printable area / height. Upload blocked.'**
  String printBoundsFail(int count);

  /// No description provided for @printUploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload to printer'**
  String get printUploadButton;

  /// No description provided for @printStartButton.
  ///
  /// In en, this message translates to:
  /// **'Print (requires visual check at printer)'**
  String get printStartButton;

  /// No description provided for @printStatusHeading.
  ///
  /// In en, this message translates to:
  /// **'Printer status'**
  String get printStatusHeading;

  /// No description provided for @printStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get printStatusIdle;

  /// No description provided for @printStatusPrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing'**
  String get printStatusPrinting;

  /// No description provided for @printStatusLeveling.
  ///
  /// In en, this message translates to:
  /// **'Leveling'**
  String get printStatusLeveling;

  /// No description provided for @printStatusHeating.
  ///
  /// In en, this message translates to:
  /// **'Heating'**
  String get printStatusHeating;

  /// No description provided for @printStatusComposing.
  ///
  /// In en, this message translates to:
  /// **'Composing timelapse'**
  String get printStatusComposing;

  /// No description provided for @printStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get printStatusUnknown;

  /// No description provided for @printPreflightNoUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload a G-code first.'**
  String get printPreflightNoUpload;

  /// No description provided for @printPreflightNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Printer not connected.'**
  String get printPreflightNotConnected;

  /// No description provided for @printPreflightBoundsFailed.
  ///
  /// In en, this message translates to:
  /// **'Bounds-check failed — see Project screen.'**
  String get printPreflightBoundsFailed;

  /// No description provided for @printPreflightNotIdle.
  ///
  /// In en, this message translates to:
  /// **'Printer is not idle — currently: {status}.'**
  String printPreflightNotIdle(String status);

  /// No description provided for @printPreflightTrayEmpty.
  ///
  /// In en, this message translates to:
  /// **'Selected tray (A{slot}) is empty.'**
  String printPreflightTrayEmpty(int slot);

  /// No description provided for @printTimelapseNotSupported.
  ///
  /// In en, this message translates to:
  /// **'This printer reports no camera — timelapse disabled.'**
  String get printTimelapseNotSupported;

  /// No description provided for @printReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Connection lost — reconnecting…'**
  String get printReconnecting;

  /// No description provided for @printStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get printStatusLabel;

  /// No description provided for @printBedLabel.
  ///
  /// In en, this message translates to:
  /// **'Bed'**
  String get printBedLabel;

  /// No description provided for @printNozzleLabel.
  ///
  /// In en, this message translates to:
  /// **'Nozzle'**
  String get printNozzleLabel;

  /// No description provided for @printExceptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Printer alarms'**
  String get printExceptionLabel;

  /// No description provided for @printTempFormat.
  ///
  /// In en, this message translates to:
  /// **'{cur} / {tgt} °C'**
  String printTempFormat(String cur, String tgt);

  /// No description provided for @printLayerProgress.
  ///
  /// In en, this message translates to:
  /// **'Layer {cur}/{tot}  ({pct}%)'**
  String printLayerProgress(int cur, int tot, int pct);

  /// No description provided for @printRemainingTime.
  ///
  /// In en, this message translates to:
  /// **'Remaining ≈ {text}'**
  String printRemainingTime(String text);

  /// No description provided for @settingsHeading.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsHeading;

  /// No description provided for @settingsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'The generated settings tree comes in a later milestone.'**
  String get settingsPlaceholder;

  /// No description provided for @settingsSourceCaption.
  ///
  /// In en, this message translates to:
  /// **'Process settings — generated from OrcaSlicer {version}.'**
  String settingsSourceCaption(String version);

  /// No description provided for @settingsTierBasis.
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get settingsTierBasis;

  /// No description provided for @settingsTierAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsTierAdvanced;

  /// No description provided for @settingsTierExpert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get settingsTierExpert;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search (option, label, help)…'**
  String get settingsSearchHint;

  /// No description provided for @settingsResetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset to profile default'**
  String get settingsResetTooltip;

  /// No description provided for @settingsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No settings match the current filter.'**
  String get settingsNoMatches;

  /// No description provided for @settingsOverridesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No overrides} =1{1 override} other{{count} overrides}}'**
  String settingsOverridesCount(int count);

  /// No description provided for @settingsSaveAsProfile.
  ///
  /// In en, this message translates to:
  /// **'Save as profile'**
  String get settingsSaveAsProfile;

  /// No description provided for @settingsSaveAsNewProfile.
  ///
  /// In en, this message translates to:
  /// **'Save as new profile…'**
  String get settingsSaveAsNewProfile;

  /// No description provided for @settingsUpdateProfile.
  ///
  /// In en, this message translates to:
  /// **'Update profile'**
  String get settingsUpdateProfile;

  /// No description provided for @settingsSaveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save process profile'**
  String get settingsSaveDialogTitle;

  /// No description provided for @settingsSaveDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Saves your current overrides as an Orca-style preset with inherits onto the active base profile. Stored locally.'**
  String get settingsSaveDialogHint;

  /// No description provided for @settingsSaveFilamentDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save filament profile'**
  String get settingsSaveFilamentDialogTitle;

  /// No description provided for @settingsSaveFilamentDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Saves the active tray\'s overrides as a filament preset with inherits onto the material base profile. When loading, the profile is offered to trays with the same material.'**
  String get settingsSaveFilamentDialogHint;

  /// No description provided for @settingsProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get settingsProfileName;

  /// No description provided for @settingsProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {file}'**
  String settingsProfileSaved(String file);

  /// No description provided for @settingsProfileSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {msg}'**
  String settingsProfileSaveFailed(String msg);

  /// No description provided for @settingsSourceCaptionFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament settings — generated from OrcaSlicer {version}.'**
  String settingsSourceCaptionFilament(String version);

  /// No description provided for @settingsFilamentActiveProfile.
  ///
  /// In en, this message translates to:
  /// **'Filament profile'**
  String get settingsFilamentActiveProfile;

  /// No description provided for @settingsFilamentActiveProfileNone.
  ///
  /// In en, this message translates to:
  /// **'Standard (base profile)'**
  String get settingsFilamentActiveProfileNone;

  /// No description provided for @settingsFilamentPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Filament profile for A{tray}'**
  String settingsFilamentPickTitle(int tray);

  /// No description provided for @settingsFilamentPickDefault.
  ///
  /// In en, this message translates to:
  /// **'Material base profile ({name})'**
  String settingsFilamentPickDefault(String name);

  /// No description provided for @settingsFilamentPickEmpty.
  ///
  /// In en, this message translates to:
  /// **'No filament profiles saved yet. Create one via \'Save as profile\' in the filament area.'**
  String get settingsFilamentPickEmpty;

  /// No description provided for @settingsFilamentNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No profiles with matching material for this tray.'**
  String get settingsFilamentNoMatch;

  /// No description provided for @focusHintDpad.
  ///
  /// In en, this message translates to:
  /// **'Use D-pad / Tab to move focus, Enter / Space to activate.'**
  String get focusHintDpad;

  /// No description provided for @sampleBannerPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Milestone 1 scaffold with sample data — nothing is wired yet.'**
  String get sampleBannerPlaceholder;

  /// No description provided for @settingsAreaProcess.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get settingsAreaProcess;

  /// No description provided for @settingsAreaFilament.
  ///
  /// In en, this message translates to:
  /// **'Filament'**
  String get settingsAreaFilament;

  /// No description provided for @settingsFilamentBase.
  ///
  /// In en, this message translates to:
  /// **'Base profile: {name}'**
  String settingsFilamentBase(String name);

  /// No description provided for @settingsFilamentNoSlot.
  ///
  /// In en, this message translates to:
  /// **'No slot assignment known. Connect to the printer and reload Canvas.'**
  String get settingsFilamentNoSlot;

  /// No description provided for @projectProfilePickTitle.
  ///
  /// In en, this message translates to:
  /// **'Load profile'**
  String get projectProfilePickTitle;

  /// No description provided for @projectProfileStandard.
  ///
  /// In en, this message translates to:
  /// **'Orca default (0.20mm Standard)'**
  String get projectProfileStandard;

  /// No description provided for @projectProfilePickEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved profiles yet. Save one from Settings → Save as profile.'**
  String get projectProfilePickEmpty;

  /// No description provided for @projectProfileMissing.
  ///
  /// In en, this message translates to:
  /// **'Saved profile missing: {slug}'**
  String projectProfileMissing(String slug);

  /// No description provided for @tabPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get tabPrinter;

  /// No description provided for @printerHistoryHeading.
  ///
  /// In en, this message translates to:
  /// **'Print history'**
  String get printerHistoryHeading;

  /// No description provided for @printerHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No prints yet.'**
  String get printerHistoryEmpty;

  /// No description provided for @printerHistoryRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get printerHistoryRefresh;

  /// No description provided for @printerHistoryClock.
  ///
  /// In en, this message translates to:
  /// **'Timestamps are the printer\'s own clock (currently UTC+8), used only as an ordering key.'**
  String get printerHistoryClock;

  /// No description provided for @printerTaskStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get printerTaskStatusCompleted;

  /// No description provided for @printerTaskStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get printerTaskStatusCancelled;

  /// No description provided for @printerTaskStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get printerTaskStatusFailed;

  /// No description provided for @printerTaskStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown ({code})'**
  String printerTaskStatusUnknown(int code);

  /// No description provided for @printerVideoNone.
  ///
  /// In en, this message translates to:
  /// **'No time-lapse'**
  String get printerVideoNone;

  /// No description provided for @printerVideoRenderable.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse frames available'**
  String get printerVideoRenderable;

  /// No description provided for @printerVideoReady.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse video ready'**
  String get printerVideoReady;

  /// No description provided for @printerVideoNotRenderable.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse not renderable'**
  String get printerVideoNotRenderable;

  /// No description provided for @printerVideoDurationBytes.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s · {kib} KiB'**
  String printerVideoDurationBytes(int seconds, int kib);

  /// No description provided for @printerDurationShort.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String printerDurationShort(int minutes);

  /// No description provided for @printerDownloadCheck.
  ///
  /// In en, this message translates to:
  /// **'Checking availability…'**
  String get printerDownloadCheck;

  /// No description provided for @printerDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get printerDownloadButton;

  /// No description provided for @printerDownloadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No longer available (deleted on the printer?)'**
  String get printerDownloadUnavailable;

  /// No description provided for @printerDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get printerDownloadStarted;

  /// No description provided for @printerDownloadDone.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String printerDownloadDone(String path);

  /// No description provided for @printerDownloadDoneGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to Movies/Handslice (visible in Gallery)'**
  String get printerDownloadDoneGallery;

  /// No description provided for @printerDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {msg}'**
  String printerDownloadFailed(String msg);

  /// No description provided for @printerShareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get printerShareButton;

  /// No description provided for @printerRenderButton.
  ///
  /// In en, this message translates to:
  /// **'Create video'**
  String get printerRenderButton;

  /// No description provided for @printerRenderStarted.
  ///
  /// In en, this message translates to:
  /// **'Rendering…'**
  String get printerRenderStarted;

  /// No description provided for @printerRenderNoFrames.
  ///
  /// In en, this message translates to:
  /// **'No raw frames available for this print.'**
  String get printerRenderNoFrames;

  /// No description provided for @printerRenderFailed.
  ///
  /// In en, this message translates to:
  /// **'Render failed: {msg}'**
  String printerRenderFailed(String msg);

  /// No description provided for @printerRenderNotPossible.
  ///
  /// In en, this message translates to:
  /// **'Not renderable (no raw frames on the printer)'**
  String get printerRenderNotPossible;

  /// No description provided for @printStatusVideoComposing.
  ///
  /// In en, this message translates to:
  /// **'Creating/exporting time-lapse'**
  String get printStatusVideoComposing;

  /// No description provided for @printStatusException1243.
  ///
  /// In en, this message translates to:
  /// **'Filament feed error — check PTFE tubes'**
  String get printStatusException1243;

  /// No description provided for @substatePausing.
  ///
  /// In en, this message translates to:
  /// **'Pausing'**
  String get substatePausing;

  /// No description provided for @substatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get substatePaused;

  /// No description provided for @substateResuming.
  ///
  /// In en, this message translates to:
  /// **'Resuming'**
  String get substateResuming;

  /// No description provided for @substateResumed.
  ///
  /// In en, this message translates to:
  /// **'Resumed'**
  String get substateResumed;

  /// No description provided for @printerNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Printer not connected.'**
  String get printerNotConnected;

  /// No description provided for @printerConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Pair and connect from the Project tab.'**
  String get printerConnectHint;

  /// No description provided for @printControlSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Print controls'**
  String get printControlSectionLabel;

  /// No description provided for @printControlPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get printControlPause;

  /// No description provided for @printControlResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get printControlResume;

  /// No description provided for @printControlCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel print'**
  String get printControlCancel;

  /// No description provided for @printControlCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel the running print?'**
  String get printControlCancelConfirmTitle;

  /// No description provided for @printControlCancelConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This stops the print immediately. It cannot be undone from the app.'**
  String get printControlCancelConfirmBody;

  /// No description provided for @printControlCancelConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get printControlCancelConfirmYes;

  /// No description provided for @printControlCancelConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'Keep printing'**
  String get printControlCancelConfirmNo;

  /// No description provided for @printControlLightLabel.
  ///
  /// In en, this message translates to:
  /// **'Chamber light'**
  String get printControlLightLabel;

  /// No description provided for @printControlLightUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown (printer doesn\'t broadcast light state)'**
  String get printControlLightUnknown;

  /// No description provided for @printControlResumeHint.
  ///
  /// In en, this message translates to:
  /// **'Resume sent — the printer replies only after the move completes (up to ~2 min).'**
  String get printControlResumeHint;

  /// No description provided for @printControlFailedPause.
  ///
  /// In en, this message translates to:
  /// **'Pause rejected by the printer: {detail}'**
  String printControlFailedPause(String detail);

  /// No description provided for @printControlFailedCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel rejected by the printer: {detail}'**
  String printControlFailedCancel(String detail);

  /// No description provided for @printControlFailedLight.
  ///
  /// In en, this message translates to:
  /// **'Chamber light command failed: {detail}'**
  String printControlFailedLight(String detail);

  /// No description provided for @printPhaseCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get printPhaseCancelling;

  /// No description provided for @printPhaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get printPhaseCancelled;

  /// No description provided for @printPhasePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get printPhasePreparing;

  /// No description provided for @machineStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get machineStatusUnknown;

  /// No description provided for @machineStatusInitializing.
  ///
  /// In en, this message translates to:
  /// **'initializing'**
  String get machineStatusInitializing;

  /// No description provided for @machineStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get machineStatusIdle;

  /// No description provided for @machineStatusPrinting.
  ///
  /// In en, this message translates to:
  /// **'printing'**
  String get machineStatusPrinting;

  /// No description provided for @machineStatusFilamentOp.
  ///
  /// In en, this message translates to:
  /// **'filament operation'**
  String get machineStatusFilamentOp;

  /// No description provided for @machineStatusAutoLeveling.
  ///
  /// In en, this message translates to:
  /// **'auto-levelling'**
  String get machineStatusAutoLeveling;

  /// No description provided for @machineStatusPidCalibrating.
  ///
  /// In en, this message translates to:
  /// **'PID calibration'**
  String get machineStatusPidCalibrating;

  /// No description provided for @machineStatusResonanceTesting.
  ///
  /// In en, this message translates to:
  /// **'resonance test'**
  String get machineStatusResonanceTesting;

  /// No description provided for @machineStatusSelfChecking.
  ///
  /// In en, this message translates to:
  /// **'self-check'**
  String get machineStatusSelfChecking;

  /// No description provided for @machineStatusUpdating.
  ///
  /// In en, this message translates to:
  /// **'firmware update'**
  String get machineStatusUpdating;

  /// No description provided for @machineStatusHoming.
  ///
  /// In en, this message translates to:
  /// **'homing'**
  String get machineStatusHoming;

  /// No description provided for @machineStatusFileTransferring.
  ///
  /// In en, this message translates to:
  /// **'file transfer'**
  String get machineStatusFileTransferring;

  /// No description provided for @machineStatusVideoComposing.
  ///
  /// In en, this message translates to:
  /// **'composing timelapse'**
  String get machineStatusVideoComposing;

  /// No description provided for @machineStatusExtruderOp.
  ///
  /// In en, this message translates to:
  /// **'extruder operation'**
  String get machineStatusExtruderOp;

  /// No description provided for @machineStatusEmergencyStop.
  ///
  /// In en, this message translates to:
  /// **'emergency stop'**
  String get machineStatusEmergencyStop;

  /// No description provided for @machineStatusPowerLossRecovery.
  ///
  /// In en, this message translates to:
  /// **'power-loss recovery'**
  String get machineStatusPowerLossRecovery;

  /// No description provided for @machineStatusOther.
  ///
  /// In en, this message translates to:
  /// **'status {code}'**
  String machineStatusOther(int code);

  /// No description provided for @printerErrorBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer error'**
  String get printerErrorBannerTitle;

  /// No description provided for @printerErrorsBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer errors ({count})'**
  String printerErrorsBannerTitle(int count);

  /// No description provided for @exceptionCodeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Printer error {code}'**
  String exceptionCodeUnknown(int code);

  /// No description provided for @reconnectBannerLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost — reconnecting…'**
  String get reconnectBannerLost;

  /// No description provided for @reconnectBannerRetrying.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting in {seconds}s…'**
  String reconnectBannerRetrying(int seconds);

  /// No description provided for @reconnectBannerBackoff.
  ///
  /// In en, this message translates to:
  /// **'Reconnect failed — next attempt in {seconds}s.'**
  String reconnectBannerBackoff(int seconds);

  /// No description provided for @printerSectionFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get printerSectionFiles;

  /// No description provided for @printerSectionHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get printerSectionHistory;

  /// No description provided for @printerSectionCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get printerSectionCamera;

  /// No description provided for @printerFilesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files on the printer yet.'**
  String get printerFilesEmpty;

  /// No description provided for @printerFilesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get printerFilesRefresh;

  /// No description provided for @printerFilesSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get printerFilesSizeLabel;

  /// No description provided for @printerFilesLayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get printerFilesLayersLabel;

  /// No description provided for @printerFilesPrintTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Print time'**
  String get printerFilesPrintTimeLabel;

  /// No description provided for @printerFilesCurrentPrint.
  ///
  /// In en, this message translates to:
  /// **'Currently printing — cannot delete'**
  String get printerFilesCurrentPrint;

  /// No description provided for @printerFilesPrintButton.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printerFilesPrintButton;

  /// No description provided for @printerFilesDownloadButton.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get printerFilesDownloadButton;

  /// No description provided for @printerFilesDeleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get printerFilesDeleteButton;

  /// No description provided for @printerFilesDeleteBlockedRunning.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete the file of the running print'**
  String get printerFilesDeleteBlockedRunning;

  /// No description provided for @printerFilesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this file from the printer?'**
  String get printerFilesDeleteConfirmTitle;

  /// No description provided for @printerFilesDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove {name} from the printer. It cannot be undone from the app.'**
  String printerFilesDeleteConfirmBody(String name);

  /// No description provided for @printerFilesDeleteConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, delete'**
  String get printerFilesDeleteConfirmYes;

  /// No description provided for @printerFilesDeleteConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'Keep file'**
  String get printerFilesDeleteConfirmNo;

  /// No description provided for @printerFilesDownloadDone.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String printerFilesDownloadDone(String path);

  /// No description provided for @printerFilesDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {msg}'**
  String printerFilesDownloadFailed(String msg);

  /// No description provided for @printerFilesDownloadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File not downloadable right now (head-probe failed).'**
  String get printerFilesDownloadUnavailable;

  /// No description provided for @printerFilesPrintTitle.
  ///
  /// In en, this message translates to:
  /// **'Print this file?'**
  String get printerFilesPrintTitle;

  /// No description provided for @printerFilesPrintSlot.
  ///
  /// In en, this message translates to:
  /// **'Current slot'**
  String get printerFilesPrintSlot;

  /// No description provided for @printerFilesPrintStart.
  ///
  /// In en, this message translates to:
  /// **'Start print'**
  String get printerFilesPrintStart;

  /// No description provided for @printerFilesPrintCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get printerFilesPrintCancel;

  /// No description provided for @printerFilesVisualCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Keep an eye on the first layer at the printer.'**
  String get printerFilesVisualCheckHint;

  /// No description provided for @printerCameraHeading.
  ///
  /// In en, this message translates to:
  /// **'Live camera'**
  String get printerCameraHeading;

  /// No description provided for @printerCameraLoading.
  ///
  /// In en, this message translates to:
  /// **'Connecting to camera…'**
  String get printerCameraLoading;

  /// No description provided for @printerCameraPaused.
  ///
  /// In en, this message translates to:
  /// **'Camera off (section hidden or app in background).'**
  String get printerCameraPaused;

  /// No description provided for @printerCameraNoUrl.
  ///
  /// In en, this message translates to:
  /// **'Could not get the stream URL from the printer.'**
  String get printerCameraNoUrl;

  /// No description provided for @printerCameraNoUrlDetail.
  ///
  /// In en, this message translates to:
  /// **'method 1042 failed: {detail}'**
  String printerCameraNoUrlDetail(String detail);

  /// No description provided for @printerCameraStreamError.
  ///
  /// In en, this message translates to:
  /// **'Stream error: {detail}'**
  String printerCameraStreamError(String detail);

  /// No description provided for @printerCameraTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the image for fullscreen'**
  String get printerCameraTapHint;

  /// No description provided for @printerCameraFullscreenClose.
  ///
  /// In en, this message translates to:
  /// **'Close fullscreen'**
  String get printerCameraFullscreenClose;

  /// No description provided for @printerFilesHeading.
  ///
  /// In en, this message translates to:
  /// **'Printer files'**
  String get printerFilesHeading;

  /// No description provided for @printerFilesDownloadDoneDownloads.
  ///
  /// In en, this message translates to:
  /// **'Saved to Download/Handslice (visible in Files app)'**
  String get printerFilesDownloadDoneDownloads;

  /// No description provided for @printerFilesDownloadOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get printerFilesDownloadOpen;

  /// No description provided for @printerFilesDownloadShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get printerFilesDownloadShare;

  /// No description provided for @printerFilesPrintPickSlot.
  ///
  /// In en, this message translates to:
  /// **'Choose slot'**
  String get printerFilesPrintPickSlot;

  /// No description provided for @printerFilesPrintSlotsUnknown.
  ///
  /// In en, this message translates to:
  /// **'Slot info unavailable (not connected?).'**
  String get printerFilesPrintSlotsUnknown;

  /// No description provided for @printerFilesFilamentIndex.
  ///
  /// In en, this message translates to:
  /// **'Filament {idx}'**
  String printerFilesFilamentIndex(int idx);

  /// No description provided for @printLevelBed.
  ///
  /// In en, this message translates to:
  /// **'Level bed before printing (~200 s)'**
  String get printLevelBed;

  /// No description provided for @startPrintForcedLevelHint.
  ///
  /// In en, this message translates to:
  /// **'Printer has no mesh data — forcing levelling'**
  String get startPrintForcedLevelHint;

  /// No description provided for @controlVerbPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get controlVerbPause;

  /// No description provided for @controlVerbCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get controlVerbCancel;

  /// No description provided for @controlVerbLight.
  ///
  /// In en, this message translates to:
  /// **'Chamber light'**
  String get controlVerbLight;

  /// No description provided for @controlFailedTimeout.
  ///
  /// In en, this message translates to:
  /// **'{verb}: no reply from the printer in time'**
  String controlFailedTimeout(String verb);

  /// No description provided for @controlFailedWithCode.
  ///
  /// In en, this message translates to:
  /// **'{verb} rejected by the printer (error_code={code})'**
  String controlFailedWithCode(String verb, String code);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
