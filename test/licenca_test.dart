import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/licenca.dart';

/// Provas reais: assinadas com a chave do servidor de licencas e
/// conferidas contra a chave publica do app. Se a versao Flutter errar um
/// bit da criptografia ou do codigo do aparelho, a esteira barra o APK.
void main() {
  const codigo = 'ABCD-EFGH-JKLM-NPQR';
  const comValidade = 'm_ZvpB1vXKSD3zs4XDXDLg6vr67amAZsI9uHKJYG2X6eWciWC8WzJi8Z3kpE4bHKAC1dX6BgY1tmReGbgVgmRA';
  const formatoAntigo = 'xLB_eruFCpzL8DxD1HuOrvRlZ7SLP6hxiBaNuOMQ3YLhi34m28tZcoxxl86QFjslaQBfoacgaNiwJPPsQsLTgg';
  const semPrazo = 'hU1Zpa5XHl9wbYOprKMh5Ss77gsqvG43hgErXaqwWLGgtapT8vFmuPECYVgW2kEJ4E3JBrU0y_MV2MWDBFelCg';

  test('codigo do aparelho igual ao do app antigo', () {
    expect(Licenca.codigoDoAparelho('9774d56d682e549c'), '8EBJ-B4B4-MBE5-LY9Q');
  });

  group('Liberacao assinada pelo servidor', () {
    test('aceita a liberacao com validade', () {
      expect(Licenca.conferir(codigo, comValidade, '2026-12-31'), isTrue);
    });
    test('recusa se mexerem na validade guardada', () {
      expect(Licenca.conferir(codigo, comValidade, '2027-12-31'), isFalse);
    });
    test('recusa em outro aparelho', () {
      expect(Licenca.conferir('ZZZZ-EFGH-JKLM-NPQR', comValidade, '2026-12-31'), isFalse);
    });
    test('aceita a licenca sem prazo, nos dois formatos', () {
      expect(Licenca.conferir(codigo, semPrazo, 'sempre'), isTrue);
      expect(Licenca.conferir(codigo, formatoAntigo, 'sempre'), isTrue);
    });
    test('formato antigo nao serve para licenca com prazo', () {
      expect(Licenca.conferir(codigo, formatoAntigo, '2026-12-31'), isFalse);
    });
    test('recusa lixo', () {
      expect(Licenca.conferir(codigo, 'abc', 'sempre'), isFalse);
    });
  });

  test('chave curta', () {
    expect(Licenca.chaveCurta('abcd efgh-jklm npqr'), 'ABCD-EFGH-JKLM-NPQR');
    expect(Licenca.chaveCurta('abc'), isNull);
  });
}
