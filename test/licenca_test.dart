import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/licenca.dart';

/// Chaves DE VERDADE, assinadas com a chave privada do taximetro para um
/// aparelho de TESTE (codigo de um ANDROID_ID ficticio). Garantem que o
/// app aceita a chave certa e recusa a adulterada. A chave privada nunca
/// entra no repositorio: so as assinaturas deste aparelho de teste.
void main() {
  const codigoTeste = 'YJPJ-P7EA-DG7B-5BEJ';
  const chaveComprida = 'pbtr-ntvfbTgHkfKlrjc5ou39W2dx6i9ah-14orjNDjpTXkx51DybEZQbXZ3Fij6dehrYisnFWWiR99tnwpSlw';
  const liberacaoComPrazo = 'eoZAicpEBqb4Z-FNbg9b7YFNLWaex7hzojPgpALKiRAukm0vbrjz1a_4_4fkTNOx5yNKIYcqKNvHt6bPY12rUA';

  test('codigo do aparelho e igual ao do app antigo (conferido no JS original)', () {
    expect(Licenca.codigoDoAparelho('9774d56d682e549c'), '8EBJ-B4B4-MBE5-LY9Q');
    expect(Licenca.codigoDoAparelho('a1b2c3d4e5f60718'), 'TL8B-SHFZ-DAFW-CW2K');
    expect(Licenca.codigoDoAparelho('teste-automatico-nao-e-um-aparelho'), 'YJPJ-P7EA-DG7B-5BEJ');
  });

  test('chave comprida do gerador de reserva e aceita', () {
    expect(Licenca.conferir(codigoTeste, chaveComprida, 'sempre'), isTrue);
  });

  test('chave comprida nao serve em outro aparelho', () {
    expect(Licenca.conferir('ZZZZ-ZZZZ-ZZZZ-ZZZZ', chaveComprida, 'sempre'), isFalse);
  });

  test('liberacao do servidor com prazo so vale com o prazo certo', () {
    expect(Licenca.conferir(codigoTeste, liberacaoComPrazo, '2026-12-31'), isTrue);
    expect(Licenca.conferir(codigoTeste, liberacaoComPrazo, '2027-12-31'), isFalse);
  });

  test('chave comprida colada passa inteira pela formatacao', () {
    expect(Licenca.formatarChaveDigitada(chaveComprida), chaveComprida);
    expect(Licenca.formatarChaveDigitada(' $chaveComprida \n'), chaveComprida);
  });

  test('chave curta e formatada em grupos', () {
    expect(Licenca.formatarChaveDigitada('abcdefghjklmnpqr'), 'ABCD-EFGH-JKLM-NPQR');
    expect(Licenca.chaveCurta('abcd efgh jklm npqr'), 'ABCD-EFGH-JKLM-NPQR');
  });
}
