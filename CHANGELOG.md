## 1.0.0

- Initial release:
  - Pure Dart SVG parser supporting `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<polygon>`, `<polyline>`, `<line>`, nested transforms, and stroke-to-contour expansion.
  - Pure Dart OpenType (`.otf` / CFF) binary font generator (`CFF `, `OS/2`, `cmap`, `head`, `hhea`, `hmtx`, `maxp`, `name`, `post` tables).
  - Flutter `IconData` class generator with `camelCase` identifiers and icon lookup map.
  - Command-line interface (`svg_icons_to_font`) and programmatic Dart API (`SvgIconsToFontGenerator`).
