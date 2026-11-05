import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taximetro/core/marca.dart';

/// 3.3.0 — o Taximetro passou a se chamar Prime Driver, com icone novo.
void main() {
  test('a versao do app e a mesma do pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versao = RegExp(r'^version:\s*([\d.]+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(versaoDoApp, versao);
  });

  test('nome Prime Driver no Android, com icone adaptativo e redondo', () {
    expect(nomeDoApp, 'Prime Driver');
    final manifesto = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifesto, contains('android:label="$nomeDoApp"'));
    expect(manifesto, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifesto, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    for (final nome in ['ic_launcher', 'ic_launcher_round']) {
      final xml = File('android/app/src/main/res/mipmap-anydpi-v26/$nome.xml').readAsStringSync();
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
    }
  });

  test('todos os tamanhos do icone, da abertura e da coroa do aviso do GPS existem', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final f in ['ic_launcher', 'ic_launcher_round', 'ic_launcher_foreground']) {
        expect(File('android/app/src/main/res/mipmap-$d/$f.png').existsSync(), isTrue, reason: '$d/$f');
      }
      for (final f in ['ic_notificacao', 'logo_abertura']) {
        expect(File('android/app/src/main/res/drawable-$d/$f.png').existsSync(), isTrue, reason: '$d/$f');
      }
    }
  });

  test('o pacote Android e a licenca continuam os mesmos (instala por cima)', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "br.com.fortalezadigitalsecurity.taximetro"'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("appId: 'taximetro'"));
  });
}
