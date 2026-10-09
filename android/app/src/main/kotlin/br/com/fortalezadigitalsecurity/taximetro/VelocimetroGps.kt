package br.com.fortalezadigitalsecurity.taximetro

import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/**
 * Velocimetro da tela (3.1.3): a velocidade direto do chip de GPS do
 * celular (GPS_PROVIDER), sem a suavizacao da localizacao do Google, que
 * deixava o numero da tela atrasado quando o carro acelerava.
 *
 * Serve SO para o numero de km/h na tela. A cobranca continua usando a
 * localizacao do Google, que ja e testada. Se o chip nao responder, a tela
 * volta sozinha a mostrar a velocidade antiga.
 */
class VelocimetroGps(private val contexto: Context) : EventChannel.StreamHandler {
    private var gerente: LocationManager? = null
    private var ouvinte: LocationListener? = null

    override fun onListen(argumentos: Any?, saida: EventChannel.EventSink) {
        onCancel(null)
        val lm = contexto.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (lm == null) {
            saida.error("sem_gps", "Aparelho sem servico de localizacao", null)
            return
        }
        // Os quatro metodos implementados: em Android 10 e anteriores, faltar
        // um deles derruba o aplicativo quando o GPS e ligado ou desligado.
        val novo = object : LocationListener {
            override fun onLocationChanged(local: Location) {
                if (!local.hasSpeed()) return
                val idadeMs = (SystemClock.elapsedRealtimeNanos() - local.elapsedRealtimeNanos) / 1_000_000
                // Leitura velha (guardada) nao serve para velocimetro.
                if (idadeMs > 2000) return
                saida.success(mapOf("ms" to local.speed.toDouble(), "idadeMs" to idadeMs))
            }

            @Deprecated("Chamado so em Android 10 e anteriores")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

            override fun onProviderEnabled(provider: String) {}

            override fun onProviderDisabled(provider: String) {}
        }
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, novo, Looper.getMainLooper())
            gerente = lm
            ouvinte = novo
        } catch (erro: SecurityException) {
            saida.error("permissao", erro.message, null)
        } catch (erro: Exception) {
            saida.error("gps", erro.message, null)
        }
    }

    override fun onCancel(argumentos: Any?) {
        val lm = gerente
        val o = ouvinte
        if (lm != null && o != null) {
            try {
                lm.removeUpdates(o)
            } catch (erro: Exception) {
                // Ja estava desligado.
            }
        }
        gerente = null
        ouvinte = null
    }
}
