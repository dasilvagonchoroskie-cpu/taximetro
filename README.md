# Taxímetro — Fortaleza Digital Security

Versão 3, em **Flutter**. Substitui a versão web (Capacitor), que fica
guardada no ramo `legado-capacitor` e na etiqueta `capacitor-v2.4`.

## Cobrança
- Bandeirada (R$ 10,00 de dia, R$ 20,00 de noite), congelada no início da corrida.
- A bandeirada inclui **1,5 km rodados** e **5 minutos de espera**, em qualquer
  momento da corrida. O que passar de cada um é cobrado.
- Cada trecho é cobrado por distância **ou** por tempo, o que der mais, como
  taxímetro de verdade. Andar muito devagar conta como espera.
- A regra fica isolada em `lib/core/tarifador.dart`, com testes em `test/`.

## Licença
- Chave curta conferida no servidor de licenças. O servidor devolve uma
  liberação assinada (ECDSA P-256), conferida no app com a chave pública.
- O código do aparelho é o mesmo da versão antiga (ANDROID_ID, mesma conta):
  a chave que o cliente já tem continua valendo.
- O app renova sozinho 5 dias antes de vencer e percebe relógio atrasado.

## APK
- Sai sozinho a cada atualização do ramo `main`: análise, testes, assinatura
  e publicação em **Releases → apk-mais-recente**.
- Assinado com a **mesma chave** da versão antiga (segredos
  `TAXIMETRO_KEYSTORE_BASE64` e `TAXIMETRO_KEYSTORE_SENHA`): instala por cima.
