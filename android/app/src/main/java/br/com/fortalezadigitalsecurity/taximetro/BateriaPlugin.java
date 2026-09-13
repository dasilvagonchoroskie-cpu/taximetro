package br.com.fortalezadigitalsecurity.taximetro;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Pedaço nativo pequeno: pergunta ao Android se o app está livre da
 * economia de bateria e, se não estiver, abre a caixa de confirmação
 * do próprio sistema. Sem isso o Android mata o taxímetro quando o
 * motorista sai da tela do app, e a corrida para de contar.
 */
@CapacitorPlugin(name = "Bateria")
public class BateriaPlugin extends Plugin {

    @PluginMethod
    public void estaLiberado(PluginCall call) {
        JSObject resposta = new JSObject();
        resposta.put("liberado", semRestricaoDeBateria());
        call.resolve(resposta);
    }

    @PluginMethod
    public void pedirLiberacao(PluginCall call) {
        JSObject resposta = new JSObject();

        if (semRestricaoDeBateria()) {
            resposta.put("liberado", true);
            resposta.put("abriu", false);
            call.resolve(resposta);
            return;
        }

        resposta.put("liberado", false);

        // Caminho normal: caixa de confirmação direta do Android.
        try {
            Intent pedido = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            pedido.setData(Uri.parse("package:" + getContext().getPackageName()));
            pedido.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(pedido);
            resposta.put("abriu", true);
            call.resolve(resposta);
            return;
        } catch (Exception erro) {
            // Alguns fabricantes bloqueiam o pedido direto.
        }

        // Reserva: abre a lista de economia de bateria do sistema.
        try {
            Intent lista = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
            lista.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(lista);
            resposta.put("abriu", true);
            resposta.put("pelaLista", true);
            call.resolve(resposta);
        } catch (Exception erro) {
            call.reject("Não consegui abrir a tela de bateria: " + erro.getMessage());
        }
    }

    private boolean semRestricaoDeBateria() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true;
        PowerManager energia = (PowerManager) getContext().getSystemService(Context.POWER_SERVICE);
        if (energia == null) return true;
        return energia.isIgnoringBatteryOptimizations(getContext().getPackageName());
    }
}
