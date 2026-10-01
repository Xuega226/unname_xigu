import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native secure storage and direct HTTPS market service',
      (tester) async {
    const secure = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true));
    final id = 'weiming_xigu.smoke.${newId()}';
    try {
      await secure.write(key: id, value: 'non-secret-test-sentinel');
      expect(await secure.read(key: id), 'non-secret-test-sentinel');
    } finally {
      await secure.delete(key: id);
    }
    expect(await secure.read(key: id), isNull);
    final store = await LocalWorkspaceStore.create();
    if (Platform.isWindows) {
      expect(store.directory.path.replaceAll('\\', '/'),
          endsWith('/com.lianghua/lianghua_assistant'));
    }
    final company = await MarketService().lookup('SZ', '000001');
    expect(company.code, '000001');
    expect(company.name, isNotEmpty);
    final quote = await MarketService().quote(company);
    expect(quote.close, greaterThan(0));
    expect(quote.tradeDate, isNotNull);
    // Only source metadata and public market data; never log credentials.
    // ignore: avoid_print
    print(
        'NATIVE_MARKET ${company.symbol} ${company.name} ${quote.tradeDate} ${quote.close}');
  });
}
