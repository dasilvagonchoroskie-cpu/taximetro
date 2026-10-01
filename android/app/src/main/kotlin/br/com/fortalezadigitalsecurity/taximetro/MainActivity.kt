package br.com.fortalezadigitalsecurity.taximetro

import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mesmo identificador que o LicencaPlugin da versao antiga entregava.
        // Com a mesma chave de assinatura do APK, o Android devolve o mesmo
        // ANDROID_ID e o codigo do aparelho nao muda na atualizacao.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taximetro/licenca")
            .setMethodCallHandler { chamada, resultado ->
                if (chamada.method == "idDoAparelho") {
                    val id = try {
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    } catch (erro: Exception) {
                        null
                    }
                    resultado.success(id ?: "")
                } else {
                    resultado.notImplemented()
                }
            }
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
