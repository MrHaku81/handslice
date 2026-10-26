import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/slicer.dart';
import 'l10n/app_localizations.dart';
import 'screens/project_screen.dart';
import 'screens/print_screen.dart';
import 'screens/printer_screen.dart';
import 'screens/settings_screen.dart';
import 'settings/settings_overrides.dart';
import 'settings/settings_schema.dart';
import 'state/printer_state.dart';
import 'state/project_state.dart';
import 'theme/workshop_theme.dart';
import 'widgets/build_info_badge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: WorkshopTokens.background,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: WorkshopTokens.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Startup-Guard: Wenn die Build-Metadaten fehlen (BUILD_COMMIT/
  // CLI_COMMIT/BUILD_TIME), wurde das APK nicht via
  // app/scripts/build_apk.sh gebaut – die App startet dann nicht
  // als Projekt-/Druck-UI, sondern zeigt ein Vollbild-Fehler-Overlay
  // mit konkretem Hinweis. Grund: ein Release ohne Hashes verwirrt
  // bei Debug-Rueckfragen ("welche App-/CLI-Version lief?"), und
  // Flutter kann dart-defines selbst nicht erzwingen.
  if (BuildInfoBadge.hasMissingMetadata) {
    runApp(const _MissingBuildMetadataApp());
    return;
  }

  // Harte Startreihenfolge: Prefs + Slicer init vor runApp – damit die
  // Projekt-Screen beim ersten Build schon lauffaehigen State hat.
  final prefs = await SharedPreferences.getInstance();
  final slicer = SlicerService();
  try {
    await slicer.init();
  } catch (e) {
    // Keine fatale Haltung – auf Hosts ohne das Binary (z. B.
    // flutter_test, Linux-Desktop) soll die UI trotzdem bauen.
    debugPrint('SlicerService.init() fehlgeschlagen: $e');
  }
  final projectState = ProjectState(prefs);
  // flutter_secure_storage 11.x: AndroidOptions nutzt EncryptedSharedPreferences
  // als Default-Backend (JetSec); kein eigener Flag mehr noetig.
  final printerState = PrinterState(
    prefs: prefs,
    secure: const FlutterSecureStorage(aOptions: AndroidOptions.defaultOptions),
  );
  // Phase 4.2: Einstellungs-Schema aus Asset laden. Schlaegt fehl, wenn
  // der Asset-Bundle nicht da ist (etwa im Test ohne pumpAsset) – dann
  // leeres Schema, damit die App weiterhin startet.
  SettingsSchema settings;
  try {
    settings = await SettingsSchema.loadFromAsset();
  } catch (e) {
    debugPrint('SettingsSchema.loadFromAsset() fehlgeschlagen: $e');
    settings = const SettingsSchema(orcaVersion: '', pagesByArea: {});
  }
  final overrides = SettingsOverrides();

  runApp(HandsliceApp(
    slicer: slicer,
    projectState: projectState,
    printerState: printerState,
    settingsSchema: settings,
    overrides: overrides,
  ));
}

class HandsliceApp extends StatelessWidget {
  const HandsliceApp({
    super.key,
    required this.slicer,
    required this.projectState,
    required this.printerState,
    required this.settingsSchema,
    required this.overrides,
  });

  final SlicerService slicer;
  final ProjectState projectState;
  final PrinterState printerState;
  final SettingsSchema settingsSchema;
  final SettingsOverrides overrides;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildWorkshopTheme(),
      debugShowCheckedModeBanner: false,
      home: RootShell(
        slicer: slicer,
        projectState: projectState,
        printerState: printerState,
        settingsSchema: settingsSchema,
        overrides: overrides,
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.slicer,
    required this.projectState,
    required this.printerState,
    required this.settingsSchema,
    required this.overrides,
  });

  final SlicerService slicer;
  final ProjectState projectState;
  final PrinterState printerState;
  final SettingsSchema settingsSchema;
  final SettingsOverrides overrides;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final screens = [
      ProjectScreen(
        slicer: widget.slicer,
        projectState: widget.projectState,
        printerState: widget.printerState,
        overrides: widget.overrides,
      ),
      PrintScreen(
        projectState: widget.projectState,
        printerState: widget.printerState,
      ),
      PrinterScreen(printerState: widget.printerState),
      SettingsScreen(
        schema: widget.settingsSchema,
        overrides: widget.overrides,
      ),
    ];

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Scaffold(
        body: SafeArea(child: screens[_index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: l.tabProject,
            ),
            NavigationDestination(
              icon: const Icon(Icons.print_outlined),
              selectedIcon: const Icon(Icons.print),
              label: l.tabPrint,
            ),
            NavigationDestination(
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history),
              label: l.tabPrinter,
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune),
              label: l.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}

// Fehler-UI, wenn `BuildInfoBadge.hasMissingMetadata` beim Start true
// war. Blockiert die restliche App bewusst – ein Release ohne
// nachvollziehbaren Build-Stand wird nicht angeboten.
class _MissingBuildMetadataApp extends StatelessWidget {
  const _MissingBuildMetadataApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildWorkshopTheme(),
      home: Scaffold(
        backgroundColor: WorkshopTokens.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.error_outline,
                      size: 48, color: Color(0xFFE57373)),
                  SizedBox(height: 16),
                  Text(
                    'Build-Metadaten fehlen',
                    style: TextStyle(
                      color: WorkshopTokens.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Dieses APK wurde ohne die üblichen Build-Hashes '
                    'erstellt. App-Commit und CLI-Commit sind unbekannt, '
                    'deshalb lässt sich dieser Stand im Zweifelsfall nicht '
                    'reproduzieren.',
                    style: TextStyle(color: WorkshopTokens.text),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Fix: statt flutter build apk das Skript '
                    'app/scripts/build_apk.sh verwenden (setzt '
                    '--dart-define BUILD_COMMIT / CLI_COMMIT / '
                    'BUILD_TIME und prüft, dass die arm64-CLI zum '
                    'App-Commit passt).',
                    style: TextStyle(color: WorkshopTokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
