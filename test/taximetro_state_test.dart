import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taximetro/state/taximetro_state.dart';

/// O defeito do 3.0: a tela abria em R$ 0,00 e o recibo saia sem a
/// bandeirada. Estes testes ligam o medidor ao que a tela e o recibo mostram.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a tela abre na bandeirada, nao em zero', () {
    final s = TaximetroState();
    s.comecarContagemParaTeste();
    expect(s.config.bandeiradaAtual, greaterThan(0));
    expect(s.estado.valorTotal, s.config.bandeiradaAtual);
  });

  test('rodando 2,5 km a tela mostra bandeirada + 1 km cobrado', () {
    final s = TaximetroState();
    s.comecarContagemParaTeste();
    for (var i = 0; i < 250; i++) {
      s.medidorParaTeste.andou(10, 1);
    }
    s.recalcularParaTeste();
    expect(s.estado.valorTotal, closeTo(s.config.bandeiradaAtual + s.config.taxaKm, 1e-6));
  });

  test('o recibo bate com a tela: bandeirada + distancia + espera', () {
    final s = TaximetroState();
    s.comecarContagemParaTeste();
    for (var i = 0; i < 250; i++) {
      s.medidorParaTeste.andou(10, 1);
    }
    s.medidorParaTeste.parou(7 * 60);
    s.recalcularParaTeste();
    final r = s.montarRegistroParaTeste();
    expect(r.valor, closeTo(s.estado.valorTotal, 1e-9));
    expect(r.valor, closeTo(r.bandeirada + r.valorDistancia + r.valorEspera, 1e-9));
    expect(r.bandeirada, s.config.bandeiradaAtual);
  });
}
