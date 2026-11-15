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
  factory Matrix2D.rotation(
    double angleDeg, [
    double cx = 0.0,
    double cy = 0.0,
  ]) {
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

/// Inherited SVG presentation style attributes for an element.
class _SvgStyle {
  const _SvgStyle({
    this.fill = 'black',
    this.stroke = 'none',
    this.strokeWidth = 1.0,
    this.strokeLinecap = 'butt',
    this.strokeLinejoin = 'miter',
    this.fillRule = 'nonzero',
    this.hidden = false,
  });

  final String fill;
  final String stroke;
  final double strokeWidth;
  final String strokeLinecap;
  final String strokeLinejoin;
  final String fillRule;
  final bool hidden;

  bool get hasFill => fill != 'none' && fill != 'transparent';
  bool get hasStroke =>
      stroke != 'none' && stroke != 'transparent' && strokeWidth > 0;

  _SvgStyle resolve(XmlElement element) {
    final inlineStyle = _parseInlineStyle(element.getAttribute('style'));

    String? readProp(String name) =>
        inlineStyle[name] ?? element.getAttribute(name)?.trim();

    final display = readProp('display')?.toLowerCase();
    final visibility = readProp('visibility')?.toLowerCase();
    final opacityStr = readProp('opacity');
    final opacity =
        opacityStr != null ? double.tryParse(opacityStr) : null;

    final isHidden = hidden ||
        display == 'none' ||
        visibility == 'hidden' ||
        visibility == 'collapse' ||
        (opacity != null && opacity <= 0.0);

    final fillAttr = readProp('fill')?.toLowerCase();
    final fillOpacityStr = readProp('fill-opacity');
    final fillOpacity =
        fillOpacityStr != null ? double.tryParse(fillOpacityStr) : null;

    var resolvedFill = fillAttr ?? fill;
    if (fillOpacity != null && fillOpacity <= 0.0) {
      resolvedFill = 'none';
    }

    final strokeAttr = readProp('stroke')?.toLowerCase();
    final strokeOpacityStr = readProp('stroke-opacity');
    final strokeOpacity =
        strokeOpacityStr != null ? double.tryParse(strokeOpacityStr) : null;

    var resolvedStroke = strokeAttr ?? stroke;
    if (strokeOpacity != null && strokeOpacity <= 0.0) {
      resolvedStroke = 'none';
    }

    final strokeWidthAttr = readProp('stroke-width');
    final resolvedStrokeWidth = strokeWidthAttr != null
        ? (SvgParser._parseDimension(strokeWidthAttr) ?? strokeWidth)
        : strokeWidth;

    final resolvedLinecap =
        readProp('stroke-linecap')?.toLowerCase() ?? strokeLinecap;
    final resolvedLinejoin =
        readProp('stroke-linejoin')?.toLowerCase() ?? strokeLinejoin;
    final resolvedFillRule =
        readProp('fill-rule')?.toLowerCase() ?? fillRule;

    return _SvgStyle(
      fill: resolvedFill,
      stroke: resolvedStroke,
      strokeWidth: resolvedStrokeWidth,
      strokeLinecap: resolvedLinecap,
      strokeLinejoin: resolvedLinejoin,
      fillRule: resolvedFillRule,
      hidden: isHidden,
    );
  }

  static Map<String, String> _parseInlineStyle(String? styleAttr) {
    if (styleAttr == null || styleAttr.trim().isEmpty) return const {};
    final map = <String, String>{};
    for (final decl in styleAttr.split(';')) {
      final colon = decl.indexOf(':');
      if (colon <= 0) continue;
      final key = decl.substring(0, colon).trim().toLowerCase();
      final value = decl.substring(colon + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        map[key] = value;
      }
    }
    return map;
  }
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

    _extractElementCommands(
      svgElement,
      commands,
      Matrix2D.identity,
      const _SvgStyle(),
    );

    final normalizedCommands = _normalizeContoursWinding(commands);

    return ParsedSvg(viewBox: viewBox, commands: normalizedCommands);
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

    final rawW = _parseDimension(svgElement.getAttribute('width'));
    final rawH = _parseDimension(svgElement.getAttribute('height'));
    final width = (rawW != null && rawW > 0) ? rawW : 24.0;
    final height = (rawH != null && rawH > 0) ? rawH : 24.0;
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
    _SvgStyle parentStyle,
  ) {
    final tag = element.name.local.toLowerCase();
    if (tag == 'defs' ||
        tag == 'clippath' ||
        tag == 'mask' ||
        tag == 'style' ||
        tag == 'title' ||
        tag == 'desc' ||
        tag == 'metadata') {
      return;
    }

    final currentStyle = parentStyle.resolve(element);
    if (currentStyle.hidden) {
      return;
    }

    final localTransform = parseTransform(element.getAttribute('transform'));
    final currentTransform = parentTransform * localTransform;

    var rawGeometry = const <PathCommand>[];
    switch (tag) {
      case 'path':
        final d = element.getAttribute('d');
        if (d != null && d.trim().isNotEmpty) {
          rawGeometry = parsePathData(d);
        }
      case 'rect':
        rawGeometry = _parseRect(element);
      case 'circle':
        rawGeometry = _parseCircle(element);
      case 'ellipse':
        rawGeometry = _parseEllipse(element);
      case 'polygon':
        rawGeometry = _parsePoly(element, close: true);
      case 'polyline':
        rawGeometry = _parsePoly(element, close: false);
      case 'line':
        rawGeometry = _parseLine(element);
    }

    if (rawGeometry.isNotEmpty) {
      final emittedCommands = <PathCommand>[];

      // <line> never has a fill area; other shapes emit fill if fill != 'none'
      if (tag != 'line' && currentStyle.hasFill) {
        if (tag == 'polyline') {
          emittedCommands.addAll(_closeOpenSubpaths(rawGeometry));
        } else {
          emittedCommands.addAll(rawGeometry);
        }
      }

      // If the element has a visible stroke (e.g. <line>, stroke icons, etc.),
      // expand the stroke into filled closed contours.
      if (currentStyle.hasStroke ||
          (tag == 'line' && !currentStyle.hasStroke && currentStyle.fill != 'none')) {
        final effectiveWidth =
            currentStyle.strokeWidth > 0 ? currentStyle.strokeWidth : 1.0;
        emittedCommands.addAll(
          _strokeToFillCommands(
            rawGeometry,
            strokeWidth: effectiveWidth,
            lineCap: currentStyle.strokeLinecap,
            lineJoin: currentStyle.strokeLinejoin,
          ),
        );
      }

      if (emittedCommands.isNotEmpty) {
        if (currentTransform.isIdentity) {
          out.addAll(emittedCommands);
        } else {
          for (final cmd in emittedCommands) {
            out.add(currentTransform.transformCommand(cmd));
          }
        }
      }
    }

    for (final child in element.children.whereType<XmlElement>()) {
      _extractElementCommands(child, out, currentTransform, currentStyle);
    }
  }

  static List<PathCommand> _closeOpenSubpaths(List<PathCommand> commands) {
    final result = <PathCommand>[];
    var hasOpenSubpath = false;
    for (final cmd in commands) {
      if (cmd.type == PathCommandType.moveTo) {
        if (hasOpenSubpath) {
          result.add(const PathCommand.close());
        }
        hasOpenSubpath = true;
      } else if (cmd.type == PathCommandType.close) {
        hasOpenSubpath = false;
      }
      result.add(cmd);
    }
    if (hasOpenSubpath) {
      result.add(const PathCommand.close());
    }
    return result;
  }

  /// Expands stroked path commands into closed filled outlines of width [strokeWidth].
  static List<PathCommand> _strokeToFillCommands(
    List<PathCommand> commands, {
    required double strokeWidth,
    String lineCap = 'butt',
    String lineJoin = 'miter',
  }) {
    final halfW = strokeWidth / 2.0;
    if (halfW <= 0) return const [];

    // Flatten each subpath into a list of 2D points + closed flag
    final subpaths = <_FlattenedSubpath>[];
    var currentPts = <Point2D>[];
    var startPt = const Point2D(0, 0);
    var curPt = const Point2D(0, 0);

    void flushSubpath({required bool closed}) {
      if (currentPts.length >= 2) {
        subpaths.add(_FlattenedSubpath(List<Point2D>.of(currentPts), closed));
      }
      currentPts = <Point2D>[];
    }

    for (final cmd in commands) {
      switch (cmd.type) {
        case PathCommandType.moveTo:
          flushSubpath(closed: false);
          curPt = Point2D(cmd.x, cmd.y);
          startPt = curPt;
          currentPts.add(curPt);
        case PathCommandType.lineTo:
          final nextPt = Point2D(cmd.x, cmd.y);
          if (_dist(curPt, nextPt) > 1e-5) {
            currentPts.add(nextPt);
            curPt = nextPt;
          }
        case PathCommandType.cubicTo:
          const steps = 12;
          final p0 = curPt;
          final p1 = Point2D(cmd.x1, cmd.y1);
          final p2 = Point2D(cmd.x2, cmd.y2);
          final p3 = Point2D(cmd.x, cmd.y);
          for (var s = 1; s <= steps; s++) {
            final t = s / steps;
            final pt = _evalCubic(p0, p1, p2, p3, t);
            if (_dist(curPt, pt) > 1e-5) {
              currentPts.add(pt);
              curPt = pt;
            }
          }
        case PathCommandType.close:
          flushSubpath(closed: true);
          curPt = startPt;
      }
    }
    flushSubpath(closed: false);

    final out = <PathCommand>[];
    for (final sub in subpaths) {
      final pts = sub.points;
      if (pts.length < 2) continue;

      final isClosed = sub.closed ||
          (pts.length > 2 && _dist(pts.first, pts.last) < 1e-4);
      final cleanPts = <Point2D>[pts.first];
      for (var i = 1; i < pts.length; i++) {
        if (_dist(cleanPts.last, pts[i]) > 1e-5) {
          cleanPts.add(pts[i]);
        }
      }
      if (isClosed &&
          cleanPts.length > 2 &&
          _dist(cleanPts.first, cleanPts.last) < 1e-4) {
        cleanPts.removeLast();
      }
      if (cleanPts.length < 2) continue;

      final n = cleanPts.length;
      final segCount = isClosed ? n : n - 1;
      final normals = <Point2D>[];

      for (var i = 0; i < segCount; i++) {
        final a = cleanPts[i];
        final b = cleanPts[(i + 1) % n];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final len = math.sqrt(dx * dx + dy * dy);
        normals.add(
          len > 1e-8 ? Point2D(-dy / len, dx / len) : const Point2D(0, 1),
        );
      }

      Point2D computeJoinOffset(Point2D n1, Point2D n2, double sign) {
        final bx = n1.x + n2.x;
        final by = n1.y + n2.y;
        final bLenSq = bx * bx + by * by;
        if (bLenSq < 1e-6) {
          return Point2D(n2.x * sign * halfW, n2.y * sign * halfW);
        }
        final scale = (sign * halfW * 2.0) / bLenSq.clamp(0.5, 4.0);
        return Point2D(bx * scale, by * scale);
      }

      if (isClosed) {
        final leftSide = <Point2D>[];
        final rightSide = <Point2D>[];
        for (var i = 0; i < n; i++) {
          final prevN = normals[(i - 1 + n) % n];
          final nextN = normals[i];
          final p = cleanPts[i];
          leftSide.add(p + computeJoinOffset(prevN, nextN, 1.0));
          rightSide.add(p + computeJoinOffset(prevN, nextN, -1.0));
        }
        // Outer loop
        out.add(PathCommand.moveTo(leftSide.first.x, leftSide.first.y));
        for (var i = 1; i < leftSide.length; i++) {
          out.add(PathCommand.lineTo(leftSide[i].x, leftSide[i].y));
        }
        out.add(const PathCommand.close());
        // Inner hole loop (reversed)
        out.add(PathCommand.moveTo(rightSide.last.x, rightSide.last.y));
        for (var i = rightSide.length - 2; i >= 0; i--) {
          out.add(PathCommand.lineTo(rightSide[i].x, rightSide[i].y));
        }
        out.add(const PathCommand.close());
      } else {
        final leftSide = <Point2D>[];
        final rightSide = <Point2D>[];

        final firstDir = Point2D(-normals.first.y, normals.first.x);
        final lastDir = Point2D(-normals.last.y, normals.last.x);
        final capExt = (lineCap == 'square') ? halfW : 0.0;

        final pStart = Point2D(
          cleanPts.first.x - firstDir.x * capExt,
          cleanPts.first.y - firstDir.y * capExt,
        );
        final pEnd = Point2D(
          cleanPts.last.x + lastDir.x * capExt,
          cleanPts.last.y + lastDir.y * capExt,
        );

        leftSide.add(
          Point2D(
            pStart.x + normals.first.x * halfW,
            pStart.y + normals.first.y * halfW,
          ),
        );
        rightSide.add(
          Point2D(
            pStart.x - normals.first.x * halfW,
            pStart.y - normals.first.y * halfW,
          ),
        );

        for (var i = 1; i < n - 1; i++) {
          final prevN = normals[i - 1];
          final nextN = normals[i];
          final p = cleanPts[i];
          leftSide.add(p + computeJoinOffset(prevN, nextN, 1.0));
          rightSide.add(p + computeJoinOffset(prevN, nextN, -1.0));
        }

        leftSide.add(
          Point2D(
            pEnd.x + normals.last.x * halfW,
            pEnd.y + normals.last.y * halfW,
          ),
        );
        rightSide.add(
          Point2D(
            pEnd.x - normals.last.x * halfW,
            pEnd.y - normals.last.y * halfW,
          ),
        );

        out.add(PathCommand.moveTo(leftSide.first.x, leftSide.first.y));
        for (var i = 1; i < leftSide.length; i++) {
          out.add(PathCommand.lineTo(leftSide[i].x, leftSide[i].y));
        }
        for (var i = rightSide.length - 1; i >= 0; i--) {
          out.add(PathCommand.lineTo(rightSide[i].x, rightSide[i].y));
        }
        out.add(const PathCommand.close());
      }
    }

    return out;
  }

  /// Normalizes the winding order of closed contours so outer contours are
  /// clockwise in SVG space (counter-clockwise in Y-up font space) and inner
  /// holes have the opposite winding direction.
  static List<PathCommand> _normalizeContoursWinding(
    List<PathCommand> commands,
  ) {
    if (commands.isEmpty) return commands;

    final contours = <_Contour>[];
    var currentCmds = <PathCommand>[];

    for (final cmd in commands) {
      if (cmd.type == PathCommandType.moveTo && currentCmds.isNotEmpty) {
        contours.add(_Contour.fromCommands(currentCmds));
        currentCmds = <PathCommand>[cmd];
      } else {
        currentCmds.add(cmd);
        if (cmd.type == PathCommandType.close) {
          contours.add(_Contour.fromCommands(currentCmds));
          currentCmds = <PathCommand>[];
        }
      }
    }
    if (currentCmds.isNotEmpty) {
      contours.add(_Contour.fromCommands(currentCmds));
    }

    if (contours.length <= 1) {
      if (contours.length == 1 && contours.first.signedArea < 0) {
        return contours.first.reversedCommands();
      }
      return commands;
    }

    final result = <PathCommand>[];
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      if (c.samplePoints.length < 3) {
        result.addAll(c.commands);
        continue;
      }

      // Count how many other contours contain a sample point of contour i
      final testPt = c.samplePoints.first;
      var nestingDepth = 0;
      for (var j = 0; j < contours.length; j++) {
        if (i == j) continue;
        final other = contours[j];
        if (other.absArea <= c.absArea) continue;
        if (_pointInPolygon(testPt, other.samplePoints)) {
          nestingDepth++;
        }
      }

      // Even nesting depth -> outer contour (positive area in SVG Y-down space)
      // Odd nesting depth -> hole contour (negative area in SVG Y-down space)
      final shouldBePositive = nestingDepth.isEven;
      final isPositive = c.signedArea >= 0;

      if (shouldBePositive != isPositive) {
        result.addAll(c.reversedCommands());
      } else {
        result.addAll(c.commands);
      }
    }

    return result;
  }

  static bool _pointInPolygon(Point2D pt, List<Point2D> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x;
      final yi = polygon[i].y;
      final xj = polygon[j].x;
      final yj = polygon[j].y;

      final intersect = ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static double _dist(Point2D a, Point2D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static Point2D _evalCubic(
    Point2D p0,
    Point2D p1,
    Point2D p2,
    Point2D p3,
    double t,
  ) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final c0 = mt2 * mt;
    final c1 = 3.0 * mt2 * t;
    final c2 = 3.0 * mt * t2;
    final c3 = t2 * t;
    return Point2D(
      c0 * p0.x + c1 * p1.x + c2 * p2.x + c3 * p3.x,
      c0 * p0.y + c1 * p1.y + c2 * p2.y + c3 * p3.y,
    );
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
    final scanner = _PathDataScanner(d);
    final commands = <PathCommand>[];
    var curX = 0.0;
    var curY = 0.0;
    var startX = 0.0;
    var startY = 0.0;
    double? lastCubicCtrlX;
    double? lastCubicCtrlY;
    double? lastQuadCtrlX;
    double? lastQuadCtrlY;

    String? currentCmd;

    while (!scanner.isAtEnd) {
      final cmdLetter = scanner.tryReadCommand();
      if (cmdLetter != null) {
        currentCmd = cmdLetter;
      } else if (currentCmd == null) {
        scanner.advance();
        continue;
      }

      switch (currentCmd) {
        case 'M':
        case 'm':
          final isRel = currentCmd == 'm';
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          commands.add(PathCommand.lineTo(x, curY));
          curX = x;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;

        case 'V':
        case 'v':
          final isRel = currentCmd == 'v';
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
          commands.add(PathCommand.lineTo(curX, y));
          curY = y;
          lastCubicCtrlX = null;
          lastCubicCtrlY = null;
          lastQuadCtrlX = null;
          lastQuadCtrlY = null;

        case 'C':
        case 'c':
          final isRel = currentCmd == 'c';
          final x1 = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y1 = scanner.nextNumber() + (isRel ? curY : 0.0);
          final x2 = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y2 = scanner.nextNumber() + (isRel ? curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final x2 = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y2 = scanner.nextNumber() + (isRel ? curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final qx1 = scanner.nextNumber() + (isRel ? curX : 0.0);
          final qy1 = scanner.nextNumber() + (isRel ? curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          final rx = scanner.nextNumber();
          final ry = scanner.nextNumber();
          final xAxisRotation = scanner.nextNumber();
          final largeArcFlag = scanner.nextArcFlag();
          final sweepFlag = scanner.nextArcFlag();
          final x = scanner.nextNumber() + (isRel ? curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? curY : 0.0);
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
          currentCmd = null;
      }
    }

    return commands;
  }

  static List<double> _tokenizeNumbers(String input) {
    final regex = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
    return regex
        .allMatches(input)
        .map((m) => double.parse(m.group(0)!))
        .toList();
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

/// Character-level scanner for SVG path `d` strings that properly handles
/// compact arc flags (`0` or `1` without spaces) and signed/decimal numbers.
class _PathDataScanner {
  _PathDataScanner(this.source);

  final String source;
  int _index = 0;

  bool get isAtEnd {
    _skipSeparators();
    return _index >= source.length;
  }

  void advance() {
    if (_index < source.length) {
      _index++;
    }
  }

  void _skipSeparators() {
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      // whitespace or comma (0x2C)
      if (code == 0x20 ||
          code == 0x09 ||
          code == 0x0A ||
          code == 0x0D ||
          code == 0x2C) {
        _index++;
      } else {
        break;
      }
    }
  }

  String? tryReadCommand() {
    _skipSeparators();
    if (_index >= source.length) return null;
    final ch = source[_index];
    if (_isCommandChar(ch)) {
      _index++;
      return ch;
    }
    return null;
  }

  bool _isCommandChar(String ch) {
    const cmds = 'MmZzLlHhVvCcSsQqTtAa';
    return cmds.contains(ch);
  }

  bool nextArcFlag() {
    _skipSeparators();
    if (_index >= source.length) {
      throw FormatException(
        'Unexpected end of SVG path data while reading arc flag in "$source".',
      );
    }
    final ch = source[_index];
    if (ch == '0') {
      _index++;
      return false;
    } else if (ch == '1') {
      _index++;
      return true;
    }
    throw FormatException(
      'Invalid SVG arc flag "$ch" at index $_index in "$source".',
    );
  }

  double nextNumber() {
    _skipSeparators();
    if (_index >= source.length) {
      throw FormatException(
        'Unexpected end of SVG path data while reading number in "$source".',
      );
    }

    final start = _index;

    // Optional sign
    if (source[_index] == '+' || source[_index] == '-') {
      _index++;
    }

    var hasDigits = false;
    while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
      _index++;
      hasDigits = true;
    }

    if (_index < source.length && source[_index] == '.') {
      _index++;
      while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
        _index++;
        hasDigits = true;
      }
    }

    if (!hasDigits) {
      throw FormatException(
        'Expected number at index $start in SVG path "$source".',
      );
    }

    // Optional exponent
    if (_index < source.length &&
        (source[_index] == 'e' || source[_index] == 'E')) {
      final expStart = _index;
      _index++;
      if (_index < source.length &&
          (source[_index] == '+' || source[_index] == '-')) {
        _index++;
      }
      var hasExpDigits = false;
      while (_index < source.length && _isDigit(source.codeUnitAt(_index))) {
        _index++;
        hasExpDigits = true;
      }
      if (!hasExpDigits) {
        _index = expStart;
      }
    }

    final token = source.substring(start, _index);
    return double.parse(token);
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
}

class _FlattenedSubpath {
  const _FlattenedSubpath(this.points, this.closed);

  final List<Point2D> points;
  final bool closed;
}

class _Contour {
  const _Contour({
    required this.commands,
    required this.samplePoints,
    required this.signedArea,
  });

  factory _Contour.fromCommands(List<PathCommand> commands) {
    final pts = <Point2D>[];
    var cur = const Point2D(0, 0);
    for (final cmd in commands) {
      switch (cmd.type) {
        case PathCommandType.moveTo:
          cur = Point2D(cmd.x, cmd.y);
          pts.add(cur);
        case PathCommandType.lineTo:
          cur = Point2D(cmd.x, cmd.y);
          pts.add(cur);
        case PathCommandType.cubicTo:
          final p0 = cur;
          final p1 = Point2D(cmd.x1, cmd.y1);
          final p2 = Point2D(cmd.x2, cmd.y2);
          final p3 = Point2D(cmd.x, cmd.y);
          for (var s = 1; s <= 4; s++) {
            pts.add(SvgParser._evalCubic(p0, p1, p2, p3, s / 4.0));
          }
          cur = p3;
        case PathCommandType.close:
          break;
      }
    }

    var area2 = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      area2 += a.x * b.y - b.x * a.y;
    }

    return _Contour(
      commands: commands,
      samplePoints: pts,
      signedArea: area2 / 2.0,
    );
  }

  final List<PathCommand> commands;
  final List<Point2D> samplePoints;
  final double signedArea;

  double get absArea => signedArea.abs();

  List<PathCommand> reversedCommands() {
    if (commands.isEmpty) return commands;

    final startCmd = commands.first;
    if (startCmd.type != PathCommandType.moveTo) return commands;

    final segments = <_ContourSegment>[];
    var curX = startCmd.x;
    var curY = startCmd.y;
    final startX = curX;
    final startY = curY;
    var hasClose = false;

    for (var i = 1; i < commands.length; i++) {
      final cmd = commands[i];
      switch (cmd.type) {
        case PathCommandType.moveTo:
          break;
        case PathCommandType.lineTo:
          segments.add(
            _ContourSegment.line(curX, curY, cmd.x, cmd.y),
          );
          curX = cmd.x;
          curY = cmd.y;
        case PathCommandType.cubicTo:
          segments.add(
            _ContourSegment.cubic(
              curX,
              curY,
              cmd.x1,
              cmd.y1,
              cmd.x2,
              cmd.y2,
              cmd.x,
              cmd.y,
            ),
          );
          curX = cmd.x;
          curY = cmd.y;
        case PathCommandType.close:
          hasClose = true;
          if ((curX - startX).abs() > 1e-6 || (curY - startY).abs() > 1e-6) {
            segments.add(
              _ContourSegment.line(curX, curY, startX, startY),
            );
            curX = startX;
            curY = startY;
          }
      }
    }

    if (segments.isEmpty) return commands;

    final reversed = <PathCommand>[
      PathCommand.moveTo(segments.last.endX, segments.last.endY),
    ];
    for (var i = segments.length - 1; i >= 0; i--) {
      final seg = segments[i];
      if (seg.isCubic) {
        reversed.add(
          PathCommand.cubicTo(
            seg.x2,
            seg.y2,
            seg.x1,
            seg.y1,
            seg.startX,
            seg.startY,
          ),
        );
      } else {
        reversed.add(PathCommand.lineTo(seg.startX, seg.startY));
      }
    }
    if (hasClose) {
      reversed.add(const PathCommand.close());
    }
    return reversed;
  }
}

class _ContourSegment {
  const _ContourSegment.line(
    this.startX,
    this.startY,
    this.endX,
    this.endY,
  )   : isCubic = false,
        x1 = 0,
        y1 = 0,
        x2 = 0,
        y2 = 0;

  const _ContourSegment.cubic(
    this.startX,
    this.startY,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.endX,
    this.endY,
  ) : isCubic = true;

  final bool isCubic;
  final double startX;
  final double startY;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double endX;
  final double endY;
}
