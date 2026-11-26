/// CNPJ da empresa do motorista (3.4.0), no formato antigo (so numeros) e no
/// novo, alfanumerico, que a Receita Federal emite desde julho de 2026
/// (IN RFB 2.229/2024): 12 posicoes com numeros ou letras + 2 digitos.
///
/// Digito verificador (modulo 11): cada caractere vale o codigo ASCII menos
/// 48 (0 a 9 continuam 0 a 9; A = 17 ... Z = 42). Para o CNPJ so de numeros a
/// conta e a mesma de sempre.
library;

import 'package:flutter/services.dart';

/// So letras maiusculas e numeros (tira ponto, barra, traco e espaco).
String limparCnpj(String texto) => texto.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

/// 12.ABC.345/01DE-35. Aceita CNPJ pela metade (mascara enquanto digita).
String formatarCnpj(String texto) {
  final c = limparCnpj(texto);
  final saida = StringBuffer();
  for (var i = 0; i < c.length && i < 14; i++) {
    if (i == 2 || i == 5) saida.write('.');
    if (i == 8) saida.write('/');
    if (i == 12) saida.write('-');
    saida.write(c[i]);
  }
  return saida.toString();
}

int _digito(List<int> valores) {
  var soma = 0;
  var peso = 2;
  for (var i = valores.length - 1; i >= 0; i--) {
    soma += valores[i] * peso;
    peso = peso == 9 ? 2 : peso + 1;
  }
  final resto = soma % 11;
  return resto < 2 ? 0 : 11 - resto;
}

/// true quando tem as 14 posicoes e os 2 digitos verificadores conferem.
bool cnpjValido(String texto) {
  final c = limparCnpj(texto);
  if (!RegExp(r'^[0-9A-Z]{12}[0-9]{2}$').hasMatch(c)) return false;
  // 00000000000000, 11111111111111... passam na conta, mas nao existem.
  if (c.split('').toSet().length == 1) return false;
  final valores = [for (final u in c.substring(0, 12).codeUnits) u - 48];
  final d1 = _digito(valores);
  final d2 = _digito([...valores, d1]);
  return c.substring(12) == '$d1$d2';
}

/// Poe os pontos, a barra e o traco enquanto o motorista digita (ou cola).
class MascaraCnpj extends TextInputFormatter {
  const MascaraCnpj();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue antes, TextEditingValue depois) {
    var limpo = limparCnpj(depois.text);
    if (limpo.length > 14) limpo = limpo.substring(0, 14);
    final texto = formatarCnpj(limpo);

    // O cursor fica depois da mesma quantidade de letras/numeros de antes.
    final fim = depois.selection.end;
    final antesDoCursor =
        fim < 0 || fim > depois.text.length ? limpo.length : limparCnpj(depois.text.substring(0, fim)).length;
    var posicao = 0;
    var contados = 0;
    while (posicao < texto.length && contados < antesDoCursor) {
      if (RegExp(r'[0-9A-Z]').hasMatch(texto[posicao])) contados++;
      posicao++;
    }
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: posicao));
  }
}
