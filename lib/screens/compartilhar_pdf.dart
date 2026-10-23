import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/pdf_corrida.dart';
import '../models/registro_corrida.dart';
import '../state/taximetro_state.dart';

/// Monta o PDF, grava numa pasta temporaria e abre o "compartilhar" do
/// Android (WhatsApp, e-mail, Drive...). Antes da 3.2.1 o comprovante era
/// gravado numa pasta interna e o botao nao abria nada.
///
/// Se der errado, mostra o motivo na tela, em vez de ficar calado.
Future<bool> compartilharPdf(
  BuildContext context, {
  required Future<List<int>> Function() montar,
  required String nomeArquivo,
  required String assunto,
  String? mensagem,
}) async {
  try {
    final bytes = await montar();
    final pasta = Directory('${(await getTemporaryDirectory()).path}/pdfs');
    await pasta.create(recursive: true);
    final arquivo = File('${pasta.path}/$nomeArquivo');
    await arquivo.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return false;
    await Share.shareXFiles(
      [XFile(arquivo.path, mimeType: 'application/pdf', name: nomeArquivo)],
      subject: assunto,
      text: mensagem,
    );
    return true;
  } catch (erro) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não consegui gerar o PDF: $erro. Tire um print desta tela e mande para o suporte.'),
          duration: const Duration(seconds: 10),
        ),
      );
    }
    return false;
  }
}

/// Comprovante de UMA corrida, para o passageiro.
Future<bool> compartilharComprovante(BuildContext context, TaximetroState s, RegistroCorrida r) {
  final quando = '${dataCurta(r.data)} às ${hora(r.data)}';
  return compartilharPdf(
    context,
    montar: () => pdfComprovante(r, DadosPrestador.daConfig(s.config)),
    nomeArquivo: nomeArquivoComprovante(r),
    assunto: 'Comprovante da corrida de $quando',
    mensagem: 'Comprovante da corrida de $quando: R\$ ${r.valor.toStringAsFixed(2).replaceAll('.', ',')}',
  );
}

/// Relatorio de todas as corridas do periodo filtrado no historico.
Future<bool> compartilharRelatorio(BuildContext context, TaximetroState s, List<RegistroCorrida> lista) {
  final periodo = s.descricaoPeriodo();
  return compartilharPdf(
    context,
    montar: () => pdfRelatorio(lista, DadosPrestador.daConfig(s.config), periodo: periodo),
    nomeArquivo: nomeArquivoRelatorio(lista, DateTime.now()),
    assunto: 'Relatório de corridas - $periodo',
  );
}

/// Botao que mostra "gerando..." enquanto o PDF e montado.
class BotaoPdf extends StatefulWidget {
  const BotaoPdf({
    super.key,
    required this.rotulo,
    required this.acao,
    this.compacto = false,
    this.principal = false,
    this.habilitado = true,
  });

  final String rotulo;
  final Future<bool> Function() acao;

  /// Botao pequeno de texto (dentro do cartao da corrida no historico).
  final bool compacto;

  /// Botao cheio, na cor principal do app.
  final bool principal;
  final bool habilitado;

  @override
  State<BotaoPdf> createState() => _BotaoPdfState();
}

class _BotaoPdfState extends State<BotaoPdf> {
  bool _gerando = false;

  Future<void> _tocar() async {
    if (_gerando) return;
    setState(() => _gerando = true);
    try {
      await widget.acao();
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final icone = _gerando
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.principal && !widget.compacto ? t.colorScheme.onPrimary : t.colorScheme.primary,
            ),
          )
        : const Icon(Icons.picture_as_pdf_outlined, size: 18);
    final rotulo = Text(_gerando ? 'Gerando PDF...' : widget.rotulo);
    final aoTocar = widget.habilitado && !_gerando ? _tocar : null;

    if (widget.compacto) {
      return TextButton.icon(
        onPressed: aoTocar,
        icon: icone,
        label: rotulo,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );
    }
    final estilo = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
    );
    return widget.principal
        ? FilledButton.icon(onPressed: aoTocar, icon: icone, label: rotulo, style: estilo)
        : OutlinedButton.icon(onPressed: aoTocar, icon: icone, label: rotulo, style: estilo);
  }
}
