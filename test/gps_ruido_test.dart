import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taximetro/state/taximetro_state.dart';

/// 3.2.2 — corridas simuladas com GPS ruidoso, passando pelo app inteiro
/// (filtro + medidor + relogio), comparadas com a distancia real da rota.
///
/// O ruido imita o celular no carro: erro de ~3 m que muda devagar (a
/// localizacao do Google suaviza), velocidade com atraso, tremida parado e
/// ~2% de "reflexos" (ponto 25 a 45 m fora, com precisao ruim). Mais a
/// posicao guardada (de cache) no comeco e uma leitura repetida.
///
/// Na simulacao feita antes de mudar o codigo (mesmo modelo, 30 corridas),
/// a logica da 3.2.1 dava em media +9,4% (ate +19%) e a nova +0,3%.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const lat0 = -18.0;
  const lng0 = -49.35;
  const raio = 6378137.0;
  final cosLat = math.cos(lat0 * math.pi / 180);

  Position leitura(double x, double y, int horarioMs, {double velocidade = 0, double precisao = 5}) => Position(
        latitude: lat0 + y / raio * 180 / math.pi,
        longitude: lng0 + x / (raio * cosLat) * 180 / math.pi,
        timestamp: DateTime.fromMillisecondsSinceEpoch(horarioMs),
        accuracy: precisao,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: velocidade,
        speedAccuracy: 0,
      );

  /// Uma corrida: rota com esquinas, semaforos e espera de passageiro.
  /// Devolve (distancia real em m, distancia medida pelo app em m, soma
  /// ingenua de todos os pontos em m, segundos de corrida, tempo no app).
  ({double real, double medida, double ingenua, int segundos, int tempoApp}) corrida(int semente) {
    final rnd = math.Random(semente);
    double gauss() {
      final u1 = 1 - rnd.nextDouble();
      final u2 = rnd.nextDouble();
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }

    var agora = 1700000000000;
    final s = TaximetroState()..relogioParaTeste = () => agora;
    s.comecarContagemParaTeste();

    const sigma = 3.0;
    const rho = 0.85;
    var ex = 0.0, ey = 0.0, vRep = 0.0;
    var x = 0.0, y = 0.0, real = 0.0, ingenua = 0.0;
    double? ultX, ultY;
    var segundos = 0;

    void umSegundo(double vReal, bool parado, {Position? trocar}) {
      for (var k = 0; k < 4; k++) {
        agora += 250;
        s.tiqueDoRelogioParaTeste();
      }
      segundos++;
      ex = rho * ex + math.sqrt(1 - rho * rho) * gauss() * sigma;
      ey = rho * ey + math.sqrt(1 - rho * rho) * gauss() * sigma;
      vRep = 0.6 * vRep + 0.4 * vReal;
      var v = math.max(0.0, vRep + gauss() * 0.15);
      if (parado && vRep < 0.3) v = (gauss() * 0.25).abs();
      var precisao = (gauss() * 2 + 6).abs() + 2;
      var ox = 0.0, oy = 0.0;
      if (rnd.nextDouble() < 0.02) {
        final ang = rnd.nextDouble() * 2 * math.pi;
        final d = 25 + rnd.nextDouble() * 20;
        ox = d * math.cos(ang);
        oy = d * math.sin(ang);
        precisao = 22 + rnd.nextDouble() * 13;
      }
      final gx = x + ex + ox, gy = y + ey + oy;
      if (ultX != null) ingenua += math.sqrt(math.pow(gx - ultX!, 2) + math.pow(gy - ultY!, 2));
      ultX = gx;
      ultY = gy;
      s.medirPosicaoParaTeste(trocar ?? leitura(gx, gy, agora, velocidade: v, precisao: precisao));
    }

    // Comeco: a ultima posicao guardada (500 m dali, de 3 min atras) chega
    // primeiro; depois 20 s parado no embarque, com uma leitura repetida.
    umSegundo(0, true, trocar: leitura(500, 300, agora + 1000 - 180000));
    for (var i = 0; i < 20; i++) {
      umSegundo(0, true);
      if (i == 5) s.medirPosicaoParaTeste(leitura(x, y, agora - 1000)); // repetida
    }

    // Trechos: (dx, dy, velocidade de cruzeiro m/s, parada no fim em s).
    const rota = [
      [0.0, 400.0, 11.0, 40],
      [300.0, 0.0, 9.0, 0],
      [0.0, 600.0, 12.0, 120],
      [-200.0, 0.0, 8.0, 0],
      [0.0, 500.0, 11.0, 30],
      [150.0, 0.0, 7.0, 0],
    ];
    var v = 0.0;
    for (final t in rota) {
      final dx = t[0] as double, dy = t[1] as double, vmax = t[2] as double, parada = t[3] as int;
      final comprimento = math.sqrt(dx * dx + dy * dy);
      final ux = dx / comprimento, uy = dy / comprimento;
      var andado = 0.0;
      while (andado < comprimento - 0.01) {
        final falta = comprimento - andado;
        final alvo = math.min(vmax, math.sqrt(2 * 1.5 * falta) + 1.0); // freia antes da esquina
        v = v < alvo ? math.min(alvo, v + 2.0) : math.max(alvo, v - 2.5);
        final passo = math.min(v, falta);
        andado += passo;
        real += passo;
        x += ux * passo;
        y += uy * passo;
        umSegundo(v, false);
      }
      v = 0;
      for (var i = 0; i < parada; i++) {
        umSegundo(0, true);
      }
    }
    final registro = s.montarRegistroParaTeste();
    return (
      real: real,
      medida: registro.distanciaKm * 1000,
      ingenua: ingenua,
      segundos: segundos,
      tempoApp: registro.tempoS,
    );
  }

  test('corridas com GPS ruidoso: o odometro fica perto da distancia real', () {
    var somaErro = 0.0;
    const corridas = 8;
    for (var semente = 1; semente <= corridas; semente++) {
      final r = corrida(semente);
      final erro = r.medida / r.real - 1;
      final ingenuo = r.ingenua / r.real - 1;
      print('corrida $semente: real ${r.real.round()} m, app ${r.medida.round()} m '
          '(${(erro * 100).toStringAsFixed(1)}%), soma de todos os pontos ${(ingenuo * 100).toStringAsFixed(0)}%');
      // O ruido da simulacao e forte: somar tudo daria muito a mais.
      expect(ingenuo, greaterThan(0.2), reason: 'a simulacao precisa ter ruido de verdade');
      expect(erro.abs(), lessThan(0.035), reason: 'corrida $semente: ${(erro * 100).toStringAsFixed(1)}%');
      // O tempo nao se perde com as leituras descartadas.
      expect(r.tempoApp, r.segundos);
      somaErro += erro;
    }
    expect((somaErro / corridas).abs(), lessThan(0.015));
  });

  test('7) um ouvinte do GPS por corrida, mesmo ligando varias vezes, e nenhum no fim', () async {
    final s = TaximetroState()..relogioParaTeste = () => 1700000000000;
    var ligados = 0;
    var abertos = 0;
    s.fluxoGpsParaTeste = (_) {
      abertos++;
      final c = StreamController<Position>(onListen: () {
        ligados++;
      }, onCancel: () {
        ligados--;
      });
      return c.stream;
    };
    s.comecarContagemParaTeste();
    await Future.wait([
      s.iniciarRastreamentoParaTeste(),
      s.iniciarRastreamentoParaTeste(),
      s.iniciarRastreamentoParaTeste(),
    ]);
    expect(abertos, 3);
    expect(ligados, 1, reason: 'so o ultimo ouvinte fica ligado');
    await s.pararRastreamentoParaTeste();
    expect(ligados, 0, reason: 'finalizar desliga o GPS');
  });

  test('7) leitura que chega de um ouvinte ja trocado e ignorada', () async {
    var agora = 1700000000000;
    final s = TaximetroState()..relogioParaTeste = () => agora;
    final controladores = <StreamController<Position>>[];
    s.fluxoGpsParaTeste = (_) {
      final c = StreamController<Position>.broadcast();
      controladores.add(c);
      return c.stream;
    };
    s.comecarContagemParaTeste();
    await s.iniciarRastreamentoParaTeste();
    await s.iniciarRastreamentoParaTeste();
    // O primeiro fluxo ainda manda leituras (broadcast): nao podem contar.
    for (var i = 1; i <= 5; i++) {
      agora += 1000;
      controladores.first.add(leitura(0, i * 12.0, agora, velocidade: 12));
    }
    await Future<void>.delayed(Duration.zero);
    expect(s.medidorParaTeste.distanciaKm, 0);
    await s.pararRastreamentoParaTeste();
  });
}
