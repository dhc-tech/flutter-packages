# Asset Generation - Usage Examples

## 📁 Folder Structure

The asset generation system automatically detects your folder structure and creates organized classes:

```
assets/
├── icons/
│   ├── svg/
│   │   ├── ic_back.svg
│   │   └── ic_home.svg
│   └── png/
│       └── logo.png
├── bottom_bar/
│   ├── svg/
│   │   ├── home.svg
│   │   └── profile.svg
│   └── png/
│       └── background.png
└── fonts/
    └── inter/
        ├── bold.ttf
        ├── regular.ttf
        └── semi-bold.ttf
```

## 🎨 Generated Classes

Based on the above structure, the following classes will be generated:

### Icons

- **`IconsSvg`** - For `assets/icons/svg/`
- **`IconsPng`** - For `assets/icons/png/`

### Bottom Bar

- **`BottomBarSvg`** - For `assets/bottom_bar/svg/`
- **`BottomBarPng`** - For `assets/bottom_bar/png/`

### Fonts

- **`FontsInterTtf`** - For `assets/fonts/inter/`

## 💻 Usage in Code

### Import

```dart
import 'package:your_app/generated/assets.dart';
```

### Using SVG Icons

```dart
import 'package:flutter_svg/flutter_svg.dart';

// Icons from icons/svg folder
SvgPicture.asset(IconsSvg.icBack);
SvgPicture.asset(IconsSvg.icHome);

// Icons from bottom_bar/svg folder
SvgPicture.asset(BottomBarSvg.home);
SvgPicture.asset(BottomBarSvg.profile);
```

### Using PNG Images

```dart
// Icons from icons/png folder
Image.asset(IconsPng.logo);

// Images from bottom_bar/png folder
Image.asset(BottomBarPng.background);
```

### Using Fonts

```dart
Text(
  'Hello World',
  style: TextStyle(
    fontFamily: FontsInterTtf.bold,
  ),
);

Text(
  'Regular Text',
  style: TextStyle(
    fontFamily: FontsInterTtf.regular,
  ),
);
```

## ⚙️ Configuration (dig.yaml)

```yaml
assets-dir: assets/
output-dir: lib/generated

# Optional: Skip specific folders
skip:
  - temp
  - draft
  - icons/old
```

## 🚀 Commands

```bash
# Generate once
dg asset build

# Watch for changes and auto-regenerate
dg asset watch
```

## 📂 Generated File Structure

```
lib/generated/
├── assets.dart                    # Main export (import this)
└── assets/
    ├── icons/
    │   ├── icons_svg.dart         # class IconsSvg
    │   └── icons_png.dart         # class IconsPng
    ├── icons.dart                 # Export file
    ├── bottom_bar/
    │   ├── bottom_bar_svg.dart    # class BottomBarSvg
    │   └── bottom_bar_png.dart    # class BottomBarPng
    ├── bottom_bar.dart            # Export file
    ├── fonts_inter/
    │   └── fonts_inter_ttf.dart   # class FontsInterTtf
    └── fonts_inter.dart           # Export file
```

## 🔍 Sample Generated Code

Here is what a generated file (e.g., `icons_svg.dart`) looks like:

```dart
// lib/generated/assets/icons/icons_svg.dart

class IconsSvg {
  IconsSvg._();

  static const String icBack = 'assets/icons/svg/ic_back.svg';
  static const String icHome = 'assets/icons/svg/ic_home.svg';
  
  static const List<String> values = [icBack, icHome];
}
```

The main `assets.dart` file exports everything for easy access:

```dart
// lib/generated/assets.dart

export 'assets/icons.dart';
export 'assets/bottom_bar.dart';
export 'assets/fonts_inter.dart';
```

## 🎯 Key Features

1. **Subfolder-Based Classes**: Each subfolder gets its own class
   - `assets/bottom_bar/svg/` → `BottomBarSvg`
   - `assets/top_bar/png/` → `TopBarPng`

2. **Smart Naming**: Automatically converts file names to camelCase
   - `ic_back.svg` → `icBack`
   - `semi-bold.ttf` → `semiBold`
   - `MyIcon.png` → `myIcon`

3. **Type Safety**: All asset paths are constants, preventing typos

4. **Single Import**: Just import `assets.dart` to access everything

5. **Skip Feature**: Exclude specific folders from generation

## 💡 Tips

- Keep your folder structure organized by feature or component
- Use descriptive folder names (they become class names)
- Avoid using file extension names as folder names (e.g., don't name a folder `svg`)
- Use the skip feature to exclude temporary or draft assets
