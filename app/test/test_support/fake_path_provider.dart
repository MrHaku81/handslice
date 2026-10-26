// Minimaler Fake fuer path_provider: liefert einen temp-Ordner als
// Application-Support-Dir. Fuer Tests, die ProfileWriter/-Reader
// zusammen laufen lassen, ohne eine echte Platform anzubinden.

import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory root = Directory.systemTemp.createTempSync('handslice-profile-');

  @override
  Future<String?> getApplicationSupportPath() async => root.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getTemporaryPath() async => root.path;
}
