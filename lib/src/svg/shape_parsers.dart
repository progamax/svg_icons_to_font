import 'dart:math' as math;
import 'package:xml/xml.dart';

import 'geometry.dart';
import 'path_data_parser.dart';

/// Converts basic SVG geometric shape elements (`<rect>`, `<circle>`,
/// `<ellipse>`, `<polygon>`, `<polyline>`, `<line>`) into [PathCommand] lists.
abstract final class SvgShapeParsers {
  /// Parses a numeric dimension attribute (stripping units like `px` or `%`).
  static double? parseDimension(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[a-zA-Z%]+'), '').trim();
    return double.tryParse(cleaned);
  }

  /// Converts a `<rect>` element (including optional rounded corners `rx`, `ry`)
  /// into normalized path commands.
  static List<PathCommand> parseRect(XmlElement el) {
    final x = parseDimension(el.getAttribute('x')) ?? 0.0;
    final y = parseDimension(el.getAttribute('y')) ?? 0.0;
    final w = parseDimension(el.getAttribute('width')) ?? 0.0;
    final h = parseDimension(el.getAttribute('height')) ?? 0.0;
    if (w <= 0 || h <= 0) return const [];

    var rx = parseDimension(el.getAttribute('rx'));
    var ry = parseDimension(el.getAttribute('ry'));
    rx ??= ry ?? 0.0;
    ry ??= rx;

    rx = math.min(rx, w / 2.0);
    ry = math.min(ry, h / 2.0);

    if (rx <= 0 || ry <= 0) {
      return [
        PathCommand.moveTo(x, y),
        PathCommand.lineTo(x + w, y),
        PathCommand.lineTo(x + w, y + h),
        PathCommand.lineTo(x, y + h),
        const PathCommand.close(),
      ];
    }

    final ox = rx * bezierCircleKappa;
    final oy = ry * bezierCircleKappa;

    return [
      PathCommand.moveTo(x + rx, y),
      PathCommand.lineTo(x + w - rx, y),
      PathCommand.cubicTo(
        x + w - rx + ox,
        y,
        x + w,
        y + ry - oy,
        x + w,
        y + ry,
      ),
      PathCommand.lineTo(x + w, y + h - ry),
      PathCommand.cubicTo(
        x + w,
        y + h - ry + oy,
        x + w - rx + ox,
        y + h,
        x + w - rx,
        y + h,
      ),
      PathCommand.lineTo(x + rx, y + h),
      PathCommand.cubicTo(
        x + rx - ox,
        y + h,
        x,
        y + h - ry + oy,
        x,
        y + h - ry,
      ),
      PathCommand.lineTo(x, y + ry),
      PathCommand.cubicTo(
        x,
        y + ry - oy,
        x + rx - ox,
        y,
        x + rx,
        y,
      ),
      const PathCommand.close(),
    ];
  }

  /// Converts a `<circle>` element into 4 cubic Bézier segments.
  static List<PathCommand> parseCircle(XmlElement el) {
    final cx = parseDimension(el.getAttribute('cx')) ?? 0.0;
    final cy = parseDimension(el.getAttribute('cy')) ?? 0.0;
    final r = parseDimension(el.getAttribute('r')) ?? 0.0;
    if (r <= 0) return const [];
    return _ellipseCommands(cx, cy, r, r);
  }

  /// Converts an `<ellipse>` element into 4 cubic Bézier segments.
  static List<PathCommand> parseEllipse(XmlElement el) {
    final cx = parseDimension(el.getAttribute('cx')) ?? 0.0;
    final cy = parseDimension(el.getAttribute('cy')) ?? 0.0;
    final rx = parseDimension(el.getAttribute('rx')) ?? 0.0;
    final ry = parseDimension(el.getAttribute('ry')) ?? 0.0;
    if (rx <= 0 || ry <= 0) return const [];
    return _ellipseCommands(cx, cy, rx, ry);
  }

  static List<PathCommand> _ellipseCommands(
    double cx,
    double cy,
    double rx,
    double ry,
  ) {
    final ox = rx * bezierCircleKappa;
    final oy = ry * bezierCircleKappa;

    return [
      PathCommand.moveTo(cx + rx, cy),
      PathCommand.cubicTo(cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry),
      PathCommand.cubicTo(cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy),
      PathCommand.cubicTo(cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry),
      PathCommand.cubicTo(cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy),
      const PathCommand.close(),
    ];
  }

  /// Converts a `<polygon>` ([close] = `true`) or `<polyline>` ([close] = `false`)
  /// element into normalized path commands.
  static List<PathCommand> parsePoly(XmlElement el, {required bool close}) {
    final pointsAttr = el.getAttribute('points');
    if (pointsAttr == null || pointsAttr.trim().isEmpty) return const [];
    final nums = SvgPathDataParser.tokenizeNumbers(pointsAttr);
    if (nums.length < 4) return const [];

    final cmds = <PathCommand>[PathCommand.moveTo(nums[0], nums[1])];
    for (var i = 2; i + 1 < nums.length; i += 2) {
      cmds.add(PathCommand.lineTo(nums[i], nums[i + 1]));
    }
    if (close) {
      cmds.add(const PathCommand.close());
    }
    return cmds;
  }

  /// Converts a `<line>` element into a `moveTo` + `lineTo` pair.
  static List<PathCommand> parseLine(XmlElement el) {
    final x1 = parseDimension(el.getAttribute('x1')) ?? 0.0;
    final y1 = parseDimension(el.getAttribute('y1')) ?? 0.0;
    final x2 = parseDimension(el.getAttribute('x2')) ?? 0.0;
    final y2 = parseDimension(el.getAttribute('y2')) ?? 0.0;
    return [
      PathCommand.moveTo(x1, y1),
      PathCommand.lineTo(x2, y2),
    ];
  }
}
