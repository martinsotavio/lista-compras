// Consulta do produto pelo código de barras
//   1. Open Food Facts      — bebidas e comidas;
//   2. Open Products Facts  — o mesmo sistema, para o que não é comida;
//   3. UPCitemdb (gratuito) — o resto (100 consultas por dia por IP).
// Os dois "Facts" pedem um User-Agent que identifique o app.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// As bases pedem um contato no User-Agent; vai a página do projeto (sem e-mail de ninguém).
const userAgent = 'ListaCompras/0.3 (https://github.com/martinsotavio/lista-compras)';

class Produto {
  const Produto({
    required this.codigo,
    required this.nome,
    required this.fonte,
    this.marca,
    this.quantidade,
    this.categorias,
    this.imagem,
    this.paises,
    this.ingredientes,
    this.nutriscore,
    this.link,
  });
  final String codigo;
  final String nome;
  final String fonte; 
  final String? marca;
  final String? quantidade;
  final String? categorias;
  final String? imagem;
  final String? paises;
  final String? ingredientes;
  final String? nutriscore;
  final String? link;
}


String? normalizarCodigo(String v) {
  final d = v.replaceAll(RegExp(r'\D'), '');
  return d.length >= 8 && d.length <= 14 ? d : null;
}


bool gtinValido(String codigo) {
  if (!RegExp(r'^\d{8,14}$').hasMatch(codigo)) return false;
  final ds = codigo.split('').map(int.parse).toList();
  final dv = ds.removeLast();
  var soma = 0;
  for (var k = 0; k < ds.length; k++) {
    soma += ds[ds.length - 1 - k] * (k.isEven ? 3 : 1);
  }
  return (10 - soma % 10) % 10 == dv;
}

String? _texto(Object? v, [int max = 400]) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t.length > max ? '${t.substring(0, max)}…' : t;
}


Produto? produtoDosFacts(Map<String, dynamic> j, String codigo, String fonte, String site) {
  final p = j['product'];
  if (j['status'] != 1 || p is! Map) return null;
  final nome = _texto(p['product_name_pt']) ?? _texto(p['product_name']) ?? _texto(p['product_name_es']) ?? _texto(p['product_name_en']);
  if (nome == null) return null;
  final marcas = _texto(p['brands']);
  return Produto(
    codigo: codigo,
    nome: nome,
    fonte: fonte,
    marca: marcas?.split(',').first.trim(),
    quantidade: _texto(p['quantity']),
    categorias: _texto(p['categories']),
    imagem: _texto(p['image_front_url']) ?? _texto(p['image_front_small_url']) ?? _texto(p['image_url']),
    paises: _texto(p['countries']),
    ingredientes: _texto(p['ingredients_text_pt']) ?? _texto(p['ingredients_text']),
    nutriscore: _texto(p['nutriscore_grade'])?.toUpperCase(),
    link: 'https://$site/product/$codigo',
  );
}


Produto? produtoDoUpcItemDb(Map<String, dynamic> j, String codigo) {
  final itens = j['items'];
  if (itens is! List || itens.isEmpty || itens.first is! Map) return null;
  final item = itens.first as Map;
  final nome = _texto(item['title']);
  if (nome == null) return null;
  final imagens = item['images'];
  return Produto(
    codigo: codigo,
    nome: nome,
    fonte: 'UPCitemdb',
    marca: _texto(item['brand']),
    quantidade: _texto(item['size']),
    categorias: _texto(item['category']),
    imagem: imagens is List && imagens.isNotEmpty ? _texto(imagens.first) : null,
    ingredientes: _texto(item['description']),
  );
}

class Consulta {
  Consulta({http.Client? cliente}) : _http = cliente ?? http.Client();
  final http.Client _http;
  static const _limite = Duration(seconds: 8);

  Future<Map<String, dynamic>?> _json(String url, Map<String, String> cabecalhos) async {
    try {
      final r = await _http.get(Uri.parse(url), headers: cabecalhos).timeout(_limite);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    } on http.ClientException {
      return null;
    }
  }

  Future<Produto?> _facts(String site, String fonte, String codigo) async {
    const campos = 'product_name,product_name_pt,product_name_es,product_name_en,brands,quantity,categories,'
        'image_front_url,image_front_small_url,image_url,countries,ingredients_text_pt,ingredients_text,nutriscore_grade';
    final j = await _json('https://$site/api/v2/product/$codigo.json?fields=$campos', {'User-Agent': userAgent});
    return j == null ? null : produtoDosFacts(j, codigo, fonte, site);
  }

  Future<Produto?> _upc(String codigo) async {
    final j = await _json('https://api.upcitemdb.com/prod/trial/lookup?upc=$codigo',
        {'Accept': 'application/json', 'User-Agent': userAgent});
    return j == null ? null : produtoDoUpcItemDb(j, codigo);
  }

  
  Future<Produto?> buscar(String codigo) async =>
      await _facts('world.openfoodfacts.org', 'Open Food Facts', codigo) ??
      await _facts('world.openproductsfacts.org', 'Open Products Facts', codigo) ??
      await _upc(codigo);
}
