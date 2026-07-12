import 'package:flutter_test/flutter_test.dart';
import 'package:lalomita_mobile/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const LaLomitaApp());
    expect(find.byType(LaLomitaApp), findsOneWidget);
  });
}
