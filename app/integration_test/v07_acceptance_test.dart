import 'package:integration_test/integration_test.dart';

import '../test/support/v07_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV07Acceptance(native: true);
}
