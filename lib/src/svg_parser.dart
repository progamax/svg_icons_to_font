import 'dart:math' as math;
import 'package:xml/xml.dart';

/// A 2D point in Cartesian space.
class Point2D {
  const Point2D(this.x, this.y);

  final double x;
  final double y;

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);
  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// A 2D affine transformation matrix:
/// ```
/// [ a  c  e ]
/// [ b  d  f ]
/// [ 0  0  1 ]
/// ```
class Matrix2D {
  const Matrix2D(this.a, this.b, this.c, this.d, this.e, this.f);

  /// Creates a translation matrix.
  factory Matrix2D.translation(double tx, [double ty = 0.0]) =>
      Matrix2D(1, 0, 0, 1, tx, ty);

  /// Creates a scaling matrix.
  factory Matrix2D.scaling(double sx, [double? sy]) =>
      Matrix2D(sx, 0, 0, sy ?? sx, 0, 0);

  /// Creates a rotation matrix (angle in degrees, optional center `cx`, `cy`).
  factory Matrix2D.rotation(double angleDeg, [double cx = 0.0, double cy = 0.0]) {
    final rad = angleDeg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final r = Matrix2D(cosA, sinA, -sinA, cosA, 0, 0);
    if (cx == 0.0 && cy == 0.0) return r;
    return Matrix2D.translation(cx, cy) * r * Matrix2D.translation(-cx, -cy);
  }

  /// Creates a skewX matrix (angle in degrees).
  factory Matrix2D.skewX(double angleDeg) {
    final tanA = math.tan(angleDeg * math.pi / 180.0);
    return Matrix2D(1, 0, tanA, 1, 0, 0);
  }

  /// Creates a skewY matrix (angle in degrees).
  factory Matrix2D.skewY(double angleDeg) {
    final tanA = math.tan(angleDeg * math.pi / 180.0);
    return Matrix2D(1, tanA, 0, 1, 0, 0);
  }

  /// Identity matrix.
  static const Matrix2D identity = Matrix2D(1, 0, 0, 1, 0, 0);

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  bool get isIdentity =>
      a == 1.0 && b == 0.0 && c == 0.0 && d == 1.0 && e == 0.0 && f == 0.0;

  /// Multiplies this matrix by [other] (`this * other`).
  Matrix2D operator *(Matrix2D other) => Matrix2D(
        a * other.a + c * other.b,
        b * other.a + d * other.b,
        a * other.c + c * other.d,
        b * other.c + d * other.d,
        a * other.e + c * other.f + e,
        b * other.e + d * other.f + f,
      );

  /// Applies this affine transformation to a point `(x, y)`.
  Point2D transformPoint(double x, double y) => Point2D(
        a * x + c * y + e,
        b * x + d * y + f,
      );

  /// Applies this affine transformation to a [PathCommand].
  PathCommand transformCommand(PathCommand cmd) {
    if (isIdentity) return cmd;
    switch (cmd.type) {
      case PathCommandType.moveTo:
        final p = transformPoint(cmd.x, cmd.y);
        return PathCommand.moveTo(p.x, p.y);
      case PathCommandType.lineTo:
        final p = transformPoint(cmd.x, cmd.y);
        return PathCommand.lineTo(p.x, p.y);
      case PathCommandType.cubicTo:
        final p1 = transformPoint(cmd.x1, cmd.y1);
        final p2 = transformPoint(cmd.x2, cmd.y2);
        final p = transformPoint(cmd.x, cmd.y);
        return PathCommand.cubicTo(p1.x, p1.y, p2.x, p2.y, p.x, p.y);
      case PathCommandType.close:
        return cmd;
    }
  }
}

/// Types of normalized path commands used to build CFF outlines.
enum PathCommandType {
  moveTo,
  lineTo,
  cubicTo,
  close,
}

/// A normalized path command in absolute coordinates (moveTo, lineTo, cubicTo, close).
class PathCommand {
  const PathCommand.moveTo(this.x, this.y)
      : type = PathCommandType.moveTo,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;

  const PathCommand.lineTo(this.x, this.y)
      : type = PathCommandType.lineTo,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;

  const PathCommand.cubicTo(
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.x,
    this.y,
  ) : type = PathCommandType.cubicTo;

  const PathCommand.close()
      : type = PathCommandType.close,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0,
        x = 0,
        y = 0;

  final PathCommandType type;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double x;
  final double y;
}

/// Bounding box of a glyph or SVG viewport.
class BoundingBox {
  const BoundingBox(this.minX, this.minY, this.maxX, this.maxY);

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
}

/// Represents a parsed SVG document with its viewBox and normalized path commands.
class ParsedSvg {
  const ParsedSvg({
    required this.viewBox,
    required this.commands,
  });

  final BoundingBox viewBox;
  final List<PathCommand> commands;
}

/// Parses an SVG XML string into normalized absolute [PathCommand]s.
class SvgParser {
  /// Parses the given SVG XML string.
  static ParsedSvg parse(String svgContent) {
    final document = XmlDocument.parse(svgContent);
    final svgElement = document.findAllElements('svg').firstOrNull;
    if (svgElement == null) {
      throw const FormatException('Missing <svg> root element.');
    }

    final viewBox = _parseViewBox(svgElement);
    final commands = <PathCommand>[];

    _extractElementCommands(svgElement, commands, Matrix2D.identity);

    return ParsedSvg(viewBox: viewBox, commands: commands);
  }

  /// Parses an SVG `transform` attribute string into a [Matrix2D].
  ///
  /// Supports `translate`, `scale`, `rotate`, `skewX`, `skewY`, and `matrix`.
  static Matrix2D parseTransform(String? transformAttr) {
    if (transformAttr == null || transformAttr.trim().isEmpty) {
      return Matrix2D.identity;
    }

    final fnRegex = RegExp(
      r'(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)',
      caseSensitive: false,
    );

    var result = Matrix2D.identity;
    for (final match in fnRegex.allMatches(transformAttr)) {
      final name = match.group(1)!.toLowerCase();
      final args = _tokenizeNumbers(match.group(2)!);
      if (args.isEmpty) continue;

      Matrix2D m = Matrix2D.identity;
      switch (name) {
        case 'translate':
          final tx = args[0];
          final ty = args.length > 1 ? args[1] : 0.0;
          m = Matrix2D.translation(tx, ty);
        case 'scale':
          final sx = args[0];
          final sy = args.length > 1 ? args[1] : sx;
          m = Matrix2D.scaling(sx, sy);
        case 'rotate':
          final angle = args[0];
          final cx = args.length >= 3 ? args[1] : 0.0;
          final cy = args.length >= 3 ? args[2] : 0.0;
          m = Matrix2D.rotation(angle, cx, cy);
        case 'skewx':
          m = Matrix2D.skewX(args[0]);
        case 'skewy':
          m = Matrix2D.skewY(args[0]);
        case 'matrix':
          if (args.length >= 6) {
            m = Matrix2D(
              args[0],
              args[1],
              args[2],
              args[3],
              args[4],
              args[5],
            );
          }
      }
      result = result * m;
    }

    return result;
  }

  static BoundingBox _parseViewBox(XmlElement svgElement) {
    final viewBoxAttr = svgElement.getAttribute('viewBox');
    if (viewBoxAttr != null && viewBoxAttr.trim().isNotEmpty) {
      final parts = viewBoxAttr
          .trim()
          .split(RegExp(r'[\s,]+'))
          .map(double.tryParse)
          .whereType<double>()
          .toList();
      if (parts.length == 4 && parts[2] > 0 && parts[3] > 0) {
        return BoundingBox(
          parts[0],
          parts[1],
          parts[0] + parts[2],
          parts[1] + parts[3],
        );
      }
    }

    final width = _parseDimension(svgElement.getAttribute('width')) ?? 24.0;
    final height = _parseDimension(svgElement.getAttribute('height')) ?? 24.0;
    return BoundingBox(0, 0, width, height);
  }

  static double? _parseDimension(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[a-zA-Z%]+'), '').trim();
    return double.tryParse(cleaned);
  }

  static void _extractElementCommands(
    XmlElement element,
    List<PathCommand> out,
    Matrix2D parentTransform,
  ) {
    final tag = element.name.local.toLowerCase();
    if (tag == 'defs' || tag == 'clippath' || tag == 'mask' || tag == 'style') {
      return;
    }

    final localTransform = parseTransform(element.getAttribute('transform'));
    final currentTransform = parentTransform * localTransform;

    var localCommands = const <PathCommand>[];
    switch (tag) {
      case 'path':
        final d = element.getAttribute('d');
        if (d != null && d.trim().isNotEmpty) {
          localCommands = parsePathData(d);
        }
      case 'rect':
        localCommands = _parseRect(element);
      case 'circle':
        localCommands = _parseCircle(element);
      case 'ellipse':
        localCommands = _parseEllipse(element);
      case 'polygon':
        localCommands = _parsePoly(element, close: true);
      case 'polyline':
        localCommands = _parsePoly(element, close: false);
      case 'line':
        localCommands = _parseLine(element);
    }

    if (localCommands.isNotEmpty) {
      if (currentTransform.isIdentity) {
        out.addAll(localCommands);
      } else {
        for (final cmd in localCommands) {
          out.add(currentTransform.transformCommand(cmd));
        }
      }
    }

    for (final child in element.children.whereType<XmlElement>()) {
      _extractElementCommands(child, out, currentTransform);
    }
  }

  static List<PathCommand> _parseRect(XmlElement el) {
    final x = _parseDimension(el.getAttribute('x')) ?? 0.0;
    final y = _parseDimension(el.getAttribute('y')) ?? 0.0;
    final w = _parseDimension(el.getAttribute('width')) ?? 0.0;
    final h = _parseDimension(el.getAttribute('height')) ?? 0.0;
    if (w <= 0 || h <= 0) return const [];

    var rx = _parseDimension(el.getAttribute('rx'));
    var ry = _parseDimension(el.getAttribute('ry'));
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

    const k = 0.5522847498307936;
    final ox = rx * k;
    final oy = ry * k;

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

  static List<PathCommand> _parseCircle(XmlElement el) {
    final cx = _parseDimension(el.getAttribute('cx')) ?? 0.0;
    final cy = _parseDimension(el.getAttribute('cy')) ?? 0.0;
    final r = _parseDimension(el.getAttribute('r')) ?? 0.0;
    if (r <= 0) return const [];
    return _ellipseCommands(cx, cy, r, r);
  }

  static List<PathCommand> _parseEllipse(XmlElement el) {
    final cx = _parseDimension(el.getAttribute('cx')) ?? 0.0;
    final cy = _parseDimension(el.getAttribute('cy')) ?? 0.0;
    final rx = _parseDimension(el.getAttribute('rx')) ?? 0.0;
    final ry = _parseDimension(el.getAttribute('ry')) ?? 0.0;
    if (rx <= 0 || ry <= 0) return const [];
    return _ellipseCommands(cx, cy, rx, ry);
  }

  static List<PathCommand> _ellipseCommands(
    double cx,
    double cy,
    double rx,
    double ry,
  ) {
    const k = 0.5522847498307936; // 4 * (sqrt(2) - 1) / 3
    final ox = rx * k;
    final oy = ry * k;

    return [
      PathCommand.moveTo(cx + rx, cy),
      PathCommand.cubicTo(cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry),
      PathCommand.cubicTo(cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy),
      PathCommand.cubicTo(cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry),
      PathCommand.cubicTo(cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy),
      const PathCommand.close(),
    ];
  }

  static List<PathCommand> _parsePoly(XmlElement el, {required bool close}) {
    final pointsAttr = el.getAttribute('points');
    if (pointsAttr == null || pointsAttr.trim().isEmpty) return const [];
    final nums = _tokenizeNumbers(pointsAttr);
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

  static List<PathCommand> _parseLine(XmlElement el) {
    final x1 = _parseDimension(el.getAttribute('x1')) ?? 0.0;
    final y1 = _parseDimension(el.getAttribute('y1')) ?? 0.0;
    final x2 = _parseDimension(el.getAttribute('x2')) ?? 0.0;
    final y2 = _parseDimension(el.getAttribute('y2')) ?? 0.0;
    return [
      PathCommand.moveTo(x1, y1),
      PathCommand.lineTo(x2, y2),
    ];
  }

  /// Parses an SVG `d` path attribute into normalized absolute [PathCommand]s.
  static List<PathCommand> parsePathData(String d) {
    final tokenRegex = RegExp(
      r'([MmZzLlHhVvCcSsQqTtAa])|([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)',
    );
    final tokens = tokenRegex.allMatches(d).map((m) => m.group(0)!).toList();

    final commands = <PathCommand>[];
    var curX = 0.0;
    var curY = 0.0;
    var startX = 0.0;
    var startY = 0.0;
    double? lastCubicCtrlX;
    double? lastCubicCtrlY;
    double? lastQuadCtrlX;
    double? lastQuadCtrlY;

    var i = 0;
    String? currentCmd;

    bool hasNextNumber() {
      if (i >= tokens.length) return false;
      final t = tokens[i];
      return !RegExp(r'^[MmZzLlHhVvCcSsQqTtAa]$').hasMatch(t);
    }

    double nextNumber() => double.parse(tokens[i++]);

    while (i < tokens.length) {
      final token = tokens[i];
      if (RegExp(r'^[MmZzLlHhVvCcSsQqTtAa]$').hasMatch(token)) {
        currentCmd = token;
        i++;
      } else if (currentCmd == null) {
        i++;
        continue;
      }

      switch (currentCmd) {
        case 'M':
        case 'm':
          final isRel = currentCmd == 'm';
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.moveTo(x, y));
          curX = x;
          curY = y;
          startX = x;
          startY = y;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;
          currentCmd = isRel ? 'l' : 'L';

        case 'L':
        case 'l':
          final isRel = currentCmd == 'l';
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.lineTo(x, y));
          curX = x;
          curY = y;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;

        case 'H':
        case 'h':
          final isRel = currentCmd == 'h';
          final x = nextNumber() + (isRel ? curX : 0.0);
          commands.add(PathCommand.lineTo(x, curY));
          curX = x;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;

        case 'V':
        case 'v':
          final isRel = currentCmd == 'v';
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.lineTo(curX, y));
          curY = y;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;

        case 'C':
        case 'c':
          final isRel = currentCmd == 'c';
          final x1 = nextNumber() + (isRel ? curX : 0.0);
          final y1 = nextNumber() + (isRel ? curY : 0.0);
          final x2 = nextNumber() + (isRel ? curX : 0.0);
          final y2 = nextNumber() + (isRel ? curY : 0.0);
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.cubicTo(x1, y1, x2, y2, x, y));
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;
          curX = x;
          curY = y;

        case 'S':
        case 's':
          final isRel = currentCmd == 's';
          final x1 =
              lastCubicCtrlX != null ? 2 * curX - lastCubicCtrlX : curX;
          final y1 =
              lastCubicCtrlY != null ? 2 * curY - lastCubicCtrlY : curY;
          final x2 = nextNumber() + (isRel ? curX : 0.0);
          final y2 = nextNumber() + (isRel ? curY : 0.0);
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.cubicTo(x1, y1, x2, y2, x, y));
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;
          curX = x;
          curY = y;

        case 'Q':
        case 'q':
          final isRel = currentCmd == 'q';
          final qx1 = nextNumber() + (isRel ? curX : 0.0);
          final qy1 = nextNumber() + (isRel ? curY : 0.0);
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          final c1x = curX + (2.0 / 3.0) * (qx1 - curX);
          final c1y = curY + (2.0 / 3.0) * (qy1 - curY);
          final c2x = x + (2.0 / 3.0) * (qx1 - x);
          final c2y = y + (2.0 / 3.0) * (qy1 - y);
          commands.add(PathCommand.cubicTo(c1x, c1y, c2x, c2y, x, y));
          lastQuadCtrlX = qx1;
          lastQuadCtrlY = qy1;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          curX = x;
          curY = y;

        case 'T':
        case 't':
          final isRel = currentCmd == 't';
          final qx1 =
              lastQuadCtrlX != null ? 2 * curX - lastQuadCtrlX : curX;
          final qy1 =
              lastQuadCtrlY != null ? 2 * curY - lastQuadCtrlY : curY;
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          final c1x = curX + (2.0 / 3.0) * (qx1 - curX);
          final c1y = curY + (2.0 / 3.0) * (qy1 - curY);
          final c2x = x + (2.0 / 3.0) * (qx1 - x);
          final c2y = y + (2.0 / 3.0) * (qy1 - y);
          commands.add(PathCommand.cubicTo(c1x, c1y, c2x, c2y, x, y));
          lastQuadCtrlX = qx1;
          lastQuadCtrlY = qy1;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          curX = x;
          curY = y;

        case 'A':
        case 'a':
          final isRel = currentCmd == 'a';
          final rx = nextNumber();
          final ry = nextNumber();
          final xAxisRotation = nextNumber();
          final largeArcFlag = nextNumber() != 0.0;
          final sweepFlag = nextNumber() != 0.0;
          final x = nextNumber() + (isRel ? curX : 0.0);
          final y = nextNumber() + (isRel ? curY : 0.0);
          commands.addAll(
            _arcToCubic(
              curX,
              curY,
              rx,
              ry,
              xAxisRotation,
              largeArcFlag,
              sweepFlag,
              x,
              y,
            ),
          );
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;
          curX = x;
          curY = y;

        case 'Z':
        case 'z':
          commands.add(const PathCommand.close());
          curX = startX;
          curY = startY;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;
          if (!hasNextNumber()) {
            currentCmd = null;
          }
      }
    }

    return commands;
  }

  static List<double> _tokenizeNumbers(String input) {
    final regex = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
    return regex.allMatches(input).map((m) => double.parse(m.group(0)!)).toList();
  }

  /// Approximates an SVG elliptical arc with one or more cubic Bézier segments.
  static List<PathCommand> _arcToCubic(
    double x1,
    double y1,
    double rxIn,
    double ryIn,
    double angleDeg,
    bool largeArcFlag,
    bool sweepFlag,
    double x2,
    double y2,
  ) {
    if (x1 == x2 && y1 == y2) return const [];
    var rx = rxIn.abs();
    var ry = ryIn.abs();
    if (rx == 0 || ry == 0) {
      return [PathCommand.lineTo(x2, y2)];
    }

    final phi = angleDeg * math.pi / 180.0;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);

    final dx2 = (x1 - x2) / 2.0;
    final dy2 = (y1 - y2) / 2.0;
    final x1p = cosPhi * dx2 + sinPhi * dy2;
    final y1p = -sinPhi * dx2 + cosPhi * dy2;

    var rxSq = rx * rx;
    var rySq = ry * ry;
    final x1pSq = x1p * x1p;
    final y1pSq = y1p * y1p;

    final radiiCheck = x1pSq / rxSq + y1pSq / rySq;
    if (radiiCheck > 1.0) {
      final scale = math.sqrt(radiiCheck);
      rx *= scale;
      ry *= scale;
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final sign = (largeArcFlag == sweepFlag) ? -1.0 : 1.0;
    final sq = ((rxSq * rySq) - (rxSq * y1pSq) - (rySq * x1pSq)) /
        ((rxSq * y1pSq) + (rySq * x1pSq));
    final coef = sign * math.sqrt(math.max(0.0, sq));
    final cxp = coef * ((rx * y1p) / ry);
    final cyp = coef * (-(ry * x1p) / rx);

    final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0;
    final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0;

    double vectorAngle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
      final cosVal = (dot / len).clamp(-1.0, 1.0);
      final angle = math.acos(cosVal);
      return (ux * vy - uy * vx < 0) ? -angle : angle;
    }

    final theta1 = vectorAngle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var dTheta = vectorAngle(
      (x1p - cxp) / rx,
      (y1p - cyp) / ry,
      (-x1p - cxp) / rx,
      (-y1p - cyp) / ry,
    );

    if (!sweepFlag && dTheta > 0) {
      dTheta -= 2.0 * math.pi;
    } else if (sweepFlag && dTheta < 0) {
      dTheta += 2.0 * math.pi;
    }

    final segments = (dTheta.abs() / (math.pi / 2.0)).ceil();
    final delta = dTheta / segments;
    final alpha = (4.0 / 3.0) * math.tan(delta / 4.0);

    final result = <PathCommand>[];
    for (var i = 0; i < segments; i++) {
      final t1 = theta1 + i * delta;
      final t2 = t1 + delta;

      final cosT1 = math.cos(t1);
      final sinT1 = math.sin(t1);
      final cosT2 = math.cos(t2);
      final sinT2 = math.sin(t2);

      final e1x = cosT1 - alpha * sinT1;
      final e1y = sinT1 + alpha * cosT1;
      final e2x = cosT2 + alpha * sinT2;
      final e2y = sinT2 - alpha * cosT2;

      Point2D mapPoint(double px, double py) {
        final sx = px * rx;
        final sy = py * ry;
        return Point2D(
          cosPhi * sx - sinPhi * sy + cx,
          sinPhi * sx + cosPhi * sy + cy,
        );
      }

      final c1 = mapPoint(e1x, e1y);
      final c2 = mapPoint(e2x, e2y);
      final end = mapPoint(cosT2, sinT2);

      result.add(PathCommand.cubicTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y));
    }

    return result;
  }
}
