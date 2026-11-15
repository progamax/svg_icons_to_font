# svg_icons_to_font

A **100% pure Dart** package and CLI tool that converts a directory of `.svg` icons into an OpenType (`.otf` / CFF) font file and generates the corresponding Flutter `IconData` class.

## Features

- **Pure Dart**: Zero external system dependencies (`fontforge`, `node`, `python` are not required).
- **Comprehensive SVG support**:
  - Elements: `<path>` (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z`), `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`, `<polyline>`, `<line>`.
  - Nested `<g>` transforms (`translate`, `scale`, `rotate`, `skewX`, `skewY`, `matrix`).
  - Automatic stroke-to-contour expansion (`stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`) and invisible bounding-box filtering.
- **OpenType `.otf` generation**: Builds SFNT tables (`CFF `, `OS/2`, `cmap` formats 4 & 12, `head`, `hhea`, `hmtx`, `maxp`, `name`, `post`).
- **Ready-to-use Flutter class**: Generates `static const IconData` constants in `camelCase` plus a `values` lookup map.

## Installation

Add `svg_icons_to_font` to your `dev_dependencies` in `pubspec.yaml`:

```yaml
dev_dependencies:
  svg_icons_to_font: ^1.0.0
```

Or activate it globally as a CLI tool:

```bash
dart pub global activate svg_icons_to_font
```

## CLI Usage

```bash
dart run svg_icons_to_font \
  --input assets/svg \
  --font-output assets/fonts/app_icons.otf \
  --dart-output lib/ui/app_icons.dart \
  --font-family AppIcons \
  --class-name AppIcons
```

### CLI Options

| Option | Abbr | Default | Description |
| :--- | :---: | :--- | :--- |
| `--input` | `-i` | *(required)* | Input directory containing `.svg` icon files |
| `--font-output` | `-f` | `assets/fonts/app_icons.otf` | Output path for the generated `.otf` font file |
| `--dart-output` | `-d` | `lib/app_icons.dart` | Output path for the generated Flutter Dart class |
| `--font-family` | `-n` | `AppIcons` | Font family name embedded in `.otf` and `IconData` |
| `--class-name` | `-c` | `AppIcons` | Name of the generated Dart class |
| `--font-package` | `-p` | `null` | Optional Flutter package name for `IconData.fontPackage` |
| `--start-codepoint` | | `0xE000` | Starting Unicode Private Use Area codepoint |
| `--units-per-em` | | `1000` | Font units per EM square |
| `--ascent` | | `850` | Typographic ascent in font units |
| `--descent` | | `-150` | Typographic descent in font units |
| `--[no-]normalize` | | `true` | Scale and center icons within the EM square |

## Programmatic Usage

```dart
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
  print('Generated font: ${result.fontOutputPath}');
  print('Generated Dart: ${result.dartOutputPath}');
}
```

## Registering the Font in Flutter

Add the generated `.otf` file to the `flutter.fonts` section of your app's `pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: AppIcons
      fonts:
        - asset: assets/fonts/app_icons.otf
```

Then use the generated icons anywhere in your Flutter widgets:

```dart
Icon(AppIcons.home)
```
