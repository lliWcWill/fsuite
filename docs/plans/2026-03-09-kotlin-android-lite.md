# Kotlin And Android-lite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Kotlin v1 structural support to `fmap` and ship a narrow Android-lite bundle covering Gradle Kotlin DSL, `AndroidManifest.xml`, and `res/layout/*.xml`.

**Architecture:** Extend `fmap` in place. Kotlin becomes a new public language in `detect_language()` and `extract_symbols()`, while Android-lite uses narrow internal detection modes for manifest and layout XML so the existing dedupe/output pipeline can stay unchanged. All verification continues through the existing shell test harness in `tests/test_fmap.sh`.

**Tech Stack:** Bash, `grep -E`, `awk`, `sort`, shell test fixtures, JSON verification via Python 3

---

### Task 1: Add Red Tests For Kotlin v1

**Files:**
- Modify: `tests/test_fmap.sh`
- Modify: `fmap`

**Step 1: Write the failing test**

Add Kotlin fixtures inside `setup()` in `tests/test_fmap.sh`:

```bash
cat > "${TEST_DIR}/src/App.kt" <<'KTEOF'
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

const val DEFAULT_TIMEOUT_MS = 5000
val API_ROUTE = "/api"
val localTimeout = 30

sealed interface AuthResult

data class UserSession(val token: String)

object SessionManager

class MainActivity : AppCompatActivity() {
    fun bootstrap(user: String): Boolean {
        return user.isNotEmpty()
    }
}

typealias SessionLoader = (String) -> Boolean
KTEOF

cat > "${TEST_DIR}/src/build.gradle.kts" <<'KTSEOF'
import com.android.build.api.dsl.ApplicationExtension

const val COMPILE_SDK = 34

fun sharedVersionName(): String = "1.0"

plugins {
    id("com.android.application")
    kotlin("android")
}
KTSEOF
```

Add Kotlin tests:

```bash
test_dir_kotlin_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "App.kt" ]] && [[ "$output" =~ "bootstrap" ]] && [[ "$output" =~ "SessionManager" ]]; then
    pass "Kotlin symbols found in directory mode"
  else
    fail "Kotlin symbols missing in directory mode" "$output"
  fi
}

test_parse_kotlin_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/App.kt" "kotlin" "function,class,import,type,constant" 7)
  if [[ "$result" == "OK" ]]; then
    pass "Kotlin exact parse: all types found, no dupes, 7+ symbols"
  else
    fail "Kotlin exact parse failed" "$result"
  fi
}

test_force_lang_kotlin() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L kotlin "${TEST_DIR}/src/App.kt" 2>&1)
  if [[ "$output" =~ "(kotlin)" ]]; then
    pass "-L kotlin forces language detection"
  else
    fail "-L kotlin not effective" "Got: $output"
  fi
}

test_kotlin_constants_are_conservative() {
  local uppercase_property lowercase_property
  uppercase_property=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "const val DEFAULT_TIMEOUT_MS" "constant")
  lowercase_property=$(_assert_symbol_type_not_present_for_text "${TEST_DIR}/src/App.kt" "val localTimeout = 30" "constant")
  if [[ "$uppercase_property" == "OK" && "$lowercase_property" == "OK" ]]; then
    pass "Kotlin constants stay conservative"
  else
    fail "Kotlin constant classification is too broad" "${uppercase_property}|${lowercase_property}"
  fi
}

test_gradle_kts_detects_as_kotlin() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/build.gradle.kts" "kotlin" "function,import,constant" 3)
  if [[ "$result" == "OK" ]]; then
    pass "Gradle Kotlin DSL file is detected as kotlin"
  else
    fail "Gradle Kotlin DSL detection failed" "$result"
  fi
}
```

Wire them into `main()` near the existing Swift and YAML language tests, and extend `test_bad_lang_lists_new_languages()` to expect `kotlin`.

**Step 2: Run test to verify it fails**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: FAIL with at least one Kotlin-related error such as `WRONG_LANG`, `NO_SYMBOLS`, or the invalid `--lang` message missing `kotlin`.

**Step 3: Write minimal implementation**

Update `fmap` to:

- add `kotlin` to help text and `--lang` validation
- detect `.kt` and `.kts`
- add a Kotlin regex table

Representative implementation:

```bash
case "$ext" in
  py|pyw|pyi) echo "python"; return ;;
  js|mjs|cjs|jsx) echo "javascript"; return ;;
  ts|tsx|mts|cts) echo "typescript"; return ;;
  kt|kts) echo "kotlin"; return ;;
  swift) echo "swift"; return ;;
```

```bash
kotlin)
  patterns=(
    "function:^[[:space:]]*((public|private|internal|protected|open|final|override|suspend|inline|operator|infix|tailrec|external|actual|expect)[[:space:]]+)*fun[[:space:]]"
    "class:^[[:space:]]*((public|private|internal|protected|sealed|data|enum|annotation|value|inline|open|abstract|final)[[:space:]]+)*(class|interface|object)[[:space:]]"
    "class:^[[:space:]]*(enum[[:space:]]+class|annotation[[:space:]]+class|data[[:space:]]+class|sealed[[:space:]]+class|sealed[[:space:]]+interface|value[[:space:]]+class)[[:space:]]"
    "import:^[[:space:]]*import[[:space:]]"
    "type:^[[:space:]]*typealias[[:space:]]"
    "constant:^[[:space:]]*(const[[:space:]]+)?val[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]*[:=]"
  )
  ;;
```

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: Kotlin tests pass and the suite ends with `All tests passed!`.

**Step 5: Commit**

```bash
git add tests/test_fmap.sh fmap
git commit -m "feat: add kotlin fmap support"
```

### Task 2: Add Red Tests For Android Manifest Detection

**Files:**
- Modify: `tests/test_fmap.sh`
- Modify: `fmap`

**Step 1: Write the failing test**

Add the manifest fixture in `setup()`:

```bash
mkdir -p "${TEST_DIR}/src/app/src/main"
cat > "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" <<'MANIFESTEOF'
<manifest package="com.example.app">
    <application android:name=".App">
        <activity android:name=".MainActivity" />
        <service android:name=".SyncService" />
        <receiver android:name=".BootReceiver" />
        <provider android:name=".DataProvider" />
    </application>
</manifest>
MANIFESTEOF
```

Add tests:

```bash
test_dir_android_manifest_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" 2>&1)
  if [[ "$output" =~ "(android_manifest)" ]] && [[ "$output" =~ "activity" ]] && [[ "$output" =~ "service" ]]; then
    pass "Android manifest symbols found"
  else
    fail "Android manifest symbols missing" "$output"
  fi
}

test_parse_android_manifest_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" "android_manifest" "class" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Android manifest exact parse: class symbols only, no dupes"
  else
    fail "Android manifest exact parse failed" "$result"
  fi
}

test_android_manifest_is_path_scoped() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/compose.yml" 2>&1)
  if [[ "$output" != *"android_manifest"* ]]; then
    pass "Android manifest detection stays path-scoped"
  else
    fail "Android manifest detection leaked into non-manifest files" "$output"
  fi
}
```

Wire the new tests into `main()`.

**Step 2: Run test to verify it fails**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: FAIL with `WRONG_LANG:` or `NO_SYMBOLS` for `AndroidManifest.xml`.

**Step 3: Write minimal implementation**

Add basename/path detection before the extension switch:

```bash
case "$base" in
  AndroidManifest.xml) echo "android_manifest"; return ;;
esac
```

Add extractor rules:

```bash
android_manifest)
  patterns=(
    "class:^[[:space:]]*<application\\b"
    "class:^[[:space:]]*<activity\\b"
    "class:^[[:space:]]*<service\\b"
    "class:^[[:space:]]*<receiver\\b"
    "class:^[[:space:]]*<provider\\b"
  )
  ;;
```

Do not expose `android_manifest` in `--lang` validation or public help text.

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: manifest tests pass and the suite ends with `All tests passed!`.

**Step 5: Commit**

```bash
git add tests/test_fmap.sh fmap
git commit -m "feat: add android manifest mapping"
```

### Task 3: Add Red Tests For Android Layout Detection

**Files:**
- Modify: `tests/test_fmap.sh`
- Modify: `fmap`

**Step 1: Write the failing test**

Add the layout fixture in `setup()`:

```bash
mkdir -p "${TEST_DIR}/src/app/src/main/res/layout"
cat > "${TEST_DIR}/src/app/src/main/res/layout/activity_main.xml" <<'LAYOUTEOF'
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android">
    <TextView
        android:text="Hello" />
    <com.example.widgets.SessionBanner
        android:layout_width="wrap_content"
        android:layout_height="wrap_content" />
</androidx.constraintlayout.widget.ConstraintLayout>
LAYOUTEOF
```

Add tests:

```bash
test_dir_android_layout_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src/app/src/main/res/layout/activity_main.xml" 2>&1)
  if [[ "$output" =~ "(android_layout)" ]] && [[ "$output" =~ "ConstraintLayout" ]] && [[ "$output" =~ "SessionBanner" ]]; then
    pass "Android layout symbols found"
  else
    fail "Android layout symbols missing" "$output"
  fi
}

test_parse_android_layout_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app/src/main/res/layout/activity_main.xml" "android_layout" "class" 3)
  if [[ "$result" == "OK" ]]; then
    pass "Android layout exact parse: view tags only, no dupes"
  else
    fail "Android layout exact parse failed" "$result"
  fi
}

test_android_layout_is_path_scoped() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" 2>&1)
  if [[ "$output" != *"android_layout"* ]]; then
    pass "Android layout detection stays path-scoped"
  else
    fail "Android layout detection leaked into non-layout files" "$output"
  fi
}
```

Wire the new tests into `main()`.

**Step 2: Run test to verify it fails**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: FAIL with `WRONG_LANG:` or `NO_SYMBOLS` for the layout file.

**Step 3: Write minimal implementation**

Add path-scoped layout detection:

```bash
if [[ "$file" == */res/layout/*.xml ]]; then
  echo "android_layout"
  return
fi
```

Add extractor rules:

```bash
android_layout)
  patterns=(
    "class:^[[:space:]]*<[A-Za-z_][A-Za-z0-9_.]*\\b"
  )
  ;;
```

Keep the rule tag-focused. Do not capture generic attributes in v1.

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: layout tests pass and the suite ends with `All tests passed!`.

**Step 5: Commit**

```bash
git add tests/test_fmap.sh fmap
git commit -m "feat: add android layout mapping"
```

### Task 4: Update Help Text And README

**Files:**
- Modify: `fmap`
- Modify: `README.md`
- Test: `tests/test_fmap.sh`

**Step 1: Write the failing test**

Tighten the existing expectations in `tests/test_fmap.sh`:

```bash
if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "kotlin" ]] && [[ "$output" =~ "dockerfile" ]] && [[ "$output" =~ "yaml" ]]; then
  pass "Invalid --lang error lists kotlin and current public languages"
else
  fail "Invalid --lang error missing kotlin" "rc=${rc:-0}, output=$output"
fi
```

Add a simple doc assertion if needed:

```bash
test_help_lists_kotlin() {
  local output
  output=$("${FMAP}" --help 2>&1)
  if [[ "$output" =~ "kotlin" ]]; then
    pass "Help text lists kotlin"
  else
    fail "Help text missing kotlin" "$output"
  fi
}
```

Wire the test into `main()`.

**Step 2: Run test to verify it fails**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: FAIL because the help text and invalid `--lang` output do not yet include `kotlin`.

**Step 3: Write minimal implementation**

Update `fmap` help text and `README.md`.

Representative help-text change:

```text
Supported: python, javascript, typescript, kotlin, swift, rust, go, java,
           c, cpp, ruby, lua, php, bash, dockerfile, makefile, yaml
```

Representative README updates:

```markdown
| Kotlin | Yes | Yes | Android / Kotlin-first mobile repos |
```

```markdown
- 17 languages / formats: Python, JavaScript, TypeScript, Kotlin, Swift, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash, Dockerfile, Makefile, YAML
```

Add a short Android-lite note in the bundle section clarifying that manifest and layout reconnaissance now lands via narrow path-aware support.

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: help-text tests pass and the suite ends with `All tests passed!`.

**Step 5: Commit**

```bash
git add fmap README.md tests/test_fmap.sh
git commit -m "docs: document kotlin and android-lite support"
```

### Task 5: Final Verification

**Files:**
- Verify: `fmap`
- Verify: `tests/test_fmap.sh`
- Verify: `README.md`

**Step 1: Run targeted smoke checks**

Run:

```bash
bash tests/test_fmap.sh
```

Expected: final summary includes `All tests passed!`.

Run:

```bash
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/app/src/main/res/layout"
cat > "$tmpdir/App.kt" <<'EOF'
import kotlin.collections.List
const val API_URL = "x"
class Greeter
fun hello() = true
EOF
cat > "$tmpdir/app/src/main/AndroidManifest.xml" <<'EOF'
<manifest><application><activity android:name=".MainActivity" /></application></manifest>
EOF
cat > "$tmpdir/app/src/main/res/layout/main.xml" <<'EOF'
<LinearLayout><TextView /></LinearLayout>
EOF
./fmap -o json "$tmpdir"
rm -rf "$tmpdir"
```

Expected: JSON includes `kotlin`, `android_manifest`, and `android_layout` file entries with non-zero symbol counts.

**Step 2: Inspect repo state**

Run:

```bash
git status --short
```

Expected: only intentional changes remain.

**Step 3: Commit**

```bash
git add fmap README.md tests/test_fmap.sh
git commit -m "feat: add kotlin and android-lite fmap support"
```
