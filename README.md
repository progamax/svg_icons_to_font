# svg_icons_to_font

Un package **100 % Dart** (avec CLI et API programmable) qui convertit un dossier d'icônes `.svg` en une police OpenType (`.otf` / CFF) et génère automatiquement la classe Dart contenant les `IconData` pour Flutter.

## Fonctionnalités

- **Pur Dart** : aucune dépendance système externe (`fontforge`, `node`, `python` ne sont pas requis).
- **Support SVG complet** : `<path>` (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z`), `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`, `<polyline>`, `<line>`.
- **Génération OpenType `.otf`** : tables SFNT `CFF `, `OS/2`, `cmap` (formats 4 et 12), `head`, `hhea`, `hmtx`, `maxp`, `name`, `post`.
- **Classe Flutter prête à l'emploi** : constantes `static const IconData` en `camelCase` + dictionnaire `values`.

## Utilisation en CLI

```bash
dart run svg_icons_to_font \
  --input assets/svg \
  --font-output assets/fonts/app_icons.otf \
  --dart-output lib/ui/app_icons.dart \
  --font-family AppIcons \
  --class-name AppIcons
```

## Utilisation via l'API Dart

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
  print('Police générée : ${result.fontOutputPath}');
  print('Fichier Dart   : ${result.dartOutputPath}');
}
```

## Déclaration dans le `pubspec.yaml` de votre application Flutter

```yaml
flutter:
  fonts:
    - family: AppIcons
      fonts:
        - asset: assets/fonts/app_icons.otf
```
