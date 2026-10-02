import 'dart:math' as math;

import 'constantes.dart';
import 'tarifador.dart';

/// A contagem da corrida, sem GPS, sem tela e sem Android: so a conta.
///
/// O estado do aplicativo entrega os trechos medidos (andando, parado ou sem
/// GPS) e le os totais daqui. Por ser uma peca pura, os testes simulam
/// corridas inteiras com ela. O TOTAL ja inclui a bandeirada: a corrida abre
/// em R$ 10,00 de dia (o 3.0 abria em R$ 0,00).
class MedidorCorrida {
  MedidorCorrida(this.tarifador);

  /// Tarifa congelada no comeco da corrida.
  final Tarifador tarifador;

  double bandeirada = 0;
  double distanciaKm = 0;
  double paradoS = 0;
  double totalS = 0;

  /// Km que valeram por distancia, no que passou da franquia.
  double kmCobrado = 0;
  bool jaAndou = false;

  /// Trecho rodado ainda aberto (fecha quando da distancia confiavel).
  double bufferDistanciaM = 0;
  double bufferTempoS = 0;

  void comecar(double bandeiradaDaCorrida) {
    bandeirada = bandeiradaDaCorrida;
    distanciaKm = 0;
    paradoS = 0;
    totalS = 0;
    kmCobrado = 0;
    jaAndou = false;
    bufferDistanciaM = 0;
    bufferTempoS = 0;
  }

  /// Carro andando. [metrosDesdeAncora] e a distancia do ponto onde o
  /// trecho comecou (a ancora) ate a leitura atual: enquanto o trecho nao
  /// fecha, a ancora nao anda, entao essa ja e a distancia do trecho todo
  /// (3.1.2: antes ela era SOMADA a cada leitura e, devagar, o odometro
  /// contava a mais). Devolve true quando o trecho fechou (a ancora pode
  /// avancar); false enquanto ainda acumula distancia confiavel.
  bool andou(double metrosDesdeAncora, double segundos) {
    bufferDistanciaM = metrosDesdeAncora;
    bufferTempoS += segundos;
    totalS += segundos;
    if (bufferDistanciaM >= Constantes.distanciaMinimaRuidoM) {
      fecharTrecho();
      return true;
    }
    return false;
  }

  /// Carro parado: o tempo vira espera, inclusive o do trecho aberto, e a
  /// distancia do trecho aberto era tremida do GPS.
  void parou(double segundos) {
    totalS += segundos;
    paradoS += segundos + bufferTempoS;
    bufferTempoS = 0;
    bufferDistanciaM = 0;
  }

  /// Leitura parada sem tempo medido: so descarta a tremida do GPS.
  void descartarTremida() => bufferDistanciaM = 0;

  /// GPS sem precisao: o tempo conta como espera, sem mexer no trecho aberto.
  void semGps(double segundos) {
    totalS += segundos;
    paradoS += segundos;
  }

  /// Tempo andando ainda sem leitura do GPS (ex.: tocou em Finalizar entre
  /// duas leituras): entra no trecho aberto, que decide distancia OU tempo.
  void tempoDoTrechoAberto(double segundos) {
    bufferTempoS += segundos;
    totalS += segundos;
  }

  /// Tempo sem distancia aproveitavel (salto impossivel do GPS).
  void soTempo(double segundos) => totalS += segundos;

  /// Distancia rodada enquanto o app ficou fechado: entra em linha reta
  /// (nunca mais que o rodado de verdade) e o tempo NAO vira espera.
  void distanciaRecuperada(double metros, double segundosSemMedir) {
    final antes = distanciaKm;
    distanciaKm += metros / 1000;
    kmCobrado += tarifador.kmCobravelDoTrecho(antes, distanciaKm);
    totalS += segundosSemMedir;
    if (!jaAndou && distanciaKm * 1000 >= Constantes.distanciaSaiuDoLugarM) jaAndou = true;
  }

  /// Fecha o trecho aberto: a distancia sempre entra no odometro, e o
  /// trecho vale por distancia OU por tempo — o que der mais.
  void fecharTrecho() {
    if (bufferDistanciaM <= 0 && bufferTempoS <= 0) return;
    final km = bufferDistanciaM / 1000;
    final antes = distanciaKm;
    distanciaKm += km;
    if (!jaAndou && distanciaKm * 1000 >= Constantes.distanciaSaiuDoLugarM) jaAndou = true;
    if (tarifador.trechoPorTempo(km, bufferTempoS)) {
      paradoS += bufferTempoS;
    } else {
      kmCobrado += tarifador.kmCobravelDoTrecho(antes, distanciaKm);
    }
    bufferDistanciaM = 0;
    bufferTempoS = 0;
  }

  double get valorDistancia => kmCobrado * tarifador.taxaKm;
  double get valorEspera => tarifador.valorEspera(paradoS);

  /// O que o passageiro paga: bandeirada + distancia + espera.
  double get total => bandeirada + valorDistancia + valorEspera;

  double get kmFranquiaUsada => tarifador.kmFranquiaUsada(distanciaKm);
  double get minutosFranquiaUsados => tarifador.minutosFranquiaUsados(paradoS);
  double get kmFranquiaRestante => math.max(0.0, tarifador.kmIncluido - distanciaKm);
  double get minutosFranquiaRestantes => math.max(0.0, tarifador.minutosIncluido - paradoS / 60);

  Map<String, dynamic> paraJson() => {
        'taxaKm': tarifador.taxaKm,
        'taxaEspera': tarifador.taxaEsperaPorMinuto,
        'kmIncluido': tarifador.kmIncluido,
        'minutosIncluido': tarifador.minutosIncluido,
        'bandeirada': bandeirada,
        'distanciaKm': distanciaKm,
        'paradoS': paradoS,
        'totalS': totalS,
        'kmCobrado': kmCobrado,
        'jaAndou': jaAndou,
      };

  static MedidorCorrida? deJson(Map<String, dynamic> j) {
    try {
      double d(String k) => (j[k] as num).toDouble();
      return MedidorCorrida(Tarifador(
        taxaKm: d('taxaKm'),
        taxaEsperaPorMinuto: d('taxaEspera'),
        kmIncluido: d('kmIncluido'),
        minutosIncluido: d('minutosIncluido'),
      ))
        ..bandeirada = d('bandeirada')
        ..distanciaKm = d('distanciaKm')
        ..paradoS = d('paradoS')
        ..totalS = d('totalS')
        ..kmCobrado = d('kmCobrado')
        ..jaAndou = j['jaAndou'] == true;
    } catch (_) {
      return null;
    }
  }
}
