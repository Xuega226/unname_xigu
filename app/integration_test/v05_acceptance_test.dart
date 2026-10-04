import 'package:integration_test/integration_test.dart';

import '../test/support/v05_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV05Acceptance(native: true);
}
