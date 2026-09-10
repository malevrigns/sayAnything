import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native secure storage persists and removes an isolated credential',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('SayAnything storage verification')),
        ),
      );
      const vault = FlutterSecureStorage(
        wOptions: WindowsOptions(useBackwardCompatibility: false),
      );
      final key =
          'sayanything-integration-${DateTime.now().microsecondsSinceEpoch}';
      try {
        await vault.write(key: key, value: 'credential-测试-123');
        expect(await vault.read(key: key), 'credential-测试-123');
        await vault.delete(key: key);
        expect(await vault.read(key: key), isNull);
      } finally {
        await vault.delete(key: key);
      }
    },
  );
}
