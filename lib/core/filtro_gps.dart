import 'package:geolocator/geolocator.dart';

// ===================================================================
// LIMITES DO FILTRO DE RUIDO DO GPS (versao 3.2.2) — ajuste aqui
// ===================================================================

/// Leitura com margem de erro pior que esta e descartada (era 30 m).
const double precisaoMaximaM = 20;

/// Abaixo desta velocidade (~1,8 km/h) o carro esta parado: semaforo, fila,
/// espera de passageiro. A distancia nao e somada; o tempo vira espera.
const double velocidadeMinimaMs = 0.5;

/// Deslocamento que exigiria mais que isto e salto do GPS: ponto ignorado.
const double velocidadeMaximaKmh = 200;

/// Trecho minimo, em metros. A distancia so entra no odometro quando o carro
/// se afasta isto do ultimo ponto valido; ate la, a tremida do GPS nao soma.
///
/// E o "distanceFilter" aplicado no CALCULO, nao no fluxo do GPS: o fluxo
/// continua com uma leitura por segundo, porque o tempo de espera depende
/// dela. Com o filtro no fluxo, o carro devagar ficaria sem leitura, o
/// relogio cobraria esses segundos como espera e a distancia depois seria
/// cobrada de novo (cobranca dupla).
const double filtroDistanciaM = 10;

/// O fluxo do GPS (LocationSettings.distanceFilter). Fica em 0 de proposito:
/// ver [filtroDistanciaM].
const int filtroDistanciaDoFluxoM = 0;

/// Leitura com hora mais velha que isto (em relacao as outras) e posicao
/// guardada em cache, nao a de agora: descartada.
const int idadeMaximaLeituraS = 10;

/// Saltos seguidos que fazem o ponto de referencia ser refeito no lugar novo
/// (sem somar distancia): protege contra uma referencia que era ela mesma
/// um ponto ruim, que travaria o odometro.
const int saltosSeguidosParaReancorar = 3;

/// Leituras "antigas" seguidas, com hora andando normal, que indicam que o
/// relogio do celular mudou (horario de rede corrigido) e nao cache.
const int antigasSeguidasParaAceitar = 3;

// ===================================================================

/// O que fazer com uma leitura do GPS.
enum TipoLeitura {
  /// Ignorada: nada muda (nem o ponto de referencia, nem o tempo).
  descartada,

  /// Primeira leitura valida da corrida: vira o ponto de referencia.
  ancorada,

  /// Carro parado: nao soma distancia; o ponto de referencia vem para ca.
  parado,

  /// Carro andando: [AvaliacaoGps.metros] desde o ponto de referencia.
  andando,

  /// Varios saltos seguidos: a referencia foi refeita aqui, sem somar nada.
  reancorada,
}

class AvaliacaoGps {
  const AvaliacaoGps(this.tipo, {this.motivo = '', this.metros = 0});

  final TipoLeitura tipo;

  /// Por que foi descartada (para os testes e para depurar).
  final String motivo;

  /// Andando: distancia em METROS do ponto de referencia ate esta leitura.
  final double metros;
}

/// Filtro das leituras do GPS de UMA corrida. Puro: os testes simulam
/// corridas inteiras com ruido.
///
/// Mantem o ultimo ponto valido (a "ancora"). Leitura descartada nunca muda
/// a ancora. A distancia de cada trecho e medida da ancora ate a leitura,
/// em metros, com [Geolocator.distanceBetween]; a conversao para km e feita
/// so no medidor.
class FiltroGps {
  Position? _ancora;
  bool _primeiraVista = false;
  DateTime? _ultimoHorario;
  int? _menorAtrasoMs;
  int _antigasSeguidas = 0;
  int _saltosSeguidos = 0;

  /// Ultimo ponto valido (referencia do trecho aberto).
  Position? get ancora => _ancora;

  /// Nova corrida, retomada depois do pagamento ou corrida recuperada: a
  /// proxima leitura volta a ser "a primeira" (e descartada).
  void reiniciar() {
    _ancora = null;
    _primeiraVista = false;
    _ultimoHorario = null;
    _menorAtrasoMs = null;
    _antigasSeguidas = 0;
    _saltosSeguidos = 0;
  }

  /// O trecho fechou (ou o carro esta parado): a referencia vem para [pos].
  void ancorar(Position pos) {
    _ancora = pos;
    _saltosSeguidos = 0;
  }

  static double metrosEntre(Position a, Position b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  AvaliacaoGps avaliar(Position pos, int agoraMs) {
    // 5) Repetida ou fora de ordem: a mesma posicao entregue de novo.
    final horario = pos.timestamp;
    final ultimo = _ultimoHorario;
    if (ultimo != null && !horario.isAfter(ultimo)) {
      return const AvaliacaoGps(TipoLeitura.descartada, motivo: 'repetida');
    }

    // 5) Antiga (cache): o atraso da leitura comparado ao menor atraso visto
    // nesta corrida. Comparar com o menor atraso, e nao com zero, aguenta o
    // relogio do celular adiantado ou atrasado.
    final atrasoMs = agoraMs - horario.millisecondsSinceEpoch;
    final menor = _menorAtrasoMs;
    if (menor == null || atrasoMs < menor) _menorAtrasoMs = atrasoMs;
    if (atrasoMs - _menorAtrasoMs! > idadeMaximaLeituraS * 1000) {
      _antigasSeguidas++;
      if (_antigasSeguidas < antigasSeguidasParaAceitar) {
        return const AvaliacaoGps(TipoLeitura.descartada, motivo: 'antiga');
      }
      // Varias seguidas com a hora andando normal: foi o relogio do celular
      // que mudou. Esse passa a ser o atraso normal.
      _menorAtrasoMs = atrasoMs;
    }
    _antigasSeguidas = 0;
    _ultimoHorario = horario;

    // 2) Precisao ruim.
    if (pos.accuracy > precisaoMaximaM) {
      return const AvaliacaoGps(TipoLeitura.descartada, motivo: 'imprecisa');
    }

    // 5) A primeira posicao da corrida costuma ser a ultima guardada.
    if (!_primeiraVista) {
      _primeiraVista = true;
      return const AvaliacaoGps(TipoLeitura.descartada, motivo: 'primeira');
    }

    final anterior = _ancora;
    if (anterior == null) {
      ancorar(pos);
      return const AvaliacaoGps(TipoLeitura.ancorada);
    }

    // 6) Distancia em metros, da ancora ate aqui.
    final metros = metrosEntre(anterior, pos);

    // 4) Salto impossivel. O tempo e o desde a ANCORA (pela hora do GPS):
    // assim um trecho longo sem leitura boa nao parece salto.
    final segundos = horario.difference(anterior.timestamp).inMilliseconds / 1000;
    if (segundos > 0 && metros / segundos > velocidadeMaximaKmh / 3.6) {
      _saltosSeguidos++;
      if (_saltosSeguidos >= saltosSeguidosParaReancorar) {
        ancorar(pos);
        return const AvaliacaoGps(TipoLeitura.reancorada, motivo: 'saltos seguidos');
      }
      return const AvaliacaoGps(TipoLeitura.descartada, motivo: 'salto');
    }
    _saltosSeguidos = 0;

    // 3) Parado: velocidade do proprio GPS; sem ela, a media desde a ancora.
    final velocidade = pos.speed >= 0 ? pos.speed : (segundos > 0 ? metros / segundos : 0.0);
    if (velocidade < velocidadeMinimaMs) {
      return const AvaliacaoGps(TipoLeitura.parado);
    }
    return AvaliacaoGps(TipoLeitura.andando, metros: metros);
  }
}
