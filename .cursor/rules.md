# SPORTSDUG Mobile UX Rules (Authoritative)

## FONT ENFORCEMENT (NON-NEGOTIABLE)

- Font family MUST be Inter
- Roboto is forbidden
- Fonts must be defined in ThemeData, not per widget
- Font sizes and weights must match design spec exactly
- If font mismatch is detected, refactor instead of compensating with spacing

### Font Family Setup

**Primary Font:** Inter  
**Fallback:** System Sans Serif

❌ Do NOT use Roboto  
❌ Do NOT rely on default Material font

### Required Font Files

Font files must be placed in `assets/fonts/`:
- `Inter-Regular.ttf` (weight: 400)
- `Inter-Medium.ttf` (weight: 500)
- `Inter-SemiBold.ttf` (weight: 600)
- `Inter-Bold.ttf` (weight: 700)

### Global Theme Configuration

ThemeData MUST include:
```dart
ThemeData(
  fontFamily: 'Inter',
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14),
  ),
)
```

⚠️ If this is missing → FAIL  
Cursor must NOT apply fonts per-widget manually.

### Exact Text Styles (LOCK THESE)

**Profile Name:**
```dart
TextStyle(
  fontFamily: 'Inter',
  fontSize: 20,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.2,
)
```

**Section Headers (Sports Identity, Friends, etc.):**
```dart
TextStyle(
  fontFamily: 'Inter',
  fontSize: 16,
  fontWeight: FontWeight.w600,
)
```

**Body Text:**
```dart
TextStyle(
  fontFamily: 'Inter',
  fontSize: 14,
  fontWeight: FontWeight.w400,
)
```

**Stat Numbers (42, 18, 6):**
```dart
TextStyle(
  fontFamily: 'Inter',
  fontSize: 20,
  fontWeight: FontWeight.w700,
)
```

**Button Text:**
```dart
TextStyle(
  fontFamily: 'Inter',
  fontSize: 14,
  fontWeight: FontWeight.w600,
)
```

### Line Height & Density Rules

- DO NOT set height unless specified
- Use default Inter line height
- No extra padding inside Text widgets
- ❌ No TextHeightBehavior overrides
- ❌ No Material 3 density scaling

### Icon + Text Alignment Fix

When using icons with text:
```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.center,
)
```

Inter has tighter vertical metrics — misalignment here causes "cheap" look.

