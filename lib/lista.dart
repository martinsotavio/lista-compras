// Lista de compras: itens, preços pagos (por loja) e produtos já conhecidos.
// [ListaCompras] é o que a tela usa; [ListaLocal] guarda no aparelho e [ListaFamilia] (lista_familia.dart)
// guarda na nuvem, dividida entre as pessoas da família.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um preço pago por unidade, numa loja, num dia.
class Preco {
  const Preco(this.valor, this.data, [this.loja]);
  final double valor;
  final DateTime data;
  final String? loja;

  Map<String, dynamic> toJson() => {'valor': valor, 'data': data.millisecondsSinceEpoch, if (loja != null) 'loja': loja};
  static Preco fromJson(Map<String, dynamic> j) => Preco(
      (j['valor'] as num).toDouble(), DateTime.fromMillisecondsSinceEpoch((j['data'] as num).toInt()), j['loja'] as String?);
}

/// Um produto que já passou pela lista (para "comprar de novo" sem consultar as bases outra vez).
class Conhecido {
  const Conhecido({required this.nome, this.codigo, this.marca, this.imagem});
  final String nome;
  final String? codigo;
  final String? marca;
  final String? imagem;

  Map<String, dynamic> toJson() =>
      {'nome': nome, if (codigo != null) 'codigo': codigo, if (marca != null) 'marca': marca, if (imagem != null) 'imagem': imagem};
  static Conhecido fromJson(Map<String, dynamic> j) => Conhecido(
      nome: j['nome'] as String, codigo: j['codigo'] as String?, marca: j['marca'] as String?, imagem: j['imagem'] as String?);
}

class Item {
  Item({
    required this.id,
    required this.nome,
    this.codigo,
    this.marca,
    this.imagem,
    this.foto,
    this.porNome,
    this.quantidade = 1,
    this.comprado = false,
    DateTime? criadoEm,
  }) : criadoEm = criadoEm ?? DateTime.now();
  final String id;
  final String nome;
  final String? codigo;
  final String? marca;

  /// Foto do produto nas bases (URL).
  final String? imagem;

  /// Foto tirada por alguém da casa (JPEG pequeno, em base64).
  final String? foto;

  /// Quem pôs na lista (na lista da família).
  final String? porNome;
  int quantidade;
  bool comprado;
  final DateTime criadoEm;

  late final Uint8List? fotoBytes = () {
    if (foto == null) return null;
    try {
      return base64Decode(foto!);
    } catch (_) {
      return null;
    }
  }();

  Map<String, dynamic> toJson() => {
        'nome': nome,
        if (codigo != null) 'codigo': codigo,
        if (marca != null) 'marca': marca,
        if (imagem != null) 'imagem': imagem,
        if (foto != null) 'foto': foto,
        if (porNome != null) 'porNome': porNome,
        'quantidade': quantidade,
        'comprado': comprado,
        'criadoEm': criadoEm.millisecondsSinceEpoch,
      };
  static Item fromJson(String id, Map<String, dynamic> j) => Item(
        id: id,
        nome: j['nome'] as String? ?? '?',
        codigo: j['codigo'] as String?,
        marca: j['marca'] as String?,
        imagem: j['imagem'] as String?,
        foto: j['foto'] as String?,
        porNome: j['porNome'] as String?,
        quantidade: (j['quantidade'] as num?)?.toInt() ?? 1,
        comprado: j['comprado'] as bool? ?? false,
        criadoEm: j['criadoEm'] is num ? DateTime.fromMillisecondsSinceEpoch((j['criadoEm'] as num).toInt()) : null,
      );
}

/// Chave do produto: o código de barras ou, sem código, o nome.
String chaveProduto(String? codigo, String nome) => codigo ?? 'nome:${nome.trim().toLowerCase()}';

/// O que a tela da lista usa. As contas (totais, menor preço, sugestões) ficam aqui; guardar é com cada lista.
abstract class ListaCompras extends ChangeNotifier {
  /// Itens, os mais novos primeiro.
  final List<Item> itens = [];
  @protected
  final Map<String, List<Preco>> precos = {};
  @protected
  final Map<String, Conhecido> conhecidos = {};
  String? ultimaLoja;
  bool carregada = false;

  /// Erro ao ler da nuvem (ex.: sem permissão), para mostrar na tela.
  String? erro;

  /// Nome que aparece no alto da lista (o da família, na lista compartilhada).
  String get titulo => 'Lista de compras';

  /// Se a lista é dividida com outras pessoas (mostra quem pediu cada item).
  bool get compartilhada => false;

  Future<void> carregar();
  Future<Item> adicionar({required String nome, String? codigo, String? marca, String? imagem, String? foto, int quantidade = 1});
  Future<void> mudarQuantidade(Item item, int delta);
  Future<void> remover(Item item);
  Future<void> devolver(Item item, int posicao);

  /// Marca como comprado (no carrinho) ou não. Com [preco], guarda o preço pago por unidade nessa [loja].
  Future<void> marcar(Item item, bool comprado, {double? preco, String? loja});
  Future<void> limparComprados();

  String chaveItem(Item i) => chaveProduto(i.codigo, i.nome);

  /// O item ainda não comprado com este produto, se já estiver na lista.
  Item? naLista(String? codigo, String nome) {
    final k = chaveProduto(codigo, nome);
    return itens.where((i) => !i.comprado && chaveItem(i) == k).firstOrNull;
  }

  Conhecido? conhecido(String codigo) => conhecidos[codigo];

  /// Produtos já usados que não estão na lista para comprar, os mais recentes primeiro.
  List<Conhecido> get sugestoes {
    final naLista = {for (final i in itens.where((i) => !i.comprado)) chaveItem(i)};
    return [
      for (final e in conhecidos.entries.toList().reversed)
        if (!naLista.contains(e.key)) e.value,
    ];
  }

  List<Preco> historico(Item item) => List.unmodifiable(precos[chaveItem(item)] ?? const <Preco>[]);
  Preco? ultimoPreco(Item item) => precos[chaveItem(item)]?.lastOrNull;
  Preco? menorPreco(Item item) {
    final h = precos[chaveItem(item)];
    if (h == null || h.isEmpty) return null;
    return h.reduce((a, b) => b.valor < a.valor ? b : a);
  }

  List<Item> get aComprar => [for (final i in itens) if (!i.comprado) i];
  List<Item> get noCarrinho => [for (final i in itens) if (i.comprado) i];

  double _total(Iterable<Item> lista) => lista.fold(0.0, (s, i) => s + (ultimoPreco(i)?.valor ?? 0) * i.quantidade);

  /// O que falta comprar, pelo último preço conhecido de cada item.
  double get totalAComprar => _total(aComprar);
  double get totalCarrinho => _total(noCarrinho);

  /// A loja digitada por último (fica no aparelho, cada pessoa tem a sua).
  @protected
  Future<void> carregarLoja() async {
    try {
      ultimaLoja = (await SharedPreferences.getInstance()).getString('ultima_loja');
    } catch (_) {}
  }

  @protected
  void guardarLoja(String? loja) {
    final l = loja?.trim();
    if (l == null || l.isEmpty) return;
    ultimaLoja = l;
    SharedPreferences.getInstance().then((p) => p.setString('ultima_loja', l)).catchError((_) => true);
  }
}

/// Lista guardada só neste aparelho (sem login).
class ListaLocal extends ListaCompras {
  static const _chave = 'lista_compras_v2';
  var _seq = 0;

  @override
  Future<void> carregar() async {
    await carregarLoja();
    try {
      final texto = (await SharedPreferences.getInstance()).getString(_chave);
      if (texto != null) {
        final j = jsonDecode(texto) as Map<String, dynamic>;
        itens
          ..clear()
          ..addAll([
            for (final i in j['itens'] as List? ?? const [])
              Item.fromJson((i as Map<String, dynamic>)['id'] as String, i),
          ]);
        precos.clear();
        (j['precos'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
          precos[k] = [for (final p in v as List) Preco.fromJson(p as Map<String, dynamic>)];
        });
        conhecidos.clear();
        (j['conhecidos'] as Map<String, dynamic>? ?? const {}).forEach((k, v) {
          conhecidos[k] = Conhecido.fromJson(v as Map<String, dynamic>);
        });
      }
    } catch (_) {
      // Dado salvo estragado ou armazenamento indisponível: começa com a lista vazia.
    }
    carregada = true;
    notifyListeners();
  }

  Future<void> _salvar() async {
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(
          _chave,
          jsonEncode({
            'itens': [for (final i in itens) {...i.toJson(), 'id': i.id}],
            'precos': {for (final e in precos.entries) e.key: [for (final p in e.value) p.toJson()]},
            'conhecidos': {for (final e in conhecidos.entries) e.key: e.value.toJson()},
          }));
    } catch (_) {}
  }

  @override
  Future<Item> adicionar(
      {required String nome, String? codigo, String? marca, String? imagem, String? foto, int quantidade = 1}) async {
    final existente = foto == null ? naLista(codigo, nome) : null;
    if (existente != null) {
      existente.quantidade += quantidade;
      await _salvar();
      return existente;
    }
    final item = Item(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      nome: nome.trim(),
      codigo: codigo,
      marca: marca,
      imagem: imagem,
      foto: foto,
      quantidade: quantidade,
    );
    itens.insert(0, item);
    if (foto == null) {
      final k = chaveItem(item);
      conhecidos.remove(k); // reinsere no fim: fica como o mais recente
      conhecidos[k] = Conhecido(nome: item.nome, codigo: codigo, marca: marca, imagem: imagem);
    }
    await _salvar();
    return item;
  }

  @override
  Future<void> mudarQuantidade(Item item, int delta) async {
    item.quantidade += delta;
    if (item.quantidade <= 0) itens.remove(item);
    await _salvar();
  }

  @override
  Future<void> remover(Item item) async {
    itens.remove(item);
    await _salvar();
  }

  @override
  Future<void> devolver(Item item, int posicao) async {
    itens.insert(posicao.clamp(0, itens.length), item);
    await _salvar();
  }

  @override
  Future<void> marcar(Item item, bool comprado, {double? preco, String? loja}) async {
    item.comprado = comprado;
    guardarLoja(loja);
    if (comprado && preco != null && preco > 0) {
      final l = loja?.trim();
      (precos[chaveItem(item)] ??= []).add(Preco(preco, DateTime.now(), l == null || l.isEmpty ? null : l));
    }
    await _salvar();
  }

  @override
  Future<void> limparComprados() async {
    itens.removeWhere((i) => i.comprado);
    await _salvar();
  }
}

/// "4,99", "R$ 1.234,50" ou "4.99" → 4.99. Vazio ou inválido → null.
double? lerPreco(String texto) {
  var t = texto.replaceAll(RegExp(r'[^\d,.]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
  final v = double.tryParse(t);
  return v != null && v > 0 ? v : null;
}

/// 1234.5 → "R$ 1.234,50".
String reais(double v) {
  final partes = v.toStringAsFixed(2).split('.');
  final inteiro = partes[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return 'R\$ $inteiro,${partes[1]}';
}
