package br.com.fortalezadigitalsecurity.taximetro;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // O registro tem que vir ANTES do super.onCreate.
        registerPlugin(BateriaPlugin.class);
        registerPlugin(LicencaPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
