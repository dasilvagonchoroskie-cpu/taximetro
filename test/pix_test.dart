import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/pix.dart';

void main() {
  test('conta de verificacao do Pix: valor de referencia universal', () {
    expect(Pix.crc16('123456789'), '29B1');
  });

  test('conta de verificacao bate com o exemplo oficial do Banco Central', () {
    const semCrc = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-'
        '4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***6304';
    expect(Pix.crc16(semCrc), '1D3D');
  });

  test('codigo com valor sai com o valor e fecha com a conta certa', () {
    final codigo = Pix.gerarPayload(
      chave: 'fabiano@exemplo.com',
      nomeRecebedor: 'Fabiano',
      cidade: 'Goiatuba',
      valor: 13.0,
    );
    expect(codigo, contains('540513.00'));
    expect(codigo, contains('5802BR'));
    final semCrc = codigo.substring(0, codigo.length - 4);
    expect(semCrc.endsWith('6304'), isTrue);
    expect(codigo.substring(codigo.length - 4), Pix.crc16(semCrc));
  });
}
