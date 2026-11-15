import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:svg_icons_to_font/svg_icons_to_font.dart';
import 'package:test/test.dart';

void main() {
  group('SvgParser', () {
    test('parses basic path commands and shapes', () {
      const svg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M2 12 L12 2 L22 12 L19 12 L19 20 L5 20 L5 12 Z"/>
  <circle cx="12" cy="12" r="4"/>
  <rect x="4" y="4" width="16" height="16"/>
</svg>
''';
      final parsed = SvgParser.parse(svg);
      expect(parsed.viewBox.width, 24);
      expect(parsed.viewBox.height, 24);
      expect(parsed.commands, isNotEmpty);
      expect(
        parsed.commands.any((c) => c.type == PathCommandType.moveTo),
        isTrue,
      );
      expect(
        parsed.commands.any((c) => c.type == PathCommandType.cubicTo),
        isTrue,
      );
    });

    test('applies nested transform (translate, scale, rotate, matrix)', () {
      const svg = '''
<svg viewBox="0 0 24 24">
  <g transform="translate(10, 5)">
    <g transform="scale(2)">
      <path d="M1 2 L3 4" transform="rotate(90, 1, 2)"/>
    </g>
  </g>
</svg>
''';
      final parsed = SvgParser.parse(svg);
      expect(parsed.commands.length, 2);

      final move = parsed.commands[0];
      final line = parsed.commands[1];

      // Initial point (1, 2):
      // 1. rotate(90, 1, 2) -> (1, 2)
      // 2. scale(2) -> (2, 4)
      // 3. translate(10, 5) -> (12, 9)
      expect(move.x, closeTo(12.0, 1e-6));
      expect(move.y, closeTo(9.0, 1e-6));

      // Second point (3, 4):
      // 1. rotate(90, 1, 2): dx=2, dy=2 -> (1 - 2, 2 + 2) = (-1, 4)
      // 2. scale(2) -> (-2, 8)
      // 3. translate(10, 5) -> (8, 13)
      expect(line.x, closeTo(8.0, 1e-6));
      expect(line.y, closeTo(13.0, 1e-6));
    });
  });

  group('DartClassGenerator', () {
    test('converts filenames into valid camelCase Dart identifiers', () {
      expect(DartClassGenerator.toDartIdentifier('arrow_left'), 'arrowLeft');
      expect(DartClassGenerator.toDartIdentifier('home-filled'), 'homeFilled');
      expect(DartClassGenerator.toDartIdentifier('24_hours'), 'icon24Hours');
      expect(DartClassGenerator.toDartIdentifier('switch'), 'switchIcon');
    });
  });

  group('End-to-end OTF & Dart generation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('svg_icons_to_font_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generates valid OTTO OpenType font and Flutter IconData class', () async {
      final svgDir = Directory(p.join(tempDir.path, 'svgs'))..createSync();

      File(p.join(svgDir.path, 'home_icon.svg')).writeAsStringSync('''
<svg viewBox="0 0 24 24">
  <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
</svg>
''');

      File(p.join(svgDir.path, 'search-icon.svg')).writeAsStringSync('''
<svg viewBox="0 0 24 24">
  <circle cx="11" cy="11" r="8"/>
  <line x1="21" y1="21" x2="16.65" y2="16.65"/>
</svg>
''');

      final otfPath = p.join(tempDir.path, 'out', 'custom_icons.otf');
      final dartPath = p.join(tempDir.path, 'out', 'custom_icons.dart');

      final config = FontGeneratorConfig(
        inputDir: svgDir.path,
        fontOutputPath: otfPath,
        dartOutputPath: dartPath,
        fontFamily: 'CustomIcons',
        className: 'CustomIcons',
        startCodePoint: 0xE000,
      );

      final result = await SvgIconsToFontGenerator.generate(config);

      expect(File(otfPath).existsSync(), isTrue);
      expect(File(dartPath).existsSync(), isTrue);
      expect(result.glyphs.length, 2);

      // Verify SFNT 'OTTO' signature and table directory
      final bytes = result.fontBytes;
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0), 0x4F54544F); // 'OTTO'
      final numTables = data.getUint16(4);
      expect(numTables, 9);

      // Verify generated Dart code
      expect(result.dartCode, contains('abstract final class CustomIcons'));
      expect(
        result.dartCode,
        contains('static const IconData homeIcon = IconData(0xE000, fontFamily: fontFamily);'),
      );
      expect(
        result.dartCode,
        contains('static const IconData searchIcon = IconData(0xE001, fontFamily: fontFamily);'),
      );
    });
  });
}
