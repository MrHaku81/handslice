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
  /// **'Printer IP (e.g. <cc2-ip>)'**
  String get pairDialogIp;

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
  /// **'Z-offset per plate (saved only)'**
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
  /// **'±0.50 mm, 0.01 mm steps — not applied yet.'**
  String get projectZOffsetHint;

  /// No description provided for @projectSliceButton.
  ///
  /// In en, this message translates to:
  /// **'Slice on device'**
  String get projectSliceButton;

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
