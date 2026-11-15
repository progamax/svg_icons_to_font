import 'dart:math' as math;

import 'geometry.dart';

/// Parses SVG `<path d="...">` attribute strings into normalized absolute [PathCommand]s.
abstract final class SvgPathDataParser {
  /// Parses an SVG `d` path attribute into normalized absolute [PathCommand]s.
  static List<PathCommand> parsePathData(String d) {
    final scanner = _PathDataScanner(d);
    final commands = <PathCommand>[];
    final state = _PathCursorState();
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
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(PathCommand.moveTo(x, y));
          state.moveTo(x, y);
          currentCmd = isRel ? 'l' : 'L';

        case 'L':
        case 'l':
          final isRel = currentCmd == 'l';
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(PathCommand.lineTo(x, y));
          state.lineTo(x, y);

        case 'H':
        case 'h':
          final isRel = currentCmd == 'h';
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          commands.add(PathCommand.lineTo(x, state.curY));
          state.lineTo(x, state.curY);

        case 'V':
        case 'v':
          final isRel = currentCmd == 'v';
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(PathCommand.lineTo(state.curX, y));
          state.lineTo(state.curX, y);

        case 'C':
        case 'c':
          final isRel = currentCmd == 'c';
          final x1 = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y1 = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          final x2 = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y2 = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(PathCommand.cubicTo(x1, y1, x2, y2, x, y));
          state.cubicTo(x2, y2, x, y);

        case 'S':
        case 's':
          final isRel = currentCmd == 's';
          final x1 = state.reflectedCubicCtrlX;
          final y1 = state.reflectedCubicCtrlY;
          final x2 = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y2 = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(PathCommand.cubicTo(x1, y1, x2, y2, x, y));
          state.cubicTo(x2, y2, x, y);

        case 'Q':
        case 'q':
          final isRel = currentCmd == 'q';
          final qx1 = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final qy1 = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(_quadToCubicCommand(state.curX, state.curY, qx1, qy1, x, y));
          state.quadTo(qx1, qy1, x, y);

        case 'T':
        case 't':
          final isRel = currentCmd == 't';
          final qx1 = state.reflectedQuadCtrlX;
          final qy1 = state.reflectedQuadCtrlY;
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.add(_quadToCubicCommand(state.curX, state.curY, qx1, qy1, x, y));
          state.quadTo(qx1, qy1, x, y);

        case 'A':
        case 'a':
          final isRel = currentCmd == 'a';
          final rx = scanner.nextNumber();
          final ry = scanner.nextNumber();
          final xAxisRotation = scanner.nextNumber();
          final largeArcFlag = scanner.nextArcFlag();
          final sweepFlag = scanner.nextArcFlag();
          final x = scanner.nextNumber() + (isRel ? state.curX : 0.0);
          final y = scanner.nextNumber() + (isRel ? state.curY : 0.0);
          commands.addAll(
            _arcToCubic(
              state.curX,
              state.curY,
              rx,
              ry,
              xAxisRotation,
              largeArcFlag,
              sweepFlag,
              x,
              y,
            ),
          );
          state.lineTo(x, y);

        case 'Z':
        case 'z':
          commands.add(const PathCommand.close());
          state.closeSubpath();
          currentCmd = null;
      }
    }

    return commands;
  }

  /// Extracts all floating-point numbers from [input].
  static List<double> tokenizeNumbers(String input) {
    final regex = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
    return regex
        .allMatches(input)
        .map((m) => double.parse(m.group(0)!))
        .toList();
  }

  /// Elevates a quadratic Bézier curve `(x0, y0) -> (qx1, qy1) -> (x, y)` to a cubic [PathCommand].
  static PathCommand _quadToCubicCommand(
    double x0,
    double y0,
    double qx1,
    double qy1,
    double x,
    double y,
  ) {
    final c1x = x0 + (2.0 / 3.0) * (qx1 - x0);
    final c1y = y0 + (2.0 / 3.0) * (qy1 - y0);
    final c2x = x + (2.0 / 3.0) * (qx1 - x);
    final c2y = y + (2.0 / 3.0) * (qy1 - y);
    return PathCommand.cubicTo(c1x, c1y, c2x, c2y, x, y);
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

    final theta1 = _vectorAngle(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var dTheta = _vectorAngle(
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

      final c1 = _mapUnitCirclePointToEllipse(
        e1x,
        e1y,
        rx,
        ry,
        cosPhi,
        sinPhi,
        cx,
        cy,
      );
      final c2 = _mapUnitCirclePointToEllipse(
        e2x,
        e2y,
        rx,
        ry,
        cosPhi,
        sinPhi,
        cx,
        cy,
      );
      final end = _mapUnitCirclePointToEllipse(
        cosT2,
        sinT2,
        rx,
        ry,
        cosPhi,
        sinPhi,
        cx,
        cy,
      );

      result.add(PathCommand.cubicTo(c1.x, c1.y, c2.x, c2.y, end.x, end.y));
    }

    return result;
  }

  static double _vectorAngle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt(ux * ux + uy * uy) * math.sqrt(vx * vx + vy * vy);
    final cosVal = (dot / len).clamp(-1.0, 1.0);
    final angle = math.acos(cosVal);
    return (ux * vy - uy * vx < 0) ? -angle : angle;
  }

  static Point2D _mapUnitCirclePointToEllipse(
    double px,
    double py,
    double rx,
    double ry,
    double cosPhi,
    double sinPhi,
    double cx,
    double cy,
  ) {
    final sx = px * rx;
    final sy = py * ry;
    return Point2D(
      cosPhi * sx - sinPhi * sy + cx,
      sinPhi * sx + cosPhi * sy + cy,
    );
  }
}

/// Tracks the current pen position, subpath origin, and previous Bézier control
/// points while parsing an SVG `d` path string.
class _PathCursorState {
  double curX = 0.0;
  double curY = 0.0;
  double startX = 0.0;
  double startY = 0.0;
  double? lastCubicCtrlX;
  double? lastCubicCtrlY;
  double? lastQuadCtrlX;
  double? lastQuadCtrlY;

  double get reflectedCubicCtrlX =>
      lastCubicCtrlX != null ? 2 * curX - lastCubicCtrlX! : curX;

  double get reflectedCubicCtrlY =>
      lastCubicCtrlY != null ? 2 * curY - lastCubicCtrlY! : curY;

  double get reflectedQuadCtrlX =>
      lastQuadCtrlX != null ? 2 * curX - lastQuadCtrlX! : curX;

  double get reflectedQuadCtrlY =>
      lastQuadCtrlY != null ? 2 * curY - lastQuadCtrlY! : curY;

  void moveTo(double x, double y) {
    curX = x;
    curY = y;
    startX = x;
    startY = y;
    resetSmoothControls();
  }

  void lineTo(double x, double y) {
    curX = x;
    curY = y;
    resetSmoothControls();
  }

  void cubicTo(double ctrlX2, double ctrlY2, double x, double y) {
    lastCubicCtrlX = ctrlX2;
    lastCubicCtrlY = ctrlY2;
    lastQuadCtrlX = null;
    lastQuadCtrlY = null;
    curX = x;
    curY = y;
  }

  void quadTo(double qx1, double qy1, double x, double y) {
    lastQuadCtrlX = qx1;
    lastQuadCtrlY = qy1;
    lastCubicCtrlX = null;
    lastCubicCtrlY = null;
    curX = x;
    curY = y;
  }

  void closeSubpath() {
    curX = startX;
    curY = startY;
    resetSmoothControls();
  }

  void resetSmoothControls() {
    lastCubicCtrlX = null;
    lastCubicCtrlY = null;
    lastQuadCtrlX = null;
    lastQuadCtrlY = null;
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
