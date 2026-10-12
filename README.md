# Taxímetro — Fortaleza Digital Security

Taxímetro por GPS que calcula a corrida por **distância e tempo** e funciona
**sem internet**. Só abre no celular liberado pela **Central de Licenças**.

**Versão 3.0 — Flutter (29/09/2026).** A versão antiga (Capacitor, 2.4)
está guardada na etiqueta `capacitor-2.4-final`.

## Regra de cobrança
- A bandeirada (dia R$ 10,00 · noite R$ 20,00) inclui **1,5 km rodados**
  e **5 minutos de espera**, em qualquer momento da corrida.
- Cada trecho é cobrado por **distância OU tempo, o que der mais**, como
  taxímetro de verdade (devagar vale o minuto, andando vale o km).
- A bandeirada fica congelada no início da corrida.
- A regra fica em `lib/core/tarifador.dart`, com testes em `test/`.

## Como sai o APK
A cada envio para `main`, a esteira (GitHub Actions) faz análise do código,
roda os testes da cobrança e gera o APK assinado com a **mesma chave da
versão anterior**. Por isso ele atualiza por cima e a licença do aparelho
continua valendo. O link fixo de download é o release `apk-mais-recente`.

## Licença (versão 3.2, 11/10/2026)
- Pacote `fortaleza_licenca` (repositório `fortaleza-central-licencas`,
  pasta `pacote/`), preso no commit `8d208fbadafd65a681bd81473a4b49619b041b4c`
  (licenca-v1). Apelido no servidor: `taximetro`.
- Celular novo: o motorista toca em **Pedir liberação** (nome e WhatsApp),
  aparece um código de 6 números, e o Evandro libera na Central (aba
  Pedidos). O app abre sozinho. A chave curta continua valendo.
- Quem já usava a 3.1 continua liberado: o código do aparelho é o mesmo
  (ANDROID_ID + mesma chave de assinatura) e a liberação antiga
  (`taxi.licenca.*`) vira licença nova sozinha na primeira conferência.
- Abre sem internet; com internet, renova em silêncio. Até 90 dias sem
  internet. Reinstalou: volta sozinho pelo servidor.
- `MainActivity.kt` entrega o ANDROID_ID e o modelo pelo canal
  `fortaleza/licenca`.
