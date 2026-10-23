import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formato.dart';
import '../core/pdf_corrida.dart' show dataCurta, hora;
import '../models/registro_corrida.dart';
import '../state/taximetro_state.dart';
import '../widgets/ui.dart';
import 'compartilhar_pdf.dart';

/// Comprovante da corrida: aparece depois de finalizar e, desde a 3.2.1,
/// tambem ao tocar numa corrida do historico ([doHistorico]).
class ReciboScreen extends StatelessWidget {
  const ReciboScreen({super.key, required this.registro, this.doHistorico = false});

  final RegistroCorrida registro;
  final bool doHistorico;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = context.read<TaximetroState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Comprovante da corrida')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface,
                  border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text('TOTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: t.colorScheme.onSurface.withValues(alpha: 0.55))),
                    const SizedBox(height: 6),
                    Text(
                      'R\$ ${Formato.moeda(registro.valor)}',
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: t.colorScheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${dataCurta(registro.data)} às ${hora(registro.data)}',
                      style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Painel(
                titulo: 'DETALHES DA CONTA',
                child: Text(registro.detalhamento, style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
              const SizedBox(height: 14),
              Painel(
                titulo: 'CORRIDA',
                child: Column(
                  children: [
                    _L(rotulo: 'Distancia', valor: '${Formato.km(registro.distanciaKm)} km'),
                    _L(rotulo: 'Tempo', valor: Formato.tempo(registro.tempoS)),
                    _L(rotulo: 'Tempo parado', valor: Formato.tempo(registro.tempoParadoS)),
                    if (registro.trajeto.isNotEmpty) _L(rotulo: 'Trajeto', valor: registro.trajeto),
                    if (registro.formaPagamento.isNotEmpty)
                      _L(rotulo: 'Pagamento', valor: rotuloPagamento[registro.formaPagamento] ?? registro.formaPagamento),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Painel(
                titulo: 'PRESTADOR',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.config.motoristaNome.isEmpty ? 'Motorista nao informado' : s.config.motoristaNome, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('CNH ${s.config.motoristaCnh.isEmpty ? '—' : s.config.motoristaCnh} ${s.config.cnhCategoria}', style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.7))),
                    Text(s.config.descricaoVeiculo.isEmpty ? 'Veiculo nao informado' : s.config.descricaoVeiculo, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.7))),
                    if (s.config.veiculoPlaca.isNotEmpty)
                      Text(s.config.veiculoPlaca, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Abre o "compartilhar" do celular com o PDF: WhatsApp do
              // passageiro, e-mail, Drive... (antes so gravava e nao abria nada)
              BotaoPdf(
                rotulo: 'ENVIAR COMPROVANTE EM PDF',
                principal: doHistorico,
                acao: () => compartilharComprovante(context, s, registro),
              ),
              const SizedBox(height: 10),
              doHistorico
                  ? BotaoApp(
                      label: 'VOLTAR',
                      icon: Icons.arrow_back,
                      cor: t.colorScheme.surfaceContainerHighest,
                      corTexto: t.colorScheme.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : BotaoApp(label: 'CONCLUIR', icon: Icons.check, onPressed: () => Navigator.of(context).pop()),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _L extends StatelessWidget {
  const _L({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(rotulo, style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.65)))),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
