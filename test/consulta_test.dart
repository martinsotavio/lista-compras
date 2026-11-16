import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leitor_ean/consulta.dart';
import 'package:leitor_ean/main.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object o, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(o)), status, headers: {'content-type': 'application/json'});

class _ConsultaFalsa extends Consulta {
  _ConsultaFalsa(this.resposta);
  final Produto? resposta;
  final pedidos = <String>[];
  @override
  Future<Produto?> buscar(String codigo) async {
    pedidos.add(codigo);
    return resposta;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dígito verificador e normalização', () {
    expect(gtinValido('7891000315507'), isTrue); // EAN-13
    expect(gtinValido('7891000315508'), isFalse);
    expect(gtinValido('96385074'), isTrue); // EAN-8
    expect(gtinValido('036000291452'), isTrue); // UPC-A
    expect(normalizarCodigo(' 789-1000-315507 '), '7891000315507');
    expect(normalizarCodigo('1234'), isNull);
  });

  test('ordem das bases: Food Facts, Products Facts e UPCitemdb; para no primeiro que acha', () async {
    final vistos = <String>[];
    final c = Consulta(
      cliente: MockClient((r) async {
        vistos.add(r.url.host);
        expect(r.headers['User-Agent'], userAgent);
        if (r.url.host == 'world.openfoodfacts.org') return _json({'status': 0});
        if (r.url.host == 'world.openproductsfacts.org') return _json({}, 404);
        return _json({
          'items': [
            {'title': 'Tubo de bolas', 'brand': 'Marca X', 'size': '3 un.', 'images': ['https://x/y.jpg'], 'category': 'Sports'}
          ]
        });
      }),
    );
    final p = await c.buscar('7891000315507');
    expect(vistos, ['world.openfoodfacts.org', 'world.openproductsfacts.org', 'api.upcitemdb.com']);
    expect(p!.nome, 'Tubo de bolas');
    expect(p.fonte, 'UPCitemdb');
    expect(p.imagem, 'https://x/y.jpg');

    vistos.clear();
    final c2 = Consulta(
      cliente: MockClient((r) async {
        vistos.add(r.url.host);
        return _json({
          'status': 1,
          'product': {
            'product_name': 'Water',
            'product_name_pt': 'Água mineral',
            'brands': 'Fonte A, Grupo B',
            'quantity': '500 ml',
            'image_front_url': 'https://img/a.jpg',
            'nutriscore_grade': 'a',
          }
        });
      }),
    );
    final a = await c2.buscar('7891000315507');
    expect(vistos, ['world.openfoodfacts.org']);
    expect(a!.nome, 'Água mineral');
    expect(a.marca, 'Fonte A');
    expect(a.nutriscore, 'A');
    expect(a.link, 'https://world.openfoodfacts.org/product/7891000315507');
  });

  test('nenhuma base conhece: nulo; erro de rede também não derruba', () async {
    final c = Consulta(cliente: MockClient((r) async => throw http.ClientException('sem rede')));
    expect(await c.buscar('7891000315507'), isNull);
  });

  testWidgets('código digitado: busca e mostra a foto com os detalhes logo abaixo', (t) async {
    final falsa = _ConsultaFalsa(const Produto(
        codigo: '7891000315507', nome: 'Água mineral', fonte: 'Open Food Facts', marca: 'Fonte A', quantidade: '500 ml'));
    await t.pumpWidget(LeitorEanApp(consulta: falsa));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('aba_consultar')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('campo_codigo')), '7891000315507');
    await t.tap(find.byKey(const ValueKey('botao_buscar')));
    await t.pumpAndSettle();
    expect(falsa.pedidos, ['7891000315507']);
    final foto = t.getRect(find.byKey(const ValueKey('foto_produto')));
    final nome = t.getRect(find.byKey(const ValueKey('nome_produto')));
    expect(nome.top, greaterThanOrEqualTo(foto.bottom), reason: 'os detalhes vêm logo abaixo da foto');
    expect(find.text('Fonte A'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
  });

  testWidgets('código com o dígito errado não consulta', (t) async {
    final falsa = _ConsultaFalsa(null);
    await t.pumpWidget(LeitorEanApp(consulta: falsa));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('aba_consultar')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('campo_codigo')), '7891000315508');
    await t.tap(find.byKey(const ValueKey('botao_buscar')));
    await t.pumpAndSettle();
    expect(falsa.pedidos, isEmpty);
    expect(find.textContaining('não confere'), findsOneWidget);
  });

  testWidgets('AppBar: escolhe a câmera traseira ou a dianteira e lembra a escolha', (t) async {
    SharedPreferences.setMockInitialValues({});
    expect(await cameraSalva(), CameraFacing.back, reason: 'sem escolha, a traseira');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [_SeletorComEstado()]),
      ),
    ));
    expect(find.byIcon(Icons.camera_rear), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('seletor_camera')));
    await t.pumpAndSettle();
    await t.tap(find.text('Câmera dianteira'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.camera_front), findsOneWidget);
    expect(await cameraSalva(), CameraFacing.front);
  });
}

class _SeletorComEstado extends StatefulWidget {
  @override
  State<_SeletorComEstado> createState() => _SeletorComEstadoState();
}

class _SeletorComEstadoState extends State<_SeletorComEstado> {
  CameraFacing _c = CameraFacing.back;
  @override
  Widget build(BuildContext context) => SeletorCamera(
        camera: _c,
        aoEscolher: (c) {
          setState(() => _c = c);
          salvarCamera(c);
        },
      );
}
