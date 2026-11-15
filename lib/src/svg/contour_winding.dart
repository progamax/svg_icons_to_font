import 'geometry.dart';

/// Normalizes the winding order of closed contours so outer contours are
/// clockwise in SVG Y-down space (counter-clockwise in Y-up font space) and
/// inner holes have the opposite winding direction.
abstract final class SvgContourWinding {
  static const int _cubicSampleSteps = 4;
  static const double _rayCastEpsilon = 1e-9;
  static const double _closePointEpsilon = 1e-6;

  /// Normalizes the winding orientation of all contours in [commands].
  static List<PathCommand> normalizeContoursWinding(
    List<PathCommand> commands,
  ) {
    if (commands.isEmpty) return commands;

    final contours = _splitIntoContours(commands);

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

      // Count how many larger contours contain a sample point of contour i
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

  static List<_Contour> _splitIntoContours(List<PathCommand> commands) {
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
    return contours;
  }

  static bool _pointInPolygon(Point2D pt, List<Point2D> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x;
      final yi = polygon[i].y;
      final xj = polygon[j].x;
      final yj = polygon[j].y;

      final dy = yj - yi;
      final safeDy = dy == 0 ? _rayCastEpsilon : dy;
      final intersect = ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / safeDy + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
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
          for (var s = 1; s <= SvgContourWinding._cubicSampleSteps; s++) {
            pts.add(
              evalCubic2D(
                p0,
                p1,
                p2,
                p3,
                s / SvgContourWinding._cubicSampleSteps,
              ),
            );
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
          if ((curX - startX).abs() > SvgContourWinding._closePointEpsilon ||
              (curY - startY).abs() > SvgContourWinding._closePointEpsilon) {
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
