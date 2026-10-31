// Pflicht 7a-Nacharbeit: regression test for the "label squeezed
// to a vertical stack of single letters" layout bug the user hit
// on the chamber-light row.
//
// The pattern is: a Row with Expanded(label) + unflexed-widget +
// trailing action. On a narrow screen the unflexed widget takes
// its intrinsic width, Expanded(label) gets whatever's left, and
// if that's < 1 character the Text wraps per character.
//
// LabeledSwitchRow fixes the pattern by stacking label + subtitle
// vertically inside the Expanded. These tests pin the layout for
// future refactors.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:handslice/l10n/app_localizations.dart';
import 'package:handslice/theme/workshop_theme.dart';
import 'package:handslice/widgets/labeled_switch_row.dart';

Widget _wrap(Widget child, {double width = 320}) => MaterialApp(
      theme: buildWorkshopTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  group('LabeledSwitchRow', () {
    testWidgets('label stays on one line at 320 px wide', (tester) async {
      await tester.pumpWidget(_wrap(
        LabeledSwitchRow(
          label: 'Kammerlicht',
          value: false,
          onChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.text('Kammerlicht'));
      expect(size.height, lessThan(32),
          reason: 'label height ${size.height} suggests the text wrapped '
              'into multiple lines — layout regression.');
      expect(size.width, greaterThan(60),
          reason: 'label got width ${size.width}; expected the full "Kammerlicht" '
              'string to render horizontally.');
    });

    testWidgets('long subtitle does not squeeze the label at 320 px wide',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const LabeledSwitchRow(
          label: 'Kammerlicht',
          subtitle: 'unbekannt (Drucker meldet den Zustand nicht)',
          value: false,
          onChanged: null,
        ),
      ));
      await tester.pumpAndSettle();
      final labelSize = tester.getSize(find.text('Kammerlicht'));
      expect(labelSize.height, lessThan(32),
          reason: 'label got stacked per character because the subtitle '
              'robbed its horizontal space — the subtitle must sit BELOW '
              'the label, not next to it.');
      expect(labelSize.width, greaterThan(60));
      // Subtitle may wrap over multiple lines on 320 px — that's OK;
      // we only require the label itself to stay horizontal.
      expect(find.textContaining('unbekannt'), findsOneWidget);
    });

    testWidgets('switch stays on the right at 320 px with a subtitle',
        (tester) async {
      // The old Row-with-unflexed-subtitle layout would push the
      // switch down into a second row (or hide it) when the
      // subtitle took all the horizontal space. In the new layout
      // the Switch sits beside the Expanded label-column, so it
      // stays right-of the label and vertically centred.
      await tester.pumpWidget(_wrap(
        LabeledSwitchRow(
          label: 'Kammerlicht',
          subtitle: 'unbekannt (Drucker meldet den Zustand nicht)',
          value: false,
          onChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      final labelRect = tester.getRect(find.text('Kammerlicht'));
      final switchRect = tester.getRect(find.byType(Switch));
      expect(switchRect.left, greaterThan(labelRect.right),
          reason: 'Switch must sit to the right of the label column, not below.');
    });
  });
}
