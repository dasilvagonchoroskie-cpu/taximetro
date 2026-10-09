import 'constantes.dart';

/// O numero de km/h da tela (3.1.3).
///
/// Ha duas fontes de velocidade. A localizacao do Google (a que mede a
/// corrida) suaviza a velocidade e, com o carro acelerando, a tela ficava
/// para tras (Evandro, 09/10/2026: carro a 57, taximetro marcando 51). A
/// leitura direta do chip de GPS responde mais rapido. A tela usa a direta
/// enquanto ela chega, e volta sozinha a do Google se ela parar.
///
/// So a TELA usa isto. A cobranca nao depende do numero do velocimetro: a
/// distancia vem das posicoes, e a velocidade so decide "parado" abaixo de
/// 2,5 km/h.
class Velocimetro {
  const Velocimetro._();

  /// Por quanto tempo uma leitura direta do chip vale para a tela (ms).
  static const int validadeDiretoMs = 2500;

  static double? paraTela({double? diretoKmh, int? idadeDiretoMs, double? googleKmh}) {
    final diretoValido = diretoKmh != null &&
        !diretoKmh.isNaN &&
        diretoKmh >= 0 &&
        idadeDiretoMs != null &&
        idadeDiretoMs >= 0 &&
        idadeDiretoMs < validadeDiretoMs;
    final v = diretoValido ? diretoKmh : googleKmh;
    if (v == null || v.isNaN || v < 0) return null;
    // Parado, o GPS treme entre 0 e 2 km/h: a tela mostra 0.
    return v < Constantes.velocidadeParadoKmh ? 0 : v;
  }
}
