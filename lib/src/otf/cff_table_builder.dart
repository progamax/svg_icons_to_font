import 'dart:typed_data';

import '../config.dart';
import '../svg/geometry.dart';
import 'cff_encoding.dart';
import 'glyph_model.dart';

/// Builds the `CFF ` (Compact Font Format) table for an OpenType font.
abstract final class CffTableBuilder {
  /// First custom String ID (SID) after the 390 standard CFF strings.
  static const int _firstCustomSid = 391;
  static const int _defaultCffUnitsPerEm = 1000;
  static const int _charstringType2 = 2;

  /// Builds the complete `CFF ` table binary.
  static Uint8List buildCffTable(
    List<TransformedGlyph> glyphs,
    FontGeneratorConfig config,
    BoundingBox fontBBox,
  ) {
    // 1. Header (4 bytes: major=1, minor=0, hdrSize=4, offSize=4)
    final header = Uint8List.fromList(const [1, 0, 4, 4]);

    // 2. Name INDEX
    final psFontName = config.fontFamily.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '',
    );
    final safePsName = psFontName.isEmpty ? 'AppIcons' : psFontName;
    final fontNameBytes = Uint8List.fromList(safePsName.codeUnits);
    final nameIndex = CffCodec.buildIndex([fontNameBytes]);

    // 3. String INDEX (custom strings start at SID 391)
    // SID 391: fontFamily
    // SID 392..: glyph names (excluding .notdef which is SID 0)
    final stringObjects = <Uint8List>[
      Uint8List.fromList(config.fontFamily.codeUnits),
      for (final g in glyphs.skip(1)) Uint8List.fromList(g.name.codeUnits),
    ];
    final stringIndex = CffCodec.buildIndex(stringObjects);

    // 4. Global Subr INDEX (empty)
    final globalSubrIndex = CffCodec.buildIndex(const []);

    // 5. Charset (format 0)
    final charsetBytes = _buildCharsetFormat0(glyphs.length);

    // 6. CharStrings INDEX
    final charStringsIndex = CffCodec.buildIndex([
      for (final g in glyphs) g.charstring,
    ]);

    // 7. Private DICT (defaultWidthX and nominalWidthX)
    final privateDictBytes = _buildPrivateDict(config.unitsPerEm);

    // Measure Top DICT size using 0 placeholders (5-byte fixed ints keep size constant)
    final dummyTopDictIndex = CffCodec.buildIndex([
      _buildTopDict(
        config: config,
        fontBBox: fontBBox,
        privateDictLength: privateDictBytes.length,
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

    final topDictIndex = CffCodec.buildIndex([
      _buildTopDict(
        config: config,
        fontBBox: fontBBox,
        privateDictLength: privateDictBytes.length,
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

  /// Builds a Format 0 CFF Charset (1 byte format + 2 bytes SID per glyph excluding `.notdef`).
  static Uint8List _buildCharsetFormat0(int glyphCount) {
    final charsetBuilder = BytesBuilder()..addByte(0); // format 0
    for (var i = 1; i < glyphCount; i++) {
      final sid = _firstCustomSid + i;
      charsetBuilder.addByte((sid >> 8) & 0xFF);
      charsetBuilder.addByte(sid & 0xFF);
    }
    return charsetBuilder.toBytes();
  }

  /// Builds the CFF Private DICT declaring `defaultWidthX` and `nominalWidthX`.
  static Uint8List _buildPrivateDict(int unitsPerEm) {
    final privateDictList = <int>[];
    CffCodec.encodeDictInt(privateDictList, unitsPerEm);
    privateDictList.add(CffDictOp.defaultWidthX);
    CffCodec.encodeDictInt(privateDictList, unitsPerEm);
    privateDictList.add(CffDictOp.nominalWidthX);
    return Uint8List.fromList(privateDictList);
  }

  /// Builds the CFF Top DICT using fixed 5-byte integers for offsets so its byte length is constant.
  static Uint8List _buildTopDict({
    required FontGeneratorConfig config,
    required BoundingBox fontBBox,
    required int privateDictLength,
    required int charsetOffset,
    required int charStringsOffset,
    required int privateDictOffset,
  }) {
    final dict = <int>[];
    // FullName (SID 391) -> op 2
    CffCodec.encodeDictInt(dict, _firstCustomSid);
    dict.add(CffDictOp.fullName);
    // FamilyName (SID 391) -> op 3
    CffCodec.encodeDictInt(dict, _firstCustomSid);
    dict.add(CffDictOp.familyName);
    // FontBBox -> op 5
    CffCodec.encodeDictInt(dict, fontBBox.minX.round());
    CffCodec.encodeDictInt(dict, fontBBox.minY.round());
    CffCodec.encodeDictInt(dict, fontBBox.maxX.round());
    CffCodec.encodeDictInt(dict, fontBBox.maxY.round());
    dict.add(CffDictOp.fontBBox);
    // FontMatrix -> op 12 7 (only needed if unitsPerEm != 1000)
    if (config.unitsPerEm != _defaultCffUnitsPerEm && config.unitsPerEm > 0) {
      final scale = 1.0 / config.unitsPerEm;
      CffCodec.encodeDictReal(dict, scale);
      CffCodec.encodeDictInt(dict, 0);
      CffCodec.encodeDictInt(dict, 0);
      CffCodec.encodeDictReal(dict, scale);
      CffCodec.encodeDictInt(dict, 0);
      CffCodec.encodeDictInt(dict, 0);
      dict.addAll(CffDictOp.fontMatrix);
    }
    // CharstringType 2 -> 12 6
    CffCodec.encodeDictInt(dict, _charstringType2);
    dict.addAll(CffDictOp.charstringType);
    // charset offset -> op 15
    CffCodec.encodeDictInt32Fixed(dict, charsetOffset);
    dict.add(CffDictOp.charset);
    // CharStrings offset -> op 17
    CffCodec.encodeDictInt32Fixed(dict, charStringsOffset);
    dict.add(CffDictOp.charStrings);
    // Private DICT size and offset -> op 18
    CffCodec.encodeDictInt32Fixed(dict, privateDictLength);
    CffCodec.encodeDictInt32Fixed(dict, privateDictOffset);
    dict.add(CffDictOp.privateDict);
    return Uint8List.fromList(dict);
  }
}
