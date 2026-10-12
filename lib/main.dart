import 'package:flutter/material.dart';
import 'package:fortaleza_licenca/fortaleza_licenca.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/constantes.dart';
import 'state/taximetro_state.dart';

/// Versao que aparece na Central ao lado da licenca deste aparelho.
const versaoTaximetro = '3.2.0';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Licenca pela Central de Licencas 3. O prefixo antigo faz quem ja usa o
  // taximetro 3.1 continuar liberado, sem perceber a troca.
  final licenca = ControleLicenca(const ConfiguracaoLicenca(
    appId: 'taximetro',
    nomeApp: 'Taxímetro',
    versaoApp: versaoTaximetro,
    prefixoLegado: Constantes.chaveLicenca,
  ));
  runApp(
    ChangeNotifierProvider<TaximetroState>(
      create: (_) => TaximetroState()..iniciar(),
      child: TaxiApp(licenca: licenca),
    ),
  );
}
