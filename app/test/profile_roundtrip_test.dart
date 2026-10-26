// Nachweis fuer Phase-5-Nacharbeit #1: Overrides direkt gesetzt vs.
// als Profil gespeichert und wieder geladen muessen am Ende identische
// Overrides fuer die Slicer-CLI ergeben. (Der Slicer kriegt
// `--overrides <json>`; wenn die beiden Maps gleich sind, ist der
// G-Code byte-identisch.)
//
// Kein Flutter-Widget-Zusammenbau, nur die Writer/Reader-Kette.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/settings/profile_reader.dart';
import 'package:handslice/settings/profile_writer.dart';
import 'package:handslice/settings/settings_overrides.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'test_support/fake_path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = FakePathProvider();
  });

  test('Save → Reload: Overrides identisch', () async {
    final overrides = SettingsOverrides();
    overrides.set('layer_height', '0.28');
    overrides.set('wall_loops', '4');
    overrides.set('sparse_infill_density', '40%');

    // Direkter Pfad (so wuerde die CLI heute gerufen werden)
    final direct = Map<String, String>.from(overrides.all);

    // Als Profil speichern
    final f = await const ProfileWriter().save(
      name: 'Testprofil 1',
      baseInherits: '0.20mm Standard @Elegoo CC2 0.4 nozzle',
      type: 'process',
      overrides: overrides.all,
    );
    expect(f.existsSync(), isTrue);

    // Simulierter App-Neustart: SettingsOverrides frisch, dann Profil
    // lesen und einspielen (so wie _applyProfile in project_screen.dart).
    final overrides2 = SettingsOverrides();
    final list = await const ProfileReader().list();
    expect(list.length, greaterThanOrEqualTo(1));
    final loaded = list.firstWhere((p) => p.name == 'Testprofil 1');
    for (final e in loaded.overrides.entries) {
      overrides2.set(e.key, e.value);
    }

    final reloaded = Map<String, String>.from(overrides2.all);
    expect(reloaded, equals(direct));
  });
}
