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

  test('descricao do periodo para o relatorio em PDF', () {
    final s = TaximetroState();
    final agora = DateTime(2026, 10, 23, 9, 30);
    s.definirFiltro(FiltroPeriodo.mes);
    expect(s.descricaoPeriodo(agora: agora), 'Outubro de 2026 (até 23/10/2026)');
    s.definirFiltro(FiltroPeriodo.semana);
    expect(s.descricaoPeriodo(agora: agora), 'Últimos 7 dias (16/10/2026 a 23/10/2026)');
    s.definirFiltro(FiltroPeriodo.hoje);
    expect(s.descricaoPeriodo(agora: agora), 'Hoje, 23/10/2026');
    s.definirPeriodoPersonalizado(DateTime(2026, 10, 1), DateTime(2026, 10, 15));
    expect(s.descricaoPeriodo(agora: agora), 'De 01/10/2026 a 15/10/2026');
  });
}
