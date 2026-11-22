import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lafleurmusic/ui/error_box.dart';

class _Boom extends StatelessWidget {
  const _Boom();
  @override
  Widget build(BuildContext context) => throw StateError('album sans nom');
}

void main() {
  test('la cause : le type, le message et l\'endroit de l\'appli', () {
    final d = FlutterErrorDetails(
      exception: StateError('album sans nom'),
      stack: StackTrace.fromString(
        '#0      Foo.bar (package:flutter/src/widgets/framework.dart:1:1)\n'
        '#1      _Rows.build (package:lafleurmusic/ui/phone/home_screen.dart:241:12)\n',
      ),
    );
    final t = ErrorBox.describe(d);
    expect(t, contains('StateError'));
    expect(t, contains('album sans nom'));
    expect(t, contains('home_screen.dart:241:12'));
    expect(t, isNot(contains('framework.dart')));
  });

  test('un message très long est coupé', () {
    final d = FlutterErrorDetails(exception: Exception('x' * 2000));
    expect(ErrorBox.describe(d).length, lessThanOrEqualTo(401));
  });

  testWidgets(
    'dans une liste, la boîte prend la hauteur de son texte, pas tout l\'écran',
    (tester) async {
      final old = ErrorWidget.builder;
      ErrorWidget.builder = (d) => ErrorBox(d);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ListView(
              children: const [Text('ALBUMS'), _Boom(), Text('après')],
            ),
          ),
        );
        expect(tester.takeException(), isA<StateError>());
        expect(find.textContaining('album sans nom'), findsOneWidget);
        expect(tester.getSize(find.byType(ErrorBox)).height, lessThan(200));
        expect(find.text('après'), findsOneWidget);
      } finally {
        ErrorWidget.builder = old;
      }
    },
  );
}
