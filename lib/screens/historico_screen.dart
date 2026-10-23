import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formato.dart';
import '../models/registro_corrida.dart';
import '../state/taximetro_state.dart';
import '../widgets/ui.dart';
import 'compartilhar_pdf.dart';
import 'recibo_pdf.dart';

class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  bool _personalizado = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TaximetroState>();
    final t = Theme.of(context);
    final lista = s.historicoFiltrado();
    final total = s.totalDoFiltro();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historico'),
        actions: [
          IconButton(
            tooltip: 'Limpar historico',
            icon: const Icon(Icons.delete_outline),
            onPressed: s.historico.isEmpty ? null : () => _limpar(context, s),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final periodo in FiltroPeriodo.values)
                        GestureDetector(
                          onTap: () {
                            if (periodo == FiltroPeriodo.personalizado) {
                              setState(() => _personalizado = true);
                            } else {
                              setState(() => _personalizado = false);
                              s.definirFiltro(periodo);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: s.filtroPeriodoAtual == periodo
                                  ? t.colorScheme.primary.withValues(alpha: 0.18)
                                  : t.colorScheme.surfaceContainerHighest,
                              border: Border.all(
                                color: s.filtroPeriodoAtual == periodo ? t.colorScheme.primary : t.dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              periodo == FiltroPeriodo.hoje
                                  ? 'Hoje'
                                  : periodo == FiltroPeriodo.semana
                                      ? '7 dias'
                                      : periodo == FiltroPeriodo.mes
                                          ? 'Mes'
                                          : 'Escolher',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: s.filtroPeriodoAtual == periodo ? t.colorScheme.primary : t.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_personalizado || s.filtroPeriodoAtual == FiltroPeriodo.personalizado) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: BotaoApp(
                            label: s.filtroDe == null ? 'De' : Formato.dataIso(s.filtroDe!),
                            cor: t.colorScheme.surfaceContainerHighest,
                            corTexto: t.colorScheme.onSurface,
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                initialDate: s.filtroDe ?? DateTime.now(),
                              );
                              if (d != null) s.definirPeriodoPersonalizado(d, s.filtroAte);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: BotaoApp(
                            label: s.filtroAte == null ? 'Ate' : Formato.dataIso(s.filtroAte!),
                            cor: t.colorScheme.surfaceContainerHighest,
                            corTexto: t.colorScheme.onSurface,
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                                initialDate: s.filtroAte ?? DateTime.now(),
                              );
                              if (d != null) s.definirPeriodoPersonalizado(s.filtroDe, d);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.colorScheme.surface,
                      border: Border.all(color: t.dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${lista.length} corrida${lista.length == 1 ? '' : 's'} - ${rotuloPeriodo[s.filtroPeriodoAtual]}',
                          style: TextStyle(fontSize: 13, color: t.colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                        Text(
                          'R\$ ${Formato.moeda(total)}',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                  // Relatorio de todas as corridas do periodo (contabilidade).
                  // Antes era um icone pequeno no topo, facil de nao achar.
                  const SizedBox(height: 10),
                  BotaoPdf(
                    rotulo: 'RELATÓRIO DO PERÍODO EM PDF',
                    habilitado: lista.isNotEmpty,
                    acao: () => compartilharRelatorio(context, s, lista),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? Vazio(
                      // O filtro abre em "Hoje": a corrida de ontem some da
                      // lista e parece que nao existe.
                      texto: s.historico.isEmpty
                          ? 'Nenhuma corrida registrada ainda.'
                          : 'Nenhuma corrida nesse período.\nAs corridas de outros dias aparecem em 7 dias, Mês ou Escolher.',
                      icon: Icons.receipt_long_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ItemHistorico(registro: lista[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _limpar(BuildContext context, TaximetroState s) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Limpar historico'),
        content: const Text('Todas as corridas serao removidas. Esta acao nao pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Limpar')),
        ],
      ),
    );

    if (confirmar == true) await s.limparHistorico();
  }
}

class _ItemHistorico extends StatelessWidget {
  const _ItemHistorico({required this.registro});

  final RegistroCorrida registro;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = context.read<TaximetroState>();
    // Tocar no cartao abre o comprovante completo (3.2.1).
    return Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ReciboScreen(registro: registro, doHistorico: true)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    Formato.dataHistorico(registro.data),
                    style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const Spacer(),
                  Text(
                    'R\$ ${Formato.moeda(registro.valor)}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.colorScheme.primary),
                  ),
                ],
              ),
              if (registro.trajeto.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(registro.trajeto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 6),
              Text(
                '${Formato.km(registro.distanciaKm)} km - ${Formato.tempo(registro.tempoS)}',
                style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 6),
              Text(
                registro.detalhamento,
                style: TextStyle(fontSize: 11, color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (registro.formaPagamento.isNotEmpty)
                    Selo(texto: (rotuloPagamento[registro.formaPagamento] ?? registro.formaPagamento).toUpperCase()),
                  const Spacer(),
                  // Um toque: PDF desta corrida, pronto para o WhatsApp.
                  BotaoPdf(
                    rotulo: 'Comprovante PDF',
                    compacto: true,
                    acao: () => compartilharComprovante(context, s, registro),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
