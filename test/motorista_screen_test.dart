import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taximetro/core/constantes.dart';
import 'package:taximetro/screens/motorista_screen.dart';
import 'package:taximetro/state/taximetro_state.dart';
import 'package:taximetro/widgets/ui.dart';

/// 3.4.0 — a tela do cadastro, tocada como o motorista toca.
void main() {
  Finder campo(String rotulo) => find.descendant(
        of: find.byWidgetPredicate((w) => w is CampoApp && w.label == rotulo),
        matching: find.byType(TextField),
      );

  Future<TaximetroState> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final estado = TaximetroState();
    await tester.pumpWidget(
      ChangeNotifierProvider<TaximetroState>.value(
        value: estado,
        child: const MaterialApp(home: MotoristaScreen()),
      ),
    );
    return estado;
  }

  Future<void> salvar(WidgetTester tester) async {
    await tester.tap(find.text('SALVAR DADOS'));
    await tester.pumpAndSettle();
  }

  testWidgets('CNPJ errado avisa e nao grava', (tester) async {
    final estado = await abrir(tester);
    await tester.enterText(campo('Nome da empresa'), 'Transportes Exemplo');
    await tester.enterText(campo('CNPJ'), '11222333000180');
    await tester.pump();
    expect(find.text('CNPJ incompleto ou inválido. Confira o número.'), findsOneWidget);
    await salvar(tester);
    expect(estado.config.empresaNome, '');
    expect(estado.config.empresaCnpj, '');
    final p = await SharedPreferences.getInstance();
    expect(p.getString(Constantes.chaveConfig), isNull);
  });

  testWidgets('CNPJ certo ganha pontuacao, grava e aparece na previa', (tester) async {
    final estado = await abrir(tester);
    await tester.enterText(campo('Nome da empresa'), 'Transportes Exemplo');
    await tester.enterText(campo('CNPJ'), '12abc34501de35');
    await salvar(tester);
    expect(estado.config.empresaNome, 'Transportes Exemplo');
    expect(estado.config.empresaCnpj, '12.ABC.345/01DE-35');
    expect(find.text('CNPJ 12.ABC.345/01DE-35'), findsOneWidget);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(Constantes.chaveConfig), contains('Transportes Exemplo'));
  });

  testWidgets('quem nao tem empresa salva com os dois campos em branco', (tester) async {
    final estado = await abrir(tester);
    await tester.enterText(campo('Nome completo'), 'Fulano de Tal');
    await salvar(tester);
    expect(estado.config.motoristaNome, 'Fulano de Tal');
    expect(estado.config.empresaCnpj, '');
    expect(find.textContaining('CNPJ 1'), findsNothing);
  });
}
