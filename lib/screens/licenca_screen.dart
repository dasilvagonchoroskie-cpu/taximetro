import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/licenca.dart';
import '../state/taximetro_state.dart';
import '../widgets/ui.dart';

/// Ativacao por licenca (tela-licenca do original).
class LicencaScreen extends StatefulWidget {
  const LicencaScreen({super.key});

  @override
  State<LicencaScreen> createState() => _LicencaScreenState();
}

class _LicencaScreenState extends State<LicencaScreen> with WidgetsBindingObserver {
  final _chave = TextEditingController();
  bool _ativando = false;

  @override
  void initState() {
    super.initState();
    // Licenca vencida: a chave ja vem preenchida, e so tocar em Ativar.
    _chave.text = context.read<TaximetroState>().chaveGuardada ?? '';
    WidgetsBinding.instance.addObserver(this);
    // 3.1.1: abriu o app com a mensagem do WhatsApp copiada? A chave entra
    // sozinha, sem digitar nada.
    WidgetsBinding.instance.addPostFrameCallback((_) => _procurarChaveCopiada());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // O Android so deixa ler o que foi copiado com a janela ja em foco.
      Future.delayed(const Duration(milliseconds: 400), _procurarChaveCopiada);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chave.dispose();
    super.dispose();
  }

  /// A chave que estiver no que foi copiado (a mensagem inteira serve).
  Future<String?> _chaveCopiada() async {
    try {
      final dados = await Clipboard.getData(Clipboard.kTextPlain);
      final texto = dados?.text ?? '';
      if (texto.trim().isEmpty || !mounted) return null;
      return Licenca.extrairChave(texto, ignorar: context.read<TaximetroState>().codigoAparelho);
    } catch (_) {
      return null;
    }
  }

  void _preencher(String chave) {
    _chave.value = TextEditingValue(text: chave, selection: TextSelection.collapsed(offset: chave.length));
    setState(() {});
  }

  /// So preenche sozinho com o campo vazio: nunca troca o que o cliente digitou.
  Future<void> _procurarChaveCopiada() async {
    if (!mounted || _ativando || _chave.text.trim().isNotEmpty) return;
    final chave = await _chaveCopiada();
    if (chave == null || !mounted || _chave.text.trim().isNotEmpty) return;
    _preencher(chave);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chave encontrada no que você copiou. Toque em ATIVAR APARELHO.')),
    );
  }

  /// Chave curta completa (16 letras) ou chave comprida do gerador de
  /// reserva (80+ caracteres). Antes so a curta acendia o botao.
  bool get _chaveCompleta {
    final limpa = _chave.text.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return limpa.replaceAll('-', '').length == 16 || limpa.length >= 80;
  }

  Future<void> _colarChave() async {
    final chave = await _chaveCopiada();
    if (!mounted) return;
    if (chave == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não achei a chave no que está copiado. No WhatsApp, segure o dedo na mensagem '
              'com a chave, toque em Copiar e volte aqui.'),
        ),
      );
      return;
    }
    _preencher(chave);
  }

  Future<void> _ativar() async {
    setState(() => _ativando = true);
    await context.read<TaximetroState>().ativarLicenca(_chave.text);
    if (mounted) setState(() => _ativando = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TaximetroState>();
    final t = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary.withValues(alpha: 0.16),
                      border: Border.all(color: t.colorScheme.primary),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.local_taxi, size: 32, color: t.colorScheme.primary),
                  ),
                  const SizedBox(height: 18),
                  const Text('Taximetro', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                  const SizedBox(height: 4),
                  Text(
                    'Ative este aparelho para comecar a usar',
                    style: TextStyle(fontSize: 14, color: t.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 24),
                  Painel(
                    titulo: 'CODIGO DESTE APARELHO',
                    child: Column(
                      children: [
                        SelectableText(
                          s.codigoAparelho ?? '—',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, color: t.colorScheme.primary),
                        ),
                        const SizedBox(height: 10),
                        BotaoApp(
                          label: 'Copiar codigo',
                          icon: Icons.copy,
                          cor: t.colorScheme.surfaceContainerHighest,
                          corTexto: t.colorScheme.onSurface,
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: s.codigoAparelho ?? ''));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Codigo copiado.')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Painel(
                    titulo: 'CHAVE DE ATIVACAO',
                    child: Column(
                      children: [
                        CampoApp(
                          label: 'Chave',
                          hint: 'XXXX-XXXX-XXXX-XXXX ou a chave comprida',
                          controller: _chave,
                          onChanged: (v) {
                            // Colou a mensagem inteira direto no campo: fica so a chave.
                            final achada = v.length > 19 ? Licenca.extrairChave(v, ignorar: s.codigoAparelho) : null;
                            final m = achada ?? Licenca.formatarChaveDigitada(v);
                            if (m != v) {
                              _chave.value = TextEditingValue(text: m, selection: TextSelection.collapsed(offset: m.length));
                            }
                            setState(() {});
                          },
                          error: s.erroLicenca,
                        ),
                        // Colar serve para a mensagem inteira do WhatsApp:
                        // o app acha a chave (curta ou comprida) no texto.
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _colarChave,
                            icon: const Icon(Icons.content_paste),
                            label: const Text('Colar chave'),
                          ),
                        ),
                        Text(
                          'Recebeu pelo WhatsApp? Segure o dedo na mensagem, toque em Copiar e volte aqui: '
                          'a chave entra sozinha.',
                          style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  BotaoApp(
                    label: 'ATIVAR APARELHO',
                    icon: Icons.lock_open,
                    loading: _ativando,
                    enabled: _chaveCompleta,
                    onPressed: _ativar,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'A chave e valida apenas para o codigo de aparelho acima.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
