import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/slicer.dart';
import 'l10n/app_localizations.dart';
import 'screens/project_screen.dart';
import 'screens/print_screen.dart';
import 'screens/settings_screen.dart';
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

  runApp(HandsliceApp(slicer: slicer, projectState: projectState));
}

class HandsliceApp extends StatelessWidget {
  const HandsliceApp({
    super.key,
    required this.slicer,
    required this.projectState,
  });

  final SlicerService slicer;
  final ProjectState projectState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildWorkshopTheme(),
      debugShowCheckedModeBanner: false,
      home: RootShell(slicer: slicer, projectState: projectState),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.slicer,
    required this.projectState,
  });

  final SlicerService slicer;
  final ProjectState projectState;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final screens = [
      ProjectScreen(slicer: widget.slicer, projectState: widget.projectState),
      PrintScreen(projectState: widget.projectState),
      const SettingsScreen(),
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
