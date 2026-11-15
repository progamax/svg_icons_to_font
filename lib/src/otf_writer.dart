import 'dart:typed_data';

import 'config.dart';
import 'otf/cff_table_builder.dart';
import 'otf/glyph_model.dart';
import 'otf/glyph_transformer.dart';
import 'otf/sfnt_tables.dart';

export 'otf/glyph_model.dart' show IconGlyph;

/// Builds a binary OpenType (`.otf` with CFF outlines) font file in pure Dart.
class OtfWriter {
  /// Compiles a list of [IconGlyph]s into a complete OpenType `.otf` binary.
  static Uint8List buildFont({
    required List<IconGlyph> glyphs,
    required FontGeneratorConfig config,
  }) {
    final sortedGlyphs = List<IconGlyph>.of(glyphs)
      ..sort((a, b) => a.codePoint.compareTo(b.codePoint));

    final transformed = <TransformedGlyph>[
      GlyphTransformer.buildNotdefGlyph(config),
      for (final g in sortedGlyphs)
        GlyphTransformer.transformIconGlyph(g, config),
    ];

    final fontBBox = GlyphTransformer.computeGlobalBBox(transformed);
    final nowSeconds = DateTime.now()
        .toUtc()
        .difference(DateTime.utc(1904, 1, 1))
        .inSeconds;

    final tables = <String, Uint8List>{
      'CFF ': CffTableBuilder.buildCffTable(transformed, config, fontBBox),
      'OS/2': SfntTableBuilder.buildOs2Table(transformed, config),
      'cmap': SfntTableBuilder.buildCmapTable(transformed),
      'head': SfntTableBuilder.buildHeadTable(config, fontBBox, nowSeconds),
      'hhea': SfntTableBuilder.buildHheaTable(transformed, config, fontBBox),
      'hmtx': SfntTableBuilder.buildHmtxTable(transformed),
      'maxp': SfntTableBuilder.buildMaxpTable(transformed.length),
      'name': SfntTableBuilder.buildNameTable(config),
      'post': SfntTableBuilder.buildPostTable(),
    };

    return SfntTableBuilder.assembleSfnt(tables);
  }
}
