import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/config.dart';
import '../models/registro_corrida.dart';
import 'formato.dart';

/// PDFs do taximetro (versao 3.2.1):
///
/// * [pdfComprovante]: UMA corrida, para mandar ao passageiro pelo WhatsApp.
/// * [pdfRelatorio]: todas as corridas de um periodo, para a contabilidade,
///   com totais por forma de pagamento e por dia.
///
/// Tudo aqui so monta os bytes do PDF (sem tela e sem Android), para os
/// testes da esteira gerarem os dois de verdade. Gravar o arquivo e abrir o
/// "compartilhar" do celular fica na tela (compartilhar_pdf.dart).
///
/// Fonte: a Helvetica que todo leitor de PDF ja tem. Ela desenha os acentos
/// do portugues, mas nao desenha travessao, seta nem emoji: no lugar, a
/// biblioteca pinta um quadradinho riscado (era o que acontecia no "—" dos
/// campos vazios do relatorio antigo). Por isso todo texto passa por
/// [textoPdf] antes de entrar no PDF.

/// Dados de quem prestou o servico (vem da tela "Motorista").
class DadosPrestador {
  const DadosPrestador({this.nome = '', this.cnh = '', this.veiculo = '', this.placa = ''});

  factory DadosPrestador.daConfig(ConfigTaxi c) {
    final numero = c.motoristaCnh.trim();
    final categoria = c.cnhCategoria.trim();
    return DadosPrestador(
      nome: c.motoristaNome.trim(),
      cnh: numero.isEmpty ? '' : (categoria.isEmpty ? numero : '$numero (categoria $categoria)'),
      veiculo: c.descricaoVeiculo.trim(),
      placa: c.veiculoPlaca.trim().toUpperCase(),
    );
  }

  final String nome;
  final String cnh;
  final String veiculo;
  final String placa;

  bool get vazio => nome.isEmpty && cnh.isEmpty && veiculo.isEmpty && placa.isEmpty;
}

// ===================================================================
// Texto
// ===================================================================

/// Caracteres comuns que a Helvetica nao tem, trocados por equivalentes.
const Map<int, String> _trocas = {
  0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2013: '-', 0x2014: '-', 0x2015: '-', 0x2212: '-',
  0x2192: '->', 0x21D2: '->', 0x27A1: '->', 0x2794: '->', 0x2190: '<-',
  0x2018: "'", 0x2019: "'", 0x201A: "'", 0x201B: "'",
  0x201C: '"', 0x201D: '"', 0x201E: '"', 0x201F: '"',
  0x2026: '...', 0x2022: '-', 0x2023: '-', 0x25CF: '-',
  0x2002: ' ', 0x2003: ' ', 0x2007: ' ', 0x2009: ' ', 0x200A: ' ', 0x202F: ' ',
  0x20AC: 'EUR', 0x2116: 'No',
};

/// Deixa o texto so com o que a fonte do PDF desenha (acentos ficam; seta,
/// travessao e aspas curvas viram os equivalentes; emoji e outras escritas
/// saem). Quebras de linha viram espaco.
String textoPdf(String? texto) {
  final saida = StringBuffer();
  for (final r in (texto ?? '').runes) {
    if (r == 0x09 || r == 0x0A || r == 0x0D) {
      saida.write(' ');
    } else if (r < 0x20 || (r >= 0x7F && r < 0xA0)) {
      continue;
    } else if (r <= 0xFF) {
      saida.writeCharCode(r);
    } else {
      final troca = _trocas[r];
      if (troca != null) saida.write(troca);
    }
  }
  return saida.toString().replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

// ===================================================================
// Datas, nomes e formas de pagamento
// ===================================================================

const List<String> _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String _d2(int n) => n.toString().padLeft(2, '0');

/// 23/10/2026
String dataCurta(DateTime d) => '${_d2(d.day)}/${_d2(d.month)}/${d.year}';

/// 09:15
String hora(DateTime d) => '${_d2(d.hour)}:${_d2(d.minute)}';

/// 23 de outubro de 2026
String dataPorExtenso(DateTime d) => '${d.day} de ${_meses[d.month - 1]} de ${d.year}';

/// Outubro de 2026
String mesPorExtenso(DateTime d) {
  final m = _meses[d.month - 1];
  return '${m[0].toUpperCase()}${m.substring(1)} de ${d.year}';
}

/// Numero do comprovante: a data e a hora da corrida, ate o segundo.
String numeroComprovante(RegistroCorrida r) {
  final d = r.data;
  return '${d.year}${_d2(d.month)}${_d2(d.day)}-${_d2(d.hour)}${_d2(d.minute)}${_d2(d.second)}';
}

/// comprovante-corrida-23-10-2026-09h15.pdf (o passageiro ve esse nome).
String nomeArquivoComprovante(RegistroCorrida r) {
  final d = r.data;
  return 'comprovante-corrida-${_d2(d.day)}-${_d2(d.month)}-${d.year}-${_d2(d.hour)}h${_d2(d.minute)}.pdf';
}

/// relatorio-corridas-01-10-2026-a-23-10-2026.pdf
String nomeArquivoRelatorio(List<RegistroCorrida> corridas, DateTime agora) {
  String dia(DateTime d) => '${_d2(d.day)}-${_d2(d.month)}-${d.year}';
  if (corridas.isEmpty) return 'relatorio-corridas-${dia(agora)}.pdf';
  final ordem = [...corridas]..sort((a, b) => a.data.compareTo(b.data));
  final ini = dia(ordem.first.data);
  final fim = dia(ordem.last.data);
  return ini == fim ? 'relatorio-corridas-$ini.pdf' : 'relatorio-corridas-$ini-a-$fim.pdf';
}

const Map<String, String> _formas = {
  'pix': 'Pix',
  'dinheiro': 'Dinheiro',
  'cartao': 'Cartão',
  'outro': 'Outro',
};

/// Ordem das formas no relatorio.
const List<String> _ordemFormas = ['pix', 'dinheiro', 'cartao', 'outro'];

String nomeDaForma(String forma) {
  final f = forma.trim().toLowerCase();
  if (f.isEmpty) return 'Não informado';
  return _formas[f] ?? textoPdf(forma);
}

String _real(double v) => 'R\$ ${Formato.moeda(v)}';

/// Corta texto muito comprido (o comprovante tem uma pagina so).
String _corte(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 3).trimRight()}...';

/// Trajeto gravado como "Origem -> Destino" (os dois preenchidos), ou so um.
({String origem, String destino, String unico}) partesDoTrajeto(String trajeto) {
  final t = textoPdf(trajeto);
  final i = t.indexOf(' -> ');
  if (i <= 0) return (origem: '', destino: '', unico: t);
  return (origem: t.substring(0, i).trim(), destino: t.substring(i + 4).trim(), unico: '');
}

// ===================================================================
// Contas
// ===================================================================

/// Uma linha da composicao do valor no comprovante.
class LinhaConta {
  const LinhaConta(this.descricao, this.detalhe, this.valor);
  final String descricao;
  final String detalhe;
  final double valor;
}

/// Bandeirada + distancia + espera. Devolve null quando as partes nao
/// fecham com o total (corridas antigas, de antes da 3.1): nesse caso o
/// comprovante mostra so o valor total cobrado, que e o que valeu.
List<LinhaConta>? composicaoDoValor(RegistroCorrida r) {
  int c(double v) => (v * 100).round();
  if (r.bandeirada <= 0) return null;
  if ((c(r.bandeirada) + c(r.valorDistancia) + c(r.valorEspera) - c(r.valor)).abs() > 1) return null;
  return [
    LinhaConta('Bandeirada', 'abertura da corrida', r.bandeirada),
    LinhaConta('Distância', r.valorDistancia > 0 ? 'além da bandeirada' : 'dentro da bandeirada', r.valorDistancia),
    LinhaConta('Tempo parado', r.valorEspera > 0 ? 'além da bandeirada' : 'dentro da bandeirada', r.valorEspera),
  ];
}

/// Soma de um grupo de corridas, em centavos (sem erro de arredondamento).
class Subtotal {
  int quantidade = 0;
  int centavos = 0;
  double km = 0;
  int tempoS = 0;

  double get valor => centavos / 100;

  void somar(RegistroCorrida r) {
    quantidade++;
    centavos += (r.valor * 100).round();
    km += r.distanciaKm;
    tempoS += r.tempoS;
  }
}

class ResumoCorridas {
  ResumoCorridas._(this.geral, this.porForma, this.porDia);

  final Subtotal geral;

  /// Forma de pagamento (rotulo pronto) -> subtotal, na ordem do relatorio.
  final List<MapEntry<String, Subtotal>> porForma;

  /// Dia (meia-noite) -> subtotal, do mais antigo ao mais novo.
  final List<MapEntry<DateTime, Subtotal>> porDia;
}

ResumoCorridas resumir(List<RegistroCorrida> corridas) {
  final geral = Subtotal();
  final formas = <String, Subtotal>{};
  final dias = <DateTime, Subtotal>{};
  for (final r in corridas) {
    geral.somar(r);
    formas.putIfAbsent(r.formaPagamento.trim().toLowerCase(), Subtotal.new).somar(r);
    dias.putIfAbsent(DateTime(r.data.year, r.data.month, r.data.day), Subtotal.new).somar(r);
  }
  int posicao(String f) {
    if (f.isEmpty) return 1000;
    final i = _ordemFormas.indexOf(f);
    return i < 0 ? 500 : i;
  }

  final chaves = formas.keys.toList()..sort((a, b) => posicao(a).compareTo(posicao(b)));
  final porDia = dias.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  return ResumoCorridas._(
    geral,
    [for (final f in chaves) MapEntry(nomeDaForma(f), formas[f]!)],
    porDia,
  );
}

// ===================================================================
// Estilo
// ===================================================================

final PdfColor _escuro = PdfColor.fromHex('#111827');
final PdfColor _medio = PdfColor.fromHex('#4B5563');
final PdfColor _claro = PdfColor.fromHex('#9CA3AF');
final PdfColor _linha = PdfColor.fromHex('#E5E7EB');
final PdfColor _fundo = PdfColor.fromHex('#F3F4F6');
final PdfColor _destaque = PdfColor.fromHex('#047857');

pw.TextStyle _t(double tamanho, {bool negrito = false, PdfColor? cor, double espaco = 0}) => pw.TextStyle(
      fontSize: tamanho,
      fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: cor ?? _escuro,
      letterSpacing: espaco,
    );

pw.Widget _tituloSecao(String texto) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
      child: pw.Text(texto.toUpperCase(), style: _t(7.5, negrito: true, cor: _medio, espaco: 0.8)),
    );

pw.Widget _par(String rotulo, String valor, {double largura = 92, double tamanho = 9.5}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: largura, child: pw.Text(rotulo, style: _t(tamanho, cor: _medio))),
          pw.Expanded(child: pw.Text(textoPdf(valor), style: _t(tamanho, negrito: true))),
        ],
      ),
    );

pw.Widget _divisor() => pw.Container(height: 0.6, color: _linha, margin: const pw.EdgeInsets.symmetric(vertical: 8));

List<pw.Widget> _blocoPrestador(DadosPrestador p, {double largura = 92}) => [
      if (p.nome.isNotEmpty) _par('Motorista', p.nome, largura: largura),
      if (p.cnh.isNotEmpty) _par('CNH', p.cnh, largura: largura),
      if (p.veiculo.isNotEmpty) _par('Veículo', p.veiculo, largura: largura),
      if (p.placa.isNotEmpty) _par('Placa', p.placa, largura: largura),
    ];

// ===================================================================
// Comprovante de UMA corrida (A5, para o passageiro)
// ===================================================================

Future<List<int>> pdfComprovante(
  RegistroCorrida r,
  DadosPrestador prestador, {
  DateTime? emitidoEm,
}) async {
  final emissao = emitidoEm ?? DateTime.now();
  final trajeto = partesDoTrajeto(r.trajeto);
  final conta = composicaoDoValor(r);
  final forma = r.formaPagamento.trim();

  final doc = pw.Document(
    title: 'Comprovante de corrida ${numeroComprovante(r)}',
    author: textoPdf(prestador.nome.isEmpty ? 'Taximetro' : prestador.nome),
    creator: 'Taximetro - Fortaleza Digital Security',
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 24),
      build: (contexto) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ---- cabecalho ----
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('COMPROVANTE DE CORRIDA', style: _t(13, negrito: true, espaco: 0.5)),
                    pw.SizedBox(height: 2),
                    pw.Text('Transporte de passageiro - táxi', style: _t(8.5, cor: _medio)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Nº', style: _t(7.5, cor: _medio)),
                  pw.Text(numeroComprovante(r), style: _t(8.5, negrito: true)),
                ],
              ),
            ],
          ),
          _divisor(),

          // ---- valor ----
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 12),
            decoration: pw.BoxDecoration(color: _fundo, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(
              children: [
                pw.Text('VALOR DA CORRIDA', style: _t(7.5, negrito: true, cor: _medio, espaco: 0.8)),
                pw.SizedBox(height: 3),
                pw.Text(_real(r.valor), style: _t(26, negrito: true, cor: _destaque)),
                pw.SizedBox(height: 3),
                pw.Text('${dataPorExtenso(r.data)}, às ${hora(r.data)}', style: _t(9, cor: _medio)),
                if (forma.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Forma de pagamento: ${nomeDaForma(forma)}', style: _t(9, negrito: true)),
                ],
              ],
            ),
          ),

          // ---- trajeto ----
          if (trajeto.origem.isNotEmpty || trajeto.unico.isNotEmpty) ...[
            _tituloSecao('Trajeto'),
            if (trajeto.unico.isNotEmpty) _par('Trajeto', _corte(trajeto.unico, 160)),
            if (trajeto.origem.isNotEmpty) _par('Origem', _corte(trajeto.origem, 110)),
            if (trajeto.destino.isNotEmpty) _par('Destino', _corte(trajeto.destino, 110)),
          ],

          // ---- corrida ----
          _tituloSecao('Corrida'),
          _par('Distância', '${Formato.km(r.distanciaKm)} km'),
          _par('Duração', Formato.tempo(r.tempoS)),
          if (r.tempoParadoS > 0) _par('Tempo parado', Formato.tempo(r.tempoParadoS)),

          // ---- composicao ----
          _tituloSecao('Composição do valor'),
          if (conta != null)
            for (final l in conta)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 92, child: pw.Text(l.descricao, style: _t(9.5, cor: _medio))),
                    pw.Expanded(child: pw.Text(l.detalhe, style: _t(8.5, cor: _claro))),
                    pw.Text(_real(l.valor), style: _t(9.5, negrito: true)),
                  ],
                ),
              ),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 3),
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _linha, width: 0.8))),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Text('Total', style: _t(10.5, negrito: true))),
                pw.Text(_real(r.valor), style: _t(10.5, negrito: true)),
              ],
            ),
          ),

          // ---- prestador ----
          if (!prestador.vazio) ...[
            _tituloSecao('Prestador do serviço'),
            ..._blocoPrestador(prestador),
          ],

          pw.Spacer(),
          _divisor(),
          pw.Text(
            'Comprovante emitido pelo aplicativo Taxímetro em ${dataCurta(emissao)} às ${hora(emissao)}. '
            'Não substitui documento fiscal.',
            style: _t(7.5, cor: _claro),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

// ===================================================================
// Relatorio do periodo (A4, para a contabilidade)
// ===================================================================

Future<List<int>> pdfRelatorio(
  List<RegistroCorrida> corridas,
  DadosPrestador prestador, {
  required String periodo,
  DateTime? emitidoEm,
}) async {
  final emissao = emitidoEm ?? DateTime.now();
  final lista = [...corridas]..sort((a, b) => a.data.compareTo(b.data));
  final resumo = resumir(lista);
  final g = resumo.geral;

  final doc = pw.Document(
    title: textoPdf('Relatório de corridas - $periodo'),
    author: textoPdf(prestador.nome.isEmpty ? 'Taximetro' : prestador.nome),
    creator: 'Taximetro - Fortaleza Digital Security',
  );

  pw.Widget numero(String rotulo, String valor, {bool destaque = false}) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: pw.BoxDecoration(color: _fundo, borderRadius: pw.BorderRadius.circular(5)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(rotulo.toUpperCase(), style: _t(7, negrito: true, cor: _medio, espaco: 0.6)),
              pw.SizedBox(height: 3),
              pw.Text(valor, style: _t(13, negrito: true, cor: destaque ? _destaque : _escuro)),
            ],
          ),
        ),
      );

  final cabecalhoTabela = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
  final celula = _t(8);
  final borda = pw.TableBorder(horizontalInside: pw.BorderSide(color: _linha, width: 0.5));

  pw.Widget tabela({
    required List<String> cabecalho,
    required List<List<String>> linhas,
    required Map<int, pw.TableColumnWidth> larguras,
    required Set<int> aDireita,
  }) =>
      pw.TableHelper.fromTextArray(
        headers: cabecalho,
        data: linhas,
        headerStyle: cabecalhoTabela,
        headerDecoration: pw.BoxDecoration(color: _escuro),
        headerAlignments: {for (var i = 0; i < cabecalho.length; i++) i: aDireita.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft},
        cellStyle: celula,
        cellAlignments: {for (var i = 0; i < cabecalho.length; i++) i: aDireita.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft},
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        oddRowDecoration: pw.BoxDecoration(color: _fundo),
        columnWidths: larguras,
        border: borda,
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 28),
      header: (contexto) => contexto.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(textoPdf('Relatório de corridas - $periodo'), style: _t(8, cor: _claro)),
            ),
      footer: (contexto) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Taxímetro - emitido em ${dataCurta(emissao)} às ${hora(emissao)}. Não substitui documento fiscal.',
                style: _t(7.5, cor: _claro),
              ),
            ),
            pw.Text('Página ${contexto.pageNumber} de ${contexto.pagesCount}', style: _t(7.5, cor: _claro)),
          ],
        ),
      ),
      build: (contexto) => [
        pw.Text('Relatório de corridas', style: _t(20, negrito: true)),
        pw.SizedBox(height: 3),
        pw.Text(textoPdf(periodo), style: _t(11, cor: _medio)),
        if (!prestador.vazio) ...[
          pw.SizedBox(height: 10),
          ..._blocoPrestador(prestador, largura: 70),
        ],
        pw.SizedBox(height: 14),

        if (lista.isEmpty)
          pw.Text('Nenhuma corrida no período.', style: _t(11, cor: _medio))
        else ...[
          // ---- numeros grandes ----
          pw.Row(
            children: [
              numero('Corridas', '${g.quantidade}'),
              numero('Distância', '${Formato.km(g.km)} km'),
              numero('Tempo rodando', Formato.tempo(g.tempoS)),
              numero('Total recebido', _real(g.valor), destaque: true),
            ],
          ),

          // ---- por forma de pagamento ----
          _tituloSecao('Por forma de pagamento'),
          tabela(
            cabecalho: ['Forma de pagamento', 'Corridas', 'Valor'],
            linhas: [
              for (final e in resumo.porForma) [e.key, '${e.value.quantidade}', _real(e.value.valor)],
              ['Total', '${g.quantidade}', _real(g.valor)],
            ],
            larguras: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.4)},
            aDireita: {1, 2},
          ),

          // ---- por dia ----
          if (resumo.porDia.length > 1) ...[
            _tituloSecao('Por dia'),
            tabela(
              cabecalho: ['Dia', 'Corridas', 'Km', 'Valor'],
              linhas: [
                for (final e in resumo.porDia)
                  [dataCurta(e.key), '${e.value.quantidade}', Formato.km(e.value.km), _real(e.value.valor)],
              ],
              larguras: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1.4),
              },
              aDireita: {1, 2, 3},
            ),
          ],

          // ---- uma linha por corrida ----
          _tituloSecao('Corridas'),
          tabela(
            cabecalho: ['Nº', 'Data', 'Hora', 'Trajeto', 'Km', 'Tempo', 'Pagamento', 'Valor'],
            linhas: [
              for (var i = 0; i < lista.length; i++)
                [
                  '${i + 1}',
                  dataCurta(lista[i].data),
                  hora(lista[i].data),
                  textoPdf(lista[i].trajeto).isEmpty ? '-' : textoPdf(lista[i].trajeto),
                  Formato.km(lista[i].distanciaKm),
                  Formato.tempo(lista[i].tempoS),
                  nomeDaForma(lista[i].formaPagamento),
                  _real(lista[i].valor),
                ],
            ],
            larguras: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FixedColumnWidth(56),
              2: const pw.FixedColumnWidth(32),
              3: const pw.FlexColumnWidth(3),
              4: const pw.FixedColumnWidth(36),
              5: const pw.FixedColumnWidth(42),
              6: const pw.FixedColumnWidth(66),
              7: const pw.FixedColumnWidth(58),
            },
            aDireita: {0, 4, 5, 7},
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('Total do período', style: _t(11, negrito: true))),
              pw.Text(_real(g.valor), style: _t(11, negrito: true)),
            ],
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
