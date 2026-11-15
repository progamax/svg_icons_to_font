import 'dart:typed_data';

import '../svg/geometry.dart';

/// Represents a single icon glyph to be written into the OpenType font.
class IconGlyph {
  const IconGlyph({
    required this.name,
    required this.codePoint,
    required this.svg,
  });

  /// Identifier name of the icon (derived from filename).
  final String name;

  /// Unicode codepoint assigned to the icon.
  final int codePoint;

  /// Parsed SVG paths and viewBox.
  final ParsedSvg svg;
}

/// Internal representation of a glyph after coordinate transformation into the
/// font EM square and CFF Type 2 charstring compilation.
class TransformedGlyph {
  const TransformedGlyph({
    required this.name,
    required this.codePoint,
    required this.advanceWidth,
    required this.bbox,
    required this.charstring,
  });

  final String name;
  final int codePoint;
  final int advanceWidth;
  final BoundingBox bbox;
  final Uint8List charstring;

  int get leftSideBearing => bbox.minX.round();
}
