import 'package:xml/xml.dart';

import 'svg/contour_winding.dart';
import 'svg/geometry.dart';
import 'svg/path_data_parser.dart';
import 'svg/shape_parsers.dart';
import 'svg/stroke_expander.dart';
import 'svg/svg_style.dart';

export 'svg/geometry.dart'
    show
        BoundingBox,
        Matrix2D,
        ParsedSvg,
        PathCommand,
        PathCommandType,
        Point2D;

/// Parses an SVG XML string into normalized absolute [PathCommand]s.
class SvgParser {
  static const double _defaultViewportSize = 24.0;
  static const Set<String> _ignoredElementTags = {
    'defs',
    'clippath',
    'mask',
    'style',
    'title',
    'desc',
    'metadata',
  };

  /// Parses the given SVG XML string into a [ParsedSvg].
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
      const SvgStyle(),
    );

    final normalizedCommands =
        SvgContourWinding.normalizeContoursWinding(commands);

    return ParsedSvg(viewBox: viewBox, commands: normalizedCommands);
  }

  /// Parses an SVG `d` path attribute into normalized absolute [PathCommand]s.
  static List<PathCommand> parsePathData(String d) =>
      SvgPathDataParser.parsePathData(d);

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
      final args = SvgPathDataParser.tokenizeNumbers(match.group(2)!);
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

    final rawW = SvgShapeParsers.parseDimension(svgElement.getAttribute('width'));
    final rawH = SvgShapeParsers.parseDimension(svgElement.getAttribute('height'));
    final width = (rawW != null && rawW > 0) ? rawW : _defaultViewportSize;
    final height = (rawH != null && rawH > 0) ? rawH : _defaultViewportSize;
    return BoundingBox(0, 0, width, height);
  }

  static void _extractElementCommands(
    XmlElement element,
    List<PathCommand> out,
    Matrix2D parentTransform,
    SvgStyle parentStyle,
  ) {
    final tag = element.name.local.toLowerCase();
    if (_ignoredElementTags.contains(tag)) {
      return;
    }

    final currentStyle = parentStyle.resolve(element);
    if (currentStyle.hidden) {
      return;
    }

    final localTransform = parseTransform(element.getAttribute('transform'));
    final currentTransform = parentTransform * localTransform;

    final rawGeometry = _parseShapeGeometry(tag, element);
    if (rawGeometry.isNotEmpty) {
      final emittedCommands = _applyFillAndStroke(tag, rawGeometry, currentStyle);
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

  static List<PathCommand> _parseShapeGeometry(String tag, XmlElement element) {
    switch (tag) {
      case 'path':
        final d = element.getAttribute('d');
        if (d != null && d.trim().isNotEmpty) {
          return parsePathData(d);
        }
        return const [];
      case 'rect':
        return SvgShapeParsers.parseRect(element);
      case 'circle':
        return SvgShapeParsers.parseCircle(element);
      case 'ellipse':
        return SvgShapeParsers.parseEllipse(element);
      case 'polygon':
        return SvgShapeParsers.parsePoly(element, close: true);
      case 'polyline':
        return SvgShapeParsers.parsePoly(element, close: false);
      case 'line':
        return SvgShapeParsers.parseLine(element);
      default:
        return const [];
    }
  }

  static List<PathCommand> _applyFillAndStroke(
    String tag,
    List<PathCommand> rawGeometry,
    SvgStyle style,
  ) {
    final emittedCommands = <PathCommand>[];

    // <line> never has a fill area; other shapes emit fill if fill != 'none'
    if (tag != 'line' && style.hasFill) {
      if (tag == 'polyline') {
        emittedCommands.addAll(_closeOpenSubpaths(rawGeometry));
      } else {
        emittedCommands.addAll(rawGeometry);
      }
    }

    // If the element has a visible stroke (e.g. <line>, stroke icons, etc.),
    // expand the stroke into filled closed contours.
    if (style.hasStroke ||
        (tag == 'line' && !style.hasStroke && style.fill != 'none')) {
      final effectiveWidth = style.strokeWidth > 0 ? style.strokeWidth : 1.0;
      emittedCommands.addAll(
        SvgStrokeExpander.strokeToFillCommands(
          rawGeometry,
          strokeWidth: effectiveWidth,
          lineCap: style.strokeLinecap,
          lineJoin: style.strokeLinejoin,
        ),
      );
    }

    return emittedCommands;
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
}
