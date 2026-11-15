/// Pure Dart library to convert a folder of SVG icons into an OpenType (.otf)
/// font and a corresponding Flutter `IconData` class.
library svg_icons_to_font;

export 'src/config.dart' show FontGeneratorConfig;
export 'src/dart_class_generator.dart' show DartClassGenerator;
export 'src/generator.dart' show FontGenerationResult, SvgIconsToFontGenerator;
export 'src/otf_writer.dart' show IconGlyph, OtfWriter;
export 'src/svg_parser.dart'
    show
        BoundingBox,
        Matrix2D,
        ParsedSvg,
        PathCommand,
        PathCommandType,
        Point2D,
        SvgParser;
