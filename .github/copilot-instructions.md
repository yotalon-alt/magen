<!-- Copilot instructions tailored for this Flutter single-file demo app -->
# Copilot / AI agent instructions (project-specific)

Purpose: make AI contributors productive quickly by documenting the app shape, local conventions, build/test commands, and important code locations to read before changing behavior.

- **Big picture:** This is a small Flutter app implemented primarily in a single file: [lib/main.dart](../lib/main.dart). It uses a BottomNavigationBar with five pages (Home, Exercises, Feedbacks, Statistics, Materials). Feedbacks are stored in-memory in `FeedbackStore.feedbacks` (in [lib/main.dart](../lib/main.dart)).

- **Key files to read first:**
  - [lib/main.dart](../lib/main.dart) — app entrypoint, UI, navigation, and the `FeedbackStore` used as the single data source.
  - [pubspec.yaml](../pubspec.yaml) — dependencies (no third-party persistence packages present).

- **Why the structure is like this:** The project is a starter/demo Flutter app (generated template) that was extended inline. Expect UI, navigation, and simple state to live together; non-trivial changes should consider extracting widgets/services into new files under `lib/`.

- **Data & integration notes:**
  - Feedbacks are plain `Map<String, dynamic>` objects held in `FeedbackStore.feedbacks`. Keys used: `role`, `name`, `scores`, `comment`. See the feedback submission flow in [lib/main.dart](../lib/main.dart).
  - There is no persistence (DB, shared_preferences, or network). Introducing persistence requires adding a package in `pubspec.yaml` and updating platform code only when necessary.
  - Many platform folders (android/, ios/, macos/, windows/, linux/) contain generated plugin registrant files — do not edit generated files directly.

- **Common UI/navigation patterns to follow:**
  - Navigation uses `Navigator.push` with `MaterialPageRoute` (see exercise -> `FeedbackFormPage`). Keep to this pattern for consistency.
  - Pages are defined as Widgets (Stateless/Stateful) directly in `lib/main.dart`. If adding complex pages, extract them to new files named logically (e.g., `lib/pages/feedback_form.dart`).
  - Score selection uses `ChoiceChip` with values {1,3,5}; maintain these discrete values when reusing scoring logic.

- **Build / run / test commands (use from repo root):**
  - `flutter pub get` — fetch deps
  - `flutter analyze` — run static analysis
  - `flutter test` — run unit/widget tests (there is a simple `test/widget_test.dart`)
  - `flutter run -d <device>` — run app locally (emulator or `-d windows`/`-d chrome` etc.)
  - `flutter build apk` / `flutter build ios` / `flutter build windows` — platform builds

- **Project-specific conventions & hints:**
  - Strings are written in Hebrew inside the UI; preserve UTF-8 encoding and RTL considerations when editing.
  - The codebase favors using `const` constructors and widgets where possible (keep this style).
  - Small, isolated changes are preferred: extract services (e.g., persistence) into `lib/services/` and widgets into `lib/widgets/` instead of expanding `main.dart` further.

- **Do / Don't (quick checklist for PRs):**
  - Do: Run `flutter analyze` and `flutter test` before opening PR.
  - Do: Add new files under `lib/` for non-trivial logic or UI.
  - Don't: Modify generated files under platform folders. Avoid changing plugin registrant files.
  - Don't: Replace the in-memory `FeedbackStore` with a network-backed store without adding tests and migration notes.

- **Examples to cite in changes:**
  - Feedback submission flow: see `FeedbackFormPage` and the button that appends to `FeedbackStore.feedbacks` in [lib/main.dart](../lib/main.dart).
  - Feedback display: `FeedbacksPage` reads `FeedbackStore.feedbacks` directly; mirror that shape if you add persistence ([lib/main.dart](../lib/main.dart)).

- **When adding persistence or networking:**
  - Update `pubspec.yaml` to include the package (for example `shared_preferences` or `hive`).
  - Add a `lib/services/feedback_service.dart` that wraps reads/writes and write migration tests.
  - Keep the UI code (widgets) dependent only on a small interface (e.g., `FeedbackRepository`) so testing is simpler.

If anything above is unclear or you want the instructions to include preferred PR titles, branching rules, or CI steps, tell me what to include and I will update this file.
