// Lista da família na nuvem (Cloud Firestore). Cada item é um documento, então duas pessoas mexendo ao mesmo
// tempo não se atrapalham; a lista se atualiza sozinha nos aparelhos de todos. Sem internet, o Firestore guarda
// as mudanças no aparelho e envia quando voltar.
//
//   familias/{id}/itens/{item}        nome, codigo, marca, imagem, foto, quantidade, comprado, porNome, criadoEm
//   familias/{id}/precos/{preco}      chave, valor, loja, data, porNome
//   familias/{id}/conhecidos/{chave}  chave, nome, codigo, marca, imagem, usadoEm

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'lista.dart';

class ListaFamilia extends ListaCompras {
  ListaFamilia(this._db, this.familiaId, {required this.nomeFamilia, required this.meuNome});
  final FirebaseFirestore _db;
  final String familiaId;
  final String nomeFamilia;
  final String meuNome;
  final _assinaturas = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  @override
  String get titulo => nomeFamilia;

  @override
  bool get compartilhada => true;

  DocumentReference<Map<String, dynamic>> get _familia => _db.collection('familias').doc(familiaId);
  CollectionReference<Map<String, dynamic>> get _itens => _familia.collection('itens');
  CollectionReference<Map<String, dynamic>> get _precos => _familia.collection('precos');
  CollectionReference<Map<String, dynamic>> get _conhecidos => _familia.collection('conhecidos');

  /// O id de documento não pode ter "/".
  static String _idDaChave(String chave) => chave.replaceAll('/', '_');

  @override
  Future<void> carregar() async {
    await carregarLoja();
    final faltam = {'itens', 'precos', 'conhecidos'};
    void chegou(String qual) {
      faltam.remove(qual);
      carregada = faltam.isEmpty;
      notifyListeners();
    }

    void falhou(Object e) {
      erro = 'Não consegui ler a lista da família ($e).';
      carregada = true;
      notifyListeners();
    }

    _assinaturas.add(_itens.snapshots().listen((s) {
      itens
        ..clear()
        ..addAll([for (final d in s.docs) Item.fromJson(d.id, d.data())])
        ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      erro = null;
      chegou('itens');
    }, onError: falhou));

    _assinaturas.add(_precos.snapshots().listen((s) {
      precos.clear();
      final todos = [
        for (final d in s.docs)
          if (d.data()['chave'] is String && d.data()['valor'] is num) (d.data()['chave'] as String, Preco.fromJson(d.data())),
      ]..sort((a, b) => a.$2.data.compareTo(b.$2.data));
      for (final (k, p) in todos) {
        (precos[k] ??= []).add(p);
      }
      chegou('precos');
    }, onError: falhou));

    _assinaturas.add(_conhecidos.snapshots().listen((s) {
      final docs = [for (final d in s.docs) if (d.data()['chave'] is String && d.data()['nome'] is String) d.data()]
        ..sort((a, b) => ((a['usadoEm'] as num?) ?? 0).compareTo((b['usadoEm'] as num?) ?? 0));
      conhecidos
        ..clear()
        ..addAll({for (final d in docs) d['chave'] as String: Conhecido.fromJson(d)});
      chegou('conhecidos');
    }, onError: falhou));
  }

  /// Envia sem esperar o servidor (offline, a mudança fica na fila do Firestore). Se o servidor recusar,
  /// mostra o erro na tela.
  void _enviar(Future<void> f) => unawaited(f.catchError((Object e) {
        erro = 'Não consegui salvar na lista da família ($e).';
        notifyListeners();
      }));

  @override
  void dispose() {
    for (final a in _assinaturas) {
      a.cancel();
    }
    super.dispose();
  }

  @override
  Future<Item> adicionar(
      {required String nome, String? codigo, String? marca, String? imagem, String? foto, int quantidade = 1}) async {
    final existente = foto == null ? naLista(codigo, nome) : null;
    if (existente != null) {
      // increment: se duas pessoas lerem o mesmo produto ao mesmo tempo, as duas somam.
      _enviar(_itens.doc(existente.id).update({'quantidade': FieldValue.increment(quantidade)}));
      existente.quantidade += quantidade; // a tela já mostra; o Firestore confirma em seguida
      return existente;
    }
    final doc = _itens.doc();
    final item = Item(
      id: doc.id,
      nome: nome.trim(),
      codigo: codigo,
      marca: marca,
      imagem: imagem,
      foto: foto,
      porNome: meuNome,
      quantidade: quantidade,
    );
    // Sem await: offline, o Firestore só completa ao falar com o servidor, mas já mostra na hora.
    _enviar(doc.set(item.toJson()));
    if (foto == null) {
      final chave = chaveItem(item);
      _enviar(_conhecidos.doc(_idDaChave(chave)).set({
        'chave': chave,
        ...Conhecido(nome: item.nome, codigo: codigo, marca: marca, imagem: imagem).toJson(),
        'usadoEm': DateTime.now().millisecondsSinceEpoch,
      }));
    }
    return item;
  }

  @override
  Future<void> mudarQuantidade(Item item, int delta) async {
    if (item.quantidade + delta <= 0) return remover(item);
    _enviar(_itens.doc(item.id).update({'quantidade': FieldValue.increment(delta)}));
  }

  @override
  Future<void> remover(Item item) async => _enviar(_itens.doc(item.id).delete());

  @override
  Future<void> devolver(Item item, int posicao) async => _enviar(_itens.doc(item.id).set(item.toJson()));

  @override
  Future<void> marcar(Item item, bool comprado, {double? preco, String? loja}) async {
    guardarLoja(loja);
    final batch = _db.batch();
    batch.update(_itens.doc(item.id), {'comprado': comprado, 'compradoPor': comprado ? meuNome : null});
    if (comprado && preco != null && preco > 0) {
      final l = loja?.trim();
      batch.set(_precos.doc(), {
        'chave': chaveItem(item),
        ...Preco(preco, DateTime.now(), l == null || l.isEmpty ? null : l).toJson(),
        'porNome': meuNome,
      });
    }
    _enviar(batch.commit());
  }

  @override
  Future<void> limparComprados() async {
    final batch = _db.batch();
    for (final i in noCarrinho) {
      batch.delete(_itens.doc(i.id));
    }
    _enviar(batch.commit());
  }
}
