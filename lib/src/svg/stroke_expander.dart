import 'dart:math' as math;

import 'geometry.dart';

/// Expands stroked SVG path commands into closed filled outlines suitable for font glyphs.
abstract final class SvgStrokeExpander {
  static const int _cubicFlattenSteps = 12;
  static const double _minSegmentDistance = 1e-5;
  static const double _closedEndpointTolerance = 1e-4;
  static const double _normalEpsilon = 1e-8;
  static const double _bisectorEpsilon = 1e-6;

  /// Expands stroked path [commands] into closed filled outlines of width [strokeWidth].
  static List<PathCommand> strokeToFillCommands(
    List<PathCommand> commands, {
    required double strokeWidth,
    String lineCap = 'butt',
    String lineJoin = 'miter',
  }) {
    final halfW = strokeWidth / 2.0;
    if (halfW <= 0) return const [];

    final subpaths = _flattenSubpaths(commands);
    final out = <PathCommand>[];

    for (final sub in subpaths) {
      final pts = sub.points;
      if (pts.length < 2) continue;

      final isClosed = sub.closed ||
          (pts.length > 2 &&
              distance2D(pts.first, pts.last) < _closedEndpointTolerance);
      final cleanPts = _deduplicatePoints(pts, isClosed: isClosed);
      if (cleanPts.length < 2) continue;

      final normals = _computeSegmentNormals(cleanPts, isClosed: isClosed);

      if (isClosed) {
        out.addAll(_buildClosedStrokeContours(cleanPts, normals, halfW));
      } else {
        out.addAll(
          _buildOpenStrokeContour(cleanPts, normals, halfW, lineCap: lineCap),
        );
      }
    }

    return out;
  }

  static List<_FlattenedSubpath> _flattenSubpaths(List<PathCommand> commands) {
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
          if (distance2D(curPt, nextPt) > _minSegmentDistance) {
            currentPts.add(nextPt);
            curPt = nextPt;
          }
        case PathCommandType.cubicTo:
          final p0 = curPt;
          final p1 = Point2D(cmd.x1, cmd.y1);
          final p2 = Point2D(cmd.x2, cmd.y2);
          final p3 = Point2D(cmd.x, cmd.y);
          for (var s = 1; s <= _cubicFlattenSteps; s++) {
            final t = s / _cubicFlattenSteps;
            final pt = evalCubic2D(p0, p1, p2, p3, t);
            if (distance2D(curPt, pt) > _minSegmentDistance) {
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
    return subpaths;
  }

  static List<Point2D> _deduplicatePoints(
    List<Point2D> pts, {
    required bool isClosed,
  }) {
    final cleanPts = <Point2D>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      if (distance2D(cleanPts.last, pts[i]) > _minSegmentDistance) {
        cleanPts.add(pts[i]);
      }
    }
    if (isClosed &&
        cleanPts.length > 2 &&
        distance2D(cleanPts.first, cleanPts.last) < _closedEndpointTolerance) {
      cleanPts.removeLast();
    }
    return cleanPts;
  }

  static List<Point2D> _computeSegmentNormals(
    List<Point2D> cleanPts, {
    required bool isClosed,
  }) {
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
        len > _normalEpsilon ? Point2D(-dy / len, dx / len) : const Point2D(0, 1),
      );
    }
    return normals;
  }

  static Point2D _computeJoinOffset(
    Point2D n1,
    Point2D n2,
    double halfW,
    double sign,
  ) {
    final bx = n1.x + n2.x;
    final by = n1.y + n2.y;
    final bLenSq = bx * bx + by * by;
    if (bLenSq < _bisectorEpsilon) {
      return Point2D(n2.x * sign * halfW, n2.y * sign * halfW);
    }
    final scale = (sign * halfW * 2.0) / bLenSq.clamp(0.5, 4.0);
    return Point2D(bx * scale, by * scale);
  }

  static List<PathCommand> _buildClosedStrokeContours(
    List<Point2D> cleanPts,
    List<Point2D> normals,
    double halfW,
  ) {
    final n = cleanPts.length;
    final leftSide = <Point2D>[];
    final rightSide = <Point2D>[];

    for (var i = 0; i < n; i++) {
      final prevN = normals[(i - 1 + n) % n];
      final nextN = normals[i];
      final p = cleanPts[i];
      leftSide.add(p + _computeJoinOffset(prevN, nextN, halfW, 1.0));
      rightSide.add(p + _computeJoinOffset(prevN, nextN, halfW, -1.0));
    }

    final out = <PathCommand>[
      // Outer loop
      PathCommand.moveTo(leftSide.first.x, leftSide.first.y),
      for (var i = 1; i < leftSide.length; i++)
        PathCommand.lineTo(leftSide[i].x, leftSide[i].y),
      const PathCommand.close(),
      // Inner hole loop (reversed)
      PathCommand.moveTo(rightSide.last.x, rightSide.last.y),
      for (var i = rightSide.length - 2; i >= 0; i--)
        PathCommand.lineTo(rightSide[i].x, rightSide[i].y),
      const PathCommand.close(),
    ];
    return out;
  }

  static List<PathCommand> _buildOpenStrokeContour(
    List<Point2D> cleanPts,
    List<Point2D> normals,
    double halfW, {
    required String lineCap,
  }) {
    final n = cleanPts.length;
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
      leftSide.add(p + _computeJoinOffset(prevN, nextN, halfW, 1.0));
      rightSide.add(p + _computeJoinOffset(prevN, nextN, halfW, -1.0));
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

    return <PathCommand>[
      PathCommand.moveTo(leftSide.first.x, leftSide.first.y),
      for (var i = 1; i < leftSide.length; i++)
        PathCommand.lineTo(leftSide[i].x, leftSide[i].y),
      for (var i = rightSide.length - 1; i >= 0; i--)
        PathCommand.lineTo(rightSide[i].x, rightSide[i].y),
      const PathCommand.close(),
    ];
  }
}

class _FlattenedSubpath {
  const _FlattenedSubpath(this.points, this.closed);

  final List<Point2D> points;
  final bool closed;
}
