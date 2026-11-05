/// Constantes do taximetro, portadas 1:1 do aplicativo original.
class Constantes {
  const Constantes._();

  // ---- GPS ----
  // Os limites do filtro de ruido (precisao, velocidade minima, salto,
  // trecho minimo) ficam no topo de lib/core/filtro_gps.dart (3.2.2).
  /// Velocimetro da TELA: abaixo disto mostra 0 (so a tela; o filtro da
  /// distancia usa velocidadeMinimaMs, de filtro_gps.dart).
  static const double velocidadeParadoKmh = 2.5;

  /// Distancia (m) para valer como "saiu do lugar" e encerrar a franquia.
  static const double distanciaSaiuDoLugarM = 50;

  /// Valvula de seguranca quando o aparelho nao informa velocidade.
  static const double fugaDaAncoraM = 150;

  /// Teto de um unico buraco de contagem (meia hora), em segundos.
  static const int tetoDoBuracoS = 1800;

  /// Intervalo do relogio da corrida (ms). 1/4 de segundo: os contadores da
  /// tela viram o segundo na hora certa, sem "travar" (3.1.2).
  static const int relogioCorridaMs = 250;

  /// Se o GPS contou ha menos que isto, deixa o tempo com ele (ms).
  static const int janelaGpsRecenteMs = 2500;

  /// GPS mudo com o carro andando por mais que isto: o trecho aberto fecha
  /// como espera (ms). Antes disso o tempo fica no trecho, para a proxima
  /// leitura boa decidir distancia OU tempo.
  static const int silencioViraEsperaMs = 30000;

  /// Intervalo minimo entre atualizacoes da notificacao (ms).
  static const int intervaloNotificacaoMs = 1000;

  // ---- Chaves de armazenamento ----
  static const String chaveConfig = 'taxi.config';
  static const String chaveHistorico = 'taxi.historico';
  static const String chaveAparencia = 'taxi.aparencia';
  static const String chaveLicenca = 'taxi.licenca';
  static const String chaveCorridaEmAndamento = 'taxi.corrida_em_andamento';
}

/// Configuracao padrao (CONFIG_PADRAO do original).
class ConfigPadrao {
  const ConfigPadrao._();

  static const double bandeiradaDia = 10.00;
  static const double bandeiradaNoite = 20.00;
  static const int horaInicioNoite = 22;
  static const int horaFimNoite = 6;
  static const double kmIncluidoNaBandeirada = 1.5;
  static const double minutosIncluidoNaBandeirada = 5;
  static const String navegador = 'waze';
  static const double taxaKm = 3.00; // tarifa do Fabiano (13/09/2026)
  static const double taxaEspera = 0.55;
  static const double limiarVelocidadeKmh = 5;
}
