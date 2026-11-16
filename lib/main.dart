

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'consulta.dart';
import 'conta.dart';
import 'firebase_options.dart';
import 'lista.dart';
import 'moldura.dart';
import 'tela_conta.dart';
import 'tela_lista.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Conta? conta;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    conta = Conta(FirebaseAuth.instance, FirebaseFirestore.instance);
  } catch (e) {
    // Firebase ainda não configurado (veja o README): o app abre com a lista só no aparelho, sem login.
    debugPrint('Firebase indisponível, usando a lista local: $e');
  }
  runApp(LeitorEanApp(conta: conta));
}


/// Câmera (mobile_scanner) no Android e no iPhone. Em outro lugar (ex.: testes), só digitando.
bool get temCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);


const _chaveCamera = 'camera';

Future<CameraFacing> cameraSalva() async {
  try {
    return (await SharedPreferences.getInstance()).getString(_chaveCamera) == 'dianteira'
        ? CameraFacing.front
        : CameraFacing.back;
  } catch (_) {
    return CameraFacing.back; 
  }
}

Future<void> salvarCamera(CameraFacing c) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_chaveCamera, c == CameraFacing.front ? 'dianteira' : 'traseira');
  } catch (_) {}
}

/// Abre a câmera certa para a plataforma e devolve o código lido (ou null se voltou sem ler).
/// Sem [camera], usa a guardada no aparelho; a troca feita lá dentro fica guardada.
Future<String?> lerCodigoComCamera(BuildContext context,
    {CameraFacing? camera, ValueChanged<CameraFacing>? aoEscolher}) async {
  final c = camera ?? await cameraSalva();
  if (!context.mounted) return null;
  final escolher = aoEscolher ?? salvarCamera;
  return Navigator.of(context).push<String>(MaterialPageRoute(
    builder: (_) => TelaCamera(camera: c, aoEscolher: escolher),
  ));
}

class SeletorCamera extends StatelessWidget {
  const SeletorCamera({super.key, required this.camera, required this.aoEscolher});
  final CameraFacing camera;
  final ValueChanged<CameraFacing> aoEscolher;

  @override
  Widget build(BuildContext context) => PopupMenuButton<CameraFacing>(
        key: const ValueKey('seletor_camera'),
        tooltip: camera == CameraFacing.front ? 'Câmera dianteira' : 'Câmera traseira',
        icon: Icon(camera == CameraFacing.front ? Icons.camera_front : Icons.camera_rear),
        initialValue: camera,
        onSelected: aoEscolher,
        itemBuilder: (_) => const [
          PopupMenuItem(
            key: ValueKey('camera_traseira'),
            value: CameraFacing.back,
            child: ListTile(leading: Icon(Icons.camera_rear), title: Text('Câmera traseira')),
          ),
          PopupMenuItem(
            key: ValueKey('camera_dianteira'),
            value: CameraFacing.front,
            child: ListTile(leading: Icon(Icons.camera_front), title: Text('Câmera dianteira')),
          ),
        ],
      );
}

class LeitorEanApp extends StatelessWidget {
  const LeitorEanApp({super.key, this.consulta, this.lista, this.conta});
  final Consulta? consulta;
  final ListaCompras? lista;

  /// Com conta (Firebase configurado): login e lista da família. Sem: lista só no aparelho.
  final Conta? conta;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Lista de compras',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1A7CB9), useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF1A7CB9), brightness: Brightness.dark, useMaterial3: true),
        home: conta != null && lista == null
            ? PortaoConta(conta: conta!, consulta: consulta ?? Consulta())
            : Inicio(consulta: consulta ?? Consulta(), lista: lista),
      );
}

/// Duas abas: a lista de compras e a consulta avulsa de um código.
class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.consulta, this.lista, this.aoAbrirFamilia});
  final Consulta consulta;

  /// Sem lista, cria uma lista local (no aparelho) e cuida dela.
  final ListaCompras? lista;
  final VoidCallback? aoAbrirFamilia;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  ListaLocal? _local;
  ListaCompras get _lista => widget.lista ?? (_local ??= ListaLocal()..carregar());
  var _aba = 0;

  @override
  void dispose() {
    _local?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _aba, children: [
          TelaLista(lista: _lista, consulta: widget.consulta, aoAbrirFamilia: widget.aoAbrirFamilia),
          TelaInicial(consulta: widget.consulta),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _aba,
          onDestinationSelected: (i) => setState(() => _aba = i),
          destinations: const [
            NavigationDestination(key: ValueKey('aba_lista'), icon: Icon(Icons.checklist), label: 'Lista'),
            NavigationDestination(key: ValueKey('aba_consultar'), icon: Icon(Icons.search), label: 'Consultar'),
          ],
        ),
      );
}

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key, required this.consulta});
  final Consulta consulta;

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

enum _Estado { inicio, buscando, achou, naoAchou, invalido }

class _TelaInicialState extends State<TelaInicial> {
  final _campo = TextEditingController();
  _Estado _estado = _Estado.inicio;
  Produto? _produto;
  String? _codigo;
  CameraFacing _camera = CameraFacing.back;

  @override
  void initState() {
    super.initState();
    cameraSalva().then((c) {
      if (mounted) setState(() => _camera = c);
    });
  }

  void _escolherCamera(CameraFacing c) {
    setState(() => _camera = c);
    salvarCamera(c);
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _consultar(String texto) async {
    final codigo = normalizarCodigo(texto);
    _campo.text = codigo ?? texto.trim();
    if (codigo == null || !gtinValido(codigo)) {
      setState(() {
        _codigo = codigo ?? texto.trim();
        _estado = _Estado.invalido;
        _produto = null;
      });
      return;
    }
    setState(() {
      _codigo = codigo;
      _estado = _Estado.buscando;
      _produto = null;
    });
    final p = await widget.consulta.buscar(codigo);
    if (!mounted || _codigo != codigo) return; 
    setState(() {
      _produto = p;
      _estado = p == null ? _Estado.naoAchou : _Estado.achou;
    });
  }

  Future<void> _lerComCamera() async {
    final lido = await lerCodigoComCamera(context, camera: _camera, aoEscolher: _escolherCamera);
    if (lido != null && mounted) _consultar(lido);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Consultar código'),
          actions: [if (temCamera) SeletorCamera(camera: _camera, aoEscolher: _escolherCamera)],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('campo_codigo'),
                controller: _campo,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Código de barras',
                  hintText: 'Digite ou use um leitor USB e Enter',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                ),
                onSubmitted: _consultar,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey('botao_buscar'),
              tooltip: 'Buscar',
              icon: const Icon(Icons.search),
              onPressed: () => _consultar(_campo.text),
            ),
          ]),
          if (temCamera) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('botao_camera'),
              onPressed: _estado == _Estado.buscando ? null : _lerComCamera,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Ler com a câmera'),
            ),
          ],
          const SizedBox(height: 20),
          _resultado(context),
        ]),
      );

  Widget _resultado(BuildContext context) => switch (_estado) {
        _Estado.inicio => const _Aviso(icone: Icons.barcode_reader, texto: 'Leia ou digite um código de barras (EAN-13, EAN-8, UPC).'),
        _Estado.buscando => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        _Estado.invalido => _Aviso(
            icone: Icons.error_outline, texto: 'O código $_codigo não confere (o último dígito não bate). Leia de novo.', erro: true),
        _Estado.naoAchou => _Aviso(
            icone: Icons.search_off, texto: 'Nenhuma base conhece o código $_codigo (Open Food Facts, Open Products Facts e UPCitemdb).'),
        _Estado.achou => DetalhesProduto(produto: _produto!),
      };
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto, this.erro = false});
  final IconData icone;
  final String texto;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final cor = erro ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Icon(icone, size: 56, color: cor),
        const SizedBox(height: 12),
        Text(texto, textAlign: TextAlign.center, style: TextStyle(color: cor)),
      ]),
    );
  }
}


class DetalhesProduto extends StatelessWidget {
  const DetalhesProduto({super.key, required this.produto});
  final Produto produto;

  @override
  Widget build(BuildContext context) {
    final p = produto;
    final tema = Theme.of(context);
    final linhas = <(String, String?)>[
      ('Marca', p.marca),
      ('Quantidade', p.quantidade),
      ('Categorias', p.categorias),
      ('Países', p.paises),
      ('Nutri-Score', p.nutriscore),
      ('Ingredientes / descrição', p.ingredientes),
      ('Código', p.codigo),
      ('Fonte', p.fonte),
      ('Página', p.link),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const ValueKey('foto_produto'),
          height: 280,
          color: tema.colorScheme.surfaceContainerHighest,
          child: p.imagem == null
              ? const Center(child: Icon(Icons.image_not_supported_outlined, size: 64))
              : Image.network(
                  p.imagem!,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, filho, progresso) =>
                      progresso == null ? filho : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, size: 64)),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(p.nome, key: const ValueKey('nome_produto'), style: tema.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final (rotulo, valor) in linhas)
              if (valor != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rotulo, style: tema.textTheme.labelMedium?.copyWith(color: tema.colorScheme.outline)),
                    SelectableText(valor),
                  ]),
                ),
          ]),
        ),
      ]),
    );
  }
}


class TelaCamera extends StatefulWidget {
  const TelaCamera({super.key, this.camera = CameraFacing.back, this.aoEscolher});
  final CameraFacing camera;

  
  final ValueChanged<CameraFacing>? aoEscolher;

  @override
  State<TelaCamera> createState() => _TelaCameraState();
}

class _TelaCameraState extends State<TelaCamera> {
  late CameraFacing _camera = widget.camera;
  late final _controle = MobileScannerController(facing: widget.camera, formats: const [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
  ]);
  bool _lido = false;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  Future<void> _trocar(CameraFacing c) async {
    if (c == _camera) return;
    setState(() => _camera = c);
    widget.aoEscolher?.call(c);
    await _controle.switchCamera();
  }

  void _detectou(BarcodeCapture c) {
    if (_lido) return;
    for (final b in c.barcodes) {
      final v = b.rawValue;
      if (v != null && normalizarCodigo(v) != null) {
        _lido = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Aponte para o código'),
          actions: [
            SeletorCamera(camera: _camera, aoEscolher: _trocar),
          ],
        ),
        backgroundColor: Colors.black,
        // Só lê o que estiver dentro da moldura (scanWindow), que fica no centro da tela.
        body: LayoutBuilder(builder: (context, limites) => Stack(fit: StackFit.expand, children: [
              MobileScanner(controller: _controle, onDetect: _detectou, scanWindow: retanguloMoldura(limites.biggest)),
              const MolduraLeitura(),
            ])),
      );
}
