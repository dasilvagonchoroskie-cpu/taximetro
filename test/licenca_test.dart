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

  // ---- 3.1.1: a chave e achada na mensagem inteira do WhatsApp ----
  const recado = 'Olá, Fabiano! Segue o aplicativo Taximetro.\n\n'
      '1) Baixe e instale o aplicativo por este link:\n'
      'https://github.com/dasilvagonchoroskie-cpu/taximetro/releases/download/apk-mais-recente/taximetro.apk\n\n'
      '2) Toque e segure nesta mensagem e toque em Copiar.\n\n'
      'Sua chave de ativação:\nYJJ4-3GVY-YMTH-7L6P\n\n'
      'A chave vale num celular só.\nFortaleza Digital Security';

  test('acha a chave no meio da mensagem do WhatsApp', () {
    expect(Licenca.extrairChave(recado), 'YJJ4-3GVY-YMTH-7L6P');
  });

  test('acha a chave minuscula, sem tracos ou com espacos', () {
    expect(Licenca.extrairChave('yjj4-3gvy-ymth-7l6p'), 'YJJ4-3GVY-YMTH-7L6P');
    expect(Licenca.extrairChave(' yjj43gvyymth7l6p \n'), 'YJJ4-3GVY-YMTH-7L6P');
    expect(Licenca.extrairChave('YJJ4 3GVY YMTH 7L6P'), 'YJJ4-3GVY-YMTH-7L6P');
  });

  test('nao confunde o codigo do proprio aparelho com a chave', () {
    expect(Licenca.extrairChave(codigoTeste, ignorar: codigoTeste), isNull);
    expect(
      Licenca.extrairChave('codigo $codigoTeste e chave YJJ4-3GVY-YMTH-7L6P', ignorar: codigoTeste),
      'YJJ4-3GVY-YMTH-7L6P',
    );
  });

  test('texto sem chave nao vira chave', () {
    expect(Licenca.extrairChave('para isso fica mais facil'), isNull);
    expect(Licenca.extrairChave('responsabilidade'), isNull);
    expect(
      Licenca.extrairChave('https://github.com/dasilvagonchoroskie-cpu/taximetro/releases/download/apk-mais-recente/taximetro.apk'),
      isNull,
    );
    expect(Licenca.extrairChave(''), isNull);
  });

  test('chave comprida colada sozinha ou no meio do texto', () {
    expect(Licenca.extrairChave(chaveComprida), chaveComprida);
    expect(Licenca.extrairChave('Sua chave:\n$chaveComprida\nobrigado'), chaveComprida);
    expect(Licenca.conferir(codigoTeste, Licenca.extrairChave('Sua chave:\n$chaveComprida\n')!, 'sempre'), isTrue);
  });
}
