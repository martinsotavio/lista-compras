import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'conta.dart';
import 'consulta.dart';
import 'lista_familia.dart';
import 'main.dart' show Inicio;

/// Sem login → tela de login. Com login → a lista da família escolhida (ou a tela para criar/entrar numa).
class PortaoConta extends StatelessWidget {
  const PortaoConta({super.key, required this.conta, required this.consulta});
  final Conta conta;
  final Consulta consulta;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: conta.auth.userChanges(),
        initialData: conta.usuario,
        builder: (context, s) => s.data == null
            ? TelaLogin(conta: conta)
            : _ComFamilia(key: ValueKey(s.data!.uid), conta: conta, consulta: consulta),
      );
}

class _ComFamilia extends StatefulWidget {
  const _ComFamilia({super.key, required this.conta, required this.consulta});
  final Conta conta;
  final Consulta consulta;

  @override
  State<_ComFamilia> createState() => _ComFamiliaState();
}

class _ComFamiliaState extends State<_ComFamilia> {
  static const _chave = 'familia_atual';
  late final Stream<List<Familia>> _familias = widget.conta.minhasFamilias();
  String? _escolhida;
  ListaFamilia? _lista;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _escolhida = p.getString(_chave));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _lista?.dispose();
    super.dispose();
  }

  void _escolher(String id) {
    setState(() => _escolhida = id);
    SharedPreferences.getInstance().then((p) => p.setString(_chave, id)).catchError((_) => true);
  }

  ListaFamilia _listaDe(Familia f) {
    final atual = _lista;
    if (atual != null && atual.familiaId == f.id && atual.nomeFamilia == f.nome) return atual;
    // Troca a lista depois deste quadro (não se descarta um ChangeNotifier no meio do build).
    if (atual != null) WidgetsBinding.instance.addPostFrameCallback((_) => atual.dispose());
    return _lista = ListaFamilia(widget.conta.db, f.id, nomeFamilia: f.nome, meuNome: widget.conta.meuNome)..carregar();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Familia>>(
        stream: _familias,
        builder: (context, s) {
          if (s.hasError) {
            return Scaffold(
                body: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Não consegui ler suas famílias: ${s.error}', textAlign: TextAlign.center))));
          }
          final familias = s.data;
          if (familias == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (familias.isEmpty) {
            return TelaSemFamilia(conta: widget.conta, aoEntrar: _escolher);
          }
          final f = familias.where((f) => f.id == _escolhida).firstOrNull ?? familias.first;
          return Inicio(
            consulta: widget.consulta,
            lista: _listaDe(f),
            aoAbrirFamilia: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TelaFamilia(
                conta: widget.conta,
                familias: _familias,
                atualId: f.id,
                aoEscolher: _escolher,
              ),
            )),
          );
        },
      );
}

/// Entrar ou criar conta, com e-mail e senha.
class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key, required this.conta});
  final Conta conta;

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController(), _email = TextEditingController(), _senha = TextEditingController();
  bool _criando = false, _ocupado = false, _verSenha = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _rodar(Future<void> Function() f) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await f();
    } on ErroConta catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não deu certo: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _enviar() {
    if (!_form.currentState!.validate()) return;
    _rodar(() => _criando
        ? widget.conta.criarConta(_nome.text, _email.text, _senha.text)
        : widget.conta.entrar(_email.text, _senha.text));
  }

  void _esqueci() {
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      setState(() => _erro = 'Digite seu e-mail acima e toque de novo em "Esqueci a senha".');
      return;
    }
    _rodar(() async {
      await widget.conta.recuperarSenha(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mandamos um link para ${_email.text.trim()} criar uma senha nova.')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.shopping_cart_checkout, size: 64, color: tema.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Lista de compras', textAlign: TextAlign.center, style: tema.textTheme.headlineSmall),
                    Text('A lista da casa, junto com a família', textAlign: TextAlign.center,
                        style: TextStyle(color: tema.colorScheme.outline)),
                    const SizedBox(height: 24),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Entrar')),
                        ButtonSegment(value: true, label: Text('Criar conta')),
                      ],
                      selected: {_criando},
                      onSelectionChanged: _ocupado ? null : (v) => setState(() {
                            _criando = v.first;
                            _erro = null;
                          }),
                    ),
                    const SizedBox(height: 16),
                    if (_criando) ...[
                      TextFormField(
                        key: const ValueKey('login_nome'),
                        controller: _nome,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                            labelText: 'Seu nome', helperText: 'Aparece para a família: "pedido por …"',
                            border: OutlineInputBorder()),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Digite seu nome' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const ValueKey('login_email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                      validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : 'E-mail inválido',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('login_senha'),
                      controller: _senha,
                      obscureText: !_verSenha,
                      autofillHints: [_criando ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _verSenha ? 'Esconder senha' : 'Mostrar senha',
                          icon: Icon(_verSenha ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _verSenha = !_verSenha),
                        ),
                      ),
                      validator: (v) => (v ?? '').length < 6 ? 'Pelo menos 6 caracteres' : null,
                      onFieldSubmitted: (_) => _enviar(),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!, style: TextStyle(color: tema.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('login_enviar'),
                      onPressed: _ocupado ? null : _enviar,
                      child: _ocupado
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_criando ? 'Criar conta' : 'Entrar'),
                    ),
                    if (!_criando)
                      TextButton(onPressed: _ocupado ? null : _esqueci, child: const Text('Esqueci a senha')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mensagem do convite, pronta para o e-mail ou para colar no WhatsApp.
String textoConvite(String familia, String codigo, String quem) =>
    '$quem convidou você para a lista de compras "$familia".\n\n'
    '1. Instale o app Lista de compras.\n'
    '2. Crie sua conta com este e-mail (o convite já vai aparecer), ou toque em "Entrar com código".\n'
    '3. Código: ${mostrarCodigo(codigo)}';

Future<void> _abrirEmail(BuildContext context, String email, String assunto, String corpo) async {
  final uri = Uri.parse('mailto:$email?subject=${Uri.encodeComponent(assunto)}&body=${Uri.encodeComponent(corpo)}');
  var abriu = false;
  try {
    abriu = await launchUrl(uri);
  } catch (_) {}
  if (!abriu) {
    await Clipboard.setData(ClipboardData(text: corpo));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não achei um app de e-mail. Copiei a mensagem do convite: cole onde quiser.')));
    }
  }
}

Future<String?> _pedirTexto(BuildContext context,
    {required String titulo, required String rotulo, String? ajuda, String? inicial, String botao = 'OK',
    TextInputType? teclado, String? Function(String)? validar}) {
  final campo = TextEditingController(text: inicial);
  String? erro;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      void ok() {
        final t = campo.text.trim();
        final e = t.isEmpty ? 'Preencha o campo' : validar?.call(t);
        if (e != null) {
          setState(() => erro = e);
        } else {
          Navigator.pop(ctx, t);
        }
      }

      return AlertDialog(
        title: Text(titulo),
        content: TextField(
          key: const ValueKey('dialogo_campo'),
          controller: campo,
          autofocus: true,
          keyboardType: teclado,
          textCapitalization: teclado == null ? TextCapitalization.sentences : TextCapitalization.none,
          decoration: InputDecoration(labelText: rotulo, helperText: ajuda, errorText: erro, border: const OutlineInputBorder()),
          onSubmitted: (_) => ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('dialogo_ok'), onPressed: ok, child: Text(botao)),
        ],
      );
    }),
  ).whenComplete(campo.dispose);
}

Future<void> _entrarComCodigo(BuildContext context, Conta conta, ValueChanged<String> aoEntrar) async {
  final codigo = await _pedirTexto(context,
      titulo: 'Entrar com código',
      rotulo: 'Código da família',
      ajuda: 'Peça para alguém da família (8 letras e números)',
      botao: 'Entrar',
      teclado: TextInputType.visiblePassword,
      validar: (t) => normalizarConvite(t) == null ? 'O código tem 8 letras e números, como ABCD-2345' : null);
  if (codigo == null || !context.mounted) return;
  await _comAviso(context, () async => aoEntrar(await conta.entrarComCodigo(codigo)), 'Pronto, você entrou na família.');
}

Future<void> _criarFamilia(BuildContext context, Conta conta, ValueChanged<String> aoEntrar) async {
  final nome = await _pedirTexto(context, titulo: 'Nova família', rotulo: 'Nome', ajuda: 'Ex.: Casa da praia', botao: 'Criar');
  if (nome == null || !context.mounted) return;
  await _comAviso(context, () async => aoEntrar(await conta.criarFamilia(nome)), 'Família "$nome" criada.');
}

Future<void> _comAviso(BuildContext context, Future<void> Function() f, String sucesso) async {
  final avisos = ScaffoldMessenger.of(context);
  try {
    await f();
    avisos.showSnackBar(SnackBar(content: Text(sucesso)));
  } catch (e) {
    avisos.showSnackBar(SnackBar(content: Text(e is ErroConta ? e.mensagem : 'Não deu certo: $e')));
  }
}

/// Convites pendentes para o e-mail da pessoa, com o botão de aceitar.
class _ConvitesPendentes extends StatelessWidget {
  const _ConvitesPendentes({required this.conta, required this.jaEstou, required this.aoEntrar});
  final Conta conta;
  final Set<String> jaEstou;
  final ValueChanged<String> aoEntrar;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Convite>>(
        stream: conta.convitesParaMim(jaEstou),
        builder: (context, s) => Column(children: [
          for (final c in s.data ?? const <Convite>[])
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text('Convite: ${c.familiaNome}'),
                subtitle: c.porNome == null ? null : Text('de ${c.porNome}'),
                trailing: FilledButton(
                  onPressed: () => _comAviso(context, () async => aoEntrar(await conta.entrarComCodigo(c.codigo)),
                      'Você entrou em ${c.familiaNome}.'),
                  child: const Text('Entrar'),
                ),
              ),
            ),
        ]),
      );
}

/// Quem saiu de todas as famílias (ou foi convidado antes de ter uma).
class TelaSemFamilia extends StatelessWidget {
  const TelaSemFamilia({super.key, required this.conta, required this.aoEntrar});
  final Conta conta;
  final ValueChanged<String> aoEntrar;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sua família'), actions: [
          IconButton(tooltip: 'Sair da conta', icon: const Icon(Icons.logout), onPressed: conta.sair),
        ]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          _ConvitesPendentes(conta: conta, jaEstou: const {}, aoEntrar: aoEntrar),
          const SizedBox(height: 8),
          const Text('A lista de compras é dividida com a família. Crie uma, ou entre na de alguém com o código.',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
              onPressed: () => _criarFamilia(context, conta, aoEntrar),
              icon: const Icon(Icons.add_home),
              label: const Text('Criar uma família')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () => _entrarComCodigo(context, conta, aoEntrar),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Entrar com código')),
        ]),
      );
}

/// A família atual: pessoas, código, convite por e-mail; trocar, criar, entrar em outra, sair.
class TelaFamilia extends StatelessWidget {
  const TelaFamilia({super.key, required this.conta, required this.familias, required this.atualId, required this.aoEscolher});
  final Conta conta;
  final Stream<List<Familia>> familias;
  final String atualId;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Familia>>(
        stream: familias,
        builder: (context, s) {
          final todas = s.data ?? const <Familia>[];
          final f = todas.where((f) => f.id == atualId).firstOrNull;
          void entrou(String id) {
            aoEscolher(id);
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          }

          return Scaffold(
            appBar: AppBar(title: Text(f?.nome ?? 'Família')),
            body: f == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                    _ConvitesPendentes(conta: conta, jaEstou: {for (final x in todas) x.id}, aoEntrar: entrou),
                    _CartaoCodigo(conta: conta, familia: f),
                    const _Titulo('Pessoas'),
                    for (final e in f.nomes.entries)
                      ListTile(
                        leading: CircleAvatar(child: Text(e.value.isEmpty ? '?' : e.value[0].toUpperCase())),
                        title: Text(e.key == conta.usuario?.uid ? '${e.value} (você)' : e.value),
                        subtitle: e.key == f.dono ? const Text('criou a família') : null,
                      ),
                    if (todas.length > 1) ...[
                      const _Titulo('Trocar de família'),
                      for (final x in todas)
                        if (x.id != f.id)
                          ListTile(
                            leading: const Icon(Icons.home_outlined),
                            title: Text(x.nome),
                            subtitle: Text('${x.nomes.length} pessoa(s)'),
                            onTap: () => entrou(x.id),
                          ),
                    ],
                    const _Titulo('Mais'),
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Mudar o nome da família'),
                      onTap: () async {
                        final nome = await _pedirTexto(context, titulo: 'Nome da família', rotulo: 'Nome', inicial: f.nome);
                        if (nome != null && context.mounted) {
                          await _comAviso(context, () => conta.renomearFamilia(f, nome), 'Nome mudado.');
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: const Text('Entrar em outra família com código'),
                      onTap: () => _entrarComCodigo(context, conta, entrou),
                    ),
                    ListTile(
                      leading: const Icon(Icons.add_home_outlined),
                      title: const Text('Criar outra família'),
                      onTap: () => _criarFamilia(context, conta, entrou),
                    ),
                    ListTile(
                      leading: const Icon(Icons.exit_to_app),
                      title: const Text('Sair desta família'),
                      onTap: () => _confirmarSaida(context, f),
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Sair da conta'),
                      subtitle: Text(conta.usuario?.email ?? ''),
                      onTap: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        conta.sair();
                      },
                    ),
                  ]),
          );
        },
      );

  Future<void> _confirmarSaida(BuildContext context, Familia f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sair de ${f.nome}?'),
        content: const Text('Você deixa de ver a lista desta família. Para voltar, precisa do código.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    await _comAviso(context, () => conta.sairDaFamilia(f), 'Você saiu de ${f.nome}.');
    nav.popUntil((r) => r.isFirst);
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(texto,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _CartaoCodigo extends StatelessWidget {
  const _CartaoCodigo({required this.conta, required this.familia});
  final Conta conta;
  final Familia familia;

  Future<void> _convidar(BuildContext context) async {
    final email = await _pedirTexto(context,
        titulo: 'Convidar por e-mail',
        rotulo: 'E-mail da pessoa',
        ajuda: 'Quando ela criar a conta com este e-mail, o convite já aparece',
        botao: 'Convidar',
        teclado: TextInputType.emailAddress,
        validar: (t) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(t) ? null : 'E-mail inválido');
    if (email == null || !context.mounted) return;
    try {
      final codigo = await conta.convidarPorEmail(familia, email);
      if (!context.mounted) return;
      await _abrirEmail(context, email, 'Convite: lista de compras "${familia.nome}"',
          textoConvite(familia.nome, codigo, conta.meuNome));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não consegui criar o convite: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Código para entrar nesta família', style: tema.textTheme.labelLarge),
          const SizedBox(height: 8),
          SelectableText(mostrarCodigo(familia.codigo),
              key: const ValueKey('codigo_familia'),
              textAlign: TextAlign.center,
              style: tema.textTheme.headlineMedium?.copyWith(letterSpacing: 4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar convite'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: textoConvite(familia.nome, familia.codigo, conta.meuNome)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Convite copiado: cole no WhatsApp ou onde quiser.')));
                }
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.forward_to_inbox),
              label: const Text('Convidar por e-mail'),
              onPressed: () => _convidar(context),
            ),
          ]),
        ]),
      ),
    );
  }
}
