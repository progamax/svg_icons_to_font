import 'dart:io';

import 'package:args/args.dart';
import 'package:svg_icons_to_font/svg_icons_to_font.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'input',
      abbr: 'i',
      help: 'Input directory containing .svg icon files.',
      mandatory: true,
    )
    ..addOption(
      'font-output',
      abbr: 'f',
      help: 'Output path for the generated .otf font file.',
      defaultsTo: 'assets/fonts/app_icons.otf',
    )
    ..addOption(
      'dart-output',
      abbr: 'd',
      help: 'Output path for the generated Flutter Dart class.',
      defaultsTo: 'lib/app_icons.dart',
    )
    ..addOption(
      'font-family',
      abbr: 'n',
      help: 'Font family name inside the OTF and Flutter IconData.',
      defaultsTo: 'AppIcons',
    )
    ..addOption(
      'class-name',
      abbr: 'c',
      help: 'Name of the generated Dart class.',
      defaultsTo: 'AppIcons',
    )
    ..addOption(
      'font-package',
      abbr: 'p',
      help: 'Optional Flutter package name for IconData.fontPackage.',
    )
    ..addOption(
      'start-codepoint',
      help: 'Starting Unicode codepoint (hex or decimal, e.g. 0xE000).',
      defaultsTo: '0xE000',
    )
    ..addFlag(
      'normalize',
      help: 'Scale and center icons within the EM square.',
      defaultsTo: true,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show usage information.',
    );

  try {
    if (arguments.contains('-h') || arguments.contains('--help')) {
      _printUsage(parser);
      return;
    }

    final results = parser.parse(arguments);
    final inputDir = results['input'] as String;
    final fontOutput = results['font-output'] as String;
    final dartOutput = results['dart-output'] as String;
    final fontFamily = results['font-family'] as String;
    final className = results['class-name'] as String;
    final fontPackage = results['font-package'] as String?;
    final startCodePointRaw = results['start-codepoint'] as String;
    final normalize = results['normalize'] as bool;

    final startCodePoint = int.parse(startCodePointRaw);

    final config = FontGeneratorConfig(
      inputDir: inputDir,
      fontOutputPath: fontOutput,
      dartOutputPath: dartOutput,
      fontFamily: fontFamily,
      className: className,
      fontPackage: fontPackage,
      startCodePoint: startCodePoint,
      normalize: normalize,
    );

    final result = await SvgIconsToFontGenerator.generate(config);
    stdout.writeln(
      'Generated ${result.glyphs.length} icon(s):\n'
      '  • OTF font : ${result.fontOutputPath} (${result.fontBytes.length} bytes)\n'
      '  • Dart file: ${result.dartOutputPath}',
    );
  } on Object catch (e) {
    stderr.writeln('Error: $e\n');
    _printUsage(parser);
    exitCode = 64;
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln(
    'Usage: dart run svg_icons_to_font --input <svg_dir> [options]\n\n'
    'Options:\n${parser.usage}',
  );
}
