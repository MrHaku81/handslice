// Unit-Tests fuer die Fehlertabelle aus
// `app/lib/net/cc2_exception_codes.dart`. Quelle Englisch: Orca-UI
// (locale "en"). DE: eigene sinngemaesse Uebersetzung.

import 'package:flutter_test/flutter_test.dart';
import 'package:handslice/net/cc2_exception_codes.dart';

void main() {
  group('cc2ExceptionLookup', () {
    test('bekannte Codes EN liefern Orca-Text', () {
      // Stichproben aus den drei Kernkategorien.
      final mainboardFan = cc2ExceptionLookup(701, locale: 'en');
      expect(mainboardFan, isNotNull);
      expect(mainboardFan, contains('Mainboard fan'));

      final clog = cc2ExceptionLookup(1243, locale: 'en');
      expect(clog, isNotNull);
      expect(clog, contains('toolhead'));

      final cloud = cc2ExceptionLookup(2003, locale: 'en');
      expect(cloud, isNotNull);
      expect(cloud, contains('cloud'));
    });

    test('bekannte Codes DE liefern uebersetzten Text', () {
      final mainboardFan = cc2ExceptionLookup(701, locale: 'de');
      expect(mainboardFan, isNotNull);
      expect(mainboardFan, contains('Mainboard-Lüfter'));

      final chamberHot = cc2ExceptionLookup(901, locale: 'de');
      expect(chamberHot, isNotNull);
      expect(chamberHot, contains('Kammer'));

      final usbFull = cc2ExceptionLookup(904, locale: 'de');
      expect(usbFull, isNotNull);
      expect(usbFull, contains('USB'));
    });

    test('locale-Fallback: "en-US" wird als Englisch behandelt', () {
      // locale.startsWith("de") → sonst immer EN.
      expect(cc2ExceptionLookup(701, locale: 'en-US'),
          equals(cc2ExceptionLookup(701, locale: 'en')));
      expect(cc2ExceptionLookup(701, locale: 'fr-FR'),
          equals(cc2ExceptionLookup(701, locale: 'en')));
      // de-DE und de-AT greifen beide die deutsche Tabelle
      expect(cc2ExceptionLookup(701, locale: 'de-DE'),
          equals(cc2ExceptionLookup(701, locale: 'de')));
    });

    test('unbekannte Codes liefern null (Caller zeigt "Printer error N")', () {
      expect(cc2ExceptionLookup(99999, locale: 'en'), isNull);
      expect(cc2ExceptionLookup(99999, locale: 'de'), isNull);
      // nicht in der Orca-Tabelle:
      expect(cc2ExceptionLookup(1500, locale: 'en'), isNull);
    });

    test('Tabelle EN hat alle Keys der Tabelle DE und umgekehrt', () {
      final enKeys = cc2ExceptionEn.keys.toSet();
      final deKeys = cc2ExceptionDe.keys.toSet();
      expect(enKeys, equals(deKeys),
          reason: 'EN und DE Tabellen muessen dieselben Codes abdecken');
    });

    test('Alle Texte sind nicht-leer', () {
      for (final v in cc2ExceptionEn.values) {
        expect(v, isNotEmpty);
      }
      for (final v in cc2ExceptionDe.values) {
        expect(v, isNotEmpty);
      }
    });

    test('77 Eintraege gemaess Orca-Bundle v2.4.2', () {
      // Sichert, dass die Tabelle nicht versehentlich schrumpft.
      // (Entries aus Orca `Zve`-Objekt, Pfad in cc2_exception_codes.dart
      // dokumentiert.)
      expect(cc2ExceptionEn.length, equals(77));
      expect(cc2ExceptionDe.length, equals(77));
    });

    test('1243 ist in der Tabelle als Clog-Variante enthalten', () {
      // UI behandelt 1243 separat ("Filamentzufuhr-Fehler"), aber
      // die Tabelle muss ihn trotzdem kennen, damit Fallback-Pfade
      // (z.B. Tests) ihn nicht als unbekannt melden.
      expect(cc2ExceptionEn.containsKey(1243), isTrue);
      expect(cc2ExceptionDe.containsKey(1243), isTrue);
    });
  });
}
