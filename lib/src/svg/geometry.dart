import 'dart:math' as math;

/// Constant $4 (\sqrt{2} - 1) / 3$ used to approximate a quarter circle with a cubic Bézier curve.
const double bezierCircleKappa = 0.5522847498307936;

/// Evaluates the Euclidean distance between two 2D points [a] and [b].
double distance2D(Point2D a, Point2D b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Evaluates a 2D cubic Bézier curve at parameter $t \in [0, 1]$.
Point2D evalCubic2D(
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
