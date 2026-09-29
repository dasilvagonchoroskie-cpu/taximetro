import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart'
    show ECCurve_secp256r1, ECDSASigner, ECPublicKey, ECSignature, PublicKeyParameter, SHA256Digest;

/// Licenca do taximetro — portada 1:1 da versao original (Capacitor), no
/// modelo combinado em 14/09/2026: chave curta conferida no servidor.
///
/// * CODIGO DO APARELHO: sai do ANDROID_ID pela mesma conta do app antigo,
///   SHA-256("taximetro|" + id), 10 primeiros bytes em grupos de 5 bits.
///   Assinado com a mesma chave do APK antigo, o Android devolve o mesmo
///   ANDROID_ID: o codigo nao muda e a chave do cliente continua valendo.
/// * ATIVACAO: a chave curta vai ao servidor junto com o codigo; ele
///   devolve uma liberacao ASSINADA (ECDSA P-256) sobre
///   "taximetro:CODIGO:VALIDADE". O app confere com a chave PUBLICA:
///   ninguem fabrica liberacao nem estica o prazo mexendo no celular.
class Licenca {
  const Licenca._();

  static const String appId = 'taximetro';
  static const String servidor = 'https://fortaleza-licencas.fortalezadigitalsecurity.workers.dev';
  static const String alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Quantos dias antes de vencer o app ja tenta renovar sozinho.
  static const int diasPraRenovarAntes = 5;

  // Chave PUBLICA: so confere. Quem assina e o servidor.
  static const String _x = 'yBHKjFLZZJzoY1l490yRD3ru9ROE03gS9C3XH0Gb0v4';
  static const String _y = '-sa1VYlT3Fvxhh9fJEaav3VO69vM5qiiJ3yE5io-AJw';

  /// Codigo do aparelho, igual ao do app antigo: XXXX-XXXX-XXXX-XXXX.
  static String codigoDoAparelho(String idBruto) {
    final hash = crypto.sha256.convert(utf8.encode('$appId|$idBruto')).bytes.sublist(0, 10);
    final bits = hash.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
    final texto = StringBuffer();
    for (var i = 0; i + 5 <= bits.length; i += 5) {
      texto.write(alfabeto[int.parse(bits.substring(i, i + 5), radix: 2)]);
    }
    return _emGrupos(texto.toString());
  }

  /// Chave curta no formato XXXX-XXXX-XXXX-XXXX, ou null se nao tiver 16.
  static String? chaveCurta(String digitada) {
    final limpa = digitada.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return limpa.length == 16 ? _emGrupos(limpa) : null;
  }

  /// Formata enquanto o cliente digita. Chave antiga (comprida) passa
  /// como esta, para continuar aceita.
  static String formatarChaveDigitada(String valor) {
    final semEspaco = valor.replaceAll(RegExp(r'\s'), '');
    if (semEspaco.length > 19) return semEspaco;
    final limpa = semEspaco.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return _emGrupos(limpa.length > 16 ? limpa.substring(0, 16) : limpa);
  }

  /// Confere a liberacao guardada para este codigo e validade (mesma regra
  /// do original, inclusive o formato antigo "taximetro:CODIGO").
  static bool conferir(String codigo, String assinaturaTexto, String validade) {
    final limpa = assinaturaTexto.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (limpa.length < 80) return false;
    final bytes = _base64url(limpa);
    if (bytes == null) return false;
    final v = validade.isEmpty ? 'sempre' : validade;
    if (_verificar(bytes, '$appId:$codigo:$v')) return true;
    if (v != 'sempre') return false;
    return _verificar(bytes, '$appId:$codigo');
  }

  /// Leva a chave curta ao servidor (POST /ativar), como o original.
  static Future<RespostaAtivacao> ativarNoServidor(String chave, String codigo) async {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final pedido = await cliente.postUrl(Uri.parse('$servidor/ativar'));
      pedido.headers.contentType = ContentType.json;
      pedido.write(jsonEncode({'chave': chave, 'app_id': appId, 'aparelho': codigo}));
      final resposta = await pedido.close().timeout(const Duration(seconds: 20));
      final dados = _json(await resposta.transform(utf8.decoder).join());
      if (dados == null) {
        return const RespostaAtivacao(motivo: 'O servidor respondeu uma coisa estranha.');
      }
      final assinatura = dados['assinatura']?.toString() ?? '';
      if (dados['ok'] != true || assinatura.isEmpty) {
        return RespostaAtivacao(motivo: dados['motivo']?.toString() ?? 'Não deu para ativar.');
      }
      final validade = dados['validade']?.toString() ?? '';
      return RespostaAtivacao(
        ok: true,
        assinatura: assinatura,
        validade: validade.isEmpty ? 'sempre' : validade,
      );
    } catch (_) {
      return const RespostaAtivacao(
        motivo: 'Sem internet. Ligue os dados do celular e toque em Ativar de novo.',
      );
    } finally {
      cliente.close();
    }
  }

  static String _emGrupos(String s) => s.replaceAllMapped(RegExp(r'(.{4})(?=.)'), (m) => '${m[1]}-');

  static BigInt _inteiro(List<int> bytes) =>
      bytes.fold(BigInt.zero, (a, b) => (a << 8) | BigInt.from(b));

  static Uint8List? _base64url(String texto) {
    try {
      return base64Url.decode(base64Url.normalize(texto));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _json(String corpo) {
    try {
      final valor = jsonDecode(corpo);
      return valor is Map<String, dynamic> ? valor : null;
    } catch (_) {
      return null;
    }
  }

  static bool _verificar(Uint8List assinatura, String texto) {
    if (assinatura.length != 64) return false;
    final x = _base64url(_x);
    final y = _base64url(_y);
    if (x == null || y == null) return false;
    final dominio = ECCurve_secp256r1();
    final publica = ECPublicKey(dominio.curve.createPoint(_inteiro(x), _inteiro(y)), dominio);
    final verificador = ECDSASigner(SHA256Digest())..init(false, PublicKeyParameter<ECPublicKey>(publica));
    try {
      return verificador.verifySignature(
        Uint8List.fromList(utf8.encode(texto)),
        ECSignature(_inteiro(assinatura.sublist(0, 32)), _inteiro(assinatura.sublist(32))),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Resposta do servidor de licencas.
class RespostaAtivacao {
  const RespostaAtivacao({
    this.ok = false,
    this.assinatura = '',
    this.validade = 'sempre',
    this.motivo = '',
  });

  final bool ok;
  final String assinatura;
  final String validade;
  final String motivo;
}
