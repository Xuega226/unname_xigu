import 'package:integration_test/integration_test.dart';

import '../test/support/v03_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV03Acceptance(native: true);
}
