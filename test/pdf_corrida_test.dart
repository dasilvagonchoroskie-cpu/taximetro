import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/pdf_corrida.dart';
import 'package:taximetro/models/registro_corrida.dart';

/// 3.2.1 — PDFs do historico. O Fabiano nao conseguia mandar o comprovante
/// de uma corrida antiga para a passageira: o historico so tinha o relatorio
/// do periodo, e o botao do comprovante gravava o PDF sem abrir nada.
///
/// Estes testes geram os dois PDFs de verdade (dados FICTICIOS) e guardam
/// amostras em build/amostras-pdf/, que a esteira devolve ao repositorio
/// para conferir o visual.
void main() {
  const prestador = DadosPrestador(
    nome: 'João da Silva (exemplo)',
    cnh: '00000000000 (categoria B)',
    veiculo: 'Chevrolet Spin Branca 2022',
    placa: 'ABC1D23',
  );
  final emissao = DateTime(2026, 10, 23, 9, 30);
  final pasta = Directory('build/amostras-pdf')..createSync(recursive: true);

  void guardar(String nome, List<int> bytes) => File('${pasta.path}/$nome').writeAsBytesSync(bytes);
  bool ehPdf(List<int> b) => b.length > 800 && String.fromCharCodes(b.take(5)) == '%PDF-';

  /// Corrida coerente com a cobranca: total = bandeirada + distancia + espera.
  RegistroCorrida corrida({
    required DateTime data,
    double distanciaKm = 4.2,
    int tempoS = 760,
    int paradoS = 130,
    double valorDistancia = 8.10,
    double valorEspera = 0,
    double bandeirada = 10,
    String trajeto = '',
    String forma = 'pix',
  }) =>
      RegistroCorrida(
        data: data,
        valor: ((bandeirada + valorDistancia + valorEspera) * 100).round() / 100,
        distanciaKm: distanciaKm,
        tempoS: tempoS,
        bandeirada: bandeirada,
        valorDistancia: valorDistancia,
        valorEspera: valorEspera,
        tempoParadoS: paradoS,
        kmIncluidoUsado: 1.5,
        minutosIncluidoUsado: 5,
        trajeto: trajeto,
        formaPagamento: forma,
      );

  test('texto do PDF: acentos ficam, seta e travessao viram equivalentes, emoji sai', () {
    expect(textoPdf('Goiânia → Itumbiara'), 'Goiânia -> Itumbiara');
    expect(textoPdf('Rua São João — nº 10'), 'Rua São João - nº 10');
    expect(textoPdf('“Hospital” 🚕 centro\n2º andar'), '"Hospital" centro 2º andar');
    expect(textoPdf(null), '');
    for (final r in textoPdf('ção ã é ü ñ ß — → 🚕 € …').runes) {
      expect(r, lessThanOrEqualTo(0xFF), reason: 'a Helvetica so desenha ate U+00FF');
    }
  });

  test('trajeto "Origem -> Destino" vira duas linhas no comprovante', () {
    final p = partesDoTrajeto('Rodoviária -> Hospital Municipal');
    expect(p.origem, 'Rodoviária');
    expect(p.destino, 'Hospital Municipal');
    expect(partesDoTrajeto('Centro').unico, 'Centro');
    expect(partesDoTrajeto('').unico, '');
  });

  test('composicao do valor fecha com o total', () {
    final r = corrida(data: DateTime(2026, 10, 22, 18, 40), valorDistancia: 8.10, valorEspera: 1.65);
    final linhas = composicaoDoValor(r)!;
    expect(linhas.map((l) => l.descricao), ['Bandeirada', 'Distância', 'Tempo parado']);
    final soma = linhas.fold<int>(0, (t, l) => t + (l.valor * 100).round());
    expect(soma, (r.valor * 100).round());
  });

  test('corrida antiga cujas partes nao fecham: comprovante mostra so o total', () {
    final antiga = RegistroCorrida(
      data: DateTime(2026, 9, 29, 10),
      valor: 4.29, // a 3.0 gravava sem a bandeirada
      distanciaKm: 2.93,
      tempoS: 278,
      bandeirada: 10,
      valorDistancia: 4.29,
    );
    expect(composicaoDoValor(antiga), isNull);
  });

  test('nomes dos arquivos', () {
    final r = corrida(data: DateTime(2026, 10, 23, 9, 5, 7));
    expect(nomeArquivoComprovante(r), 'comprovante-corrida-23-10-2026-09h05.pdf');
    expect(numeroComprovante(r), '20261023-090507');
    final outra = corrida(data: DateTime(2026, 10, 1, 7));
    expect(nomeArquivoRelatorio([r, outra], emissao), 'relatorio-corridas-01-10-2026-a-23-10-2026.pdf');
    expect(nomeArquivoRelatorio([r], emissao), 'relatorio-corridas-23-10-2026.pdf');
    expect(nomeArquivoRelatorio([], emissao), 'relatorio-corridas-23-10-2026.pdf');
  });

  test('comprovante completo de uma corrida', () async {
    final r = corrida(
      data: DateTime(2026, 10, 22, 18, 40, 12),
      distanciaKm: 5.83,
      tempoS: 1145,
      paradoS: 412,
      valorDistancia: 12.99,
      valorEspera: 0.94,
      trajeto: 'Rodoviária de Goiatuba -> Hospital Municipal, Rua São José, 1200',
      forma: 'pix',
    );
    final bytes = await pdfComprovante(r, prestador, emitidoEm: emissao);
    expect(ehPdf(bytes), isTrue);
    guardar('comprovante-exemplo.pdf', bytes);
  });

  test('comprovante sem trajeto, sem pagamento e sem dados do motorista', () async {
    final r = corrida(data: DateTime(2026, 10, 23, 7, 2), distanciaKm: 1.1, valorDistancia: 0, paradoS: 0, forma: '');
    final bytes = await pdfComprovante(r, const DadosPrestador(), emitidoEm: emissao);
    expect(ehPdf(bytes), isTrue);
    guardar('comprovante-minimo.pdf', bytes);
  });

  test('comprovante com texto estranho e trajeto enorme nao quebra', () async {
    final enorme = List.filled(40, 'Avenida Brasil — trecho 🚕 “longo”').join(' ');
    final r = corrida(data: DateTime(2026, 10, 23, 23, 59), trajeto: '$enorme -> $enorme', forma: 'cartao');
    final bytes = await pdfComprovante(r, prestador, emitidoEm: emissao);
    expect(ehPdf(bytes), isTrue);
    guardar('comprovante-texto-estranho.pdf', bytes);
  });

  test('corrida antiga (3.0) gera comprovante so com o total', () async {
    final antiga = RegistroCorrida(
      data: DateTime(2026, 9, 29, 10),
      valor: 4.29,
      distanciaKm: 2.93,
      tempoS: 278,
      bandeirada: 10,
      valorDistancia: 4.29,
    );
    expect(ehPdf(await pdfComprovante(antiga, prestador, emitidoEm: emissao)), isTrue);
  });

  List<RegistroCorrida> mesDeCorridas() {
    final lista = <RegistroCorrida>[];
    const formas = ['pix', 'dinheiro', 'pix', 'cartao', '', 'dinheiro', 'outro'];
    var n = 0;
    for (var dia = 1; dia <= 23; dia++) {
      for (var k = 0; k < 6; k++) {
        n++;
        final distancia = 1.2 + (n * 37 % 90) / 10;
        final cobrado = distancia > 1.5 ? ((distancia - 1.5) * 3 * 100).round() / 100 : 0.0;
        final espera = n % 4 == 0 ? ((n % 7) * 0.55 * 100).round() / 100 : 0.0;
        lista.add(corrida(
          data: DateTime(2026, 10, dia, 6 + k * 3, (n * 13) % 60),
          distanciaKm: distancia,
          tempoS: 300 + (n * 97) % 1800,
          paradoS: (n * 31) % 600,
          valorDistancia: cobrado,
          valorEspera: espera,
          bandeirada: 6 + k * 3 >= 22 ? 20 : 10,
          trajeto: n % 3 == 0 ? '' : (n % 3 == 1 ? 'Centro -> Bairro Bela Vista' : 'Rodoviária'),
          forma: formas[n % formas.length],
        ));
      }
    }
    // O historico guarda a mais nova primeiro.
    return lista.reversed.toList();
  }

  test('resumo do relatorio: por forma e por dia batem com o total, centavo a centavo', () {
    final lista = mesDeCorridas();
    final resumo = resumir(lista);
    final esperado = lista.fold<int>(0, (t, r) => t + (r.valor * 100).round());
    expect(resumo.geral.centavos, esperado);
    expect(resumo.geral.quantidade, lista.length);
    expect(resumo.porForma.fold<int>(0, (t, e) => t + e.value.centavos), esperado);
    expect(resumo.porDia.fold<int>(0, (t, e) => t + e.value.centavos), esperado);
    expect(resumo.porDia.length, 23);
    expect(resumo.porDia.first.key.isBefore(resumo.porDia.last.key), isTrue);
    expect(resumo.porForma.map((e) => e.key).toList(), ['Pix', 'Dinheiro', 'Cartão', 'Outro', 'Não informado']);
  });

  test('relatorio de um mes (138 corridas, varias paginas)', () async {
    final lista = mesDeCorridas();
    final bytes = await pdfRelatorio(lista, prestador, periodo: 'Outubro de 2026 (até 23/10/2026)', emitidoEm: emissao);
    expect(ehPdf(bytes), isTrue);
    guardar('relatorio-exemplo.pdf', bytes);
  });

  test('relatorio de um dia so e relatorio vazio nao quebram', () async {
    final dia = [
      corrida(data: DateTime(2026, 10, 23, 8, 10), trajeto: 'Centro -> Hospital'),
      corrida(data: DateTime(2026, 10, 23, 11, 45), forma: 'dinheiro'),
    ];
    final umDia = await pdfRelatorio(dia, prestador, periodo: 'Hoje, 23/10/2026', emitidoEm: emissao);
    expect(ehPdf(umDia), isTrue);
    guardar('relatorio-um-dia.pdf', umDia);
    final vazio = await pdfRelatorio([], const DadosPrestador(), periodo: 'Hoje, 23/10/2026', emitidoEm: emissao);
    expect(ehPdf(vazio), isTrue);
  });
}
