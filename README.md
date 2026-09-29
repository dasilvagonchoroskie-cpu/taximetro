# Taxímetro — Fortaleza Digital Security

Taxímetro por GPS que calcula a corrida por **distância e tempo**, funciona
**sem internet** e é ativado por chave (servidor de licenças).

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
