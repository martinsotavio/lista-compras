// Conta (Firebase Auth, e-mail e senha) e famílias (Cloud Firestore).
//
//   familias/{id}       nome, dono, codigo, membros: [uid], nomes: {uid: nome}, entrouCom
//   convites/{CODIGO}   familiaId, familiaNome, criadoPor, porNome, email (só no convite por e-mail), criadoEm
//
// Cada família tem um código fixo (o "convite aberto", sem e-mail). O convite por e-mail gera outro código,
// ligado ao e-mail: quando essa pessoa entra no app com esse e-mail, o convite já aparece para ela.
// Quem entra numa família grava `entrouCom` = código, e a regra do Firestore (firestore.rules) confere que o
// código é mesmo dessa família.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Familia {
  const Familia({required this.id, required this.nome, required this.dono, required this.codigo, required this.nomes});
  final String id;
  final String nome;
  final String dono;
  final String codigo;

  /// uid → nome de cada pessoa da família.
  final Map<String, String> nomes;

  static Familia fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return Familia(
      id: d.id,
      nome: j['nome'] as String? ?? 'Família',
      dono: j['dono'] as String? ?? '',
      codigo: j['codigo'] as String? ?? '',
      nomes: {for (final e in (j['nomes'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
    );
  }
}

class Convite {
  const Convite({required this.codigo, required this.familiaId, required this.familiaNome, this.porNome});
  final String codigo;
  final String familiaId;
  final String familiaNome;
  final String? porNome;

  static Convite fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return Convite(
      codigo: d.id,
      familiaId: j['familiaId'] as String? ?? '',
      familiaNome: j['familiaNome'] as String? ?? 'Família',
      porNome: j['porNome'] as String?,
    );
  }
}

/// Erro com mensagem pronta para mostrar.
class ErroConta implements Exception {
  const ErroConta(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Sem letras e números que se confundem (O/0, I/1/L).
const _alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String gerarCodigo([Random? r]) {
  final g = r ?? Random.secure();
  return List.generate(8, (_) => _alfabeto[g.nextInt(_alfabeto.length)]).join();
}

/// "abcd-2345 " → "ABCD2345"; null se não tem cara de código.
String? normalizarConvite(String texto) {
  final t = texto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return t.length == 8 && t.split('').every(_alfabeto.contains) ? t : null;
}

/// "ABCD2345" → "ABCD-2345".
String mostrarCodigo(String c) => c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;

String mensagemDoErro(FirebaseAuthException e) => switch (e.code) {
      'invalid-email' => 'E-mail inválido.',
      'user-disabled' => 'Esta conta foi desativada.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' => 'E-mail ou senha errados.',
      'email-already-in-use' => 'Já existe uma conta com este e-mail. Entre com a senha, ou use "Esqueci a senha".',
      'weak-password' => 'Senha fraca: use pelo menos 6 caracteres.',
      'too-many-requests' => 'Muitas tentativas. Espere um pouco e tente de novo.',
      'network-request-failed' => 'Sem internet. Confira a conexão.',
      _ => 'Não deu certo (${e.code}).',
    };

class Conta {
  Conta(this.auth, this.db);
  final FirebaseAuth auth;
  final FirebaseFirestore db;

  User? get usuario => auth.currentUser;
  String get meuNome => usuario?.displayName?.trim().isNotEmpty == true
      ? usuario!.displayName!.trim()
      : (usuario?.email?.split('@').first ?? 'Alguém');

  CollectionReference<Map<String, dynamic>> get _familias => db.collection('familias');
  CollectionReference<Map<String, dynamic>> get _convites => db.collection('convites');

  Future<T> _auth<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FirebaseAuthException catch (e) {
      throw ErroConta(mensagemDoErro(e));
    }
  }

  Future<void> entrar(String email, String senha) =>
      _auth(() => auth.signInWithEmailAndPassword(email: email.trim(), password: senha));

  /// Cria a conta já com uma família própria, para a lista funcionar de cara.
  Future<void> criarConta(String nome, String email, String senha) async {
    final cred = await _auth(() => auth.createUserWithEmailAndPassword(email: email.trim(), password: senha));
    await cred.user!.updateDisplayName(nome.trim());
    await cred.user!.reload();
    await criarFamilia('Casa de ${nome.trim().split(' ').first}');
  }

  Future<void> recuperarSenha(String email) => _auth(() => auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> sair() => auth.signOut();

  /// As famílias de que a pessoa faz parte, ao vivo.
  Stream<List<Familia>> minhasFamilias() => _familias
      .where('membros', arrayContains: usuario!.uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) Familia.fromDoc(d)]..sort((a, b) => a.nome.compareTo(b.nome)));

  Future<String> criarFamilia(String nome) async {
    final u = usuario!;
    final doc = _familias.doc();
    final codigo = gerarCodigo();
    final batch = db.batch()
      ..set(doc, {
        'nome': nome.trim(),
        'dono': u.uid,
        'codigo': codigo,
        'membros': [u.uid],
        'nomes': {u.uid: meuNome},
        'criadaEm': FieldValue.serverTimestamp(),
      })
      ..set(_convites.doc(codigo), {
        'familiaId': doc.id,
        'familiaNome': nome.trim(),
        'criadoPor': u.uid,
        'porNome': meuNome,
        'criadoEm': FieldValue.serverTimestamp(),
      });
    await batch.commit();
    return doc.id;
  }

  /// Cria um convite ligado ao [email] e devolve o código (para mandar na mensagem).
  Future<String> convidarPorEmail(Familia f, String email) async {
    final codigo = gerarCodigo();
    await _convites.doc(codigo).set({
      'familiaId': f.id,
      'familiaNome': f.nome,
      'criadoPor': usuario!.uid,
      'porNome': meuNome,
      'email': email.trim().toLowerCase(),
      'criadoEm': FieldValue.serverTimestamp(),
    });
    return codigo;
  }

  /// Convites feitos para o e-mail da pessoa, de famílias em que ela ainda não está.
  Stream<List<Convite>> convitesParaMim(Set<String> jaEstou) {
    final email = usuario?.email?.toLowerCase();
    if (email == null) return Stream.value(const []);
    return _convites.where('email', isEqualTo: email).snapshots().map((s) => [
          for (final d in s.docs)
            if (!jaEstou.contains(d.data()['familiaId'])) Convite.fromDoc(d),
        ]);
  }

  /// Entra na família do código. Devolve o id da família.
  Future<String> entrarComCodigo(String texto) async {
    final codigo = normalizarConvite(texto);
    if (codigo == null) throw const ErroConta('O código tem 8 letras e números, como ABCD-2345.');
    final DocumentSnapshot<Map<String, dynamic>> c;
    try {
      c = await _convites.doc(codigo).get();
    } on FirebaseException catch (e) {
      throw ErroConta('Não consegui conferir o código (${e.code}).');
    }
    if (!c.exists) throw const ErroConta('Código não encontrado. Confira com quem convidou.');
    final convite = Convite.fromDoc(c);
    final u = usuario!;
    try {
      await _familias.doc(convite.familiaId).update({
        'membros': FieldValue.arrayUnion([u.uid]),
        'nomes.${u.uid}': meuNome,
        'entrouCom': codigo,
      });
    } on FirebaseException catch (e) {
      throw ErroConta('Não consegui entrar na família (${e.code}).');
    }
    // O convite por e-mail é de uso único; o código fixo da família continua valendo.
    if (c.data()?['email'] != null) {
      try {
        await _convites.doc(codigo).delete();
      } catch (_) {}
    }
    return convite.familiaId;
  }

  Future<void> sairDaFamilia(Familia f) => _familias.doc(f.id).update({
        'membros': FieldValue.arrayRemove([usuario!.uid]),
        'nomes.${usuario!.uid}': FieldValue.delete(),
      });

  Future<void> renomearFamilia(Familia f, String nome) => _familias.doc(f.id).update({'nome': nome.trim()});
}
