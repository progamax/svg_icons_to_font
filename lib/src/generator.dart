import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'dart_class_generator.dart';
import 'otf_writer.dart';
import 'svg_parser.dart';

/// Result returned after generating the `.otf` font and `.dart` icon class.
class FontGenerationResult {
  const FontGenerationResult({
    required this.glyphs,
    required this.fontBytes,
    required this.dartCode,
    required this.fontOutputPath,
    required this.dartOutputPath,
  });

  /// All parsed icon glyphs included in the font.
  final List<IconGlyph> glyphs;

  /// Raw binary bytes of the generated `.otf` file.
  final Uint8List fontBytes;

  /// Generated Dart source code containing the Flutter `IconData` class.
  final String dartCode;

  /// File path where the `.otf` font was written.
  final String fontOutputPath;

  /// File path where the `.dart` class was written.
  final String dartOutputPath;
}

/// High-level service that reads a directory of `.svg` files, compiles them
/// into an OpenType (`.otf`) font, and writes the corresponding Flutter Dart file.
class SvgIconsToFontGenerator {
  /// Runs the full generation pipeline from [config] and writes both output files.
  static Future<FontGenerationResult> generate(
    FontGeneratorConfig config,
  ) async {
    final dir = Directory(config.inputDir);
    if (!dir.existsSync()) {
      throw ArgumentError('Input SVG directory does not exist: ${config.inputDir}');
    }

    final svgFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.svg')
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    if (svgFiles.isEmpty) {
      throw StateError('No .svg files found in directory: ${config.inputDir}');
    }

    final glyphs = <IconGlyph>[];
    var codePoint = config.startCodePoint;

    for (final file in svgFiles) {
      final name = p.basenameWithoutExtension(file.path);
      final svgContent = await file.readAsString();
      final parsedSvg = SvgParser.parse(svgContent);
      glyphs.add(
        IconGlyph(
          name: name,
          codePoint: codePoint++,
          svg: parsedSvg,
        ),
      );
    }

    final fontBytes = OtfWriter.buildFont(glyphs: glyphs, config: config);
    final dartCode = DartClassGenerator.generate(glyphs: glyphs, config: config);

    final fontFile = File(config.fontOutputPath);
    await fontFile.parent.create(recursive: true);
    await fontFile.writeAsBytes(fontBytes, flush: true);

    final dartFile = File(config.dartOutputPath);
    await dartFile.parent.create(recursive: true);
    await dartFile.writeAsString(dartCode, flush: true);

    return FontGenerationResult(
      glyphs: glyphs,
      fontBytes: fontBytes,
      dartCode: dartCode,
      fontOutputPath: fontFile.path,
      dartOutputPath: dartFile.path,
    );
  }
}
