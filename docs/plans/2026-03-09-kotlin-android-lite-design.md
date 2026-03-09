# Kotlin And Android-lite Design

**Date:** 2026-03-09

## Goal

Add Kotlin v1 structural support to `fmap` and land a narrow Android-lite bundle that improves reconnaissance for modern Android repos without introducing a generic XML or Gradle parser.

## Constraints

- Preserve `fmap`'s current architecture: extension/path detection plus regex-only symbol extraction.
- Keep the implementation dependency-free and compatible with the existing `grep -n -E -I` pipeline.
- Bias toward low-noise output over broad coverage.
- Keep Android-lite as an ecosystem bundle, not a broad new language family.

## Architecture

The change should extend the existing flow in [`fmap`](/home/player3vsgpt/Desktop/Scripts/fsuite/fmap):

1. `detect_language()` maps a file to one language or narrow internal mode.
2. `extract_symbols()` selects a regex table for that mode.
3. The current dedupe, filtering, truncation, and JSON/pretty output logic remains unchanged.

Public user-facing language support grows by one language: `kotlin`.

Android-lite support is added through narrow internal modes:

- `android_manifest`
- `android_layout`

Those labels are intended for detection and output only. They should not be exposed as accepted `--lang` values in v1.

## Scope

### Kotlin v1

Support:

- `.kt`
- `.kts`

Symbol coverage:

- `import`
- `function`
- `class`
- `type`
- `constant`

Expected Kotlin constructs:

- `fun`
- `class`
- `interface`
- `object`
- `enum class`
- `sealed class`
- `sealed interface`
- `data class`
- `annotation class`
- `typealias`
- uppercase `const val`
- uppercase top-level `val`

### Android-lite v1

Support:

- `AndroidManifest.xml`
- `res/layout/*.xml`
- Gradle Kotlin DSL files via `.kts` / `*.gradle.kts`

Android manifest extraction:

- `<application>`
- `<activity>`
- `<service>`
- `<receiver>`
- `<provider>`

Android layout extraction:

- root and nested view tags such as `LinearLayout`, `ConstraintLayout`, `TextView`
- custom fully-qualified view tags

Gradle Kotlin DSL handling:

- treat `.kts` as Kotlin-compatible input
- keep extraction conservative
- prefer imports, top-level declarations, and real Kotlin constructs over broad DSL-call capture

## Detection Rules

`detect_language()` should be extended in this order:

1. Path/basename-specific Android-lite checks
2. Kotlin extension checks
3. Existing language checks

Recommended rules:

- `AndroidManifest.xml` -> `android_manifest`
- `*/res/layout/*.xml` -> `android_layout`
- `*.kt` -> `kotlin`
- `*.kts` -> `kotlin`

There should be no generic `xml` mode in this branch.

## Extraction Rules

### Kotlin

Use conservative regexes that capture declarations instead of broad executable lines.

Recommended categories:

- `import`: `import ...`
- `function`: `fun ...`
- `class`: class/interface/object and class-like variants
- `type`: `typealias ...`
- `constant`: uppercase `const val` and uppercase `val`

The constant rule must avoid ordinary instance properties and lowercase bindings.

### Android Manifest

Use tag-only structural extraction. Skip package/version/sdk attributes and intent-filter details in v1 to avoid noisy output.

### Android Layout

Use tag-level view extraction. Skip broad attribute extraction by default.

`android:id` should remain out of scope unless tests prove it stays clean and useful.

## Testing Strategy

Extend [`tests/test_fmap.sh`](/home/player3vsgpt/Desktop/Scripts/fsuite/tests/test_fmap.sh) with new fixtures and exact-parse checks.

Required fixture coverage:

- Kotlin source file
- Gradle Kotlin DSL file
- Android manifest file
- Android layout file with common and custom views

Required assertions:

- correct detection for `.kt` and `.kts`
- path-scoped Android detection only on manifest/layout paths
- exact symbol coverage for Kotlin and Android-lite surfaces
- false-positive guard for Kotlin constants
- directory-mode visibility for Kotlin and Android-lite files
- no duplicate-line regressions in the expanded fixture set

## Documentation

Update [`README.md`](/home/player3vsgpt/Desktop/Scripts/fsuite/README.md) to:

- add Kotlin to current structural support
- keep Android-lite in the ecosystem bundle section
- note that Android-lite now has narrow manifest/layout reconnaissance support
- update the `fmap` feature count from 16 to 17 user-facing languages/formats

Update `fmap` help text to list Kotlin among supported public languages.

## Non-goals

- generic XML parsing
- legacy Groovy `build.gradle`
- broader Android resource directories beyond `res/layout`
- semantic parsing or cross-file resolution
- exposing Android internal modes via `--lang`

## Risks And Mitigations

### Noise

Risk:
Android XML and Kotlin properties can produce too many low-value matches.

Mitigation:
Keep Android detection path-specific and Kotlin constants uppercase-only.

### Gradle Kotlin DSL under-matching

Risk:
Pure declaration-based Kotlin regexes may under-report some real-world `build.gradle.kts` structure.

Mitigation:
Accept conservative v1 coverage. Prefer low-noise partial support over a broad DSL parser.

### Public surface confusion

Risk:
Users may confuse Android-lite internals with public `--lang` support.

Mitigation:
Document only Kotlin as a new public language. Describe Android-lite as bundle-level support in the README.
