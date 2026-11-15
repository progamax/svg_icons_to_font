import 'dart:math' as math;
import 'dart:typed_data';

import '../config.dart';
import '../svg/geometry.dart';
import 'glyph_model.dart';

/// Builds standard OpenType SFNT tables (`head`, `hhea`, `maxp`, `hmtx`,
/// `OS/2`, `cmap`, `name`, `post`) and assembles the final `.otf` binary.
abstract final class SfntTableBuilder {
  /// OpenType with CFF outlines SFNT signature `'OTTO'` (`0x4F54544F`).
  static const int _ottoSignature = 0x4F54544F;

  /// OpenType `head` table magic number (`0x5F0F3CF5`).
  static const int _headMagicNumber = 0x5F0F3CF5;

  /// OpenType global checksum adjustment constant (`0xB1B0AFBA`).
  static const int _sfntChecksumMagic = 0xB1B0AFBA;

  /// `maxp` table version 0.5 for CFF OpenType fonts (`0x00005000`).
  static const int _cffMaxpVersion = 0x00005000;

  /// `post` table version 3.0 (`0x00030000`).
  static const int _postVersion3 = 0x00030000;

  /// Builds the `head` (Font Header) table (54 bytes).
  static Uint8List buildHeadTable(
    FontGeneratorConfig config,
    BoundingBox fontBBox,
    int nowSeconds,
  ) {
    final data = ByteData(54);
    data.setUint16(0, 1); // majorVersion
    data.setUint16(2, 0); // minorVersion
    data.setUint32(4, 0x00010000); // fontRevision 1.0
    data.setUint32(8, 0); // checkSumAdjustment (filled during SFNT assembly)
    data.setUint32(12, _headMagicNumber); // magicNumber
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

  /// Builds the `hhea` (Horizontal Header) table (36 bytes).
  static Uint8List buildHheaTable(
    List<TransformedGlyph> glyphs,
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

  /// Builds the `maxp` (Maximum Profile) table (6 bytes for CFF version 0.5).
  static Uint8List buildMaxpTable(int numGlyphs) {
    final data = ByteData(6);
    data.setUint32(0, _cffMaxpVersion);
    data.setUint16(4, numGlyphs);
    return data.buffer.asUint8List();
  }

  /// Builds the `hmtx` (Horizontal Metrics) table.
  static Uint8List buildHmtxTable(List<TransformedGlyph> glyphs) {
    final data = ByteData(glyphs.length * 4);
    for (var i = 0; i < glyphs.length; i++) {
      data.setUint16(i * 4, glyphs[i].advanceWidth);
      data.setInt16(i * 4 + 2, glyphs[i].leftSideBearing);
    }
    return data.buffer.asUint8List();
  }

  /// Builds the `OS/2` (OS/2 and Windows Metrics) table (version 4, 96 bytes).
  static Uint8List buildOs2Table(
    List<TransformedGlyph> glyphs,
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

  /// Builds the `cmap` (Character to Glyph Index Mapping) table with Format 4 and Format 12 subtables.
  static Uint8List buildCmapTable(List<TransformedGlyph> glyphs) {
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
    const offset4 = headerLen;
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

  static Uint8List _buildCmapFormat12(List<TransformedGlyph> glyphs) {
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

  /// Builds the `name` (Naming) table with UTF-16BE Windows English records.
  static Uint8List buildNameTable(FontGeneratorConfig config) {
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

  /// Builds the `post` (PostScript) table (version 3.0, 32 bytes).
  static Uint8List buildPostTable() {
    final data = ByteData(32);
    data.setUint32(0, _postVersion3); // version 3.0
    data.setInt32(4, 0); // italicAngle
    data.setInt16(8, -100); // underlinePosition
    data.setInt16(10, 50); // underlineThickness
    data.setUint32(12, 0); // isFixedPitch
    return data.buffer.asUint8List();
  }

  /// Assembles all SFNT [tables] into a complete `.otf` binary with table directory and checksums.
  static Uint8List assembleSfnt(Map<String, Uint8List> tables) {
    final tags = tables.keys.toList()..sort();
    final numTables = tags.length;
    final maxPowerOf2 = 1 << (math.log(numTables) / math.ln2).floor();
    final searchRange = maxPowerOf2 * 16;
    final entrySelector = (math.log(maxPowerOf2) / math.ln2).floor();
    final rangeShift = numTables * 16 - searchRange;

    final headerSize = 12 + numTables * 16;
    var currentOffset = headerSize;

    final directory = ByteData(headerSize);
    directory.setUint32(0, _ottoSignature);
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
    final adjustment = (_sfntChecksumMagic - totalChecksum) & 0xFFFFFFFF;
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
