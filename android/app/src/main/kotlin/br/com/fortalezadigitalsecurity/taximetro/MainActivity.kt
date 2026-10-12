package br.com.fortalezadigitalsecurity.taximetro

import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Licenca (pacote fortaleza_licenca, versao 3.2): o mesmo ANDROID_ID de
        // sempre. Com a mesma chave de assinatura do APK, o Android devolve o
        // mesmo ANDROID_ID e o codigo do aparelho nao muda na atualizacao.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fortaleza/licenca")
            .setMethodCallHandler { chamada, resultado ->
                when (chamada.method) {
                    "idDoAparelho" -> {
                        val id = try {
                            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                        } catch (erro: Exception) {
                            null
                        }
                        resultado.success(id ?: "")
                    }
                    "modelo" -> resultado.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                    else -> resultado.notImplemented()
                }
            }
        // Velocimetro da tela direto do chip de GPS (3.1.3).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "taximetro/velocimetro")
            .setStreamHandler(VelocimetroGps(applicationContext))
        // Tela acesa durante a corrida: o motorista ve o valor sem tocar.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taximetro/tela")
            .setMethodCallHandler { chamada, resultado ->
                if (chamada.method == "manterAcesa") {
                    val ligar = chamada.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (ligar) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    resultado.success(null)
                } else {
                    resultado.notImplemented()
                }
            }
    }
}
