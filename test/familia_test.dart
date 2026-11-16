import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leitor_ean/conta.dart';
import 'package:leitor_ean/lista_familia.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Espera os snapshots do Firestore falso chegarem.
Future<void> assentar() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('códigos de convite: 8 caracteres sem ambíguos, aceita com hífen e minúsculas', () {
    final c = gerarCodigo();
    expect(c.length, 8);
    expect(normalizarConvite(c), c);
    expect(normalizarConvite('abcd-2345'), 'ABCD2345');
    expect(normalizarConvite('ABCD0123'), isNull, reason: '0 e 1 não existem no alfabeto');
    expect(normalizarConvite('ABC'), isNull);
    expect(mostrarCodigo('ABCD2345'), 'ABCD-2345');
  });

  test('duas pessoas da família veem a mesma lista ao vivo', () async {
    final db = FakeFirebaseFirestore();
    final ana = ListaFamilia(db, 'f1', nomeFamilia: 'Casa', meuNome: 'Ana')..carregar();
    final beto = ListaFamilia(db, 'f1', nomeFamilia: 'Casa', meuNome: 'Beto')..carregar();
    await assentar();
    expect(ana.carregada, isTrue);

    await ana.adicionar(nome: 'Iogurte', foto: 'AAAA'); // com foto: sempre item novo
    await ana.adicionar(nome: 'Café', codigo: '7891000100103');
    await assentar();
    expect(beto.itens.map((i) => i.nome), containsAll(['Iogurte', 'Café']));
    expect(beto.itens.firstWhere((i) => i.nome == 'Iogurte').porNome, 'Ana');

    // Beto lê o mesmo café: soma, não duplica.
    await beto.adicionar(nome: 'Café', codigo: '7891000100103');
    await assentar();
    expect(ana.itens.where((i) => i.nome == 'Café').single.quantidade, 2);

    // Beto compra no mercado; Ana vê o preço.
    final cafe = beto.itens.firstWhere((i) => i.nome == 'Café');
    await beto.marcar(cafe, true, preco: 19.9, loja: 'Mercado');
    await assentar();
    final cafeAna = ana.itens.firstWhere((i) => i.nome == 'Café');
    expect(cafeAna.comprado, isTrue);
    expect(ana.ultimoPreco(cafeAna)!.loja, 'Mercado');
    expect(ana.totalCarrinho, closeTo(39.8, 0.001));

    await ana.limparComprados();
    await assentar();
    expect(beto.itens.map((i) => i.nome), ['Iogurte']);
    expect(beto.sugestoes.map((s) => s.nome), ['Café'], reason: 'o café vira sugestão de "comprar de novo"');

    ana.dispose();
    beto.dispose();
  });

  test('criar família, convidar por e-mail e entrar com o código', () async {
    final db = FakeFirebaseFirestore();
    final authAna = MockFirebaseAuth(mockUser: MockUser(uid: 'ana', email: 'ana@ex.com', displayName: 'Ana'), signedIn: true);
    final ana = Conta(authAna, db);
    final fid = await ana.criarFamilia('Casa');
    final familia = (await ana.minhasFamilias().first).single;
    expect(familia.id, fid);
    expect(familia.nomes, {'ana': 'Ana'});

    final codigo = await ana.convidarPorEmail(familia, 'Beto@Ex.com');

    final authBeto = MockFirebaseAuth(mockUser: MockUser(uid: 'beto', email: 'beto@ex.com', displayName: 'Beto'), signedIn: true);
    final beto = Conta(authBeto, db);
    final convites = await beto.convitesParaMim({}).first;
    expect(convites.single.familiaNome, 'Casa');
    expect(convites.single.porNome, 'Ana');

    expect(await beto.entrarComCodigo(mostrarCodigo(codigo).toLowerCase()), fid);
    expect((await beto.minhasFamilias().first).single.nomes, {'ana': 'Ana', 'beto': 'Beto'});
    expect(await beto.convitesParaMim({}).first, isEmpty, reason: 'convite por e-mail é de uso único');

    // O código fixo da família continua valendo para outra pessoa.
    final authCaio = MockFirebaseAuth(mockUser: MockUser(uid: 'caio', email: 'caio@ex.com', displayName: 'Caio'), signedIn: true);
    expect(await Conta(authCaio, db).entrarComCodigo(familia.codigo), fid);

    await beto.sairDaFamilia(familia);
    expect(await beto.minhasFamilias().first, isEmpty);
  });

  test('código errado dá mensagem clara', () async {
    final conta = Conta(MockFirebaseAuth(mockUser: MockUser(uid: 'x'), signedIn: true), FakeFirebaseFirestore());
    expect(() => conta.entrarComCodigo('ABCD2345'),
        throwsA(isA<ErroConta>().having((e) => e.mensagem, 'mensagem', contains('não encontrado'))));
    expect(() => conta.entrarComCodigo('12'), throwsA(isA<ErroConta>()));
  });
}
