import 'package:integration_test/integration_test.dart';

import '../test/support/v04_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV04Acceptance(native: true);
}
