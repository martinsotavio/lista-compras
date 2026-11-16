import 'package:flutter_test/flutter_test.dart';
import 'package:leitor_ean/lista.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lerPreco aceita vírgula, ponto, R\$ e milhar', () {
    expect(lerPreco('4,99'), 4.99);
    expect(lerPreco('4.99'), 4.99);
    expect(lerPreco('R\$ 1.234,50'), 1234.5);
    expect(lerPreco(''), isNull);
    expect(lerPreco('0'), isNull);
    expect(lerPreco('abc'), isNull);
  });

  test('reais formata em real', () {
    expect(reais(4.9), 'R\$ 4,90');
    expect(reais(1234.5), 'R\$ 1.234,50');
    expect(reais(0), 'R\$ 0,00');
  });

  test('ler o mesmo produto de novo soma a quantidade', () async {
    final l = ListaLocal();
    await l.carregar();
    await l.adicionar(nome: 'Café', codigo: '7891000100103');
    await l.adicionar(nome: 'Café', codigo: '7891000100103');
    await l.adicionar(nome: 'banana');
    await l.adicionar(nome: 'Banana ');
    expect(l.itens.length, 2);
    expect(l.itens.every((i) => i.quantidade == 2), isTrue);
  });

  test('preços, menor preço e totais', () async {
    final l = ListaLocal();
    await l.carregar();
    final cafe = await l.adicionar(nome: 'Café', codigo: '7891000100103', quantidade: 2);
    await l.adicionar(nome: 'Leite');
    await l.marcar(cafe, true, preco: 20, loja: 'Mercado A');
    expect(l.totalCarrinho, 40);
    expect(l.ultimaLoja, 'Mercado A');
    await l.limparComprados();

    final cafe2 = await l.adicionar(nome: 'Café', codigo: '7891000100103');
    expect(l.ultimoPreco(cafe2)!.valor, 20);
    expect(l.totalAComprar, 20); // café pelo último preço; leite sem preço conta zero
    await l.marcar(cafe2, true, preco: 18, loja: 'Mercado B');
    expect(l.menorPreco(cafe2)!.loja, 'Mercado B');
    expect(l.historico(cafe2).length, 2);
  });

  test('guarda e recarrega lista, preços e produtos conhecidos', () async {
    final a = ListaLocal();
    await a.carregar();
    final i = await a.adicionar(nome: 'Arroz', codigo: '7896006716112', marca: 'Tio João');
    await a.marcar(i, true, preco: 25.9, loja: 'Atacado');
    await a.limparComprados();

    final b = ListaLocal();
    await b.carregar();
    expect(b.itens, isEmpty);
    expect(b.ultimaLoja, 'Atacado');
    final c = b.conhecido('7896006716112');
    expect(c?.marca, 'Tio João');
    expect(b.sugestoes.map((s) => s.nome), ['Arroz']);
    final de = await b.adicionar(nome: c!.nome, codigo: c.codigo);
    expect(b.ultimoPreco(de)!.valor, 25.9);
    expect(b.sugestoes, isEmpty); // já está na lista
  });

  test('dado salvo estragado não derruba o app', () async {
    SharedPreferences.setMockInitialValues({'lista_compras_v2': '{quebrado'});
    final l = ListaLocal();
    await l.carregar();
    expect(l.carregada, isTrue);
    expect(l.itens, isEmpty);
  });
}
