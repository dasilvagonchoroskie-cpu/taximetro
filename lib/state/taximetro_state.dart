import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constantes.dart';
import '../core/licenca.dart';
import '../core/medidor_corrida.dart';
import '../core/tarifador.dart';
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
  bool licenciado = false;
  String? codigoAparelho;
  String? erroLicenca;

  /// Chave curta guardada (para renovar sozinho e preencher a tela).
  String? chaveGuardada;
  bool ativandoLicenca = false;

  static const String _kAssinatura = '${Constantes.chaveLicenca}.assinatura';
  static const String _kValidade = '${Constantes.chaveLicenca}.validade';
  static const String _kChave = '${Constantes.chaveLicenca}.chave';
  static const String _kDataVista = '${Constantes.chaveLicenca}.dataVista';

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
  int? _ultimoInstanteMs;
  Timer? _relogioCorrida;
  StreamSubscription<Position>? _posicaoSub;


  /// Ancora: ponto de referencia do trecho acumulado.
  Position? _ancora;

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
    estado.valorTotal = _medidor.total;
    estado.tempoParadoS = _medidor.paradoS.floor();
    estado.tempoTotalS = _medidor.totalS.floor();
    _gravarCorridaEmAndamento();
  }

  /// Parte pura do comeco da corrida (sem GPS e sem Android).
  void _comecarContagem() {
    estado.reiniciar();
    _medidor = MedidorCorrida(_tarifadorDaConfig())..comecar(config.bandeiradaAtual);
    _ultimoInstanteMs = null;
    _ancora = null;
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
    final ancora = _ancora;
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
      _ancora = null;
      _ultimoInstanteMs = null;
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
    final metros = _haversineMetros(lat, lng, pos.latitude, pos.longitude);
    if (metros / _segundosSemMedir <= Constantes.velocidadeImpossivelMs) {
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
    _pausadaParaPagamento = true;
    desligarRelogioDaCorrida();
    await _pararRastreamento();
    _medidor.fecharTrecho();
    _recalcular();
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
    _ultimoInstanteMs = null;
    _ancora = null;
    statusTexto = 'Corrida em andamento';
    statusClasse = 'ativo';
    ligarRelogioDaCorrida();
    await _iniciarRastreamento();
    notifyListeners();
  }

  /// O registro da corrida, com os mesmos valores da tela:
  /// valor = bandeirada + distancia + espera.
  RegistroCorrida _montarRegistro(String formaPagamento) {
    _medidor.fecharTrecho();
    _recalcular();
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

    await _carregarCodigoAparelho();
    await _conferirLicencaNaAbertura(prefs);
    if (licenciado) await _recuperarCorridaEmAndamento(prefs);
    pronto = true;
    notifyListeners();
  }

  /// Mesmo identificador que o plugin nativo da versao antiga entregava
  /// (ANDROID_ID), pela mesma conta: o codigo do aparelho nao muda.
  Future<void> _carregarCodigoAparelho() async {
    var bruto = '';
    try {
      bruto = await const MethodChannel('taximetro/licenca').invokeMethod<String>('idDoAparelho') ?? '';
    } catch (_) {
      bruto = '';
    }
    codigoAparelho = bruto.isEmpty ? null : Licenca.codigoDoAparelho(bruto);
  }

  /// Confere a licenca toda vez que o app abre (logica do original).
  Future<void> _conferirLicencaNaAbertura(SharedPreferences prefs) async {
    licenciado = false;
    chaveGuardada = prefs.getString(_kChave);
    final codigo = codigoAparelho ?? '';
    final assinatura = prefs.getString(_kAssinatura) ?? '';
    final validade = prefs.getString(_kValidade) ?? 'sempre';
    if (codigo.isEmpty || assinatura.isEmpty) return;
    if (!Licenca.conferir(codigo, assinatura, validade)) return;
    // Licenca sem prazo: nunca mais precisa de internet.
    if (validade == 'sempre') {
      licenciado = true;
      return;
    }
    final fim = DateTime.tryParse(validade);
    if (fim == null) return;
    final diasQueFaltam = fim.difference(DateTime.now()).inMinutes / 1440;
    final mexeram = _relogioFoiPraTras(prefs);
    if (diasQueFaltam > Licenca.diasPraRenovarAntes && !mexeram) {
      licenciado = true;
      return;
    }
    // Perto de vencer, vencida ou relogio mexido: tenta renovar sozinho.
    if (await _renovarNoServidor(prefs)) {
      licenciado = true;
      return;
    }
    if (diasQueFaltam > 0 && !mexeram) {
      licenciado = true;
      avisoGps = 'Seu acesso vence em ${_dataPorExtenso(fim)}. Abra o aplicativo '
          'com a internet ligada pra renovar sozinho.';
      return;
    }
    erroLicenca = mexeram
        ? 'A data do celular não confere. Ligue a internet e toque em Ativar.'
        : 'Seu acesso venceu em ${_dataPorExtenso(fim)}. Ligue a internet e toque em '
            'Ativar. Se não liberar, fale com quem te vendeu o aplicativo.';
  }

  /// Relogio atrasado mais de um dia em relacao a ultima vez que o app viu.
  bool _relogioFoiPraTras(SharedPreferences prefs) {
    final vista = int.tryParse(prefs.getString(_kDataVista) ?? '') ?? 0;
    final agora = DateTime.now().millisecondsSinceEpoch;
    if (agora > vista) {
      unawaited(prefs.setString(_kDataVista, '$agora'));
      return false;
    }
    return (vista - agora) > 86400000;
  }

  Future<bool> _renovarNoServidor(SharedPreferences prefs) async {
    final chave = prefs.getString(_kChave) ?? '';
    final codigo = codigoAparelho ?? '';
    if (chave.isEmpty || codigo.isEmpty) return false;
    final resposta = await Licenca.ativarNoServidor(chave, codigo);
    if (!resposta.ok || !Licenca.conferir(codigo, resposta.assinatura, resposta.validade)) {
      return false;
    }
    await _guardarLicenca(prefs, resposta.assinatura, resposta.validade, chave);
    return true;
  }

  Future<void> _guardarLicenca(
    SharedPreferences prefs,
    String assinatura,
    String validade,
    String? chave,
  ) async {
    await prefs.setString(_kAssinatura, assinatura);
    await prefs.setString(_kValidade, validade.isEmpty ? 'sempre' : validade);
    if (chave != null && chave.isNotEmpty) {
      await prefs.setString(_kChave, chave);
      chaveGuardada = chave;
    }
    await prefs.setString(_kDataVista, '${DateTime.now().millisecondsSinceEpoch}');
  }

  static String _dataPorExtenso(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Identificador bruto e estavel do aparelho.

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
  // Licenca
  // ==================================================================
  /// Ativa com a chave curta (servidor) ou com a chave antiga comprida.
  Future<bool> ativarLicenca(String digitada) async {
    if (ativandoLicenca) return false;
    final codigo = codigoAparelho ?? '';
    if (codigo.isEmpty) {
      erroLicenca = 'Não consegui identificar este aparelho. Feche e abra o aplicativo de novo.';
      notifyListeners();
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    // Chave antiga, comprida: confere aqui mesmo, sem internet.
    final comprida = digitada.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (comprida.length >= 80) {
      if (!Licenca.conferir(codigo, comprida, 'sempre')) {
        erroLicenca = 'Essa chave não serve neste aparelho.';
        notifyListeners();
        return false;
      }
      await _guardarLicenca(prefs, comprida, 'sempre', null);
      return _liberar();
    }
    final chave = Licenca.chaveCurta(digitada);
    if (chave == null) {
      erroLicenca = 'A chave tem 16 letras e números, em quatro grupos de quatro.';
      notifyListeners();
      return false;
    }
    ativandoLicenca = true;
    erroLicenca = null;
    notifyListeners();
    final resposta = await Licenca.ativarNoServidor(chave, codigo);
    ativandoLicenca = false;
    if (!resposta.ok) {
      erroLicenca = resposta.motivo.isEmpty ? 'Não deu para ativar.' : resposta.motivo;
      notifyListeners();
      return false;
    }
    if (!Licenca.conferir(codigo, resposta.assinatura, resposta.validade)) {
      erroLicenca = 'A liberação veio errada. Fale com quem te passou a chave.';
      notifyListeners();
      return false;
    }
    await _guardarLicenca(prefs, resposta.assinatura, resposta.validade, chave);
    return _liberar();
  }

  bool _liberar() {
    erroLicenca = null;
    licenciado = true;
    notifyListeners();
    return true;
  }

  /// Apaga so a liberacao guardada. Historico e tarifa ficam; na proxima
  /// abertura o aplicativo pede a chave de novo (como no original).
  Future<void> desativarEsteAparelho() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAssinatura);
    await prefs.remove(_kValidade);
    await prefs.remove(_kChave);
    await prefs.remove('${Constantes.chaveLicenca}.ativa');
    chaveGuardada = null;
    erroLicenca = null;
    licenciado = false;
    notifyListeners();
  }

  // ==================================================================
  // Corrida
  // ==================================================================
  Future<bool> iniciarCorrida() async {
    final permissao = await _garantirPermissao();
    if (!permissao) {
      statusTexto = 'Permissao de localizacao negada';
      statusClasse = 'erro';
      notifyListeners();
      return false;
    }
    _comecarContagem();
    velocidadeAtualKmh = null;
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
    velocidadeAtualKmh = null;
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
    velocidadeAtualKmh = null;
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
    _ancora = null;
    avisoCorridaRecuperada = null;
    velocidadeAtualKmh = null;
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

  Future<void> _iniciarRastreamento() async {
    await _pararRastreamento();

    // Servico em primeiro plano: com a tela apagada o Android corta o GPS
    // de aplicativo comum e o medidor congelava — "travava e depois pulava".
    // Com o aviso fixo e a trava de processador ele segue medindo.
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Taxímetro medindo a corrida',
              notificationText: 'A cobrança continua mesmo com a tela apagada.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);

    _posicaoSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (posicao) {
        try {
          _medirPosicao(posicao);
        } catch (erro) {
          avisarFalhaNoGps(erro);
        }
      },
      onError: (Object erro) => avisarFalhaNoGps(erro),
    );
  }

  Future<void> _pararRastreamento() async {
    await _posicaoSub?.cancel();
    _posicaoSub = null;
  }

  void avisarFalhaNoGps(Object erro) {
    avisoGps = 'Deu problema ao ler a localizacao: '
        '${erro is Error ? erro.toString() : erro.toString()}. '
        'O tempo continua contando. Tire um print desta tela.';
    notifyListeners();
  }

  void _medirPosicao(Position pos) {
    velocidadeAtualKmh = pos.speed >= 0 ? pos.speed * 3.6 : null;
    ultimaPosicao = pos;
    if (!corridaAtiva || _pausadaParaPagamento) {
      notifyListeners();
      return;
    }
    if (pos.accuracy > Constantes.precisaoMaximaM) {
      _contarTempoApenas();
      notifyListeners();
      return;
    }
    final anterior = _ancora;
    if (anterior == null) {
      _ancora = pos;
      _ultimoInstanteMs = DateTime.now().millisecondsSinceEpoch;
      _recuperarDistanciaDoTempoFechado(pos);
      statusTexto = 'Corrida em andamento';
      statusClasse = 'ativo';
      notifyListeners();
      return;
    }
    final metros = _haversineMetros(
      anterior.latitude,
      anterior.longitude,
      pos.latitude,
      pos.longitude,
    );
    final agoraMs = DateTime.now().millisecondsSinceEpoch;
    final segundos = _tempoDesdeAUltimaContagem(agoraMs);
    if (segundos != null && segundos > 0) {
      final velocidadeMs = metros / segundos;
      if (velocidadeMs > Constantes.velocidadeImpossivelMs) {
        // Salto do GPS: descarta a distancia, mas o tempo passou de verdade.
        _ancora = pos;
        _medidor.soTempo(segundos);
        _recalcular();
        notifyListeners();
        return;
      }
    }
    final velocidadeKmh = pos.speed >= 0 ? pos.speed * 3.6 : null;
    final parado = velocidadeKmh != null
        ? velocidadeKmh < Constantes.velocidadeParadoKmh
        : metros < Constantes.distanciaMinimaRuidoM;
    if (parado) {
      if (segundos != null) {
        _medidor.parou(segundos);
      } else {
        _medidor.descartarTremida();
      }
      _recalcular();
      _ancora = pos;
      statusTexto = 'Parado - cobrando espera';
      statusClasse = 'espera';
      notifyListeners();
      return;
    }
    if (_medidor.andou(metros, segundos ?? 0)) {
      _ancora = pos;
      statusTexto = 'Corrida em andamento';
      statusClasse = 'ativo';
    } else {
      // Ainda nao deu distancia confiavel: mantem a ancora anterior.
      _ancora = anterior;
    }
    _recalcular();
    notifyListeners();
  }

  void _contarTempoApenas() {
    final agoraMs = DateTime.now().millisecondsSinceEpoch;
    final segundos = _tempoDesdeAUltimaContagem(agoraMs);
    if (segundos == null) return;
    _medidor.semGps(segundos);
    _recalcular();
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
      (_) {
        if (!corridaAtiva || _pausadaParaPagamento) return;
        final agoraMs = DateTime.now().millisecondsSinceEpoch;
        if (_ultimoInstanteMs != null &&
            (agoraMs - _ultimoInstanteMs!) < Constantes.janelaGpsRecenteMs) {
          return;
        }
        final segundos = _tempoDesdeAUltimaContagem(agoraMs);
        if (segundos == null) return;
        // Sem GPS recente: o tempo conta como espera (carro parado).
        _medidor.parou(segundos);
        _recalcular();
        notifyListeners();
      },
    );
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
  static double _haversineMetros(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double toRad(double g) => g * math.pi / 180;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a));
    return r * c;
  }

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
    super.dispose();
  }
}

