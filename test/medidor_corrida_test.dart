import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/medidor_corrida.dart';
import 'package:taximetro/core/tarifador.dart';

/// Corridas simuladas com a tarifa do Fabiano: bandeirada R$ 10,00,
/// R$ 3,00/km, R$ 0,55/min, 1,5 km e 5 min incluidos.
void main() {
  const tarifa = Tarifador(
    taxaKm: 3.00,
    taxaEsperaPorMinuto: 0.55,
    kmIncluido: 1.5,
    minutosIncluido: 5,
  );

  MedidorCorrida nova([double bandeirada = 10]) => MedidorCorrida(tarifa)..comecar(bandeirada);

  /// Uma leitura do GPS por segundo. Como no app, cada leitura passa a
  /// distancia DESDE A ANCORA, que so avanca quando o trecho fecha.
  void rodar(MedidorCorrida m, int metros, {int metrosPorSegundo = 10}) {
    var desdeAncora = 0.0;
    for (var i = 0; i < metros ~/ metrosPorSegundo; i++) {
      desdeAncora += metrosPorSegundo;
      if (m.andou(desdeAncora, 1)) desdeAncora = 0;
    }
  }

  test('abre na bandeirada: R\$ 10,00 de dia (o 3.0 abria em zero)', () {
    expect(nova().total, 10.0);
  });

  test('bandeira 2 abre em R\$ 20,00', () {
    expect(nova(20).total, 20.0);
  });

  test('rodando 1 km continua R\$ 10,00', () {
    final m = nova();
    rodar(m, 1000);
    expect(m.total, closeTo(10.0, 1e-6));
  });

  test('rodando 2,5 km vai a R\$ 13,00', () {
    final m = nova();
    rodar(m, 2500);
    expect(m.distanciaKm, closeTo(2.5, 1e-6));
    expect(m.total, closeTo(13.0, 1e-6));
  });

  test('trecho que cruza a marca de 1,5 km cobra so o que passa', () {
    final m = nova();
    m.andou(1600, 60);
    expect(m.total, closeTo(10.30, 1e-6));
  });

  test('parado ate 5 min fica em R\$ 10,00; 7 min vai a R\$ 11,10', () {
    final m = nova();
    m.parou(4 * 60);
    expect(m.total, closeTo(10.0, 1e-6));
    m.parou(3 * 60);
    expect(m.total, closeTo(11.10, 1e-6));
  });

  test('transito devagar (3,6 km/h) conta como espera', () {
    final m = nova();
    rodar(m, 300, metrosPorSegundo: 1);
    expect(m.paradoS, closeTo(300, 1e-6));
    expect(m.total, closeTo(10.0, 1e-6));
    rodar(m, 120, metrosPorSegundo: 1);
    expect(m.total, closeTo(11.10, 1e-6));
  });

  test('a franquia de espera vale tambem no meio da corrida', () {
    final m = nova();
    rodar(m, 2000);
    expect(m.total, closeTo(11.50, 1e-6));
    m.parou(4 * 60);
    expect(m.total, closeTo(11.50, 1e-6));
    m.parou(2 * 60);
    expect(m.total, closeTo(12.05, 1e-6));
  });

  test('tremida do GPS parado nao vira distancia', () {
    final m = nova();
    m.andou(2, 1);
    m.parou(1);
    expect(m.distanciaKm, 0);
    expect(m.paradoS, closeTo(2, 1e-9));
  });

  test('corrida recuperada: distancia em linha reta, sem cobrar espera', () {
    final m = nova();
    m.distanciaRecuperada(2000, 300);
    expect(m.paradoS, 0);
    expect(m.total, closeTo(11.50, 1e-6));
  });

  test('grava e recupera a corrida sem mudar o valor', () {
    final m = nova();
    rodar(m, 2500);
    m.parou(7 * 60);
    final volta = MedidorCorrida.deJson(m.paraJson());
    expect(volta, isNotNull);
    expect(volta!.total, closeTo(m.total, 1e-9));
    expect(volta.distanciaKm, closeTo(m.distanciaKm, 1e-9));
  });

  // ---- 3.1.2 ----
  test('devagar o odometro nao conta em dobro (distancia desde a ancora)', () {
    final m = nova();
    m.andou(2, 1); // 2 m da ancora: ainda e tremida possivel
    m.andou(4, 1); // 4 m da ancora: fecha o trecho com 4 m, nao 2 + 4
    expect(m.distanciaKm, closeTo(0.004, 1e-9));
  });

  test('a 7,2 km/h, 300 m rodados marcam 300 m', () {
    final m = nova();
    rodar(m, 300, metrosPorSegundo: 2);
    expect(m.distanciaKm, closeTo(0.300, 1e-9));
    expect(m.totalS, closeTo(150, 1e-9));
  });

  test('tempo andando entre duas leituras entra no trecho aberto', () {
    final m = nova();
    m.andou(2, 1);
    m.tempoDoTrechoAberto(0.6);
    expect(m.totalS, closeTo(1.6, 1e-9));
    m.fecharTrecho();
    expect(m.paradoS, closeTo(1.6, 1e-9)); // 2 m valem menos que 1,6 s
  });
}
