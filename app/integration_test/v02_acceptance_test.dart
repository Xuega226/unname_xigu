import 'package:integration_test/integration_test.dart';
import '../test/support/v02_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV02Acceptance(native: true);
}
