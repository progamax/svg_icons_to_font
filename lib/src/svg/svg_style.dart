import 'package:xml/xml.dart';

import 'shape_parsers.dart';

/// Inherited SVG presentation style attributes for an element.
class SvgStyle {
  const SvgStyle({
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

  /// Resolves the effective style for [element] by combining inherited values
  /// with the element's presentation attributes and inline `style` attribute.
  SvgStyle resolve(XmlElement element) {
    final inlineStyle = _parseInlineStyle(element.getAttribute('style'));

    String? readProp(String name) =>
        inlineStyle[name] ?? element.getAttribute(name)?.trim();

    final display = readProp('display')?.toLowerCase();
    final visibility = readProp('visibility')?.toLowerCase();
    final opacityStr = readProp('opacity');
    final opacity = opacityStr != null ? double.tryParse(opacityStr) : null;

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
        ? (SvgShapeParsers.parseDimension(strokeWidthAttr) ?? strokeWidth)
        : strokeWidth;

    final resolvedLinecap =
        readProp('stroke-linecap')?.toLowerCase() ?? strokeLinecap;
    final resolvedLinejoin =
        readProp('stroke-linejoin')?.toLowerCase() ?? strokeLinejoin;
    final resolvedFillRule =
        readProp('fill-rule')?.toLowerCase() ?? fillRule;

    return SvgStyle(
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
