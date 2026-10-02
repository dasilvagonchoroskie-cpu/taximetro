import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taximetro/state/taximetro_state.dart';

/// 3.1.2 — o relogio da corrida. O Evandro viu no teste de 01/10/2026 o
/// tempo contar 1, 2, 3, 4, "travar" um segundo e seguir. Estes testes usam
/// um relogio de mentira e leituras de GPS em intervalos irregulares, como
/// no celular, e conferem que a tela anda de segundo em segundo, que nada se
/// perde e que o odometro marca a distancia certa andando devagar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const lat0 = -18.0;
  const lng0 = -49.35;
  double grausDeLatitude(double metros) => metros / 6371000.0 * 180 / math.pi;

  Position ponto(double metrosAoNorte, {double velocidadeMs = 0}) => Position(
        latitude: lat0 + grausDeLatitude(metrosAoNorte),
        longitude: lng0,
        timestamp: DateTime(2026, 10, 1),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: velocidadeMs,
        speedAccuracy: 0,
      );

  late int agora;
  late int inicio;
  late TaximetroState s;

  void comecar() {
    agora = 1000000;
    inicio = agora;
    s = TaximetroState()..relogioParaTeste = () => agora;
    s.comecarContagemParaTeste();
  }

  int segundosPassados() => (agora - inicio) ~/ 1000;

  /// Anda o relogio como o Timer do app (um tique a cada 1/4 de segundo) e
  /// confere, a cada tique, que a tela mostra o tempo de verdade.
  void avancar(int ms) {
    var falta = ms;
    while (falta >= 250) {
      agora += 250;
      falta -= 250;
      s.tiqueDoRelogioParaTeste();
      expect(s.estado.tempoTotalS, segundosPassados(), reason: 'tempo na tela travou ou pulou');
    }
    agora += falta;
  }

  test('sem GPS o tempo anda de segundo em segundo, sem travar e sem perder', () {
    comecar();
    final vistos = <int>[];
    for (var i = 0; i < 30; i++) {
      avancar(1000);
      vistos.add(s.estado.tempoTotalS);
    }
    expect(vistos, List.generate(30, (i) => i + 1));
    expect(s.estado.tempoParadoS, 30);
    expect(s.medidorParaTeste.totalS, closeTo(30, 1e-9));
  });

  test('GPS em intervalos irregulares: a tela nao trava e o tempo nao se perde', () {
    comecar();
    s.medirPosicaoParaTeste(ponto(0));
    const intervalos = [1000, 1125, 875, 1375, 625, 1000, 1250, 750, 1500, 2000];
    for (var volta = 0; volta < 6; volta++) {
      for (final ms in intervalos) {
        avancar(ms);
        s.medirPosicaoParaTeste(ponto(0));
        expect(s.estado.tempoTotalS, segundosPassados());
      }
    }
    final passou = (agora - inicio) / 1000;
    expect(s.medidorParaTeste.totalS, closeTo(passou, 1e-9));
    expect(s.medidorParaTeste.paradoS, closeTo(passou, 1e-9));
  });

  test('o primeiro GPS nao apaga o tempo do comeco da corrida', () {
    comecar();
    avancar(2000);
    s.medirPosicaoParaTeste(ponto(0));
    expect(s.medidorParaTeste.totalS, closeTo(2.0, 1e-9));
    expect(s.estado.tempoTotalS, 2);
  });

  test('andando a 7,2 km/h, 300 m marcam 300 m (antes marcava 450 m)', () {
    comecar();
    s.medirPosicaoParaTeste(ponto(0));
    var metros = 0.0;
    for (var i = 0; i < 150; i++) {
      avancar(1000);
      metros += 2;
      s.medirPosicaoParaTeste(ponto(metros, velocidadeMs: 2));
    }
    final r = s.montarRegistroParaTeste();
    expect(r.distanciaKm, closeTo(0.300, 0.001));
    expect(r.tempoS, 150);
  });

  test('Finalizar conta ate o toque, e a tela de pagamento nao conta', () async {
    comecar();
    s.medirPosicaoParaTeste(ponto(0));
    for (var i = 0; i < 10; i++) {
      avancar(1000);
      s.medirPosicaoParaTeste(ponto(0));
    }
    avancar(600);
    final valor = await s.pararParaPagamento();
    expect(s.medidorParaTeste.totalS, closeTo(10.6, 1e-9));
    expect(s.estado.tempoTotalS, 10);
    agora += 120000; // dois minutos na tela de pagamento
    final r = s.montarRegistroParaTeste();
    expect(r.tempoS, 10);
    expect(r.valor, closeTo(valor, 1e-9));
    expect(r.valor, closeTo(s.estado.valorTotal, 1e-9));
  });

  test('espera passando da franquia: o valor sobe com o relogio, sem esperar o GPS', () {
    comecar();
    s.medirPosicaoParaTeste(ponto(0));
    for (var i = 0; i < 300; i++) {
      avancar(1000);
      s.medirPosicaoParaTeste(ponto(0));
    }
    expect(s.estado.valorTotal, closeTo(10.0, 1e-9)); // 5 min dentro da franquia
    avancar(1250); // sem leitura do GPS: so o relogio
    expect(s.estado.tempoParadoS, 301);
    expect(s.estado.valorTotal, greaterThan(10.0));
    s.medirPosicaoParaTeste(ponto(0));
    expect(s.estado.valorTotal, closeTo(10 + 1.25 / 60 * s.config.taxaEspera, 1e-9));
  });
}
