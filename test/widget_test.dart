import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_ct/app.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PokemonCTApp());
    expect(find.byType(PokemonCTApp), findsOneWidget);
  });
}
