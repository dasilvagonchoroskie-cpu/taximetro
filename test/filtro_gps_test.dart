import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taximetro/core/filtro_gps.dart';

/// 3.2.2 — filtro do ruido do GPS, item por item do pedido do Evandro
/// (05/11/2026): a distancia saia maior que a real por causa do ruido.
void main() {
  const lat0 = -18.0;
  const lng0 = -49.35;
  const raio = 6378137.0; // o mesmo do Geolocator.distanceBetween
  final inicio = DateTime.utc(2026, 11, 5, 12);
  final inicioMs = inicio.millisecondsSinceEpoch;

  /// Leitura a [metros] ao norte do ponto inicial, [s] segundos depois do inicio.
  Position p(double metros, {double s = 0, double precisao = 5, double velocidade = 5, int? horarioMs}) => Position(
        latitude: lat0 + metros / raio * 180 / math.pi,
        longitude: lng0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(horarioMs ?? inicioMs + (s * 1000).round(), isUtc: true),
        accuracy: precisao,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: velocidade,
        speedAccuracy: 0,
      );
  int agora(double s) => inicioMs + (s * 1000).round();

  /// Filtro ja com a primeira descartada e a referencia no ponto 0, em s=1.
  FiltroGps comReferencia() {
    final f = FiltroGps();
    expect(f.avaliar(p(0), agora(0)).motivo, 'primeira');
    expect(f.avaliar(p(0, s: 1), agora(1)).tipo, TipoLeitura.ancorada);
    return f;
  }

  test('limites nomeados com os valores pedidos', () {
    expect(precisaoMaximaM, 20);
    expect(velocidadeMinimaMs, 0.5);
    expect(velocidadeMaximaKmh, 200);
    expect(filtroDistanciaM, inInclusiveRange(5, 10));
    expect(filtroDistanciaDoFluxoM, 0, reason: 'o fluxo fica com uma leitura por segundo (tempo de espera)');
  });

  test('6) distancia em metros pelo Geolocator.distanceBetween', () {
    // 0,001 grau de latitude = 111,32 m com o raio do Geolocator.
    final a = p(0);
    final b = Position(
      latitude: lat0 + 0.001,
      longitude: lng0,
      timestamp: inicio,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    expect(FiltroGps.metrosEntre(a, b), closeTo(111.32, 0.01));
    expect(FiltroGps.metrosEntre(a, b), Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude));
  });

  test('5) a primeira posicao da corrida e descartada; a segunda vira a referencia', () {
    final f = FiltroGps();
    final r1 = f.avaliar(p(500), agora(0)); // a ultima posicao guardada, longe
    expect(r1.tipo, TipoLeitura.descartada);
    expect(f.ancora, isNull);
    expect(f.avaliar(p(0, s: 1), agora(1)).tipo, TipoLeitura.ancorada);
    expect(f.ancora!.latitude, closeTo(lat0, 1e-12));
  });

  test('5) leitura repetida e leitura antiga (cache) sao descartadas', () {
    final f = comReferencia();
    expect(f.avaliar(p(0, s: 1), agora(2)).motivo, 'repetida');
    expect(f.avaliar(p(3, s: 2), agora(2)).tipo, TipoLeitura.andando);
    // Chega aos 60 s uma leitura com hora de 2,5 s: posicao de cache.
    final velha = p(300, horarioMs: inicioMs + 2500);
    expect(f.avaliar(velha, agora(60)).motivo, 'antiga');
    expect(f.ancora!.latitude, closeTo(lat0, 1e-12));
    // A leitura de agora segue normal.
    expect(f.avaliar(p(11, s: 61), agora(61)).tipo, TipoLeitura.andando);
  });

  test('5) relogio do celular que muda no meio da corrida nao trava o filtro', () {
    final f = comReferencia();
    // O relogio do aparelho pula 60 s para frente; a hora do GPS segue normal.
    final pulo = 60000;
    expect(f.avaliar(p(5, s: 2), agora(2) + pulo).motivo, 'antiga');
    expect(f.avaliar(p(10, s: 3), agora(3) + pulo).motivo, 'antiga');
    final terceira = f.avaliar(p(15, s: 4), agora(4) + pulo);
    expect(terceira.tipo, TipoLeitura.andando, reason: 'na 3a seguida aceita: era o relogio, nao cache');
    expect(f.avaliar(p(20, s: 5), agora(5) + pulo).tipo, TipoLeitura.andando);
  });

  test('2) precisao pior que 20 m e descartada e nao muda a referencia', () {
    final f = comReferencia();
    final r = f.avaliar(p(40, s: 2, precisao: 25), agora(2));
    expect(r.motivo, 'imprecisa');
    expect(f.ancora!.latitude, closeTo(lat0, 1e-12));
    final ok = f.avaliar(p(12, s: 3, precisao: 20), agora(3));
    expect(ok.tipo, TipoLeitura.andando);
    expect(ok.metros, closeTo(12, 0.01));
  });

  test('3) abaixo de 0,5 m/s e parado; a partir dai e andando', () {
    final f = comReferencia();
    expect(f.avaliar(p(3, s: 2, velocidade: 0.49), agora(2)).tipo, TipoLeitura.parado);
    expect(f.avaliar(p(3, s: 3, velocidade: 0.5), agora(3)).tipo, TipoLeitura.andando);
  });

  test('3) sem velocidade do GPS, usa a media desde a referencia', () {
    final f = comReferencia();
    expect(f.avaliar(p(0.3, s: 2, velocidade: -1), agora(2)).tipo, TipoLeitura.parado); // 0,3 m/s
    expect(f.avaliar(p(8, s: 3, velocidade: -1), agora(3)).tipo, TipoLeitura.andando); // 4 m/s
  });

  test('4) salto acima de 200 km/h e ignorado e a referencia fica', () {
    final f = comReferencia();
    final salto = f.avaliar(p(100, s: 2), agora(2)); // 100 m em 1 s = 360 km/h
    expect(salto.motivo, 'salto');
    expect(f.ancora!.latitude, closeTo(lat0, 1e-12));
    final volta = f.avaliar(p(15, s: 3), agora(3));
    expect(volta.tipo, TipoLeitura.andando);
    expect(volta.metros, closeTo(15, 0.01));
  });

  test('4) o salto e medido pelo tempo desde a referencia (trecho longo sem leitura boa nao e salto)', () {
    final f = comReferencia();
    // 30 s sem leitura boa e o carro a 54 km/h: 450 m desde a referencia.
    final r = f.avaliar(p(450, s: 31), agora(31));
    expect(r.tipo, TipoLeitura.andando);
    expect(r.metros, closeTo(450, 0.1));
  });

  test('4) tres saltos seguidos: a referencia e refeita no lugar novo, sem somar', () {
    final f = comReferencia();
    expect(f.avaliar(p(2000, s: 2), agora(2)).motivo, 'salto');
    expect(f.avaliar(p(2001, s: 3), agora(3)).motivo, 'salto');
    final r = f.avaliar(p(2002, s: 4), agora(4));
    expect(r.tipo, TipoLeitura.reancorada);
    expect(r.metros, 0);
    expect(f.avaliar(p(2014, s: 5), agora(5)).metros, closeTo(12, 0.01));
  });

  test('8) leitura descartada nao mexe na referencia; ancorar() so quando o trecho fecha', () {
    final f = comReferencia();
    final a1 = f.avaliar(p(4, s: 2), agora(2));
    expect(a1.metros, closeTo(4, 0.01));
    // O estado so chama ancorar() quando o trecho fecha: a referencia fica.
    expect(f.avaliar(p(8, s: 3), agora(3)).metros, closeTo(8, 0.01));
    f.ancorar(p(11, s: 4));
    expect(f.avaliar(p(14, s: 5), agora(5)).metros, closeTo(3, 0.01));
  });

  test('reiniciar (nova corrida) volta a descartar a primeira posicao', () {
    final f = comReferencia();
    f.reiniciar();
    expect(f.ancora, isNull);
    expect(f.avaliar(p(0, s: 10), agora(10)).motivo, 'primeira');
    expect(f.avaliar(p(0, s: 11), agora(11)).tipo, TipoLeitura.ancorada);
  });
}
