import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/cnpj.dart';
import 'package:taximetro/core/pdf_corrida.dart';
import 'package:taximetro/models/config.dart';

/// 3.4.0 — empresa e CNPJ no cadastro do motorista e nos comprovantes.
/// Todos os numeros daqui sao ficticios ou exemplos publicos de documentacao.
void main() {
  test('CNPJ numerico: confere os dois digitos', () {
    expect(cnpjValido('11.222.333/0001-81'), isTrue);
    expect(cnpjValido('11222333000181'), isTrue);
    expect(cnpjValido('11.222.333/0001-80'), isFalse);
    expect(cnpjValido('11.222.333/0001-91'), isFalse);
  });

  test('CNPJ com letras: exemplo oficial da Receita Federal', () {
    expect(cnpjValido('12.ABC.345/01DE-35'), isTrue);
    expect(cnpjValido('12.abc.345/01de-35'), isTrue);
    expect(cnpjValido('12.ABC.345/01DE-36'), isFalse);
  });

  test('CNPJ incompleto, repetido ou com letra no digito nao passa', () {
    expect(cnpjValido(''), isFalse);
    expect(cnpjValido('11.222.333/0001-8'), isFalse);
    expect(cnpjValido('11.222.333/0001-811'), isFalse);
    expect(cnpjValido('00.000.000/0000-00'), isFalse);
    expect(cnpjValido('12.ABC.345/01DE-3A'), isFalse);
  });

  test('mascara: poe a pontuacao enquanto digita e aceita colar', () {
    expect(formatarCnpj(''), '');
    expect(formatarCnpj('11'), '11');
    expect(formatarCnpj('112'), '11.2');
    expect(formatarCnpj('112223330'), '11.222.333/0');
    expect(formatarCnpj('11222333000181'), '11.222.333/0001-81');
    TextEditingValue digitar(String t, [int? cursor]) => const MascaraCnpj().formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: t, selection: TextSelection.collapsed(offset: cursor ?? t.length)),
        );
    expect(digitar('12abc34501de35999').text, '12.ABC.345/01DE-35');
    expect(digitar('112').selection.end, 4);
    // Corrigindo no meio, o cursor nao pula para o fim.
    expect(digitar('19.222.333/0001-81', 2).selection.end, 2);
  });

  test('empresa e CNPJ sao gravados; cadastro antigo continua abrindo', () {
    final c = ConfigTaxi(empresaNome: 'Transportes Exemplo LTDA', empresaCnpj: '11.222.333/0001-81');
    final volta = ConfigTaxi.fromJson(c.toJson());
    expect(volta.empresaNome, 'Transportes Exemplo LTDA');
    expect(volta.empresaCnpj, '11.222.333/0001-81');
    final antigo = ConfigTaxi.fromJson({'motoristaNome': 'Fulano'});
    expect(antigo.motoristaNome, 'Fulano');
    expect(antigo.empresaNome, '');
    expect(antigo.empresaCnpj, '');
  });

  test('dados do cadastro chegam no PDF; em branco, nao aparecem', () {
    final p = DadosPrestador.daConfig(ConfigTaxi(empresaNome: '  Transportes Exemplo ', empresaCnpj: '11222333000181'));
    expect(p.empresa, 'Transportes Exemplo');
    expect(p.cnpj, '11.222.333/0001-81');
    expect(p.vazio, isFalse);
    final semEmpresa = DadosPrestador.daConfig(ConfigTaxi(motoristaNome: 'Fulano'));
    expect(semEmpresa.empresa, '');
    expect(semEmpresa.cnpj, '');
    expect(DadosPrestador.daConfig(ConfigTaxi()).vazio, isTrue);
  });
}
