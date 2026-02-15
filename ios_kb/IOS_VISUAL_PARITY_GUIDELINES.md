# iOS Visual Parity Guidelines

## Goal
Make iOS look and feel like the current Android app, not a redesign.

## 1. Design System Parity
Android theme source:
- `app/src/main/java/com/synapsenotes/ai/ui/theme/Color.kt`
- `app/src/main/java/com/synapsenotes/ai/ui/theme/Theme.kt`
- `app/src/main/java/com/synapsenotes/ai/ui/theme/Type.kt`

Use equivalent tokens in iOS (SwiftUI `Color` + typography constants).

## 2. Color Tokens (Mirror Exactly)
- `Primary`: `#6650A5`
- `PrimaryDark`: `#513F84`
- `PrimaryLight`: `#8B7FC7`
- `Secondary`: `#625B71`
- `Tertiary`: `#7D5260`
- `BackgroundLight`: `#F7F6F7`
- `BackgroundDark`: `#17151D`
- `SurfaceLight`: `#FFFFFF`
- `SurfaceDark`: `#25232B`
- `OnSurfaceLight`: `#1C1B1F`
- `OnSurfaceDark`: `#EDEDED`
- `SecondaryText`: `#A8A5B1`
- `GreenSuccess`: `#22C55E`
- `RedError`: `#DC2626`
- Chat bubble AI background: `#EADCF5`

Rules:
- Keep same light/dark palettes.
- Do not replace with iOS default blue accent.
- Keep subtle selected-state indicator tint (primary at low alpha).

## 3. Typography Parity
Android uses sans-serif system font with Material 3 style scale.

iOS mapping rule:
- Use SF Pro (system) but preserve Android visual hierarchy and weights.
- Keep these functional sizes:
  - Note title editor: ~28pt bold
  - Top bar feature titles: medium/large title
  - Body text: ~14-16pt
  - Labels/chips/meta: ~11-12pt
- Preserve contrast between `title`, `body`, and `metadata`.

## 4. Shape and Spacing Parity
From current screens:
- Rounded controls/chips/cards: 16dp baseline (about 16pt)
- Search field: pill-like radius ~24
- FAB corners: rounded rectangle (~16)
- Message spacing: airy vertical rhythm (about 12-16)
- Screen horizontal padding: ~16

iOS rules:
- Use consistent 16pt rhythm across cards, paddings, and button radii.
- Keep note cards soft-rounded, not sharp iOS table style.
- Keep chat bubbles rounded and visually separated.

## 5. Component Behavior Parity
Bottom navigation (`notes`, `chat`, `files`):
- Persistent tab bar with selected icon tint in primary color.
- Unselected state uses muted on-surface variant color.

Top bars:
- Flat to background (no heavy blur as default style).
- Keep action icons and back behavior same as Android flow.

Search:
- Filled/soft container look, not plain line style.

Chat:
- AI bubbles use dedicated tint (`BubbleAi`) and copied/share affordances.
- Typing indicator visible during generation.
- Context/source chips visible and tappable.

Note detail:
- Large editable title at top.
- AI FAB and bottom toolbar behavior mirrored.
- Preview state must visually differ from normal edit state.

## 6. Motion and Interaction Parity
- Keep transitions quick and unobtrusive.
- Preserve streamed token feel in chat and AI note actions.
- Keep destructive actions explicit with confirmation dialogs.
- Keep swipe-to-delete affordance in notes list.

## 7. Accessibility and Localization Parity
- Keep semantic color meaning:
  - green success
  - red destructive/error
- Maintain readable contrast in dark mode.
- Keep strings externalized for localization (as on Android).

## 8. Visual QA Checklist (Must Pass)
- [ ] Dark/light theme looks close to Android for all main screens.
- [ ] Bottom tabs match iconography intent and selected-state behavior.
- [ ] Note cards, bubbles, and chips use matching radii and spacing.
- [ ] Primary accent appears as purple family, not iOS default blue.
- [ ] Chat AI bubble tint and metadata styling match Android.
- [ ] Note detail title/editor density matches Android feel.
- [ ] Settings and model management screens keep same hierarchy.

