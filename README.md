# Lista de compras

App de celular (Android e iPhone), feito em **Flutter / Dart**, para a lista de compras da casa, dividida com a família.

Acabou alguma coisa? Leia o código de barras, tire uma foto ou digite o nome. A lista se atualiza na hora no
celular de todo mundo da família, e quem for ao mercado já sabe o que comprar.

> Começou como o leitor de EAN-13 de um exemplo da disciplina. Ficou dele a leitura pela câmera e a consulta do
> produto nas bases públicas. Em cima disso vieram a lista, o login, as famílias e o histórico de preços.

## O que faz

- **Ler o código de barras** (EAN-13, EAN-8, UPC-A, UPC-E) pela câmera, só dentro da moldura da tela. O app confere o
  dígito verificador e busca o produto no [Open Food Facts](https://world.openfoodfacts.org), no
  [Open Products Facts](https://world.openproductsfacts.org) e no [UPCitemdb](https://www.upcitemdb.com), nessa
  ordem. O item entra na lista com nome, marca e foto. Ler o mesmo produto de novo soma a quantidade.
- **Foto do que acabou:** para o que não tem código (fruta, pão, um pote sem rótulo), basta tirar a foto e dar um nome.
- **Digitar** um código ou um nome (ex.: "Banana").
- **Comprar de novo:** os produtos já usados aparecem como sugestão, sem precisar consultar a internet outra vez.
- **Carrinho e preços:** ao marcar um item, informe o preço e a loja (os dois são opcionais). O app mostra o
  último preço, o menor preço já pago (e onde), o total estimado do que falta e o total no carrinho.
- **Quem pediu:** cada item mostra quem da família o pôs na lista.
- **Consultar:** a segunda aba mostra todos os dados de um produto (ingredientes, Nutri-Score, países…) sem pôr na lista.

### Conta e família

- Login com **e-mail e senha**, com "Esqueci a senha".
- Ao criar a conta, você ganha uma família ("Casa de Fulano"). Dá para criar outras famílias, trocar entre elas,
  mudar o nome ou sair.
- **Convidar** de duas formas:
  - **Código da família**, como `ABCD-2345`. A pessoa toca em *Entrar com código*. O botão *Copiar convite*
    gera a mensagem pronta para mandar no WhatsApp.
  - **Por e-mail:** o app abre o seu e-mail com o convite pronto. Quando a pessoa cria a conta com aquele
    e-mail, o convite já aparece para ela. Esse código vale uma vez só.
- Sem internet, a lista continua funcionando e sincroniza quando a conexão voltar.

## Como funciona

| Parte | Com o quê |
|---|---|
| App | Flutter (Dart), Material 3, tema claro e escuro |
| Leitura do código | [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) (ML Kit no Android, Vision no iOS) |
| Dados do produto | Open Food Facts → Open Products Facts → UPCitemdb, direto do celular |
| Login | Firebase Authentication (e-mail e senha) |
| Lista da família, ao vivo | Cloud Firestore, com cache offline |
| Fotos do que acabou | JPEG reduzido (até 640 px, uns 50 KB) dentro do próprio item no Firestore |
| Segurança | [`firestore.rules`](firestore.rules): só os membros leem e escrevem a lista da família |

Tudo cabe no **plano grátis (Spark)** do Firebase. As fotos não usam o Firebase Storage porque, desde 2024, ele
exige o plano pago. Por isso o convite também não é enviado pelo servidor: quem manda é você, pelo seu e-mail.

```
lib/
  main.dart            início do app, abas (Lista | Consultar), tela de consulta e câmera
  tela_lista.dart      a lista: ler, foto, digitar, carrinho, preços, totais
  lista.dart           regras da lista (totais, menor preço, sugestões) e a versão local, sem login
  lista_familia.dart   a lista da família no Firestore, atualizada ao vivo
  conta.dart           login, famílias, códigos e convites
  tela_conta.dart      telas de login, família e convites
  consulta.dart        bases de produtos e dígito verificador
  moldura.dart         a moldura de leitura na câmera
  firebase_options.dart  gerado pelo `flutterfire configure` (veja abaixo)
firestore.rules        regras de segurança do Firestore
test/                  testes (lista, família e convites com Firestore falso, telas)
```

Sem o Firebase configurado, o app abre **sem login**, com a lista guardada só no aparelho. Isso ajuda a testar as
telas antes de criar o projeto no Firebase.

## Rodando

Pré-requisitos: [Flutter](https://docs.flutter.dev/get-started/install) 3.32 ou mais novo e o Android Studio (Android
SDK). O app do iPhone só compila num Mac, com o Xcode.

```bash
flutter pub get
flutter test                 # roda os testes
flutter run                  # com o celular ligado no USB (depuração USB ativa)
flutter build apk --release  # gera build/app/outputs/flutter-apk/app-release.apk
```

### Configurar o Firebase (uma vez)

1. No [console do Firebase](https://console.firebase.google.com), crie um projeto.
2. Em **Authentication › Método de login**, ative **E-mail/senha**.
3. Em **Firestore Database**, crie o banco (modo produção). Em **Regras**, cole o conteúdo de
   [`firestore.rules`](firestore.rules) e clique em Publicar.
4. No computador:

   ```bash
   npm install -g firebase-tools && firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=android,ios
   ```

   O comando escreve `lib/firebase_options.dart` e `android/app/google-services.json` com os dados do seu projeto.
   O ID do app é `io.github.martinsotavio.listacompras`.

As chaves do `firebase_options.dart` não são senhas: elas só dizem qual projeto usar, e quem protege os dados são as
regras do Firestore. Mesmo assim, vale
[restringir a chave](https://firebase.google.com/docs/projects/api-keys) ao app Android/iOS no Google Cloud.

## Limites conhecidos

- O UPCitemdb gratuito aceita 100 consultas por dia por IP. As outras duas bases não têm esse limite.
- Uma foto fica com uns 50 KB, e um item pode ter até 1 MB no Firestore, então cabe com folga.
- Quem é da família pode tirar outra pessoa (a regra confia nos membros). Para uma casa, isso basta.

## Próximos passos

- Notificação no celular quando alguém põe um item na lista (Firebase Cloud Messaging).
- Leitura contínua: ler vários produtos seguidos sem fechar a câmera.
- Comparar preços entre famílias, por loja e por região.
- Ler a nota fiscal (QR Code da NFC-e) para lançar todos os preços de uma vez.
