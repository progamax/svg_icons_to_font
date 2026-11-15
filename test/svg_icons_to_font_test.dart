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
      <path d="M1 2 L3 4" transform="rotate(90, 1, 2)" stroke="black" stroke-width="2" fill="none"/>
    </g>
  </g>
</svg>
''';
      // Also test raw path data + matrix transform directly
      final rawCmds = SvgParser.parsePathData('M1 2 L3 4');
      final m = Matrix2D.translation(10, 5) *
          Matrix2D.scaling(2) *
          Matrix2D.rotation(90, 1, 2);
      final move = m.transformCommand(rawCmds[0]);
      final line = m.transformCommand(rawCmds[1]);

      expect(move.x, closeTo(12.0, 1e-6));
      expect(move.y, closeTo(9.0, 1e-6));
      expect(line.x, closeTo(8.0, 1e-6));
      expect(line.y, closeTo(13.0, 1e-6));

      final parsed = SvgParser.parse(svg);
      expect(parsed.commands, isNotEmpty);
    });

    test('parses compact elliptical arc flags without spaces (e.g. a5,5 0 0110,0)', () {
      final cmds = SvgParser.parsePathData(
        'M10 10 A 5 5 0 0115 15 a 5 5 0 10-5 5 Z',
      );
      expect(cmds.first.type, PathCommandType.moveTo);
      expect(cmds.first.x, closeTo(10.0, 1e-6));
      expect(cmds.first.y, closeTo(10.0, 1e-6));

      final cubics = cmds
          .where((c) => c.type == PathCommandType.cubicTo)
          .toList();
      expect(cubics, isNotEmpty);
      expect(cubics.last.x, closeTo(10.0, 1e-5));
      expect(cubics.last.y, closeTo(20.0, 1e-5));
      expect(cmds.last.type, PathCommandType.close);
    });

    test('ignores invisible fill="none" bounding boxes and display="none" elements', () {
      const svg = '''
<svg viewBox="0 0 24 24">
  <rect width="24" height="24" fill="none"/>
  <path d="M0 0 H24 V24 H0 Z" style="fill:none"/>
  <g display="none">
    <circle cx="12" cy="12" r="10"/>
  </g>
  <circle cx="12" cy="12" r="5" fill="#000"/>
</svg>
''';
      final parsed = SvgParser.parse(svg);
      // Only the visible circle (moveTo + 4 cubicTo + close = 6 commands) should remain
      expect(parsed.commands.length, 6);
    });

    test('expands stroked lines and paths with fill="none" into closed contours', () {
      const svg = '''
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <line x1="4" y1="12" x2="20" y2="12"/>
</svg>
''';
      final parsed = SvgParser.parse(svg);
      expect(parsed.commands, isNotEmpty);
      expect(parsed.commands.first.type, PathCommandType.moveTo);
      expect(parsed.commands.last.type, PathCommandType.close);
    });
  });

  group('DartClassGenerator', () {
    test('converts filenames into valid camelCase Dart identifiers and preserves existing camelCase', () {
      expect(DartClassGenerator.toDartIdentifier('arrow_left'), 'arrowLeft');
      expect(DartClassGenerator.toDartIdentifier('home-filled'), 'homeFilled');
      expect(DartClassGenerator.toDartIdentifier('arrowLeft'), 'arrowLeft');
      expect(DartClassGenerator.toDartIdentifier('ArrowLeft'), 'arrowLeft');
      expect(DartClassGenerator.toDartIdentifier('XMLIcon'), 'xmlIcon');
      expect(DartClassGenerator.toDartIdentifier('24_hours'), 'icon24Hours');
      expect(DartClassGenerator.toDartIdentifier('switch'), 'switchIcon');
      expect(DartClassGenerator.toDartIdentifier('int'), 'intIcon');
    });

    test('deduplicates colliding icon identifiers', () {
      const dummySvg = ParsedSvg(
        viewBox: BoundingBox(0, 0, 24, 24),
        commands: [],
      );
      final code = DartClassGenerator.generate(
        glyphs: const [
          IconGlyph(name: 'arrow_left', codePoint: 0xE000, svg: dummySvg),
          IconGlyph(name: 'arrow-left', codePoint: 0xE001, svg: dummySvg),
        ],
        config: const FontGeneratorConfig(
          inputDir: 'in',
          fontOutputPath: 'out.otf',
          dartOutputPath: 'out.dart',
        ),
      );
      expect(code, contains('static const IconData arrowLeft ='));
      expect(code, contains('static const IconData arrowLeft2 ='));
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
  <rect width="24" height="24" fill="none"/>
  <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
</svg>
''');

      File(p.join(svgDir.path, 'search-icon.svg')).writeAsStringSync('''
<svg viewBox="0 0 24 24">
  <circle cx="11" cy="11" r="8"/>
  <line x1="21" y1="21" x2="16.65" y2="16.65" stroke="black" stroke-width="2"/>
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
