import 'dart:io';

import 'package:svg_icons_to_font/svg_icons_to_font.dart';

Future<void> main() async {
  const config = FontGeneratorConfig(
    inputDir: 'assets/svg',
    fontOutputPath: 'assets/fonts/app_icons.otf',
    dartOutputPath: 'lib/app_icons.dart',
    fontFamily: 'AppIcons',
    className: 'AppIcons',
    startCodePoint: 0xE000,
  );

  final result = await SvgIconsToFontGenerator.generate(config);

  stdout.writeln('Generated ${result.glyphs.length} icons:');
  stdout.writeln('  Font file : ${result.fontOutputPath}');
  stdout.writeln('  Dart class: ${result.dartOutputPath}');
}
