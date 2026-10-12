import 'package:flutter/material.dart';
import 'package:fortaleza_licenca/fortaleza_licenca.dart';
import 'package:provider/provider.dart';

import 'screens/autorizacoes_screen.dart';
import 'screens/medidor_screen.dart';
import 'state/taximetro_state.dart';
import 'widgets/ui.dart';

class TaxiApp extends StatelessWidget {
  const TaxiApp({super.key, required this.licenca});

  final ControleLicenca licenca;

  @override
  Widget build(BuildContext context) {
    final aparencia = context.watch<TaximetroState>().aparencia;
    return MaterialApp(
      title: 'Taximetro',
      debugShowCheckedModeBanner: false,
      theme: temaDoApp(aparencia),
      home: _Raiz(licenca: licenca),
    );
  }
}

class _Raiz extends StatelessWidget {
  const _Raiz({required this.licenca});

  final ControleLicenca licenca;

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<TaximetroState>();

    if (!estado.pronto) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // So abre no aparelho liberado pela Central de Licencas. Fora isso, o
    // portao mostra a tela de pedir liberacao (sem chave) ou a chave.
    return PortaoLicenca(
      controle: licenca,
      icone: Icons.local_taxi,
      child: const AutorizacoesScreen(child: MedidorScreen()),
    );
  }
}
