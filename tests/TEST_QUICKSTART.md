# fsuite Test Suite - Quick Start

## Overview

This test suite provides comprehensive coverage for all fsuite tools across 9 suites.

## Files Created

```
test_fsearch.sh       - fsearch coverage
test_fcontent.sh      - fcontent coverage
test_fmap.sh          - fmap coverage
test_fread.sh         - fread coverage
test_fedit.sh         - fedit coverage
test_install.sh       - install.sh and relocatable install coverage
test_ftree.sh         - ftree coverage
test_integration.sh   - pipeline coverage
test_telemetry.sh     - telemetry coverage
run_all_tests.sh      - Master test runner
TESTING.md            - Complete testing documentation
```

## Quick Start

### Run All Tests

```bash
bash run_all_tests.sh
```

`run_all_tests.sh` now defaults to `FSUITE_TELEMETRY=3` unless you override it explicitly.

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

# Test fread
bash test_fread.sh

# Test fedit
bash test_fedit.sh

# Test installer
bash test_install.sh

# Test telemetry
bash test_telemetry.sh
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

### fsearch
✓ Pattern matching (globs, extensions, wildcards)
✓ Output formats (pretty, paths, JSON)
✓ Backend selection (find, fd, auto)
✓ Path handling and error cases

### fcontent
✓ Directory and stdin modes
✓ Output formats and JSON structure
✓ Query handling (case, multi-word, special chars)
✓ rg-args pass-through
✓ Limits and edge cases

### fmap
✓ Language extraction (all 12: Python, JS, TS, Rust, Go, Java, C, C++, Ruby, Lua, PHP, Bash)
✓ Per-language exact parsing (type validation, symbol counts, zero-duplication)
✓ Dedup regression (JS arrow functions, cross-language)
✓ All three modes (directory, single file, stdin)
✓ Output formats (pretty, paths, JSON)
✓ Filters, caps, and precedence rules
✓ Default ignore, shebang detection, pipeline

### fread
✓ Bounded file reads, ranges, head/tail, and context windows
✓ JSON/pretty/paths output
✓ Pipeline modes (stdin paths, unified diff)
✓ Budget caps, truncation hints, telemetry

### fedit
✓ Dry-run-first patching and `--apply` semantics
✓ Exact replacement, before/after anchors, and ambiguity rejection
✓ Symbol-scoped edits via `fmap` JSON
✓ Preconditions, JSON output, and telemetry

### install.sh
✓ Prefix installs into a clean temp directory
✓ Copies all seven tools plus shared assets
✓ Installed tools report versions from the installed prefix
✓ Installed fmetrics finds the packaged predict helper

### ftree
✓ Tree mode with smart defaults
✓ Recon mode (sizes and counts)
✓ Snapshot mode (recon + tree)
✓ Depth, truncation, ignore patterns
✓ All output formats

### Integration
✓ fsearch → fcontent pipelines
✓ Multi-stage pipelines
✓ Real-world workflows (security, code quality, log analysis)
✓ Complete agent workflows
✓ Error handling

### Telemetry
✓ Tiered telemetry (0/1/2/3)
✓ Hardware and machine profile capture
✓ Migration and rollback validation
✓ Project-name and flag accumulation behavior

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

Override telemetry tier when needed:
```bash
FSUITE_TELEMETRY=2 bash run_all_tests.sh
FSUITE_TELEMETRY=3 bash run_all_tests.sh
```

## Test Coverage

| Tool | Test Cases | Coverage |
|------|-----------|----------|
| fsearch | comprehensive | Pattern matching, backends, output formats, error handling |
| fcontent | comprehensive | Search modes, queries, rg-args, limits, edge cases |
| fmap | comprehensive | Language extraction, exact parsing, dedup regression, modes, filters, caps, pipeline |
| fread | comprehensive | File reads, stdin modes, truncation budgets, JSON output, telemetry |
| fedit | comprehensive | Patch safety, symbol scoping, preconditions, dry-run/apply, telemetry |
| install.sh | comprehensive | Prefix install, copied assets, relocatable helper lookup |
| ftree | comprehensive | Tree/recon/snapshot modes, ignore patterns, validation |
| Integration | comprehensive | Pipelines, workflows, real-world use cases |
| Telemetry | comprehensive | Tiered telemetry, hardware detection, machine profile, migration |
| **Total** | **9 suites** | **Comprehensive end-to-end coverage** |

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
bash test_fread.sh
bash test_fedit.sh
bash test_install.sh
bash test_ftree.sh
bash test_telemetry.sh
bash test_integration.sh

# Check tool versions
./fsearch --version
./fcontent --version
./fmap --version
./fread --version
./fedit --version
./ftree --version

# Check dependencies
./fsearch --self-check
./fcontent --self-check
./fmap --self-check
./fread --self-check
./fedit --self-check
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
./fread --help
./fedit --help
./ftree --help
```
