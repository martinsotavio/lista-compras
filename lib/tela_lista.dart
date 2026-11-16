import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'consulta.dart';
import 'lista.dart';
import 'main.dart' show temCamera, lerCodigoComCamera;

/// A lista de compras: o que falta comprar, o que já está no carrinho e os totais.
class TelaLista extends StatefulWidget {
  const TelaLista({super.key, required this.lista, required this.consulta, this.aoAbrirFamilia, this.tirarFoto});
  final ListaCompras lista;
  final Consulta consulta;

  /// Abre a tela da família (só na lista com login).
  final VoidCallback? aoAbrirFamilia;

  /// Tira a foto (JPEG pequeno). Nos testes, uma falsa; sem ela, usa a câmera pelo image_picker.
  final Future<List<int>?> Function()? tirarFoto;

  @override
  State<TelaLista> createState() => _TelaListaState();
}

class _TelaListaState extends State<TelaLista> {
  bool _buscando = false;

  ListaCompras get _lista => widget.lista;

  void _avisar(String texto, {SnackBarAction? acao}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), action: acao));
  }

  Future<void> _lerCamera() async {
    final lido = await lerCodigoComCamera(context);
    if (lido != null && mounted) await _adicionarCodigo(lido);
  }

  /// Código lido ou digitado → produto na lista. Usa o que já é conhecido; senão consulta as bases;
  /// se nenhuma base conhece, pede o nome.
  Future<void> _adicionarCodigo(String texto) async {
    final codigo = normalizarCodigo(texto);
    if (codigo == null || !gtinValido(codigo)) {
      _avisar('O código ${codigo ?? texto.trim()} não confere. Leia de novo.');
      return;
    }
    var conhecido = _lista.conhecido(codigo);
    if (conhecido == null) {
      setState(() => _buscando = true);
      final p = await widget.consulta.buscar(codigo);
      if (!mounted) return;
      setState(() => _buscando = false);
      if (p != null) {
        conhecido = Conhecido(nome: p.nome, codigo: codigo, marca: p.marca, imagem: p.imagem);
      } else {
        final nome = await _pedirTexto('Produto não encontrado',
            'Nenhuma base conhece o código $codigo. Qual é o nome do produto?', 'Nome do produto');
        if (nome == null || !mounted) return;
        conhecido = Conhecido(nome: nome, codigo: codigo);
      }
    }
    await _adicionarConhecido(conhecido);
  }

  Future<void> _adicionarConhecido(Conhecido c) async {
    final item = await _lista.adicionar(nome: c.nome, codigo: c.codigo, marca: c.marca, imagem: c.imagem);
    if (mounted) _avisar(item.quantidade > 1 ? '${item.nome}: agora ${item.quantidade}' : '${item.nome} na lista');
  }

  Future<String?> _pedirTexto(String titulo, String mensagem, String rotulo) {
    final campo = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        void ok() {
          final t = campo.text.trim();
          if (t.isNotEmpty) Navigator.pop(ctx, t);
        }

        return AlertDialog(
          title: Text(titulo),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mensagem),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('campo_nome'),
              controller: campo,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
              onSubmitted: (_) => ok(),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(key: const ValueKey('confirmar_nome'), onPressed: ok, child: const Text('Adicionar')),
          ],
        );
      },
    ).whenComplete(campo.dispose);
  }

  /// Acabou algo sem código (ou não dá tempo de achar o código): tira foto e quem for ao mercado vê.
  Future<void> _foto() async {
    List<int>? bytes;
    try {
      bytes = await (widget.tirarFoto ?? _tirarFotoCamera)();
    } catch (e) {
      _avisar('Não consegui abrir a câmera: $e');
      return;
    }
    if (bytes == null || !mounted) return;
    final nome = await _pedirTexto('O que acabou?', 'Dê um nome para quem for ao mercado (ex.: "Iogurte", "Detergente").',
        'Nome do produto');
    if (nome == null || !mounted) return;
    await _lista.adicionar(nome: nome, foto: base64Encode(bytes));
    if (mounted) _avisar('$nome na lista, com foto');
  }

  /// Foto pequena (até 640 px, JPEG 60%): fica com ~50 KB, cabe no documento do item na nuvem.
  static Future<List<int>?> _tirarFotoCamera() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 640, maxHeight: 640, imageQuality: 60);
    return f?.readAsBytes();
  }

  /// Folha para digitar um código ou um nome (ex.: "Banana"), ou tocar num produto já usado.
  Future<void> _adicionarDigitando() async {
    final escolha = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FolhaAdicionar(sugestoes: _lista.sugestoes),
    );
    if (!mounted) return;
    switch (escolha) {
      case Conhecido c:
        await _adicionarConhecido(c);
      case String t when normalizarCodigo(t) != null && RegExp(r'^[\d\s-]+$').hasMatch(t):
        await _adicionarCodigo(t);
      case String t:
        await _adicionarConhecido(Conhecido(nome: t));
    }
  }

  Future<void> _marcar(Item item, bool comprado) async {
    if (!comprado) {
      await _lista.marcar(item, false);
      return;
    }
    final r = await showDialog<(double?, String?)>(
      context: context,
      builder: (_) => _DialogoPreco(item: item, sugerido: _lista.ultimoPreco(item)?.valor, loja: _lista.ultimaLoja),
    );
    if (r == null) return; // fechou sem escolher: continua para comprar
    await _lista.marcar(item, true, preco: r.$1, loja: r.$2);
  }

  Future<void> _remover(Item item) async {
    final posicao = _lista.itens.indexOf(item);
    await _lista.remover(item);
    if (mounted) {
      _avisar('${item.nome} removido',
          acao: SnackBarAction(label: 'Desfazer', onPressed: () => _lista.devolver(item, posicao)));
    }
  }

  void _detalhes(Item item) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _FolhaDetalhes(item: item, historico: _lista.historico(item)),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _lista,
        builder: (context, _) {
          final aComprar = _lista.aComprar, carrinho = _lista.noCarrinho;
          return Scaffold(
            appBar: AppBar(
              title: Text(_lista.titulo),
              bottom: _buscando
                  ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
                  : null,
              actions: [
                if (widget.aoAbrirFamilia != null)
                  IconButton(
                    key: const ValueKey('botao_familia'),
                    tooltip: 'Família e convites',
                    icon: const Icon(Icons.group_outlined),
                    onPressed: widget.aoAbrirFamilia,
                  ),
                if (carrinho.isNotEmpty)
                  IconButton(
                    key: const ValueKey('limpar_comprados'),
                    tooltip: 'Tirar os comprados da lista',
                    icon: const Icon(Icons.remove_done),
                    onPressed: _confirmarLimpeza,
                  ),
              ],
            ),
            floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              FloatingActionButton.small(
                key: const ValueKey('botao_digitar'),
                heroTag: 'digitar',
                tooltip: 'Digitar código ou nome',
                onPressed: _buscando ? null : _adicionarDigitando,
                child: const Icon(Icons.edit_note),
              ),
              if (temCamera) ...[
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  key: const ValueKey('botao_foto'),
                  heroTag: 'foto',
                  tooltip: 'Tirar foto do que acabou',
                  onPressed: _buscando ? null : _foto,
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  key: const ValueKey('botao_ler'),
                  heroTag: 'ler',
                  onPressed: _buscando ? null : _lerCamera,
                  icon: const Icon(Icons.barcode_reader),
                  label: const Text('Ler código'),
                ),
              ],
            ]),
            bottomNavigationBar: _lista.itens.isEmpty ? null : _Totais(aComprar: _lista.totalAComprar, carrinho: _lista.totalCarrinho),
            body: !_lista.carregada
                ? const Center(child: CircularProgressIndicator())
                : _lista.itens.isEmpty
                    ? const _Vazia()
                    : ListView(padding: const EdgeInsets.only(bottom: 220), children: [
                        if (_lista.erro != null)
                          MaterialBanner(
                            content: Text(_lista.erro!),
                            leading: const Icon(Icons.cloud_off),
                            actions: [TextButton(onPressed: () => setState(() => _lista.erro = null), child: const Text('OK'))],
                          ),
                        if (aComprar.isNotEmpty) _Secao('Para comprar (${aComprar.length})'),
                        for (final i in aComprar) _linha(i),
                        if (carrinho.isNotEmpty) _Secao('No carrinho (${carrinho.length})'),
                        for (final i in carrinho) _linha(i),
                      ]),
          );
        },
      );

  Future<void> _confirmarLimpeza() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar os comprados?'),
        content: const Text('Os itens do carrinho saem da lista. Os preços ficam guardados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tirar')),
        ],
      ),
    );
    if (ok == true) await _lista.limparComprados();
  }

  Widget _linha(Item item) {
    final tema = Theme.of(context);
    final ultimo = _lista.ultimoPreco(item), menor = _lista.menorPreco(item);
    final detalhes = [
      if (_lista.compartilhada && item.porNome != null) 'pedido por ${item.porNome}',
      if (item.marca != null) item.marca!,
      if (ultimo != null) '${reais(ultimo.valor)}${ultimo.loja != null ? ' (${ultimo.loja})' : ''}',
      if (menor != null && ultimo != null && menor.valor < ultimo.valor)
        'menor: ${reais(menor.valor)}${menor.loja != null ? ' (${menor.loja})' : ''}',
    ];
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: tema.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: tema.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) => _remover(item),
      child: ListTile(
        key: ValueKey('item_${item.id}'),
        onTap: () => _detalhes(item),
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          Checkbox(value: item.comprado, onChanged: (v) => _marcar(item, v ?? false)),
          _Miniatura(url: item.imagem, bytes: item.fotoBytes),
        ]),
        title: Text(
          item.nome,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: item.comprado
              ? TextStyle(decoration: TextDecoration.lineThrough, color: tema.colorScheme.outline)
              : null,
        ),
        subtitle: detalhes.isEmpty ? null : Text(detalhes.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Menos',
            icon: Icon(item.quantidade == 1 ? Icons.delete_outline : Icons.remove),
            onPressed: () => item.quantidade == 1 ? _remover(item) : _lista.mudarQuantidade(item, -1),
          ),
          Text('${item.quantidade}', style: tema.textTheme.titleMedium),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Mais',
            icon: const Icon(Icons.add),
            onPressed: () => _lista.mudarQuantidade(item, 1),
          ),
        ]),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(texto,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _Vazia extends StatelessWidget {
  const _Vazia();

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_cart_outlined, size: 64, color: cor),
          const SizedBox(height: 12),
          Text('Lista vazia. Leia o código de barras do que acabou, tire uma foto ou digite o nome.',
              textAlign: TextAlign.center, style: TextStyle(color: cor)),
        ]),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({this.url, this.bytes});
  final String? url;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final fundo = Theme.of(context).colorScheme.surfaceContainerHighest;
    const icone = Icon(Icons.shopping_basket_outlined, size: 22);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: fundo,
        child: bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => icone)
            : url == null
                ? icone
                : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => icone),
      ),
    );
  }
}

class _Totais extends StatelessWidget {
  const _Totais({required this.aComprar, required this.carrinho});
  final double aComprar, carrinho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget valor(String rotulo, double v, {Key? key}) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.outline)),
            Text(reais(v), key: key, style: tema.textTheme.titleMedium),
          ]),
        );
    return Material(
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            valor('Falta (estimado)', aComprar, key: const ValueKey('total_falta')),
            valor('No carrinho', carrinho, key: const ValueKey('total_carrinho')),
          ]),
        ),
      ),
    );
  }
}

/// Ao pôr no carrinho: preço por unidade e loja, ambos opcionais. Devolve (preço, loja), ou null se fechou.
class _DialogoPreco extends StatefulWidget {
  const _DialogoPreco({required this.item, this.sugerido, this.loja});
  final Item item;
  final double? sugerido;
  final String? loja;

  @override
  State<_DialogoPreco> createState() => _DialogoPrecoState();
}

class _DialogoPrecoState extends State<_DialogoPreco> {
  late final _preco = TextEditingController(
      text: widget.sugerido == null ? '' : widget.sugerido!.toStringAsFixed(2).replaceAll('.', ','));
  late final _loja = TextEditingController(text: widget.loja ?? '');

  @override
  void dispose() {
    _preco.dispose();
    _loja.dispose();
    super.dispose();
  }

  void _ok() => Navigator.pop(context, (lerPreco(_preco.text), _loja.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const ValueKey('campo_preco'),
            controller: _preco,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Preço por unidade (opcional)',
              prefixText: 'R\$ ',
              border: const OutlineInputBorder(),
              helperText: widget.item.quantidade > 1 ? '${widget.item.quantidade} unidades' : null,
            ),
            onSubmitted: (_) => _ok(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('campo_loja'),
            controller: _loja,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Loja (opcional)', border: OutlineInputBorder()),
            onSubmitted: (_) => _ok(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, (null, null)), child: const Text('Sem preço')),
          FilledButton(key: const ValueKey('salvar_preco'), onPressed: _ok, child: const Text('No carrinho')),
        ],
      );
}

/// Digitar um código ou nome, ou escolher um produto já usado. Devolve String (digitado) ou Conhecido.
class _FolhaAdicionar extends StatefulWidget {
  const _FolhaAdicionar({required this.sugestoes});
  final List<Conhecido> sugestoes;

  @override
  State<_FolhaAdicionar> createState() => _FolhaAdicionarState();
}

class _FolhaAdicionarState extends State<_FolhaAdicionar> {
  final _campo = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _enviar() {
    final t = _campo.text.trim();
    if (t.isNotEmpty) Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final f = _filtro.toLowerCase();
    final lista = [
      for (final s in widget.sugestoes)
        if (f.isEmpty || s.nome.toLowerCase().contains(f) || (s.codigo?.contains(f) ?? false)) s,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey('campo_adicionar'),
              controller: _campo,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Código de barras ou nome',
                hintText: 'Ex.: 7891000100103 ou Banana',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const ValueKey('enviar_adicionar'),
                  icon: const Icon(Icons.add_circle),
                  onPressed: _enviar,
                ),
              ),
              onChanged: (v) => setState(() => _filtro = v.trim()),
              onSubmitted: (_) => _enviar(),
            ),
          ),
          if (lista.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Comprar de novo', style: Theme.of(context).textTheme.titleSmall),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final s in lista)
                  ListTile(
                    leading: _Miniatura(url: s.imagem),
                    title: Text(s.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: s.marca == null ? null : Text(s.marca!),
                    trailing: const Icon(Icons.add),
                    onTap: () => Navigator.pop(context, s),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _FolhaDetalhes extends StatelessWidget {
  const _FolhaDetalhes({required this.item, required this.historico});
  final Item item;
  final List<Preco> historico;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    String data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        if (item.fotoBytes != null)
          SizedBox(height: 260, child: Image.memory(item.fotoBytes!, fit: BoxFit.contain))
        else if (item.imagem != null)
          SizedBox(
            height: 180,
            child: Image.network(item.imagem!, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 48)),
          ),
        const SizedBox(height: 12),
        Text(item.nome, style: tema.textTheme.titleLarge),
        if (item.marca != null) Text(item.marca!, style: TextStyle(color: tema.colorScheme.outline)),
        if (item.porNome != null) Text('Pedido por ${item.porNome}', style: TextStyle(color: tema.colorScheme.outline)),
        if (item.codigo != null) SelectableText('Código ${item.codigo}', style: TextStyle(color: tema.colorScheme.outline)),
        const SizedBox(height: 16),
        Text('Preços pagos', style: tema.textTheme.titleSmall),
        if (historico.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nenhum ainda. Ao marcar no carrinho, informe o preço.')),
        for (final p in historico.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(reais(p.valor)),
            subtitle: Text([data(p.data), if (p.loja != null) p.loja!].join(' · ')),
          ),
      ]),
    );
  }
}
