// Explicit opt-in live check: uses the locally saved key and a paid model call.
// Not part of the default test suite. Never prints credentials or user records.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live DeepSeek connection, JSON draft and evidence validation',
      (tester) async {
    final report = <String, dynamic>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceType': 'explicitly fictional test excerpt',
      'workspaceModified': false,
    };
    try {
      report['supportDirectory'] =
          (await getApplicationSupportDirectory()).path;
      final settings = await SecureCredentialStore().read();
      if (settings.key.trim().isEmpty) {
        throw ServiceFailure('当前 Windows 用户的应用安全存储中尚无 DeepSeek 密钥');
      }
      final service = DeepSeekService();
      final models = await service.models(settings.key);
      report['models'] = models;
      report['configuredModel'] = settings.model;
      if (!models.contains(settings.model)) {
        throw ServiceFailure('配置模型不在账户可用列表中，请在本地设置选择可用模型');
      }
      const source = SourceExcerpt(
        id: 'live-test-source-1',
        studyId: 'live-test-study',
        title: '虚构公司测试资料（不是实际财报）',
        url: 'https://example.com/fictional-test-only',
        period: '2025 年度',
        disclosedAt: '2026-03-31',
        page: '测试片段第 1 段',
        unit: '万元',
        text: '以下内容完全虚构，仅用于验证 API 和引用流程，不可用于真实投资判断。'
            '测试公司的2025年度营业收入为100万元，扣非净利润为8万元。'
            '经营活动现金流量净额为负20万元，期末现金为30万元，有息负债为50万元。'
            '公司说明应收账款回收延后，对现金流形成压力。'
            '资料未提供客户集中度、往年数据或当前估值，均应标为缺失。',
      );
      final stopwatch = Stopwatch()..start();
      final draft = await service.draft(
          key: settings.key,
          model: settings.model,
          company: '虚构测试公司（仅验证 AI 服务）',
          sources: [source]);
      stopwatch.stop();
      final errors = draft.validate([source]);
      report['generationMilliseconds'] = stopwatch.elapsedMilliseconds;
      report['sections'] = {
        for (final k in ResearchDraft.keys) k: draft.render(k)
      };
      report['citationErrors'] = errors;
      if (errors.isNotEmpty) throw ServiceFailure('模型已返回草稿，但引用检查未通过');
      final tampered = ResearchDraft.fromJson({
        'facts': [
          {
            'text': '测试伪造引用',
            'refs': [
              {'sourceId': 'unknown', 'quote': source.text.substring(0, 12)}
            ]
          }
        ],
        'support': [],
        'counter': [],
        'missing': [],
        'review': [],
      });
      if (tampered.validate([source]).isEmpty) throw ServiceFailure('伪造引用未被拦截');
      report['tamperedCitationBlocked'] = true;
      report['status'] = 'passed';
    } on ServiceFailure catch (e) {
      report['status'] = 'failed';
      report['error'] = e.message;
    } catch (_) {
      report['status'] = 'failed';
      report['error'] = '本机安全存储或模型响应读取失败；敏感细节未输出';
    }
    report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    final directory = Directory('../artifacts');
    await directory.create(recursive: true);
    await File('${directory.path}/deepseek-live-test.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(
        'DEEPSEEK_LIVE status=${report['status']} model=${report['configuredModel']} '
        'latency=${report['generationMilliseconds']}ms error=${report['error'] ?? 'none'}');
    expect(report['status'], 'passed', reason: '${report['error'] ?? ''}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
