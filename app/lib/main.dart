import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/slicer.dart';
import 'l10n/app_localizations.dart';
import 'screens/project_screen.dart';
import 'screens/print_screen.dart';
import 'screens/settings_screen.dart';
import 'settings/settings_overrides.dart';
import 'settings/settings_schema.dart';
import 'state/printer_state.dart';
import 'state/project_state.dart';
import 'theme/workshop_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: WorkshopTokens.background,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: WorkshopTokens.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

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
      ),
      PrintScreen(
        projectState: widget.projectState,
        printerState: widget.printerState,
      ),
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
