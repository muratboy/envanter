import 'package:envanter/ui/widgets/text_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ayar kaydı gibi, pencere kapanırken bütün uygulamayı yeniden çizen durum.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String name = '';
  int rebuilds = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final values = await showTextPrompt(
                  context,
                  title: 'Ad',
                  fields: const [PromptField(label: 'Adın')],
                  cancelLabel: 'Vazgeç',
                  confirmLabel: 'Kaydet',
                );
                // Kapanış animasyonu sürerken yeniden çiz.
                setState(() {
                  name = values?.single ?? '';
                  rebuilds++;
                });
              },
              child: Text('aç $name'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('pencere kapanırken uygulama yeniden çizilse de çökmez', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Ali');
    await tester.tap(find.text('Kaydet'));
    // Animasyonun ortasında birkaç kare: eski hata burada patlıyordu.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('aç Ali'), findsOneWidget);
  });

  testWidgets('vazgeçince null döner', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('aç '), findsOneWidget);
  });

  testWidgets('sayı alanında başlangıç değeri seçili gelir, diğerinde imleç sonda', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showTextPrompt(
              context,
              title: 'Adet',
              fields: const [
                PromptField(label: 'Adet', initial: '12', keyboardType: TextInputType.number, selectAll: true),
                PromptField(label: 'Not', initial: 'kutu'),
              ],
              cancelLabel: 'Vazgeç',
              confirmLabel: 'Tamam',
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(fields[1].controller!.selection, const TextSelection.collapsed(offset: 4));
  });
}
