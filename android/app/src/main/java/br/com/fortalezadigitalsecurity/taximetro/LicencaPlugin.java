package br.com.fortalezadigitalsecurity.taximetro;

import android.provider.Settings;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Devolve o identificador do aparelho (ANDROID_ID). Ele é diferente em
 * cada celular, sobrevive a desinstalar e instalar o app de novo, e só
 * muda se a pessoa resetar o telefone de fábrica. É nele que a licença
 * fica amarrada: a chave liberada num aparelho não serve em outro.
 */
@CapacitorPlugin(name = "Licenca")
public class LicencaPlugin extends Plugin {

    @PluginMethod
    public void idDoAparelho(PluginCall call) {
        String id = "";
        try {
            id = Settings.Secure.getString(getContext().getContentResolver(), Settings.Secure.ANDROID_ID);
        } catch (Exception erro) {
            id = "";
        }
        JSObject resposta = new JSObject();
        resposta.put("id", id == null ? "" : id);
        call.resolve(resposta);
    }
}
