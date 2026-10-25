import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'screens/project_screen.dart';
import 'screens/print_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/workshop_theme.dart';

void main() {
  // Dunkle Statusleiste + Nav-Bar passend zum Werkstatt-Hintergrund.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: WorkshopTokens.background,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: WorkshopTokens.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const HandsliceApp());
}

class HandsliceApp extends StatelessWidget {
  const HandsliceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildWorkshopTheme(),
      debugShowCheckedModeBanner: false,
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final screens = [
      const ProjectScreen(),
      const PrintScreen(),
      const SettingsScreen(),
    ];

    // FocusTraversalGroup fuer die ganze Shell, damit D-Pad-Nav
    // deterministisch den Reading-Order durchlaeuft.
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
