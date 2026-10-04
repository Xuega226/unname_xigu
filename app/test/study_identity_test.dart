import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/reports.dart';

const _study = Study(
  id: 'study-1',
  code: '000001',
  name: '测试银行',
  business: '',
  thesis: '原判断',
  counterEvidence: '',
  reviewCondition: '',
  source: '',
  updatedAt: '2026-10-04',
);
const _source = SourceExcerpt(
  id: 'source-1',
  studyId: 'study-1',
  title: '虚构报告',
  url: 'https://example.com/report',
  period: '2025年度',
  disclosedAt: '2026-03-31',
  page: '第1页',
  unit: '万元',
  text: '以下仅为测试资料，营业收入为100万元。',
);

void main() {
  final empty = WorkspaceData.empty().copyWith(studies: [_study]);
  final linked = <String, WorkspaceData>{
    'source': empty.copyWith(sources: [_source]),
    'financial': empty.copyWith(
      financials: [
        const FinancialRecord(
          id: 'financial-1',
          studyId: 'study-1',
          sourceId: 'source-1',
          start: '2025-01-01',
          end: '2025-12-31',
          disclosedAt: '2026-03-31',
          unit: '万元',
          revenue: 100,
        ),
      ],
    ),
    'watchlist': empty.copyWith(
      watchlist: [
        const WatchCompany(
          id: 'SZ:000001',
          code: '000001',
          exchange: 'SZ',
          name: '测试银行',
          industry: '银行',
          source: 'https://example.com/company',
          fetchedAt: '2026-10-04T00:00:00Z',
        ),
      ],
    ),
    'PDF': empty.copyWith(
      documents: [
        ReportDocument(
          id: 'document-1',
          studyId: 'study-1',
          fileName: 'test.pdf',
          sha256: 'a' * 64,
          title: '虚构报告',
          url: '',
          period: '2025年度',
          start: '2025-01-01',
          end: '2025-12-31',
          disclosedAt: '2026-03-31',
          unit: '万元',
          importedAt: '2026-10-04T00:00:00Z',
          pageCount: 1,
          pages: const [ReportPage(number: 1, text: '虚构报告选页原文。')],
        ),
      ],
    ),
    'history': empty.copyWith(
      studyVersions: [
        const StudyVersion(
          id: 'version-1',
          study: _study,
          createdAt: '2026-10-04T00:00:00Z',
          reason: '原历史',
        ),
      ],
    ),
    'review date': empty.copyWith(
      studies: [_study.copyWith(nextReviewAt: '2026-11-04')],
    ),
    'review tasks': empty.copyWith(
      studies: [
        _study.copyWith(
          reviewTasks: const [ReviewTask(id: 'task-1', text: '待核验条件')],
        ),
      ],
    ),
  };
  for (final entry in linked.entries) {
    test(
      '${entry.key} prevents code and name reassignment and retains edits',
      () {
        final data = entry.value;
        final old = data.studies.single;
        final before = data.encode();
        expect(studyIdentityLocked(data, old), isTrue);
        for (final identity in [
          {'code': '600000'},
          {'name': '另一家公司'},
        ]) {
          final reassigned = Study.fromJson({...old.toJson(), ...identity});
          expect(
            () => saveStudyVersion(data, reassigned, '身份变更'),
            throwsFormatException,
          );
          expect(data.encode(), before);
        }
        final edited = old.copyWith(thesis: '同公司的新判断');
        final saved = saveStudyVersion(data, edited, '正常内容编辑');
        expect(saved.studies.single.thesis, '同公司的新判断');
        expect(saved.studies.single.code, old.code);
        expect(saved.studies.single.name, old.name);
        expect(saved.studyVersions.length, data.studyVersions.length + 1);
        expect(saved.studyVersions.last.study.toJson(), old.toJson());
        expect(saved.reviews.single.text, contains('原判断'));
        expect(saved.studies.single.nextReviewAt, old.nextReviewAt);
        expect(saved.studies.single.reviewTasks, old.reviewTasks);
        expect(saved.sources, data.sources);
        expect(saved.financials, data.financials);
        expect(saved.documents, data.documents);
      },
    );
  }
  test('unbound identity correction preserves historical identity and locks later edits', () {
    expect(studyIdentityLocked(empty, _study), isFalse);
    final corrected = Study.fromJson({
      ..._study.toJson(),
      'code': '600000',
      'name': '更正后的公司',
    });
    final saved = saveStudyVersion(empty, corrected, '更正未关联公司的身份');
    final restored = WorkspaceData.decode(saved.encode());
    expect(restored.studies.single.code, '600000');
    expect(restored.studyVersions.single.study.code, '000001');
    expect(restored.studyVersions.single.study.name, '测试银行');
    expect(studyIdentityLocked(restored, restored.studies.single), isTrue);
    expect(
      () => saveStudyVersion(restored, _study, '再次重分配身份'),
      throwsFormatException,
    );
    final edited = saveStudyVersion(
      restored,
      restored.studies.single.copyWith(thesis: '后续正常编辑'),
      '保留历史',
    );
    expect(WorkspaceData.decode(edited.encode()).studyVersions.length, 2);
    expect(edited.studyVersions.first.study.code, '000001');
  });
}
