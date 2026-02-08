# fsuite Test Suite

Comprehensive test suite for the fsuite CLI tools (fsearch, fcontent, ftree).

## Test Files

### Individual Tool Tests

1. **test_fsearch.sh** - Tests for fsearch (file search tool)
   - 37 test cases covering:
     - Basic functionality (version, help, error handling)
     - Pattern matching (globs, extensions, wildcards)
     - Output formats (pretty, paths, json)
     - Backend selection (find, fd, auto)
     - Edge cases and boundary conditions
     - Path handling and integration

1. **test_fcontent.sh** - Tests for fcontent (content search tool)
   - 47 test cases covering:
     - Basic functionality and error handling
     - Directory mode vs stdin mode
     - Output formats (pretty, paths, json)
     - Query handling (case-sensitive, multi-word, special chars)
     - rg-args pass-through
     - Max matches/files limits
     - Edge cases (empty files, binary files, deep structures)

1. **test_fmap.sh** - Tests for fmap (code cartography tool)
   - 58 test cases covering:
     - Basic functionality (version, help, self-check, install-hints)
     - Language extraction (all 12: Python, JS, TS, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash)
     - Bash function forms (both `name()` and `function name`)
     - Single file, directory, and stdin modes
     - Output formats (pretty, paths, json)
     - Filters (--no-imports, -t function/class, -L lang, -m, -n)
     - Precedence rule (-t import overrides --no-imports)
     - Truncation and cap enforcement
     - Negative tests (bad flags, bad types, non-integer args)
     - Telemetry (tool=fmap, backend=grep)
     - Default ignore (node_modules excluded/included)
     - Shebang detection for extensionless files
     - Per-language exact parsing (all 12 languages: Python, JS, TS, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash)
     - Dedup regression (JS arrow functions, cross-language zero-duplication)
     - Pipeline (fsearch | fmap)

1. **test_ftree.sh** - Tests for ftree (directory tree tool)
   - 54 test cases covering:
     - Basic tree mode functionality
     - Recon mode (directory scanning with sizes)
     - Snapshot mode (combined recon + tree)
     - Output formats (pretty, paths, json)
     - Depth and truncation controls
     - Ignore patterns and includes
     - Edge cases and boundary conditions
     - Flag validation

### Integration Tests

1. **test_integration.sh** - Integration tests for tool pipelines
   - 33 test cases covering:
     - fsearch → fcontent pipelines
     - Multi-stage pipelines with shell tools
     - ftree exploration followed by targeted searches
     - Complete agent workflows (scout → structure → find → search)
     - Real-world use cases:
       - Security audits (find secrets, passwords)
       - Code quality scans (TODO/FIXME comments)
       - Log analysis (ERROR/CRITICAL events)
       - Dependency audits (import statements)
     - Error handling in pipelines
     - Performance with large file sets

### Master Test Runner

1. **run_all_tests.sh** - Master script that runs all test suites
   - Runs all six test suites in sequence
   - Provides unified summary
   - Returns appropriate exit codes
## Running the Tests

### Run All Tests

```bash
bash run_all_tests.sh
```

### Run Individual Test Suites

```bash
# Test fsearch
bash test_fsearch.sh

# Test fcontent
bash test_fcontent.sh

# Test ftree
bash test_ftree.sh

# Test integrations
bash test_integration.sh
```

## Test Coverage

### fsearch Coverage
- ✅ Version and help output
- ✅ Pattern normalization (*.log, log, .log all work)
- ✅ Glob patterns (starts-with, contains, ends-with)
- ✅ Wildcard support (*, ?)
- ✅ Output formats (pretty, paths, JSON)
- ✅ Backend selection (find, fd, auto)
- ✅ Max result limits
- ✅ Path handling (absolute, relative, default)
- ✅ Error handling (invalid flags, missing dependencies)
- ✅ Edge cases (no results, empty directories, special characters)
- ✅ JSON structure validation
- ✅ Pipe-ability of paths output

### fcontent Coverage
- ✅ Version and help output
- ✅ Directory mode (recursive search)
- ✅ Stdin mode (piped file lists)
- ✅ Output formats (pretty, paths, JSON)
- ✅ Case-sensitive/insensitive searches
- ✅ Multi-word queries
- ✅ rg-args pass-through (--hidden, -w, etc.)
- ✅ Max matches and max files limits
- ✅ Error handling (missing query, missing rg)
- ✅ Edge cases (empty files, binary files, deep nesting)
- ✅ JSON structure validation
- ✅ Mode detection (directory vs stdin_files)

### fmap Coverage
- ✅ Version and help output
- ✅ Self-check and install hints
- ✅ Language extraction (Python, JS, TS, Rust, Go, Java, Ruby, Bash)
- ✅ Bash function forms (POSIX `name()` and `function name`)
- ✅ Bash source/dot imports, exports, readonly constants
- ✅ Single file mode with correct path in JSON
- ✅ Directory mode (recursive with ignore list)
- ✅ Stdin mode (piped file list)
- ✅ Output formats (pretty, paths, JSON)
- ✅ JSON structure validation (all required fields)
- ✅ Type filtering (-t function, -t class)
- ✅ Import removal (--no-imports)
- ✅ Precedence rule (-t import overrides --no-imports)
- ✅ Force language (-L)
- ✅ Symbol cap (-m) with truncation indicator
- ✅ File cap (-n)
- ✅ Default ignore (node_modules excluded)
- ✅ --no-default-ignore flag
- ✅ Shebang detection for extensionless files
- ✅ Quiet mode (-q)
- ✅ Error handling (bad flags, bad types, non-integer args, non-existent paths)
- ✅ Telemetry (tool=fmap, backend=grep)
- ✅ Pipeline (fsearch | fmap)
- ✅ Per-language exact parsing — all 12 languages (Python, JS, TS, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash)
- ✅ Per-language type validation (function, class, import, type, export, constant per language)
- ✅ Per-language zero-duplication verification via JSON line-number checks
- ✅ Dedup regression — JS `const fn = async () => {}` multi-pattern overlap
- ✅ Cross-language dedup — zero duplicates across all 14 fixture files

### ftree Coverage
- ✅ Version and help output
- ✅ Tree mode with smart defaults
- ✅ Recon mode (sizes and item counts)
- ✅ Snapshot mode (recon + tree in one)
- ✅ Output formats (pretty, paths, JSON)
- ✅ Depth controls
- ✅ Default excludes (node_modules, .git, etc.)
- ✅ Custom ignore patterns
- ✅ Include flag (remove from excludes)
- ✅ Directories-only mode
- ✅ Max lines truncation
- ✅ Filelimit per directory
- ✅ Error handling (invalid flags, missing tree)
- ✅ Edge cases (empty dirs, deep nesting, special chars)
- ✅ JSON metadata fields
- ✅ Budget controls for recon
- ✅ Mutual exclusivity checks

### Integration Coverage
- ✅ fsearch → fcontent pipelines
- ✅ Multiple output format combinations
- ✅ Security scans (.env secrets, config passwords)
- ✅ Code quality scans (TODO/FIXME markers)
- ✅ Log analysis (ERROR/CRITICAL events)
- ✅ Dependency audits (imports)
- ✅ Three-stage pipelines with shell tools
- ✅ ftree exploration workflows
- ✅ Complete agent workflows (4-stage)
- ✅ Snapshot + search workflows
- ✅ Error handling in pipelines
- ✅ Empty result handling
- ✅ Permission error handling
- ✅ Large file sets
- ✅ Deep directory structures

## Test Results Summary

**Total Test Cases: 259**

- fsearch: 37 tests
- fcontent: 47 tests
- fmap: 58 tests
- ftree: 54 tests
- Integration: 33 tests
- Telemetry: 30 tests

## Dependencies

### Required
- **bash** 4.0+ (uses arrays, process substitution)
- **find** (POSIX standard, should be available everywhere)

### Optional (tests will skip if missing)
- **tree** - Required for ftree tree mode tests
- **rg** (ripgrep) - Required for fcontent tests
- **fd** / **fdfind** - Optional faster backend for fsearch

The test suite automatically detects missing dependencies and skips relevant tests with warnings.

## Known Limitations

### Environment Requirements

The fsuite tools use bash process substitution (`< <(command)`), which requires `/dev/fd` to be available. In some restricted/sandboxed environments where `/dev/fd` is not mounted, the tools themselves will not function even though they are syntactically correct.

**Environments where this may occur:**
- Some Docker containers with restricted `/dev`
- Chroot environments without `/dev/fd`
- Certain restricted shells

**Workaround:**
If you encounter `/dev/fd` errors, the tools need to be run in a standard Linux environment with full `/dev` filesystem support.

### Test Output

Tests output colored results:
- ✓ Green = Passed
- ✗ Red = Failed
- Yellow = Warnings (e.g., skipped due to missing dependencies)

## Test Design Philosophy

1. **Comprehensive**: Tests cover normal usage, edge cases, error conditions, and boundary values
2. **Independent**: Each test is self-contained with its own setup/teardown
3. **Fast**: Tests use temporary directories and small data sets
4. **Informative**: Failed tests show detailed error messages
5. **Realistic**: Integration tests simulate real-world workflows
6. **Defensive**: Tests handle missing dependencies gracefully

## Adding New Tests

To add new tests, follow this pattern:

```bash
test_new_feature() {
  # Arrange: set up test data
  local test_file="${TEST_DIR}/test.txt"
  echo "content" > "$test_file"

  # Act: run the command
  local output
  output=$("${TOOL}" "args" 2>&1)

  # Assert: check results
  if [[ "$output" =~ "expected" ]]; then
    pass "Test description"
  else
    fail "Test description" "Got: $output"
  fi
}

# Register in main():
run_test "New feature" test_new_feature
```

## Continuous Integration

The test suite is designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run tests
  run: bash run_all_tests.sh
```

Exit codes:
- `0` = All tests passed
- `1` = One or more tests failed

## Code Quality Checks

The tests themselves serve as:
- **Documentation**: Show how tools are meant to be used
- **Regression prevention**: Catch breaking changes
- **Specification**: Define expected behavior
- **Integration validation**: Verify tools work together

## Performance Benchmarks

Tests include performance checks:
- Large file lists (50+ files)
- Deep directory structures (5+ levels)
- Large output handling (truncation behavior)

## Maintenance

When modifying fsuite tools:
1. Run full test suite before committing
2. Add tests for new features
3. Update tests when changing behavior
4. Keep tests in sync with tool versions

## License

Tests follow the same MIT license as fsuite.