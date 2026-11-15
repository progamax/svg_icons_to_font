/// Configuration options for generating the OTF icon font and Dart class.
class FontGeneratorConfig {
  /// Creates a configuration for [SvgIconsToFontGenerator].
  const FontGeneratorConfig({
    required this.inputDir,
    required this.fontOutputPath,
    required this.dartOutputPath,
    this.fontFamily = 'AppIcons',
    this.className = 'AppIcons',
    this.fontPackage,
    this.startCodePoint = 0xE000,
    this.unitsPerEm = 1000,
    this.ascent = 850,
    this.descent = -150,
    this.normalize = true,
  });

  /// Directory path containing the `.svg` files.
  final String inputDir;

  /// Output file path for the generated `.otf` font file.
  final String fontOutputPath;

  /// Output file path for the generated `.dart` file.
  final String dartOutputPath;

  /// Font family name embedded in the `.otf` file and referenced in `IconData`.
  final String fontFamily;

  /// Name of the generated Dart class containing the `IconData` constants.
  final String className;

  /// Optional Flutter package name if the font is distributed inside a package.
  final String? fontPackage;

  /// Starting Unicode Private Use Area codepoint (default `0xE000`).
  final int startCodePoint;

  /// Font units per EM square (default `1000` for OpenType CFF).
  final int unitsPerEm;

  /// Typographic ascent in font units (default `850`).
  final int ascent;

  /// Typographic descent in font units (default `-150`).
  final int descent;

  /// Whether to normalize and center each SVG icon within the EM square.
  final bool normalize;
}
