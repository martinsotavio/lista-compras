import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leitor_ean/lista.dart';
import 'package:leitor_ean/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('abre na lista vazia e troca para a consulta', (t) async {
    await t.pumpWidget(const LeitorEanApp());
    await t.pumpAndSettle();
    expect(find.text('Lista de compras'), findsOneWidget);
    expect(find.textContaining('Lista vazia'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('aba_consultar')));
    await t.pumpAndSettle();
    expect(find.textContaining('Leia ou digite'), findsOneWidget);
  });

  testWidgets('adiciona pelo nome, marca no carrinho com preço e mostra o total', (t) async {
    final lista = ListaLocal();
    await lista.carregar();
    await t.pumpWidget(LeitorEanApp(lista: lista));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('botao_digitar')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('campo_adicionar')), 'Banana');
    await t.tap(find.byKey(const ValueKey('enviar_adicionar')));
    await t.pumpAndSettle();
    expect(find.text('Banana'), findsOneWidget);
    expect(find.text('Para comprar (1)'), findsOneWidget);

    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('campo_preco')), '6,50');
    await t.enterText(find.byKey(const ValueKey('campo_loja')), 'Feira');
    await t.tap(find.byKey(const ValueKey('salvar_preco')));
    await t.pumpAndSettle();

    expect(find.text('No carrinho (1)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('total_carrinho')), matching: find.text('R\$ 6,50'), matchRoot: true),
        findsOneWidget);
    expect(lista.ultimaLoja, 'Feira');
  });
}
