# fsuite Test Suite - Quick Start

## Overview

This test suite provides comprehensive coverage for all fsuite tools with 259 total test cases across 6 suites.

## Files Created

```
test_fsearch.sh       - 37 tests for fsearch tool
test_fcontent.sh      - 47 tests for fcontent tool
test_fmap.sh          - 58 tests for fmap tool
test_ftree.sh         - 54 tests for ftree tool
test_integration.sh   - 33 tests for tool pipelines
run_all_tests.sh      - Master test runner
TESTING.md            - Complete testing documentation
```

## Quick Start

### Run All Tests

```bash
bash run_all_tests.sh
```

### Run Individual Tool Tests

```bash
# Test file search
bash test_fsearch.sh

# Test content search
bash test_fcontent.sh

# Test code cartography
bash test_fmap.sh

# Test directory tree
bash test_ftree.sh

# Test pipelines
bash test_integration.sh
```

## Prerequisites

### Required
- bash 4.0+
- find (standard POSIX tool)

### Optional
- **tree** - For ftree tests (install: `sudo apt install tree`)
- **ripgrep (rg)** - For fcontent tests (install: `sudo apt install ripgrep`)
- **fd** - For faster fsearch backend (install: `sudo apt install fd-find`)

Without optional dependencies, relevant tests will be automatically skipped.

## What Gets Tested

### fsearch (37 tests)
✓ Pattern matching (globs, extensions, wildcards)
✓ Output formats (pretty, paths, JSON)
✓ Backend selection (find, fd, auto)
✓ Path handling and error cases

### fcontent (47 tests)
✓ Directory and stdin modes
✓ Output formats and JSON structure
✓ Query handling (case, multi-word, special chars)
✓ rg-args pass-through
✓ Limits and edge cases

### fmap (58 tests)
✓ Language extraction (all 12: Python, JS, TS, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash)
✓ Per-language exact parsing (type validation, symbol counts, zero-duplication)
✓ Dedup regression (JS arrow functions, cross-language)
✓ All three modes (directory, single file, stdin)
✓ Output formats (pretty, paths, JSON)
✓ Filters, caps, and precedence rules
✓ Default ignore, shebang detection, pipeline

### ftree (54 tests)
✓ Tree mode with smart defaults
✓ Recon mode (sizes and counts)
✓ Snapshot mode (recon + tree)
✓ Depth, truncation, ignore patterns
✓ All output formats

### Integration (33 tests)
✓ fsearch → fcontent pipelines
✓ Multi-stage pipelines
✓ Real-world workflows (security, code quality, log analysis)
✓ Complete agent workflows
✓ Error handling

## Test Output

```
======================================
  fsearch Test Suite
======================================

Running tests...

✓ Version output format is correct
✓ Help output is displayed
✓ Glob pattern *.log finds all .log files
...

======================================
  Test Results
======================================
Total:  37
Passed: 37
All tests passed!
```

## Common Issues

### Missing Dependencies

If you see warnings like:
```
Warning: ripgrep (rg) not installed. Some tests will be skipped.
```

Install the missing tool:
```bash
# Debian/Ubuntu
sudo apt install ripgrep tree fd-find

# Or check install hints
./fcontent --install-hints
./ftree --install-hints
```

### Environment Issues

The tools use bash process substitution which requires `/dev/fd`. If you encounter errors like:
```
/dev/fd/63: No such file or directory
```

This means your environment doesn't have `/dev/fd` mounted (some restricted containers). The tests document correct behavior but need a standard Linux environment to run.

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

Use in CI/CD:
```bash
bash run_all_tests.sh && echo "Ready to deploy" || echo "Tests failed"
```

## Test Coverage

| Tool | Test Cases | Coverage |
|------|-----------|----------|
| fsearch | 37 | Pattern matching, backends, output formats, error handling |
| fcontent | 47 | Search modes, queries, rg-args, limits, edge cases |
| fmap | 58 | Language extraction (12 langs), exact parsing, dedup regression, modes, filters, caps, pipeline |
| ftree | 54 | Tree/recon/snapshot modes, ignore patterns, validation |
| Integration | 33 | Pipelines, workflows, real-world use cases |
| Telemetry | 30 | Tiered telemetry, hardware detection, machine profile |
| **Total** | **259** | **Comprehensive end-to-end coverage** |

## Next Steps

1. Run the tests: `bash run_all_tests.sh`
2. Review any failures
3. Check TESTING.md for detailed documentation
4. Add tests for new features

## Quick Reference

```bash
# Run all tests
bash run_all_tests.sh

# Run specific test suite
bash test_fsearch.sh
bash test_fcontent.sh
bash test_fmap.sh
bash test_ftree.sh
bash test_integration.sh

# Check tool versions
./fsearch --version
./fcontent --version
./fmap --version
./ftree --version

# Check dependencies
./fsearch --self-check
./fcontent --self-check
./fmap --self-check
./ftree --self-check
```

## Documentation

- **TESTING.md** - Complete testing documentation
- **README.md** - Main fsuite documentation
- **docs/ftree.md** - Detailed ftree documentation

## Questions?

Run the help command for any tool:
```bash
./fsearch --help
./fcontent --help
./fmap --help
./ftree --help
```