# Testing Strategy

FieldLog's test approach, current state, and where it is headed. This is a
living document — update it as the suite grows.

## Current state

Six test files (~1,000 lines), all pure Dart under `flutter_test`. Coverage is
narrow but deep: the hard, bug-prone logic is well covered; the UI and data
layers are not.

| Area | File | Status |
|---|---|---|
| Expression engine (SurveyJS semantics) | `test/utils/expression_engine_test.dart` | Thorough — operators, precedence, fail-open, JS-compat truthiness |
| `SurveyElement` parsing | `test/models/survey_element_test.dart` | Good — dual choice formats, key-name fallbacks, recursion |
| `Session` parsing | `test/models/session_test.dart` | Good |
| `FormComponent` parsing | `test/models/form_component_test.dart` | Good |
| JWT `exp` parsing | `test/services/auth_token_test.dart` | Good |
| Widget smoke test | `test/widget_test.dart` | One test only |

### Gaps

- **Widget/component tests: near zero.** The ~20 field widgets and the three
  renderers (`surveyjs_renderer`, `tally_renderer`, `formkit_renderer`) have no
  meaningful widget coverage.
- **Service/data layer: zero.** `api_service`, `powersync_connector`,
  `auth_service`, `location_service` are untested. No mocking dependency is
  declared.
- **No integration tests** (`integration_test` is not present).
- **No E2E / clickthrough tests** (no Maestro/Patrol/Appium).
- **No golden/screenshot tests.**
- **CI runs no tests and no `flutter analyze`** — both workflows only build the
  APK.

## Testing layers and tooling (2026)

1. **Unit tests** — `flutter test`, pure Dart. The bulk of coverage; fastest.
2. **Widget/component tests** — `testWidgets` + golden tests (`alchemist`,
   `golden_toolkit`). Highest ROI for a UI-heavy app.
3. **Integration tests** — `integration_test`, on a real emulator/device.
4. **E2E / clickthrough** — Maestro (YAML flows, the current default) or Patrol
   (Flutter-native, reaches OS dialogs/permissions). Both run on the
   `budtmo/docker-android` emulator in `docker-compose.yml`.
5. **Cloud device farms** — Firebase Test Lab / BrowserStack / AWS Device Farm
   for release-gate sweeps on real hardware.

## Roadmap

1. **CI gating** (this PR) — run `flutter analyze` + `flutter test` before the
   APK build in both workflows, so a green build means *something*.
2. **Widget + golden tests** for the field widgets and the three renderers.
3. **Service-layer tests** with `mocktail` for the auth/API/PowerSync paths.
4. **Maestro E2E** clickthrough flows (login → browse → fill form → sync)
   against the Docker emulator, in CI via the emulator or a device farm.
5. **Cloud device farm** sweeps before each release.

## Running the suite

```bash
flutter analyze
flutter test
```

Both are fast and run on a plain Linux runner — no device required.
