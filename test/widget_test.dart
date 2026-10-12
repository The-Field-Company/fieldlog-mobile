import 'package:app_links/app_links.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldlog_mobile/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(FieldLogApp(initialRoute: '/login', appLinks: AppLinks()));
    expect(find.text('Scientific Field Data Collection'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
