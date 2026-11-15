import 'dart:math' as math;
import 'dart:typed_data';

import '../config.dart';
import '../svg/geometry.dart';
import 'cff_encoding.dart';
import 'glyph_model.dart';

/// Transforms parsed SVG paths into font coordinate space and compiles them
/// into CFF Type 2 charstrings.
abstract final class GlyphTransformer {
  static const double _defaultViewportSize = 24.0;
  static const double _notdefWidthRatio = 0.5;

  /// Builds the required `.notdef` glyph at glyph index 0.
  static TransformedGlyph buildNotdefGlyph(FontGeneratorConfig config) {
    final w = (config.unitsPerEm * _notdefWidthRatio).round();
    return TransformedGlyph(
      name: '.notdef',
      codePoint: 0,
      advanceWidth: w,
      bbox: const BoundingBox(0, 0, 0, 0),
      charstring: Uint8List.fromList(const [CffCharstringOp.endchar]),
    );
  }

  /// Transforms an [IconGlyph] into the font EM square and encodes its CFF charstring.
  static TransformedGlyph transformIconGlyph(
    IconGlyph glyph,
    FontGeneratorConfig config,
  ) {
    final rawVb = glyph.svg.viewBox;
    final vbWidth = rawVb.width > 0 ? rawVb.width : _defaultViewportSize;
    final vbHeight = rawVb.height > 0 ? rawVb.height : _defaultViewportSize;
    final em = config.unitsPerEm.toDouble();

    final scale = config.normalize
        ? math.min(em / vbWidth, em / vbHeight)
        : (em / vbHeight);

    final scaledWidth = vbWidth * scale;
    final scaledHeight = vbHeight * scale;
    final offsetX = config.normalize ? (em - scaledWidth) / 2.0 : 0.0;
    final offsetY = config.normalize ? (em - scaledHeight) / 2.0 : 0.0;
    final advanceWidth = config.normalize
        ? config.unitsPerEm
        : scaledWidth.round().clamp(1, 0xFFFF);

    double mapX(double svgX) => (svgX - rawVb.minX) * scale + offsetX;
    double mapY(double svgY) =>
        config.ascent - ((svgY - rawVb.minY) * scale + offsetY);

    final charstringBytes = <int>[];
    final boundsTracker = _GlyphBoundsTracker();
    var curX = 0;
    var curY = 0;

    for (final cmd in glyph.svg.commands) {
      switch (cmd.type) {
        case PathCommandType.moveTo:
          final tx = mapX(cmd.x).round();
          final ty = mapY(cmd.y).round();
          final dx = tx - curX;
          final dy = ty - curY;
          CffCodec.encodeCharstringInt(charstringBytes, dx);
          CffCodec.encodeCharstringInt(charstringBytes, dy);
          charstringBytes.add(CffCharstringOp.rmoveto);
          curX = tx;
          curY = ty;
          boundsTracker.addPoint(tx.toDouble(), ty.toDouble());

        case PathCommandType.lineTo:
          final tx = mapX(cmd.x).round();
          final ty = mapY(cmd.y).round();
          final dx = tx - curX;
          final dy = ty - curY;
          if (dx != 0 || dy != 0) {
            CffCodec.encodeCharstringInt(charstringBytes, dx);
            CffCodec.encodeCharstringInt(charstringBytes, dy);
            charstringBytes.add(CffCharstringOp.rlineto);
            curX = tx;
            curY = ty;
            boundsTracker.addPoint(tx.toDouble(), ty.toDouble());
          }

        case PathCommandType.cubicTo:
          final x0 = curX.toDouble();
          final y0 = curY.toDouble();
          final x1 = mapX(cmd.x1).round();
          final y1 = mapY(cmd.y1).round();
          final x2 = mapX(cmd.x2).round();
          final y2 = mapY(cmd.y2).round();
          final x = mapX(cmd.x).round();
          final y = mapY(cmd.y).round();

          final dx1 = x1 - curX;
          final dy1 = y1 - curY;
          final dx2 = x2 - x1;
          final dy2 = y2 - y1;
          final dx3 = x - x2;
          final dy3 = y - y2;

          if (dx1 != 0 ||
              dy1 != 0 ||
              dx2 != 0 ||
              dy2 != 0 ||
              dx3 != 0 ||
              dy3 != 0) {
            CffCodec.encodeCharstringInt(charstringBytes, dx1);
            CffCodec.encodeCharstringInt(charstringBytes, dy1);
            CffCodec.encodeCharstringInt(charstringBytes, dx2);
            CffCodec.encodeCharstringInt(charstringBytes, dy2);
            CffCodec.encodeCharstringInt(charstringBytes, dx3);
            CffCodec.encodeCharstringInt(charstringBytes, dy3);
            charstringBytes.add(CffCharstringOp.rrcurveto);

            curX = x;
            curY = y;
            boundsTracker.addCubic(
              x0,
              y0,
              x1.toDouble(),
              y1.toDouble(),
              x2.toDouble(),
              y2.toDouble(),
              x.toDouble(),
              y.toDouble(),
            );
          }

        case PathCommandType.close:
          // In CFF Type 2 charstrings, paths are implicitly closed on next
          // rmoveto or endchar.
          break;
      }
    }

    charstringBytes.add(CffCharstringOp.endchar);

    return TransformedGlyph(
      name: glyph.name,
      codePoint: glyph.codePoint,
      advanceWidth: advanceWidth,
      bbox: boundsTracker.toBoundingBox(),
      charstring: Uint8List.fromList(charstringBytes),
    );
  }

  /// Computes the union bounding box across all non-empty glyphs.
  static BoundingBox computeGlobalBBox(List<TransformedGlyph> glyphs) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final g in glyphs.skip(1)) {
      if (g.bbox.width == 0 && g.bbox.height == 0) continue;
      if (g.bbox.minX < minX) minX = g.bbox.minX;
      if (g.bbox.minY < minY) minY = g.bbox.minY;
      if (g.bbox.maxX > maxX) maxX = g.bbox.maxX;
      if (g.bbox.maxY > maxY) maxY = g.bbox.maxY;
    }

    if (!minX.isFinite) {
      return const BoundingBox(0, 0, 1000, 1000);
    }
    return BoundingBox(minX, minY, maxX, maxY);
  }
}

/// Tracks the exact bounding box of a glyph's points and cubic Bézier extrema.
class _GlyphBoundsTracker {
  static const double _rootEpsilon = 1e-9;

  double _minX = double.infinity;
  double _minY = double.infinity;
  double _maxX = double.negativeInfinity;
  double _maxY = double.negativeInfinity;

  void addPoint(double x, double y) {
    if (x < _minX) _minX = x;
    if (y < _minY) _minY = y;
    if (x > _maxX) _maxX = x;
    if (y > _maxY) _maxY = y;
  }

  void addCubic(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    addPoint(x0, y0);
    addPoint(x3, y3);
    for (final t in _cubicExtremaT(x0, x1, x2, x3)) {
      final xt = _evalCubic1D(x0, x1, x2, x3, t);
      final yt = _evalCubic1D(y0, y1, y2, y3, t);
      addPoint(xt, yt);
    }
    for (final t in _cubicExtremaT(y0, y1, y2, y3)) {
      final xt = _evalCubic1D(x0, x1, x2, x3, t);
      final yt = _evalCubic1D(y0, y1, y2, y3, t);
      addPoint(xt, yt);
    }
  }

  BoundingBox toBoundingBox() {
    if (!_minX.isFinite) {
      return const BoundingBox(0, 0, 0, 0);
    }
    return BoundingBox(
      _minX.floorToDouble(),
      _minY.floorToDouble(),
      _maxX.ceilToDouble(),
      _maxY.ceilToDouble(),
    );
  }

  /// Solves for $t \in (0, 1)$ where the derivative of the 1D cubic Bézier is 0.
  static List<double> _cubicExtremaT(
    double p0,
    double p1,
    double p2,
    double p3,
  ) {
    // B'(t) = 3 * (a*t^2 + b*t + c)
    final a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    final b = 2.0 * (p0 - 2.0 * p1 + p2);
    final c = p1 - p0;

    final roots = <double>[];
    if (a.abs() < _rootEpsilon) {
      if (b.abs() > _rootEpsilon) {
        final t = -c / b;
        if (t > 0.0 && t < 1.0) roots.add(t);
      }
      return roots;
    }

    final disc = b * b - 4.0 * a * c;
    if (disc < 0.0) return roots;
    final sqrtDisc = math.sqrt(disc);
    final t1 = (-b + sqrtDisc) / (2.0 * a);
    final t2 = (-b - sqrtDisc) / (2.0 * a);
    if (t1 > 0.0 && t1 < 1.0) roots.add(t1);
    if (t2 > 0.0 && t2 < 1.0 && (t2 - t1).abs() > _rootEpsilon) roots.add(t2);
    return roots;
  }

  static double _evalCubic1D(
    double p0,
    double p1,
    double p2,
    double p3,
    double t,
  ) {
    final mt = 1.0 - t;
    return mt * mt * mt * p0 +
        3.0 * mt * mt * t * p1 +
        3.0 * mt * t * t * p2 +
        t * t * t * p3;
  }
}
