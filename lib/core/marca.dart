/// Nome e versao do aplicativo, num lugar so (3.3.0: o Taximetro passou a se
/// chamar Prime Driver). Tela inicial, aviso fixo do GPS, tela de licenca e
/// PDFs leem daqui.
///
/// O que NAO muda com o nome: o pacote Android
/// (br.com.fortalezadigitalsecurity.taximetro), a chave de assinatura e o
/// apelido da licenca no servidor ('taximetro'). Por isso a versao nova
/// instala por cima e a licenca e o historico continuam.
library;

const String nomeDoApp = 'Prime Driver';

/// Tem que ser igual a versao do pubspec.yaml (um teste confere).
const String versaoDoApp = '3.3.0';
