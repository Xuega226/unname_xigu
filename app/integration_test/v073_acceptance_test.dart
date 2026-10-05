import 'package:integration_test/integration_test.dart';

import '../test/support/v073_acceptance.dart';
import '../test/support/v073_report_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerV073Acceptance(native: true);
  registerV073ReportAcceptance(native: true);
}
