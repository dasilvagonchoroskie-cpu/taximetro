import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/velocimetro.dart';

/// 3.1.3 — o velocimetro da tela usa a leitura direta do chip de GPS
/// (mais rapida) e volta para a do Google se ela parar de chegar.
void main() {
  test('com leitura direta recente, a tela mostra a direta', () {
    expect(Velocimetro.paraTela(diretoKmh: 57, idadeDiretoMs: 300, googleKmh: 51), 57);
  });

  test('leitura direta velha: volta para a do Google', () {
    expect(Velocimetro.paraTela(diretoKmh: 57, idadeDiretoMs: 3000, googleKmh: 51), 51);
  });

  test('sem leitura direta (aparelho sem o chip liberado): usa a do Google', () {
    expect(Velocimetro.paraTela(googleKmh: 40), 40);
  });

  test('carro parado mostra 0, sem tremer', () {
    expect(Velocimetro.paraTela(diretoKmh: 1.8, idadeDiretoMs: 100), 0);
    expect(Velocimetro.paraTela(googleKmh: 2.4), 0);
    expect(Velocimetro.paraTela(googleKmh: 2.5), 2.5);
  });

  test('sem nenhuma leitura: mostra o traco', () {
    expect(Velocimetro.paraTela(), isNull);
    expect(Velocimetro.paraTela(diretoKmh: 30, idadeDiretoMs: 5000), isNull);
    expect(Velocimetro.paraTela(googleKmh: -1), isNull);
  });
}
