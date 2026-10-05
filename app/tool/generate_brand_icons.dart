import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Resize the checked-in artwork only: never crop or redraw it.
void main() {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final source = File(
    '${root.path}/assets/branding/unnameko-stock-icon-v2.png',
  );
  final artwork = img.decodePng(source.readAsBytesSync());
  if (artwork == null || artwork.width != artwork.height) {
    throw StateError('Brand artwork must be a square PNG.');
  }

  Uint8List resized(int size) => img.encodePng(
    img.copyResize(
      artwork,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    ),
  );

  void write(String relativePath, List<int> bytes) {
    final file = File('${root.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    stdout.writeln(relativePath);
  }

  write('app/assets/branding/unnameko-stock-icon-v2.png', resized(512));
  const densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in densities.entries) {
    write(
      'app/android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      resized(entry.value),
    );
  }

  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final images = sizes.map(resized).toList();
  final header = ByteData(6 + sizes.length * 16)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, sizes.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < sizes.length; i++) {
    final entry = 6 + i * 16;
    header
      ..setUint8(entry, sizes[i] == 256 ? 0 : sizes[i])
      ..setUint8(entry + 1, sizes[i] == 256 ? 0 : sizes[i])
      ..setUint16(entry + 4, 1, Endian.little)
      ..setUint16(entry + 6, 32, Endian.little)
      ..setUint32(entry + 8, images[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += images[i].length;
  }
  final ico = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final image in images) {
    ico.add(image);
  }
  write('app/windows/runner/resources/app_icon.ico', ico.takeBytes());
}
