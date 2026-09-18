import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:star_trek_ccg_collector/main.dart';

void main() {
  testWidgets('App boots to the Sets tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StarTrekCcgApp()));
    await tester.pump();

    expect(find.text('Sets'), findsWidgets);
  });
}
