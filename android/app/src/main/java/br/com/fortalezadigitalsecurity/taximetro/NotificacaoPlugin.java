package br.com.fortalezadigitalsecurity.taximetro;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * Mostra a corrida em andamento na barra de notificacoes, com valor,
 * distancia e tempo ao vivo.
 *
 * Serve pra duas coisas:
 *  1) o motorista ve a contagem andando mesmo com o Waze na frente;
 *  2) uma notificacao em andamento segura a prioridade do aplicativo no
 *     Android, que e o que evita o sistema congelar a contagem.
 *
 * Canal com IMPORTANCE_LOW: nao toca som, nao vibra, nao pula na tela.
 */
@CapacitorPlugin(name = "NotificacaoCorrida")
public class NotificacaoPlugin extends Plugin {

    private static final String CANAL = "corrida_em_andamento";
    private static final int ID_NOTIFICACAO = 7321;
    private static final String PERMISSAO_NOTIFICAR = "android.permission.POST_NOTIFICATIONS";

    private void criarCanal() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager gerente =
                (NotificationManager) getContext().getSystemService(Context.NOTIFICATION_SERVICE);
        if (gerente == null) return;
        if (gerente.getNotificationChannel(CANAL) != null) return;

        NotificationChannel canal = new NotificationChannel(
                CANAL, "Corrida em andamento", NotificationManager.IMPORTANCE_LOW);
        canal.setDescription("Mostra valor, distancia e tempo enquanto a corrida esta aberta.");
        canal.setShowBadge(false);
        canal.enableVibration(false);
        canal.setSound(null, null);
        gerente.createNotificationChannel(canal);
    }

    private boolean podeNotificar() {
        try {
            return NotificationManagerCompat.from(getContext()).areNotificationsEnabled();
        } catch (Exception e) {
            return false;
        }
    }

    @PluginMethod
    public void pedirPermissao(PluginCall chamada) {
        try {
            if (Build.VERSION.SDK_INT >= 33
                    && ContextCompat.checkSelfPermission(getContext(), PERMISSAO_NOTIFICAR)
                       != PackageManager.PERMISSION_GRANTED
                    && getActivity() != null) {
                ActivityCompat.requestPermissions(
                        getActivity(), new String[]{ PERMISSAO_NOTIFICAR }, 9911);
            }
        } catch (Exception e) {
            // se nao der, o proprio podeNotificar() abaixo entrega false
        }
        JSObject resposta = new JSObject();
        resposta.put("permitido", podeNotificar());
        chamada.resolve(resposta);
    }

    @PluginMethod
    public void mostrar(PluginCall chamada) {
        String titulo = chamada.getString("titulo", "Corrida em andamento");
        String texto = chamada.getString("texto", "");
        JSObject resposta = new JSObject();

        try {
            criarCanal();

            Intent abrirApp = getContext().getPackageManager()
                    .getLaunchIntentForPackage(getContext().getPackageName());
            int marcas = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                marcas |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent aoTocar = PendingIntent.getActivity(getContext(), 0, abrirApp, marcas);

            NotificationCompat.Builder construtor =
                    new NotificationCompat.Builder(getContext(), CANAL)
                            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                            .setContentTitle(titulo)
                            .setContentText(texto)
                            .setOngoing(true)          // nao da pra arrastar pra fora
                            .setOnlyAlertOnce(true)    // atualiza calado
                            .setShowWhen(false)
                            .setPriority(NotificationCompat.PRIORITY_LOW)
                            .setCategory(NotificationCompat.CATEGORY_SERVICE)
                            .setContentIntent(aoTocar);

            NotificationManagerCompat.from(getContext()).notify(ID_NOTIFICACAO, construtor.build());
            resposta.put("ok", true);
        } catch (Exception e) {
            resposta.put("ok", false);
            resposta.put("motivo", String.valueOf(e.getMessage()));
        }
        resposta.put("permitido", podeNotificar());
        chamada.resolve(resposta);
    }

    @PluginMethod
    public void esconder(PluginCall chamada) {
        try {
            NotificationManagerCompat.from(getContext()).cancel(ID_NOTIFICACAO);
        } catch (Exception e) {
            // nada a fazer: se nao existe, ja esta escondida
        }
        chamada.resolve();
    }
}
