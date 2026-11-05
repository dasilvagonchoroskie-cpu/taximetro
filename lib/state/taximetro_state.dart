import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constantes.dart';
import '../core/filtro_gps.dart';
import '../core/medidor_corrida.dart';
import '../core/pdf_corrida.dart' as documento;
import '../core/tarifador.dart';
import '../core/velocimetro.dart';
import '../models/aparencia.dart';
import '../models/config.dart';
import '../models/estado_corrida.dart';
import '../models/registro_corrida.dart';

enum FiltroPeriodo { hoje, semana, mes, personalizado }

const Map<FiltroPeriodo, String> rotuloPeriodo = {
  FiltroPeriodo.hoje: 'hoje',
  FiltroPeriodo.semana: 'ultimos 7 dias',
  FiltroPeriodo.mes: 'este mes',
  FiltroPeriodo.personalizado: 'periodo escolhido',
};

const Map<String, String> rotuloPagamento = {
  'dinheiro': 'Dinheiro',
  'pix': 'Pix',
  'cartao': 'Cartao',
  'outro': 'Outro',
};

/// Estado central do taximetro: portado das funcoes do aplicativo original.
class TaximetroState extends ChangeNotifier {
  // ---- Configuracao e aparencia ----
  ConfigTaxi config = ConfigTaxi();
  Aparencia aparencia = Aparencia();

  // ---- Corrida ----
  EstadoCorrida estado = EstadoCorrida();
  bool corridaAtiva = false;

  /// A contagem da corrida (bandeirada congelada, distancia, espera e total).
  /// Peca pura, testada com corridas simuladas.
  late MedidorCorrida _medidor = MedidorCorrida(_tarifadorDaConfig());

  /// Corrida recuperada depois que o Android fechou o app.
  String? avisoCorridaRecuperada;
  double? _latAntesDeFechar;
  double? _lngAntesDeFechar;
  double _segundosSemMedir = 0;
  int _ultimaGravacaoMs = 0;
  bool _pausadaParaPagamento = false;
  static const MethodChannel _canalTela = MethodChannel('taximetro/tela');

  // ---- Historico ----
  List<RegistroCorrida> historico = [];
  FiltroPeriodo filtroPeriodoAtual = FiltroPeriodo.hoje;
  DateTime? filtroDe;
  DateTime? filtroAte;

  // ---- GPS ----
  double? velocidadeAtualKmh;
  Position? ultimaPosicao;
  String statusTexto = 'Localizando...';
  String statusClasse = 'aguardando';
  String? avisoGps;
  bool pronto = false;

  // ---- Internos do calculo (identicos ao original) ----
  /// Instante da ultima CONTAGEM de tempo (GPS ou relogio). Todo tempo que
  /// passa entra na conta como (agora - _ultimoInstanteMs): nada se perde.
  int? _ultimoInstanteMs;

  /// Instante da ultima leitura do GPS que contou tempo. O relogio so conta
  /// sozinho quando o GPS fica mudo (3.1.2: antes ele olhava a ultima
  /// contagem dele mesmo e contava de 3 em 3 segundos).
  int? _ultimoGpsMs;

  /// A ultima leitura foi de carro parado (ou sem GPS): o tempo que ainda
  /// nao tem dono aparece na tela como espera.
  bool _modoEspera = true;

  /// Relogio de verdade; os testes trocam por um relogio de mentira.
  int Function() _agoraMs = () => DateTime.now().millisecondsSinceEpoch;
  Timer? _relogioCorrida;
  StreamSubscription<Position>? _posicaoSub;

  /// Velocimetro da tela (3.1.3): leitura direta do chip de GPS, mais
  /// rapida que a do Google. So para o numero de km/h; nao mexe na cobranca.
  static const EventChannel _canalVelocimetro = EventChannel('taximetro/velocimetro');
  StreamSubscription<dynamic>? _velocimetroSub;
  double? _velDiretoKmh;
  int? _velDiretoEmMs;
  double? _velGoogleKmh;


  /// Filtro do ruido do GPS (3.2.2): guarda o ultimo ponto valido (a ancora)
  /// e decide o que fazer com cada leitura. Limites no topo de filtro_gps.dart.
  final FiltroGps _filtro = FiltroGps();

  /// Cada vez que o GPS e ligado ou desligado, a geracao muda: leitura que
  /// chegue de um ouvinte antigo e ignorada. Um ouvinte por corrida.
  int _geracaoGps = 0;

  /// Os testes trocam o GPS de verdade por um fluxo simulado.
  Stream<Position> Function(LocationSettings)? _fluxoGpsDeTeste;

  bool get emHorarioNoturno => config.emHorarioNoturno;
  double get bandeiradaAtual => corridaAtiva ? _medidor.bandeirada : config.bandeiradaAtual;

  Tarifador _tarifadorDaConfig() => Tarifador(
        taxaKm: config.taxaKm,
        taxaEsperaPorMinuto: config.taxaEspera,
        kmIncluido: config.kmIncluidoNaBandeirada,
        minutosIncluido: config.minutosIncluidoNaBandeirada,
      );

  /// Km cobrados de fato (trechos que valeram por distancia).
  double get kmCobrados => _medidor.kmCobrado;

  double get kmFranquiaRestante =>
      corridaAtiva ? _medidor.kmFranquiaRestante : config.kmIncluidoNaBandeirada;

  double get minutosFranquiaRestantes =>
      corridaAtiva ? _medidor.minutosFranquiaRestantes : config.minutosIncluidoNaBandeirada;

  /// Copia os totais do medidor para a tela. O TOTAL ja inclui a bandeirada.
  void _recalcular() {
    estado.distanciaTotalKm = _medidor.distanciaKm;
    estado.jaAndou = _medidor.jaAndou;
    estado.kmIncluidoUsado = _medidor.kmFranquiaUsada;
    estado.minutosIncluidoUsado = _medidor.minutosFranquiaUsados;
    estado.esperaInicialS = math.min(_medidor.paradoS, _medidor.tarifador.minutosIncluido * 60);
    estado.valorEspera = _medidor.valorEspera;
    _mostrarContadores();
    _gravarCorridaEmAndamento();
  }

  /// Tempo que ja passou e ainda nao foi contado (ate a proxima leitura).
  double _pendenteS(int agoraMs) {
    final ultimo = _ultimoInstanteMs;
    if (ultimo == null || !corridaAtiva || _pausadaParaPagamento) return 0;
    final s = (agoraMs - ultimo) / 1000;
    if (s <= 0) return 0;
    return s > Constantes.tetoDoBuracoS ? Constantes.tetoDoBuracoS.toDouble() : s;
  }

  /// Os contadores da TELA (tempo, espera e valor) andam com o relogio, sem
  /// esperar o GPS (3.1.2). Antes eles so mudavam quando chegava leitura do
  /// GPS — que vem a cada 0,9 a 1,3 s —, e o segundo parecia travar. O tempo
  /// ainda sem dono entra no tempo total e, se o carro estava parado, na
  /// espera. Para nao "voltar" na tela quando a leitura seguinte mostra que o
  /// carro andou, espera e valor nunca diminuem durante a corrida.
  /// [exato] mostra so o que ja foi contado (Finalizar, recibo).
  /// Devolve true quando algum numero da tela mudou.
  bool _mostrarContadores({bool exato = false}) {
    final pend = exato ? 0.0 : _pendenteS(_agoraMs());
    final paradoPrevia = _medidor.paradoS + (_modoEspera ? pend : 0);
    final total = (_medidor.totalS + pend).floor();
    final parado = paradoPrevia.floor();
    final valor = _medidor.bandeirada + _medidor.valorDistancia + _medidor.tarifador.valorEspera(paradoPrevia);
    final antes = '${estado.tempoTotalS}|${estado.tempoParadoS}|${(estado.valorTotal * 100).round()}';
    if (exato) {
      estado.tempoTotalS = total;
      estado.tempoParadoS = parado;
      estado.valorTotal = valor;
    } else {
      estado.tempoTotalS = math.max(estado.tempoTotalS, total);
      estado.tempoParadoS = math.max(estado.tempoParadoS, parado);
      estado.valorTotal = math.max(estado.valorTotal, valor);
    }
    return antes != '${estado.tempoTotalS}|${estado.tempoParadoS}|${(estado.valorTotal * 100).round()}';
  }

  /// Conta o tempo ate agora no modo em que o carro estava (parado vira
  /// espera; andando entra no trecho aberto, que decide distancia OU tempo).
  void _contarAteAgora() {
    // Na tela de pagamento o taximetro ja parou: o tempo ali nao conta.
    if (!corridaAtiva || _pausadaParaPagamento) return;
    final s = _tempoDesdeAUltimaContagem(_agoraMs());
    if (s == null) return;
    if (_modoEspera) {
      _medidor.parou(s);
    } else {
      _medidor.tempoDoTrechoAberto(s);
    }
  }

  /// Parte pura do comeco da corrida (sem GPS e sem Android).
  void _comecarContagem() {
    estado.reiniciar();
    _medidor = MedidorCorrida(_tarifadorDaConfig())..comecar(config.bandeiradaAtual);
    // O tempo comeca a contar no toque de Iniciar (antes o 1o segundo e o
    // tempo ate o primeiro GPS se perdiam).
    final agora = _agoraMs();
    _ultimoInstanteMs = agora;
    _ultimoGpsMs = agora;
    _modoEspera = true;
    _filtro.reiniciar();
    avisoCorridaRecuperada = null;
    _latAntesDeFechar = null;
    _pausadaParaPagamento = false;
    corridaAtiva = true;
    _ultimaGravacaoMs = 0;
    _recalcular();
  }

  /// Grava a corrida em andamento (no maximo a cada 3 s). Se o Android
  /// fechar o app, ela volta de onde parou.
  void _gravarCorridaEmAndamento({bool agora = false}) {
    if (!corridaAtiva) return;
    final ms = DateTime.now().millisecondsSinceEpoch;
    if (!agora && ms - _ultimaGravacaoMs < 3000) return;
    _ultimaGravacaoMs = ms;
    final ancora = _filtro.ancora;
    final dados = <String, dynamic>{
      'versao': 1,
      'salvoEmMs': ms,
      'medidor': _medidor.paraJson(),
      'origem': trajetoOrigem,
      'destino': trajetoDestino,
      if (ancora != null) 'lat': ancora.latitude,
      if (ancora != null) 'lng': ancora.longitude,
    };
    SharedPreferences.getInstance()
        .then((p) => p.setString(Constantes.chaveCorridaEmAndamento, jsonEncode(dados)))
        .catchError((Object _) => false);
  }

  Future<void> _apagarCorridaEmAndamento() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(Constantes.chaveCorridaEmAndamento);
    } catch (_) {
      // Sem armazenamento: nada para apagar.
    }
  }

  /// Se o Android fechou o app no meio da corrida, ela volta de onde parou.
  Future<void> _recuperarCorridaEmAndamento(SharedPreferences prefs) async {
    final bruto = prefs.getString(Constantes.chaveCorridaEmAndamento);
    if (bruto == null || bruto.isEmpty) return;
    try {
      final dados = jsonDecode(bruto) as Map<String, dynamic>;
      final salvoEmMs = (dados['salvoEmMs'] as num).toInt();
      final semMedirS = (DateTime.now().millisecondsSinceEpoch - salvoEmMs) / 1000;
      final medidor = MedidorCorrida.deJson(dados['medidor'] as Map<String, dynamic>);
      if (medidor == null || semMedirS < 0 || semMedirS > 12 * 3600) {
        await prefs.remove(Constantes.chaveCorridaEmAndamento);
        return;
      }
      _medidor = medidor;
      trajetoOrigem = (dados['origem'] as String?) ?? '';
      trajetoDestino = (dados['destino'] as String?) ?? '';
      _latAntesDeFechar = (dados['lat'] as num?)?.toDouble();
      _lngAntesDeFechar = (dados['lng'] as num?)?.toDouble();
      _segundosSemMedir = semMedirS;
      if (_latAntesDeFechar == null || _lngAntesDeFechar == null) {
        _medidor.soTempo(semMedirS);
        _latAntesDeFechar = null;
      }
      estado.reiniciar();
      _filtro.reiniciar();
      // O tempo fechado ja entrou acima; daqui em diante conta normal.
      _ultimoInstanteMs = _agoraMs();
      _ultimoGpsMs = _ultimoInstanteMs;
      _modoEspera = true;
      corridaAtiva = true;
      avisoCorridaRecuperada = 'Corrida recuperada: o aplicativo ficou fechado por '
          '${(semMedirS / 60).ceil()} min. A distancia desse tempo entra em linha reta '
          'e o tempo dele nao e cobrado como espera.';
      statusTexto = 'Corrida recuperada - aguardando GPS';
      statusClasse = 'ativo';
      _recalcular();
      ligarRelogioDaCorrida();
      unawaited(_manterTelaAcesa(true));
      await _iniciarRastreamento();
    } catch (_) {
      await prefs.remove(Constantes.chaveCorridaEmAndamento);
    }
  }

  /// O primeiro GPS bom depois de recuperar mede, em linha reta, quanto o
  /// carro andou enquanto o app estava fechado.
  void _recuperarDistanciaDoTempoFechado(Position pos) {
    final lat = _latAntesDeFechar;
    final lng = _lngAntesDeFechar;
    _latAntesDeFechar = null;
    if (lat == null || lng == null || _segundosSemMedir <= 0) return;
    final metros = Geolocator.distanceBetween(lat, lng, pos.latitude, pos.longitude);
    if (metros / _segundosSemMedir <= velocidadeMaximaKmh / 3.6) {
      _medidor.distanciaRecuperada(metros, _segundosSemMedir);
    } else {
      _medidor.soTempo(_segundosSemMedir);
    }
    _segundosSemMedir = 0;
    _recalcular();
  }

  void dispensarAvisoCorridaRecuperada() {
    avisoCorridaRecuperada = null;
    notifyListeners();
  }

  /// Tela acesa durante a corrida: o motorista ve o valor sem tocar.
  Future<void> _manterTelaAcesa(bool ligar) async {
    try {
      await _canalTela.invokeMethod<void>('manterAcesa', ligar);
    } catch (_) {
      // Sem a ponte com o Android (ex.: testes): segue sem tela acesa.
    }
  }

  /// "Finalizar": o taximetro PARA de contar e devolve o valor final. O que
  /// aparece no pagamento e o que vai para o recibo (antes a espera seguia
  /// contando enquanto o passageiro pagava).
  Future<double> pararParaPagamento() async {
    if (!corridaAtiva) return estado.valorTotal;
    // Conta ate o instante do toque (antes perdia o que passou desde a
    // ultima leitura do GPS) e so depois para.
    _contarAteAgora();
    _pausadaParaPagamento = true;
    desligarRelogioDaCorrida();
    await _pararRastreamento();
    _medidor.fecharTrecho();
    _recalcular();
    _mostrarContadores(exato: true);
    _gravarCorridaEmAndamento(agora: true);
    statusTexto = 'Corrida parada - aguardando pagamento';
    statusClasse = 'espera';
    notifyListeners();
    return _medidor.total;
  }

  /// Desistiu do pagamento: volta a contar de onde parou. O tempo na tela
  /// de pagamento nao e cobrado.
  Future<void> retomarAposPagamentoCancelado() async {
    if (!corridaAtiva || !_pausadaParaPagamento) return;
    _pausadaParaPagamento = false;
    // O tempo na tela de pagamento nao e cobrado: volta a contar daqui.
    _ultimoInstanteMs = _agoraMs();
    _ultimoGpsMs = _ultimoInstanteMs;
    _modoEspera = true;
    _filtro.reiniciar();
    statusTexto = 'Corrida em andamento';
    statusClasse = 'ativo';
    ligarRelogioDaCorrida();
    await _iniciarRastreamento();
    notifyListeners();
  }

  /// O registro da corrida, com os mesmos valores da tela:
  /// valor = bandeirada + distancia + espera.
  RegistroCorrida _montarRegistro(String formaPagamento) {
    _contarAteAgora();
    _medidor.fecharTrecho();
    _recalcular();
    _mostrarContadores(exato: true);
    return RegistroCorrida(
      data: DateTime.now(),
      valor: _medidor.total,
      distanciaKm: _medidor.distanciaKm,
      tempoS: estado.tempoTotalS,
      bandeirada: _medidor.bandeirada,
      valorDistancia: _medidor.valorDistancia,
      valorEspera: _medidor.valorEspera,
      tempoParadoS: estado.tempoParadoS,
      esperaInicialS: estado.esperaInicialS,
      kmIncluidoUsado: estado.kmIncluidoUsado,
      minutosIncluidoUsado: estado.minutosIncluidoUsado,
      trajeto: [trajetoOrigem, trajetoDestino].where((p) => p.trim().isNotEmpty).join(' -> '),
      formaPagamento: formaPagamento,
    );
  }

  @visibleForTesting
  void comecarContagemParaTeste() => _comecarContagem();

  @visibleForTesting
  MedidorCorrida get medidorParaTeste => _medidor;

  @visibleForTesting
  void recalcularParaTeste() => _recalcular();

  @visibleForTesting
  RegistroCorrida montarRegistroParaTeste() => _montarRegistro('');

  @visibleForTesting
  set relogioParaTeste(int Function() agoraMs) => _agoraMs = agoraMs;

  @visibleForTesting
  void tiqueDoRelogioParaTeste() => _tiqueDoRelogio();

  @visibleForTesting
  void medirPosicaoParaTeste(Position pos) => _medirPosicao(pos);

  // ==================================================================
  // Ciclo de vida
  // ==================================================================
  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();

    final rawConfig = prefs.getString(Constantes.chaveConfig);
    if (rawConfig != null && rawConfig.isNotEmpty) {
      try {
        config = ConfigTaxi.fromJson(jsonDecode(rawConfig) as Map<String, dynamic>);
      } catch (_) {
        config = ConfigTaxi();
      }
    }

    final rawAparencia = prefs.getString(Constantes.chaveAparencia);
    if (rawAparencia != null && rawAparencia.isNotEmpty) {
      try {
        aparencia = Aparencia.fromJson(jsonDecode(rawAparencia) as Map<String, dynamic>);
      } catch (_) {
        aparencia = Aparencia();
      }
    }

    final rawHistorico = prefs.getString(Constantes.chaveHistorico);
    if (rawHistorico != null && rawHistorico.isNotEmpty) {
      try {
        historico = (jsonDecode(rawHistorico) as List<dynamic>)
            .map((item) => RegistroCorrida.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        historico = [];
      }
    }

    // A licenca agora e do pacote fortaleza_licenca (portao em app.dart).
    await _recuperarCorridaEmAndamento(prefs);
    pronto = true;
    notifyListeners();
  }

  // ==================================================================
  // Persistencia
  // ==================================================================
  Future<void> gravarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constantes.chaveConfig, jsonEncode(config.toJson()));
  }

  Future<void> gravarAparencia() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constantes.chaveAparencia, jsonEncode(aparencia.toJson()));
    notifyListeners();
  }

  Future<void> _gravarHistorico() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      Constantes.chaveHistorico,
      jsonEncode(historico.map((r) => r.toJson()).toList()),
    );
  }

  // ==================================================================
  // Corrida
  // ==================================================================
  Future<bool> iniciarCorrida() async {
    // Dois toques rapidos em Iniciar nao abrem duas corridas nem dois GPS.
    if (corridaAtiva || _iniciandoCorrida) return false;
    _iniciandoCorrida = true;
    try {
      return await _iniciarCorridaDeFato();
    } finally {
      _iniciandoCorrida = false;
    }
  }

  bool _iniciandoCorrida = false;

  Future<bool> _iniciarCorridaDeFato() async {
    final permissao = await _garantirPermissao();
    if (!permissao) {
      statusTexto = 'Permissao de localizacao negada';
      statusClasse = 'erro';
      notifyListeners();
      return false;
    }
    _comecarContagem();
    _zerarVelocimetro();
    avisoGps = null;
    statusTexto = 'Corrida iniciada - aguardando GPS';
    statusClasse = 'ativo';
    _gravarCorridaEmAndamento(agora: true);
    ligarRelogioDaCorrida();
    unawaited(_manterTelaAcesa(true));
    await _iniciarRastreamento();
    notifyListeners();
    return true;
  }

  Future<void> cancelarCorrida() async {
    corridaAtiva = false;
    _pausadaParaPagamento = false;
    desligarRelogioDaCorrida();
    await _pararRastreamento();
    unawaited(_manterTelaAcesa(false));
    await _apagarCorridaEmAndamento();
    estado.reiniciar();
    _medidor = MedidorCorrida(_tarifadorDaConfig());
    avisoCorridaRecuperada = null;
    _zerarVelocimetro();
    statusTexto = 'Corrida cancelada';
    statusClasse = 'aguardando';
    notifyListeners();
  }

  Future<void> reiniciarCorrida() async {
    if (corridaAtiva) {
      _comecarContagem();
      _gravarCorridaEmAndamento(agora: true);
    } else {
      estado.reiniciar();
      _medidor = MedidorCorrida(_tarifadorDaConfig());
    }
    _zerarVelocimetro();
    statusTexto = corridaAtiva ? 'Corrida reiniciada' : 'Pronto para iniciar';
    statusClasse = corridaAtiva ? 'ativo' : 'aguardando';
    notifyListeners();
  }

  Future<RegistroCorrida> finalizarCorrida({String formaPagamento = ''}) async {
    final registro = _montarRegistro(formaPagamento);
    corridaAtiva = false;
    _pausadaParaPagamento = false;
    desligarRelogioDaCorrida();
    await _pararRastreamento();
    unawaited(_manterTelaAcesa(false));
    await _apagarCorridaEmAndamento();
    historico = [registro, ...historico];
    await _gravarHistorico();
    estado.reiniciar();
    _medidor = MedidorCorrida(_tarifadorDaConfig());
    _ultimoInstanteMs = null;
    _filtro.reiniciar();
    avisoCorridaRecuperada = null;
    _zerarVelocimetro();
    statusTexto = 'Corrida finalizada';
    statusClasse = 'aguardando';
    notifyListeners();
    return registro;
  }

  String trajetoAtual = '';
  String trajetoOrigem = '';
  String trajetoDestino = '';

  // ==================================================================
  // GPS
  // ==================================================================
  Future<bool> _garantirPermissao() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    return permissao == LocationPermission.whileInUse ||
        permissao == LocationPermission.always;
  }

  /// Liga o GPS da corrida. Um ouvinte so: o anterior (se houver) e
  /// desligado, e a troca e feita sem esperar nada no meio, para dois
  /// chamados seguidos nunca deixarem dois ouvintes ligados (3.2.2).
  Future<void> _iniciarRastreamento() async {
    // Servico em primeiro plano: com a tela apagada o Android corta o GPS
    // de aplicativo comum e o medidor congelava — "travava e depois pulava".
    // Com o aviso fixo e a trava de processador ele segue medindo.
    // Uma leitura por segundo e distanceFilter 0: o tempo de espera depende
    // dela. O filtro de distancia fica no calculo (filtro_gps.dart).
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: filtroDistanciaDoFluxoM,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Taxímetro medindo a corrida',
              notificationText: 'A cobrança continua mesmo com a tela apagada.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: filtroDistanciaDoFluxoM);

    final antigaPosicao = _posicaoSub;
    final antigoVelocimetro = _velocimetroSub;
    _velocimetroSub = null;
    final geracao = ++_geracaoGps;
    final fluxo = _fluxoGpsDeTeste?.call(settings) ?? Geolocator.getPositionStream(locationSettings: settings);
    _posicaoSub = fluxo.listen(
      (posicao) {
        // Leitura de um ouvinte que ja foi trocado: ignora.
        if (geracao != _geracaoGps) return;
        try {
          _medirPosicao(posicao);
        } catch (erro) {
          avisarFalhaNoGps(erro);
        }
      },
      onError: (Object erro) {
        if (geracao == _geracaoGps) avisarFalhaNoGps(erro);
      },
    );
    if (_fluxoGpsDeTeste == null) _ligarVelocimetroDireto();
    await antigaPosicao?.cancel();
    await antigoVelocimetro?.cancel();
  }

  Future<void> _pararRastreamento() async {
    _geracaoGps++;
    final posicao = _posicaoSub;
    final velocimetro = _velocimetroSub;
    _posicaoSub = null;
    _velocimetroSub = null;
    _velDiretoKmh = null;
    _velDiretoEmMs = null;
    await posicao?.cancel();
    await velocimetro?.cancel();
  }

  @visibleForTesting
  set fluxoGpsParaTeste(Stream<Position> Function(LocationSettings) fluxo) => _fluxoGpsDeTeste = fluxo;

  @visibleForTesting
  Future<void> iniciarRastreamentoParaTeste() => _iniciarRastreamento();

  @visibleForTesting
  Future<void> pararRastreamentoParaTeste() => _pararRastreamento();

  void avisarFalhaNoGps(Object erro) {
    avisoGps = 'Deu problema ao ler a localizacao: '
        '${erro is Error ? erro.toString() : erro.toString()}. '
        'O tempo continua contando. Tire um print desta tela.';
    notifyListeners();
  }

  /// Atualiza o numero de km/h da tela. Devolve true se mudou.
  bool _mostrarVelocidade() {
    final antes = velocidadeAtualKmh?.round();
    final emMs = _velDiretoEmMs;
    velocidadeAtualKmh = Velocimetro.paraTela(
      diretoKmh: _velDiretoKmh,
      idadeDiretoMs: emMs == null ? null : _agoraMs() - emMs,
      googleKmh: _velGoogleKmh,
    );
    return antes != velocidadeAtualKmh?.round();
  }

  void _zerarVelocimetro() {
    _velDiretoKmh = null;
    _velDiretoEmMs = null;
    _velGoogleKmh = null;
    velocidadeAtualKmh = null;
  }

  void _ligarVelocimetroDireto() {
    _velocimetroSub?.cancel();
    try {
      _velocimetroSub = _canalVelocimetro.receiveBroadcastStream().listen(
        (dado) {
          if (dado is! Map) return;
          final ms = (dado['ms'] as num?)?.toDouble();
          if (ms == null || ms.isNaN || ms < 0) return;
          _velDiretoKmh = ms * 3.6;
          _velDiretoEmMs = _agoraMs();
          if (_mostrarVelocidade()) notifyListeners();
        },
        // Sem o chip liberado: a tela fica com a velocidade do Google.
        onError: (Object _) {},
      );
    } catch (_) {
      _velocimetroSub = null;
    }
  }

  @visibleForTesting
  void velocidadeDiretaParaTeste(double kmh) {
    _velDiretoKmh = kmh;
    _velDiretoEmMs = _agoraMs();
    _mostrarVelocidade();
  }

  void _medirPosicao(Position pos) {
    _velGoogleKmh = pos.speed >= 0 ? pos.speed * 3.6 : null;
    _mostrarVelocidade();
    ultimaPosicao = pos;
    if (!corridaAtiva || _pausadaParaPagamento) {
      notifyListeners();
      return;
    }
    final agoraMs = _agoraMs();
    final avaliacao = _filtro.avaliar(pos, agoraMs);
    switch (avaliacao.tipo) {
      case TipoLeitura.descartada:
        {
          // Leitura ruim (imprecisa, antiga, a primeira, salto): como se nao
          // tivesse chegado. Nao mexe na ancora nem no tempo; se o GPS ficar
          // mudo, o relogio da corrida cuida do tempo.
          return;
        }

      case TipoLeitura.reancorada:
        {
          // Varios saltos seguidos: a ancora antiga era ruim. Recomeca o trecho
          // aqui, sem somar distancia (o tempo do trecho aberto fica).
          _medidor.descartarTremida();
          return;
        }

      case TipoLeitura.ancorada:
        {
          // Primeira leitura valida: o tempo desde o Iniciar conta como espera.
          final esperou = _tempoDesdeAUltimaContagem(agoraMs);
          if (esperou != null) _medidor.parou(esperou);
          _ultimoGpsMs = agoraMs;
          _modoEspera = true;
          _recuperarDistanciaDoTempoFechado(pos);
          _recalcular();
          statusTexto = 'Corrida em andamento';
          statusClasse = 'ativo';
          notifyListeners();
          return;
        }

      case TipoLeitura.parado:
        {
          final segundos = _tempoDesdeAUltimaContagem(agoraMs);
          _ultimoGpsMs = agoraMs;
          if (segundos != null) {
            _medidor.parou(segundos);
          } else {
            _medidor.descartarTremida();
        }
        _modoEspera = true;
        _filtro.ancorar(pos);
        _recalcular();
        statusTexto = 'Parado - cobrando espera';
        statusClasse = 'espera';
        notifyListeners();
        return;
        }

      case TipoLeitura.andando:
        {
          final segundos = _tempoDesdeAUltimaContagem(agoraMs);
          _ultimoGpsMs = agoraMs;
          _modoEspera = false;
          // [metros] e a distancia DESDE A ANCORA: enquanto o trecho nao fecha
          // (menos de filtroDistanciaM), a ancora fica parada e essa distancia
          // ja e o total do trecho.
          if (_medidor.andou(avaliacao.metros, segundos ?? 0)) {
            _filtro.ancorar(pos);
            statusTexto = 'Corrida em andamento';
            statusClasse = 'ativo';
        }
        _recalcular();
        notifyListeners();
        return;
        }
    }
  }

  /// Tempo desde a ultima contagem, com teto para buracos longos.
  double? _tempoDesdeAUltimaContagem(int agoraMs) {
    if (_ultimoInstanteMs == null) {
      _ultimoInstanteMs = agoraMs;
      return null;
    }
    final segundos = (agoraMs - _ultimoInstanteMs!) / 1000;
    _ultimoInstanteMs = agoraMs;
    if (segundos <= 0) return null;
    return segundos > Constantes.tetoDoBuracoS
        ? Constantes.tetoDoBuracoS.toDouble()
        : segundos;
  }

  // ==================================================================
  // Cobranca
  // ==================================================================
  void cobrarComoParado(double segundosParado) {
    _medidor.paradoS += segundosParado;
    _recalcular();
  }

  // ==================================================================
  // Relogio da corrida (independente do GPS)
  // ==================================================================
  void ligarRelogioDaCorrida() {
    desligarRelogioDaCorrida();
    _relogioCorrida = Timer.periodic(
      const Duration(milliseconds: Constantes.relogioCorridaMs),
      (_) => _tiqueDoRelogio(),
    );
  }

  /// A cada 1/4 de segundo: com o GPS mudo, conta o tempo como espera
  /// (continuo, sem pular); com o GPS falando, so anda os contadores da tela.
  void _tiqueDoRelogio() {
    if (!corridaAtiva || _pausadaParaPagamento) return;
    final agoraMs = _agoraMs();
    final ultimoGps = _ultimoGpsMs;
    final gpsMudo = ultimoGps == null || agoraMs - ultimoGps >= Constantes.janelaGpsRecenteMs;
    if (gpsMudo) {
      final segundos = _tempoDesdeAUltimaContagem(agoraMs);
      if (segundos != null) {
        if (_modoEspera) {
          // Sem GPS recente com o carro parado: o tempo conta como espera.
          _medidor.parou(segundos);
        } else {
          // Sem GPS recente com o carro andando (leituras descartadas): o
          // tempo fica no trecho aberto, e a proxima leitura boa decide
          // distancia OU tempo. Antes ele virava espera e a distancia era
          // cobrada de novo depois.
          _medidor.tempoDoTrechoAberto(segundos);
          if (ultimoGps == null || agoraMs - ultimoGps >= Constantes.silencioViraEsperaMs) {
            // GPS mudo por muito tempo: fecha o trecho como espera (a parte
            // sem distancia confiavel continua medida a partir da ancora).
            _medidor.descartarTremida();
            _medidor.fecharTrecho();
            _modoEspera = true;
          }
        }
        _recalcular();
        _mostrarVelocidade();
        notifyListeners();
        return;
      }
    }
    final mudouContador = _mostrarContadores();
    final mudouVelocidade = _mostrarVelocidade();
    if (mudouContador || mudouVelocidade) notifyListeners();
  }

  void desligarRelogioDaCorrida() {
    _relogioCorrida?.cancel();
    _relogioCorrida = null;
  }

  // ==================================================================
  // Historico
  // ==================================================================
  List<RegistroCorrida> historicoFiltrado() {
    final agora = DateTime.now();
    DateTime? de;
    DateTime? ate;

    switch (filtroPeriodoAtual) {
      case FiltroPeriodo.hoje:
        de = DateTime(agora.year, agora.month, agora.day);
        break;
      case FiltroPeriodo.semana:
        de = agora.subtract(const Duration(days: 7));
        break;
      case FiltroPeriodo.mes:
        de = DateTime(agora.year, agora.month, 1);
        break;
      case FiltroPeriodo.personalizado:
        de = filtroDe;
        ate = filtroAte;
        break;
    }

    return historico.where((item) {
      if (de != null && item.data.isBefore(de)) return false;
      if (ate != null) {
        final fim = DateTime(ate.year, ate.month, ate.day, 23, 59, 59);
        if (item.data.isAfter(fim)) return false;
      }
      return true;
    }).toList();
  }

  double totalDoFiltro() =>
      historicoFiltrado().fold(0, (soma, item) => soma + item.valor);

  /// O periodo do filtro, por extenso, para o relatorio em PDF (3.2.1).
  String descricaoPeriodo({DateTime? agora}) {
    final hoje = agora ?? DateTime.now();
    String d(DateTime x) => documento.dataCurta(x);
    switch (filtroPeriodoAtual) {
      case FiltroPeriodo.hoje:
        return 'Hoje, ${d(hoje)}';
      case FiltroPeriodo.semana:
        return 'Últimos 7 dias (${d(hoje.subtract(const Duration(days: 7)))} a ${d(hoje)})';
      case FiltroPeriodo.mes:
        return '${documento.mesPorExtenso(hoje)} (até ${d(hoje)})';
      case FiltroPeriodo.personalizado:
        final de = filtroDe;
        final ate = filtroAte;
        if (de != null && ate != null) return 'De ${d(de)} a ${d(ate)}';
        if (de != null) return 'A partir de ${d(de)}';
        if (ate != null) return 'Até ${d(ate)}';
        return 'Todas as corridas';
    }
  }

  Future<void> limparHistorico() async {
    historico = [];
    await _gravarHistorico();
    notifyListeners();
  }

  void definirFiltro(FiltroPeriodo periodo) {
    filtroPeriodoAtual = periodo;
    notifyListeners();
  }

  void definirPeriodoPersonalizado(DateTime? de, DateTime? ate) {
    filtroDe = de;
    filtroAte = ate;
    filtroPeriodoAtual = FiltroPeriodo.personalizado;
    notifyListeners();
  }

  // ==================================================================
  // Utilidades
  // ==================================================================
  /// Aviso de validade da CNH (mesma regra do original).
  String? avisoValidadeCnh() {
    if (config.cnhValidade.trim().isEmpty) return null;
    final fim = DateTime.tryParse(config.cnhValidade);
    if (fim == null) return null;

    final dias = fim.difference(DateTime.now()).inDays;
    if (dias < 0) return 'CNH VENCIDA ha ${-dias} dia(s). Providencie a renovacao.';
    if (dias <= 30) return 'CNH vence em $dias dia(s).';
    return null;
  }

  bool get cnhVencida {
    if (config.cnhValidade.trim().isEmpty) return false;
    final fim = DateTime.tryParse(config.cnhValidade);
    if (fim == null) return false;
    return fim.isBefore(DateTime.now());
  }

  @override
  void dispose() {
    desligarRelogioDaCorrida();
    _posicaoSub?.cancel();
    _velocimetroSub?.cancel();
    super.dispose();
  }
}

