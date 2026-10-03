import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'reports.dart';
import 'services.dart';
import 'storage.dart';

class ParsedReport {
  const ParsedReport({
    required this.fileName,
    required this.bytes,
    required this.hash,
    required this.pages,
  });
  final String fileName, hash;
  final Uint8List bytes;
  final List<ReportPage> pages;
}

class PdfImportService {
  static const maxBytes = 25 * 1024 * 1024;
  Future<ParsedReport?> pick({void Function(int, int)? progress}) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PDF 财报',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxBytes) throw ServiceFailure('单份 PDF 最多 25 MB');
    return parse(await file.readAsBytes(), file.name, progress: progress);
  }

  Future<void> initialize() async {
    await pdfrxInitialize(tmpPath: (await getTemporaryDirectory()).path);
  }

  Future<ParsedReport> parse(
    Uint8List bytes,
    String fileName, {
    void Function(int, int)? progress,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        !String.fromCharCodes(bytes.take(1024)).contains('%PDF-')) {
      throw ServiceFailure('不是有效 PDF，或文件超过 25 MB');
    }
    PdfDocument? document;
    try {
      await initialize();
      document = await PdfDocument.openData(bytes);
      if (document.isEncrypted) throw ServiceFailure('本轮不支持加密 PDF，请选择可公开读取的财报');
      if (document.pages.length > 1000) throw ServiceFailure('PDF 页数超过 1000 页');
      final pages = <ReportPage>[];
      var total = 0;
      for (final page in document.pages) {
        final text = (await page.loadText())?.fullText ?? '';
        total += text.length;
        if (text.length > 64000 || total > 2000000) {
          throw ServiceFailure('PDF 文本过大，请先拆分财报文件');
        }
        pages.add(ReportPage(number: page.pageNumber, text: text));
        progress?.call(pages.length, document.pages.length);
      }
      if (pages.every((p) => p.text.trim().isEmpty)) {
        throw ServiceFailure('未提取到文字，可能是扫描件；本轮尚不支持 OCR');
      }
      return ParsedReport(
        fileName: fileName,
        bytes: bytes,
        hash: crypto.sha256.convert(bytes).toString(),
        pages: pages,
      );
    } on ServiceFailure {
      rethrow;
    } on PdfPasswordException {
      throw ServiceFailure('PDF 需要密码，本轮不支持加密文件');
    } catch (_) {
      throw ServiceFailure('PDF 读取失败，请确认文件完整且包含可提取文字');
    } finally {
      await document?.dispose();
    }
  }

  Future<Uint8List> renderPage(Uint8List bytes, int number) async {
    await initialize();
    final document = await PdfDocument.openData(bytes);
    try {
      if (number < 1 || number > document.pages.length) {
        throw ServiceFailure('页码越界');
      }
      final page = document.pages[number - 1];
      final scale = math.min(
        2.0,
        math.min(1000 / page.width, 1800 / page.height),
      );
      final width = (page.width * scale).round().clamp(1, 1000);
      final height = (page.height * scale).round().clamp(1, 1800);
      final bitmap = await page.render(
        width: width,
        height: height,
        fullWidth: width.toDouble(),
        fullHeight: height.toDouble(),
      );
      if (bitmap == null) throw ServiceFailure('原页渲染失败');
      try {
        return image.encodePng(bitmap.createImageNF());
      } finally {
        bitmap.dispose();
      }
    } finally {
      await document.dispose();
    }
  }
}

abstract class ReportFileStore {
  Future<void> put(String hash, Uint8List bytes);
  Future<Uint8List?> read(String hash);
}

class LocalReportFileStore implements ReportFileStore {
  LocalReportFileStore(this.directory);
  final Directory directory;
  static Future<LocalReportFileStore> create() async => LocalReportFileStore(
    Directory('${(await LocalWorkspaceStore.create()).directory.path}/reports'),
  );
  File file(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('文件校验值无效');
    }
    return File('${directory.path}/$hash.pdf');
  }

  @override
  Future<void> put(String hash, Uint8List bytes) async {
    final target = file(hash);
    if (bytes.length > PdfImportService.maxBytes ||
        crypto.sha256.convert(bytes).toString() != hash) {
      throw const FormatException('PDF 内容与校验值不一致');
    }
    if (await target.exists()) {
      if (await read(hash) == null) throw const FormatException('已存原文件异常');
      return;
    }
    await directory.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  }

  @override
  Future<Uint8List?> read(String hash) async {
    final target = file(hash);
    if (!await target.exists()) return null;
    if (await target.length() > PdfImportService.maxBytes) {
      throw const FormatException('已存 PDF 超过大小限制');
    }
    final bytes = await target.readAsBytes();
    if (crypto.sha256.convert(bytes).toString() != hash) {
      throw const FormatException('原 PDF 校验失败');
    }
    return bytes;
  }
}

class MemoryReportFileStore implements ReportFileStore {
  final files = <String, Uint8List>{};
  @override
  Future<void> put(String hash, Uint8List bytes) async {
    files[hash] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String hash) async => files[hash];
}
