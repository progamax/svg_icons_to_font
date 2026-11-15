import 'dart:typed_data';

/// CFF Type 2 charstring operator byte codes.
abstract final class CffCharstringOp {
  static const int rlineto = 5;
  static const int rrcurveto = 8;
  static const int endchar = 14;
  static const int rmoveto = 21;
  static const int fixed1616 = 255;
}

/// CFF Top DICT and Private DICT operator byte codes.
abstract final class CffDictOp {
  static const int fullName = 2;
  static const int familyName = 3;
  static const int fontBBox = 5;
  static const int charset = 15;
  static const int charStrings = 17;
  static const int privateDict = 18;
  static const int defaultWidthX = 20;
  static const int nominalWidthX = 21;
  static const int int16 = 28;
  static const int int32 = 29;
  static const int realNumber = 30;
  static const List<int> charstringType = [12, 6];
  static const List<int> fontMatrix = [12, 7];
}

/// Encodes numbers and INDEX structures in the Adobe Compact Font Format (CFF).
abstract final class CffCodec {
  /// Encodes an integer operand for a CFF Type 2 charstring.
  static void encodeCharstringInt(List<int> out, int v) {
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
      out.add(CffCharstringOp.fixed1616);
      out.add((fixed >> 24) & 0xFF);
      out.add((fixed >> 16) & 0xFF);
      out.add((fixed >> 8) & 0xFF);
      out.add(fixed & 0xFF);
    }
  }

  /// Encodes an integer operand for a CFF DICT.
  static void encodeDictInt(List<int> out, int v) {
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
      out.add(CffDictOp.int16);
      out.add((v >> 8) & 0xFF);
      out.add(v & 0xFF);
    } else {
      encodeDictInt32Fixed(out, v);
    }
  }

  /// Encodes a 32-bit integer in fixed 5-byte CFF DICT format (opcode 29).
  static void encodeDictInt32Fixed(List<int> out, int v) {
    out.add(CffDictOp.int32);
    out.add((v >> 24) & 0xFF);
    out.add((v >> 16) & 0xFF);
    out.add((v >> 8) & 0xFF);
    out.add(v & 0xFF);
  }

  /// Encodes a floating-point number in CFF DICT real format (opcode 30, nibble-packed BCD).
  static void encodeDictReal(List<int> out, double value) {
    out.add(CffDictOp.realNumber);
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

  /// Builds a CFF INDEX structure from a list of binary [objects].
  static Uint8List buildIndex(List<Uint8List> objects) {
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
}
