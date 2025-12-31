# Inter Font Files Required

This directory must contain the following Inter font files:

- `Inter-Regular.ttf` (weight: 400)
- `Inter-Medium.ttf` (weight: 500)
- `Inter-SemiBold.ttf` (weight: 600)
- `Inter-Bold.ttf` (weight: 700)

## How to Get Inter Font Files

1. Download Inter font from: https://fonts.google.com/specimen/Inter
2. Extract the font files
3. Copy the following files to this directory:
   - `Inter-Regular.ttf`
   - `Inter-Medium.ttf`
   - `Inter-SemiBold.ttf`
   - `Inter-Bold.ttf`

## Verification

After adding the font files, run:
```bash
flutter pub get
flutter run
```

The app should now use Inter font throughout. If you see any Roboto or default Material fonts, check that:
1. Font files are in `assets/fonts/`
2. `pubspec.yaml` has the font configuration
3. `main.dart` has `fontFamily: 'Inter'` in ThemeData

