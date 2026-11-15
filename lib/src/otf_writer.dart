import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';
import 'svg_parser.dart';

/// Represents a single icon glyph to be written into the OpenType font.
class IconGlyph {
  const IconGlyph({
    required this.name,
    required this.codePoint,
    required this.svg,
  });

  /// Identifier name of the icon (derived from filename).
  final String name;

  /// Unicode codepoint assigned to the icon.
  final int codePoint;

  /// Parsed SVG paths and viewBox.
  final ParsedSvg svg;
}

class _TransformedGlyph {
  const _TransformedGlyph({
    required this.name,
    required this.codePoint,
    required this.advanceWidth,
    required this.bbox,
    required this.charstring,
  });

  final String name;
  final int codePoint;
  final int advanceWidth;
  final BoundingBox bbox;
  final Uint8List charstring;

  int get leftSideBearing => bbox.minX.round();
}

/// Builds a binary OpenType (`.otf` with CFF outlines) font file in pure Dart.
class OtfWriter {
  /// Compiles a list of [IconGlyph]s into a complete OpenType `.otf` binary.
  static Uint8List buildFont({
    required List<IconGlyph> glyphs,
    required FontGeneratorConfig config,
  }) {
    final sortedGlyphs = List<IconGlyph>.of(glyphs)
      ..sort((a, b) => a.codePoint.compareTo(b.codePoint));

    final transformed = <_TransformedGlyph>[
      _buildNotdefGlyph(config),
      for (final g in sortedGlyphs) _transformIconGlyph(g, config),
    ];

    final fontBBox = _computeGlobalBBox(transformed);
    final nowSeconds = DateTime.now()
        .toUtc()
        .difference(DateTime.utc(1904, 1, 1))
        .inSeconds;

    final tables = <String, Uint8List>{
      'CFF ': _buildCffTable(transformed, config, fontBBox),
      'OS/2': _buildOs2Table(transformed, config),
      'cmap': _buildCmapTable(transformed),
      'head': _buildHeadTable(config, fontBBox, nowSeconds),
      'hhea': _buildHheaTable(transformed, config, fontBBox),
      'hmtx': _buildHmtxTable(transformed),
      'maxp': _buildMaxpTable(transformed.length),
      'name': _buildNameTable(config),
      'post': _buildPostTable(),
    };

    return _assembleSfnt(tables);
  }

  static _TransformedGlyph _buildNotdefGlyph(FontGeneratorConfig config) {
    final w = (config.unitsPerEm * 0.5).round();
    return _TransformedGlyph(
      name: '.notdef',
      codePoint: 0,
      advanceWidth: w,
      bbox: const BoundingBox(0, 0, 0, 0),
      charstring: Uint8List.fromList(const [14]), // endchar
    );
  }

  static _TransformedGlyph _transformIconGlyph(
    IconGlyph glyph,
    FontGeneratorConfig config,
  ) {
    final rawVb = glyph.svg.viewBox;
    final vbWidth = rawVb.width > 0 ? rawVb.width : 24.0;
    final vbHeight = rawVb.height > 0 ? rawVb.height : 24.0;
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
    var curX = 0;
    var curY = 0;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    void trackCoord(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    void trackCubicBounds(
      double x0,
      double y0,
      double x1,
      double y1,
      double x2,
      double y2,
      double x3,
      double y3,
    ) {
      trackCoord(x0, y0);
      trackCoord(x3, y3);
      for (final t in _cubicExtremaT(x0, x1, x2, x3)) {
        final xt = _evalCubic1D(x0, x1, x2, x3, t);
        final yt = _evalCubic1D(y0, y1, y2, y3, t);
        trackCoord(xt, yt);
      }
      for (final t in _cubicExtremaT(y0, y1, y2, y3)) {
        final xt = _evalCubic1D(x0, x1, x2, x3, t);
        final yt = _evalCubic1D(y0, y1, y2, y3, t);
        trackCoord(xt, yt);
      }
    }

    for (final cmd in glyph.svg.commands) {
      switch (cmd.type) {
        case PathCommandType.moveTo:
          final tx = mapX(cmd.x).round();
          final ty = mapY(cmd.y).round();
          final dx = tx - curX;
          final dy = ty - curY;
          _encodeCharstringInt(charstringBytes, dx);
          _encodeCharstringInt(charstringBytes, dy);
          charstringBytes.add(21); // rmoveto
          curX = tx;
          curY = ty;
          trackCoord(tx.toDouble(), ty.toDouble());

        case PathCommandType.lineTo:
          final tx = mapX(cmd.x).round();
          final ty = mapY(cmd.y).round();
          final dx = tx - curX;
          final dy = ty - curY;
          if (dx != 0 || dy != 0) {
            _encodeCharstringInt(charstringBytes, dx);
            _encodeCharstringInt(charstringBytes, dy);
            charstringBytes.add(5); // rlineto
            curX = tx;
            curY = ty;
            trackCoord(tx.toDouble(), ty.toDouble());
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
            _encodeCharstringInt(charstringBytes, dx1);
            _encodeCharstringInt(charstringBytes, dy1);
            _encodeCharstringInt(charstringBytes, dx2);
            _encodeCharstringInt(charstringBytes, dy2);
            _encodeCharstringInt(charstringBytes, dx3);
            _encodeCharstringInt(charstringBytes, dy3);
            charstringBytes.add(8); // rrcurveto

            curX = x;
            curY = y;
            trackCubicBounds(
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

    charstringBytes.add(14); // endchar

    final bbox = minX.isFinite
        ? BoundingBox(
            minX.floorToDouble(),
            minY.floorToDouble(),
            maxX.ceilToDouble(),
            maxY.ceilToDouble(),
          )
        : const BoundingBox(0, 0, 0, 0);

    return _TransformedGlyph(
      name: glyph.name,
      codePoint: glyph.codePoint,
      advanceWidth: advanceWidth,
      bbox: bbox,
      charstring: Uint8List.fromList(charstringBytes),
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
    if (a.abs() < 1e-9) {
      if (b.abs() > 1e-9) {
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
    if (t2 > 0.0 && t2 < 1.0 && (t2 - t1).abs() > 1e-9) roots.add(t2);
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

  static BoundingBox _computeGlobalBBox(List<_TransformedGlyph> glyphs) {
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

  static void _encodeCharstringInt(List<int> out, int v) {
    if (v >= -107 && v <= 107) {
      out.add(v + 139);
    } else if (v >= 108 && v <= 1131) {
      final v1 = v - 108;
      out.add((v1 >> 8) + 247);
      out.add(v1 & 0xFF);
    } else if (v >= -1131 && v <= -108) {
      final v1 = -v - 108;
      out.add((v1 >> 8) + 251);
      out.add(v1 & 0xFF);
    } else {
      // 16.16 fixed-point number in Type 2 charstring (opcode 255)
      final fixed = v << 16;
      out.add(255);
      out.add((fixed >> 24) & 0xFF);
      out.add((fixed >> 16) & 0xFF);
      out.add((fixed >> 8) & 0xFF);
      out.add(fixed & 0xFF);
    }
  }

  static void _encodeCffDictInt(List<int> out, int v) {
    if (v >= -107 && v <= 107) {
      out.add(v + 139);
    } else if (v >= 108 && v <= 1131) {
      final v1 = v - 108;
      out.add((v1 >> 8) + 247);
      out.add(v1 & 0xFF);
    } else if (v >= -1131 && v <= -108) {
      final v1 = -v - 108;
      out.add((v1 >> 8) + 251);
      out.add(v1 & 0xFF);
    } else if (v >= -32768 && v <= 32767) {
      out.add(28);
      out.add((v >> 8) & 0xFF);
      out.add(v & 0xFF);
    } else {
      out.add(29);
      out.add((v >> 24) & 0xFF);
      out.add((v >> 16) & 0xFF);
      out.add((v >> 8) & 0xFF);
      out.add(v & 0xFF);
    }
  }

  /// Encodes a floating-point number in CFF DICT real format (opcode 30, nibble-packed BCD).
  static void _encodeCffDictReal(List<int> out, double value) {
    out.add(30);
    final str = value.toStringAsExponential(8);
    final nibbles = <int>[];
    for (var i = 0; i < str.length; i++) {
      final ch = str[i];
      if (ch == '+') continue;
      if (ch == '0' && i > 0 && str[i - 1] == 'e') continue;
      switch (ch) {
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
          nibbles.add(ch.codeUnitAt(0) - 0x30);
        case '.':
          nibbles.add(0x0A);
        case 'e':
        case 'E':
          if (i + 1 < str.length && str[i + 1] == '-') {
            nibbles.add(0x0C); // E-
            i++;
          } else {
            nibbles.add(0x0B); // E
          }
        case '-':
          nibbles.add(0x0E);
      }
    }
    nibbles.add(0x0F); // end of real number
    if (nibbles.length.isOdd) {
      nibbles.add(0x0F);
    }
    for (var i = 0; i < nibbles.length; i += 2) {
      out.add((nibbles[i] << 4) | nibbles[i + 1]);
    }
  }

  static void _encodeCffDictInt32Fixed(List<int> out, int v) {
    out.add(29);
    out.add((v >> 24) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add(v & 0xFF);
  }

  static Uint8List _buildCffIndex(List<Uint8List> objects) {
    if (objects.isEmpty) {
      return Uint8List.fromList(const [0, 0]);
    }
    var totalDataSize = 0;
    for (final obj in objects) {
      totalDataSize += obj.length;
    }

    const offSize = 4;
    final builder = BytesBuilder();
    // count (Card16)
    builder.addByte((objects.length >> 8) & 0xFF);
    builder.addByte(objects.length & 0xFF);
    // offSize (OffSize = 4)
    builder.addByte(offSize);

    var currentOffset = 1;
    for (var i = 0; i <= objects.length; i++) {
      builder.addByte((currentOffset >> 24) & 0xFF);
      builder.addByte((currentOffset >> 16) & 0xFF);
      builder.addByte((currentOffset >> 8) & 0xFF);
      builder.addByte(currentOffset & 0xFF);
      if (i < objects.length) {
        currentOffset += objects[i].length;
      }
    }

    for (final obj in objects) {
      builder.add(obj);
    }

    assert(currentOffset - 1 == totalDataSize);
    return builder.toBytes();
  }

  static Uint8List _buildCffTable(
    List<_TransformedGlyph> glyphs,
    FontGeneratorConfig config,
    BoundingBox fontBBox,
  ) {
    // 1. Header (4 bytes)
    final header = Uint8List.fromList(const [1, 0, 4, 4]);

    // 2. Name INDEX
    final psFontName = config.fontFamily.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '',
    );
    final safePsName = psFontName.isEmpty ? 'AppIcons' : psFontName;
    final fontNameBytes = Uint8List.fromList(safePsName.codeUnits);
    final nameIndex = _buildCffIndex([fontNameBytes]);

    // 3. String INDEX (custom strings start at SID 391)
    // SID 391: fontFamily
    // SID 392..: glyph names (excluding .notdef which is SID 0)
    final stringObjects = <Uint8List>[
      Uint8List.fromList(config.fontFamily.codeUnits),
      for (final g in glyphs.skip(1)) Uint8List.fromList(g.name.codeUnits),
    ];
    final stringIndex = _buildCffIndex(stringObjects);

    // 4. Global Subr INDEX (empty)
    final globalSubrIndex = _buildCffIndex(const []);

    // 5. Charset (format 0: 1 byte format + 2 bytes SID per glyph excluding .notdef)
    final charsetBuilder = BytesBuilder();
    charsetBuilder.addByte(0); // format 0
    for (var i = 1; i < glyphs.length; i++) {
      final sid = 391 + i;
      charsetBuilder.addByte((sid >> 8) & 0xFF);
      charsetBuilder.addByte(sid & 0xFF);
    }
    final charsetBytes = charsetBuilder.toBytes();

    // 6. CharStrings INDEX
    final charStringsIndex = _buildCffIndex([
      for (final g in glyphs) g.charstring,
    ]);

    // 7. Private DICT (defaultWidthX and nominalWidthX)
    final privateDictList = <int>[];
    _encodeCffDictInt(privateDictList, config.unitsPerEm);
    privateDictList.add(20); // defaultWidthX
    _encodeCffDictInt(privateDictList, config.unitsPerEm);
    privateDictList.add(21); // nominalWidthX
    final privateDictBytes = Uint8List.fromList(privateDictList);

    // Build Top DICT using fixed 5-byte integers for offsets so its size is constant
    Uint8List buildTopDict({
      required int charsetOffset,
      required int charStringsOffset,
      required int privateDictOffset,
    }) {
      final dict = <int>[];
      // FullName (SID 391) -> op 2
      _encodeCffDictInt(dict, 391);
      dict.add(2);
      // FamilyName (SID 391) -> op 3
      _encodeCffDictInt(dict, 391);
      dict.add(3);
      // FontBBox -> op 5
      _encodeCffDictInt(dict, fontBBox.minX.round());
      _encodeCffDictInt(dict, fontBBox.minY.round());
      _encodeCffDictInt(dict, fontBBox.maxX.round());
      _encodeCffDictInt(dict, fontBBox.maxY.round());
      dict.add(5);
      // FontMatrix -> op 12 7 (only needed if unitsPerEm != 1000)
      if (config.unitsPerEm != 1000 && config.unitsPerEm > 0) {
        final scale = 1.0 / config.unitsPerEm;
        _encodeCffDictReal(dict, scale);
        _encodeCffDictInt(dict, 0);
        _encodeCffDictInt(dict, 0);
        _encodeCffDictReal(dict, scale);
        _encodeCffDictInt(dict, 0);
        _encodeCffDictInt(dict, 0);
        dict.addAll(const [12, 7]);
      }
      // CharstringType 2 -> 12 6
      _encodeCffDictInt(dict, 2);
      dict.addAll(const [12, 6]);
      // charset offset -> op 15
      _encodeCffDictInt32Fixed(dict, charsetOffset);
      dict.add(15);
      // CharStrings offset -> op 17
      _encodeCffDictInt32Fixed(dict, charStringsOffset);
      dict.add(17);
      // Private DICT size and offset -> op 18
      _encodeCffDictInt32Fixed(dict, privateDictBytes.length);
      _encodeCffDictInt32Fixed(dict, privateDictOffset);
      dict.add(18);
      return Uint8List.fromList(dict);
    }

    final dummyTopDictIndex = _buildCffIndex([
      buildTopDict(
        charsetOffset: 0,
        charStringsOffset: 0,
        privateDictOffset: 0,
      ),
    ]);

    final charsetOffset = header.length +
        nameIndex.length +
        dummyTopDictIndex.length +
        stringIndex.length +
        globalSubrIndex.length;
    final charStringsOffset = charsetOffset + charsetBytes.length;
    final privateDictOffset = charStringsOffset + charStringsIndex.length;

    final topDictIndex = _buildCffIndex([
      buildTopDict(
        charsetOffset: charsetOffset,
        charStringsOffset: charStringsOffset,
        privateDictOffset: privateDictOffset,
      ),
    ]);

    final cffBuilder = BytesBuilder()
      ..add(header)
      ..add(nameIndex)
      ..add(topDictIndex)
      ..add(stringIndex)
      ..add(globalSubrIndex)
      ..add(charsetBytes)
      ..add(charStringsIndex)
      ..add(privateDictBytes);

    return cffBuilder.toBytes();
  }

  static Uint8List _buildHeadTable(
    FontGeneratorConfig config,
    BoundingBox fontBBox,
    int nowSeconds,
  ) {
    final data = ByteData(54);
    data.setUint16(0, 1); // majorVersion
    data.setUint16(2, 0); // minorVersion
    data.setUint32(4, 0x00010000); // fontRevision 1.0
    data.setUint32(8, 0); // checkSumAdjustment (filled during SFNT assembly)
    data.setUint32(12, 0x5F0F3CF5); // magicNumber
    data.setUint16(16, 0x0003); // flags
    data.setUint16(18, config.unitsPerEm); // unitsPerEm
    data.setInt64(20, nowSeconds); // created
    data.setInt64(28, nowSeconds); // modified
    data.setInt16(36, fontBBox.minX.round()); // xMin
    data.setInt16(38, fontBBox.minY.round()); // yMin
    data.setInt16(40, fontBBox.maxX.round()); // xMax
    data.setInt16(42, fontBBox.maxY.round()); // yMax
    data.setUint16(44, 0); // macStyle (Regular)
    data.setUint16(46, 8); // lowestRecPPEM
    data.setInt16(48, 2); // fontDirectionHint
    data.setInt16(50, 0); // indexToLocFormat
    data.setInt16(52, 0); // glyphDataFormat
    return data.buffer.asUint8List();
  }

  static Uint8List _buildHheaTable(
    List<_TransformedGlyph> glyphs,
    FontGeneratorConfig config,
    BoundingBox fontBBox,
  ) {
    var maxAdvance = 0;
    var minLsb = 0;
    var minRsb = 0;
    var maxExtent = 0;

    for (final g in glyphs) {
      if (g.advanceWidth > maxAdvance) maxAdvance = g.advanceWidth;
      final lsb = g.leftSideBearing;
      final rsb = g.advanceWidth - (lsb + g.bbox.width.round());
      final extent = lsb + g.bbox.width.round();
      if (lsb < minLsb) minLsb = lsb;
      if (rsb < minRsb) minRsb = rsb;
      if (extent > maxExtent) maxExtent = extent;
    }

    final data = ByteData(36);
    data.setUint16(0, 1); // majorVersion
    data.setUint16(2, 0); // minorVersion
    data.setInt16(4, config.ascent); // ascender
    data.setInt16(6, config.descent); // descender
    data.setInt16(8, 0); // lineGap
    data.setUint16(10, maxAdvance); // advanceWidthMax
    data.setInt16(12, minLsb); // minLeftSideBearing
    data.setInt16(14, minRsb); // minRightSideBearing
    data.setInt16(16, maxExtent); // xMaxExtent
    data.setInt16(18, 1); // caretSlopeRise
    data.setInt16(20, 0); // caretSlopeRun
    data.setInt16(22, 0); // caretOffset
    // 24..30 reserved (0)
    data.setInt16(32, 0); // metricDataFormat
    data.setUint16(34, glyphs.length); // numberOfHMetrics
    return data.buffer.asUint8List();
  }

  static Uint8List _buildMaxpTable(int numGlyphs) {
    // CFF OpenType fonts use maxp version 0.5 (0x00005000), length 6 bytes
    final data = ByteData(6);
    data.setUint32(0, 0x00005000);
    data.setUint16(4, numGlyphs);
    return data.buffer.asUint8List();
  }

  static Uint8List _buildHmtxTable(List<_TransformedGlyph> glyphs) {
    final data = ByteData(glyphs.length * 4);
    for (var i = 0; i < glyphs.length; i++) {
      data.setUint16(i * 4, glyphs[i].advanceWidth);
      data.setInt16(i * 4 + 2, glyphs[i].leftSideBearing);
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _buildOs2Table(
    List<_TransformedGlyph> glyphs,
    FontGeneratorConfig config,
  ) {
    final iconGlyphs = glyphs.skip(1).toList();
    final firstChar = iconGlyphs.isEmpty
        ? 0xFFFF
        : iconGlyphs.first.codePoint.clamp(0, 0xFFFF);
    final lastChar = iconGlyphs.isEmpty
        ? 0xFFFF
        : iconGlyphs.last.codePoint.clamp(0, 0xFFFF);

    final data = ByteData(96); // OS/2 version 4
    data.setUint16(0, 4); // version
    data.setInt16(2, config.unitsPerEm); // xAvgCharWidth
    data.setUint16(4, 400); // usWeightClass (Normal)
    data.setUint16(6, 5); // usWidthClass (Medium)
    data.setUint16(8, 0); // fsType (Installable embedding)
    data.setInt16(10, (config.unitsPerEm * 0.65).round()); // ySubscriptXSize
    data.setInt16(12, (config.unitsPerEm * 0.60).round()); // ySubscriptYSize
    data.setInt16(14, 0); // ySubscriptXOffset
    data.setInt16(16, (config.unitsPerEm * 0.14).round()); // ySubscriptYOffset
    data.setInt16(18, (config.unitsPerEm * 0.65).round()); // ySuperscriptXSize
    data.setInt16(20, (config.unitsPerEm * 0.60).round()); // ySuperscriptYSize
    data.setInt16(22, 0); // ySuperscriptXOffset
    data.setInt16(24, (config.unitsPerEm * 0.48).round()); // ySuperscriptYOffset
    data.setInt16(26, (config.unitsPerEm * 0.05).round()); // yStrikeoutSize
    data.setInt16(28, (config.unitsPerEm * 0.26).round()); // yStrikeoutPosition
    data.setInt16(30, 0); // sFamilyClass
    // panose (10 bytes at 32..41) -> 0
    // ulUnicodeRange1..4 (16 bytes at 42..57) -> bit 57 (Private Use Area)
    data.setUint32(50, 1 << (57 - 32));
    // achVendID (4 bytes at 58..61) -> 'DART'
    data.setUint8(58, 0x44);
    data.setUint8(59, 0x41);
    data.setUint8(60, 0x52);
    data.setUint8(61, 0x54);
    data.setUint16(62, 0x0040); // fsSelection (REGULAR)
    data.setUint16(64, firstChar); // usFirstCharIndex
    data.setUint16(66, lastChar); // usLastCharIndex
    data.setInt16(68, config.ascent); // sTypoAscender
    data.setInt16(70, config.descent); // sTypoDescender
    data.setInt16(72, 0); // sTypoLineGap
    data.setUint16(74, config.ascent.clamp(0, 0xFFFF)); // usWinAscent
    data.setUint16(76, (-config.descent).clamp(0, 0xFFFF)); // usWinDescent
    data.setUint32(78, 1); // ulCodePageRange1
    data.setUint32(82, 0); // ulCodePageRange2
    data.setInt16(86, (config.unitsPerEm * 0.5).round()); // sxHeight
    data.setInt16(88, (config.unitsPerEm * 0.7).round()); // sCapHeight
    data.setUint16(90, 0); // usDefaultChar
    data.setUint16(92, 0x0020); // usBreakChar
    data.setUint16(94, 1); // usMaxContext
    return data.buffer.asUint8List();
  }

  static Uint8List _buildCmapTable(List<_TransformedGlyph> glyphs) {
    final bmpEntries = <MapEntry<int, int>>[];
    for (var i = 1; i < glyphs.length; i++) {
      final cp = glyphs[i].codePoint;
      if (cp <= 0xFFFF) {
        bmpEntries.add(MapEntry(cp, i));
      }
    }

    final format4 = _buildCmapFormat4(bmpEntries);
    final format12 = _buildCmapFormat12(glyphs);

    // Header: version (2) + numTables (2) + 2 * encodingRecord (8 each) = 20 bytes
    const headerLen = 20;
    final offset4 = headerLen;
    final offset12 = offset4 + format4.length;

    final header = ByteData(headerLen);
    header.setUint16(0, 0); // version
    header.setUint16(2, 2); // numTables

    // Record 0: Platform 3 (Windows), Encoding 1 (Unicode BMP)
    header.setUint16(4, 3);
    header.setUint16(6, 1);
    header.setUint32(8, offset4);

    // Record 1: Platform 3 (Windows), Encoding 10 (Unicode Full Repertoire)
    header.setUint16(12, 3);
    header.setUint16(14, 10);
    header.setUint32(16, offset12);

    final builder = BytesBuilder()
      ..add(header.buffer.asUint8List())
      ..add(format4)
      ..add(format12);
    return builder.toBytes();
  }

  static Uint8List _buildCmapFormat4(List<MapEntry<int, int>> bmpEntries) {
    // Merge contiguous (codePoint, glyphId) ranges into compact segments
    final startCodes = <int>[];
    final endCodes = <int>[];
    final idDeltas = <int>[];

    for (final entry in bmpEntries) {
      final cp = entry.key;
      final gid = entry.value;
      final delta = (gid - cp) & 0xFFFF;
      if (startCodes.isNotEmpty &&
          endCodes.last + 1 == cp &&
          idDeltas.last == delta) {
        endCodes[endCodes.length - 1] = cp;
      } else {
        startCodes.add(cp);
        endCodes.add(cp);
        idDeltas.add(delta);
      }
    }

    // Required sentinel segment
    startCodes.add(0xFFFF);
    endCodes.add(0xFFFF);
    idDeltas.add(1);

    final segCount = startCodes.length;
    final segCountX2 = segCount * 2;
    final maxPowerOf2 = 1 << (math.log(segCount) / math.ln2).floor();
    final searchRange = 2 * maxPowerOf2;
    final entrySelector = (math.log(maxPowerOf2) / math.ln2).floor();
    final rangeShift = segCountX2 - searchRange;

    final length = 16 + 4 * segCountX2;
    final data = ByteData(length);
    data.setUint16(0, 4); // format
    data.setUint16(2, length); // length
    data.setUint16(4, 0); // language
    data.setUint16(6, segCountX2);
    data.setUint16(8, searchRange);
    data.setUint16(10, entrySelector);
    data.setUint16(12, rangeShift);

    var offset = 14;
    for (final end in endCodes) {
      data.setUint16(offset, end);
      offset += 2;
    }
    data.setUint16(offset, 0); // reservedPad
    offset += 2;
    for (final start in startCodes) {
      data.setUint16(offset, start);
      offset += 2;
    }
    for (final delta in idDeltas) {
      data.setUint16(offset, delta);
      offset += 2;
    }
    for (var i = 0; i < segCount; i++) {
      data.setUint16(offset, 0); // idRangeOffset = 0
      offset += 2;
    }

    return data.buffer.asUint8List();
  }

  static Uint8List _buildCmapFormat12(List<_TransformedGlyph> glyphs) {
    final startCodes = <int>[];
    final endCodes = <int>[];
    final startGids = <int>[];

    for (var i = 1; i < glyphs.length; i++) {
      final cp = glyphs[i].codePoint;
      if (startCodes.isNotEmpty &&
          endCodes.last + 1 == cp &&
          startGids.last + (endCodes.last - startCodes.last) + 1 == i) {
        endCodes[endCodes.length - 1] = cp;
      } else {
        startCodes.add(cp);
        endCodes.add(cp);
        startGids.add(i);
      }
    }

    final groupsCount = startCodes.length;
    final length = 16 + groupsCount * 12;
    final data = ByteData(length);
    data.setUint16(0, 12); // format 12
    data.setUint16(2, 0); // reserved
    data.setUint32(4, length);
    data.setUint32(8, 0); // language
    data.setUint32(12, groupsCount);

    var offset = 16;
    for (var i = 0; i < groupsCount; i++) {
      data.setUint32(offset, startCodes[i]); // startCharCode
      data.setUint32(offset + 4, endCodes[i]); // endCharCode
      data.setUint32(offset + 8, startGids[i]); // startGlyphID
      offset += 12;
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _buildNameTable(FontGeneratorConfig config) {
    final psName = config.fontFamily.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final records = <int, String>{
      1: config.fontFamily, // Font Family
      2: 'Regular', // Font Subfamily
      3: '${config.fontFamily}-Regular', // Unique ID
      4: config.fontFamily, // Full Font Name
      5: 'Version 1.0', // Version
      6: psName.isEmpty ? 'AppIcons' : psName, // PostScript Name
    };

    final encodedStrings = <Uint8List>[];
    final nameRecords = <ByteData>[];
    var stringOffset = 0;

    for (final entry in records.entries) {
      final utf16Be = _encodeUtf16Be(entry.value);
      final rec = ByteData(12);
      rec.setUint16(0, 3); // platformID = 3 (Windows)
      rec.setUint16(2, 1); // encodingID = 1 (Unicode BMP)
      rec.setUint16(4, 0x0409); // languageID = English (US)
      rec.setUint16(6, entry.key); // nameID
      rec.setUint16(8, utf16Be.length); // length
      rec.setUint16(10, stringOffset); // offset
      nameRecords.add(rec);
      encodedStrings.add(utf16Be);
      stringOffset += utf16Be.length;
    }

    final storageOffset = 6 + nameRecords.length * 12;
    final header = ByteData(6);
    header.setUint16(0, 0); // format
    header.setUint16(2, nameRecords.length); // count
    header.setUint16(4, storageOffset); // stringOffset

    final builder = BytesBuilder()..add(header.buffer.asUint8List());
    for (final rec in nameRecords) {
      builder.add(rec.buffer.asUint8List());
    }
    for (final str in encodedStrings) {
      builder.add(str);
    }
    return builder.toBytes();
  }

  static Uint8List _encodeUtf16Be(String s) {
    final units = s.codeUnits;
    final data = ByteData(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      data.setUint16(i * 2, units[i]);
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _buildPostTable() {
    // Version 3.0 post table (32 bytes, standard for OpenType/CFF fonts)
    final data = ByteData(32);
    data.setUint32(0, 0x00030000); // version 3.0
    data.setInt32(4, 0); // italicAngle
    data.setInt16(8, -100); // underlinePosition
    data.setInt16(10, 50); // underlineThickness
    data.setUint32(12, 0); // isFixedPitch
    return data.buffer.asUint8List();
  }

  static Uint8List _assembleSfnt(Map<String, Uint8List> tables) {
    final tags = tables.keys.toList()..sort();
    final numTables = tags.length;
    final maxPowerOf2 = 1 << (math.log(numTables) / math.ln2).floor();
    final searchRange = maxPowerOf2 * 16;
    final entrySelector = (math.log(maxPowerOf2) / math.ln2).floor();
    final rangeShift = numTables * 16 - searchRange;

    final headerSize = 12 + numTables * 16;
    var currentOffset = headerSize;

    final directory = ByteData(headerSize);
    // OpenType with CFF outlines uses 'OTTO' (0x4F54544F)
    directory.setUint32(0, 0x4F54544F);
    directory.setUint16(4, numTables);
    directory.setUint16(6, searchRange);
    directory.setUint16(8, entrySelector);
    directory.setUint16(10, rangeShift);

    var headOffset = 0;

    for (var i = 0; i < numTables; i++) {
      final tag = tags[i];
      final bytes = tables[tag]!;
      final recOffset = 12 + i * 16;

      for (var c = 0; c < 4; c++) {
        directory.setUint8(recOffset + c, tag.codeUnitAt(c));
      }
      directory.setUint32(recOffset + 4, _computeTableChecksum(bytes));
      directory.setUint32(recOffset + 8, currentOffset);
      directory.setUint32(recOffset + 12, bytes.length);

      if (tag == 'head') {
        headOffset = currentOffset;
      }

      final paddedLength = (bytes.length + 3) & ~3;
      currentOffset += paddedLength;
    }

    final fontBytes = Uint8List(currentOffset);
    fontBytes.setRange(0, headerSize, directory.buffer.asUint8List());

    var writeOffset = headerSize;
    for (final tag in tags) {
      final bytes = tables[tag]!;
      fontBytes.setRange(writeOffset, writeOffset + bytes.length, bytes);
      writeOffset += (bytes.length + 3) & ~3;
    }

    // Compute global checkSumAdjustment in 'head' table (offset + 8)
    final totalChecksum = _computeTableChecksum(fontBytes);
    final adjustment = (0xB1B0AFBA - totalChecksum) & 0xFFFFFFFF;
    final fontData = ByteData.sublistView(fontBytes);
    fontData.setUint32(headOffset + 8, adjustment);

    return fontBytes;
  }

  static int _computeTableChecksum(Uint8List bytes) {
    final paddedLen = (bytes.length + 3) & ~3;
    final padded = Uint8List(paddedLen);
    padded.setRange(0, bytes.length, bytes);
    final data = ByteData.sublistView(padded);

    var sum = 0;
    for (var i = 0; i < paddedLen; i += 4) {
      sum = (sum + data.getUint32(i)) & 0xFFFFFFFF;
    }
    return sum;
  }
}
