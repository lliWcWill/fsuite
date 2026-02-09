# fsuite Build Summary

**Date:** January 28, 2026
**Version:** 1.3.0
**Maintainer:** Cwilliams333 <cwilliams@futuredial.com>

---

## Overview

fsuite is a filesystem reconnaissance toolkit designed for both human operators and AI agents. It provides composable CLI utilities that turn filesystem exploration into a clean, scriptable, agent-friendly pipeline.

### Design Philosophy

The toolkit addresses a critical gap identified by AI agents during self-assessment:

> "The gap isn't in any single tool. It's in the reconnaissance layer. I have no native way to answer the question: 'What is this project, how big is it, and where should I look first?'"
>
> *-- Claude Code (Opus 4.5), self-assessment, January 2026*

### Target Environment

- **Primary:** Debian 9 (Stretch) - RADi testers at FutureDial
- **Secondary:** Debian 12 (Bookworm) - Bertta hosts and WSL development
- **Compatibility:** Works across all Debian versions 9-12 using static musl binaries

---

## Tools Created

### ftree (v1.2.0) - Directory Structure Visualization

Smart directory snapshot tool with recon mode and agent-friendly output.

**Key Features:**
- Wraps `tree(1)` with intelligent defaults
- Recon mode: per-directory item counts and sizes without full tree expansion
- Snapshot mode: combined recon + tree in one command
- Smart noise filtering: excludes node_modules, .git, venv, __pycache__, etc.
- Three output formats: `pretty`, `paths`, `json`
- Configurable depth, line limits, and file limits
- Context-budget awareness for LLM consumption

**Usage Examples:**
```bash
# Default tree view (depth 3, smart excludes)
ftree /project

# Recon: scout per-directory sizes
ftree --recon /project

# Snapshot: recon + tree in one shot (best for agents)
ftree --snapshot -o json /project

# Drill deeper into subdirectory
ftree -L 5 /project/src
```

### fsearch (v1.0.0) - Filename/Path Search

Fast filename search with glob pattern support and automatic backend selection.

**Key Features:**
- Glob-aware patterns: `'upscale*'`, `'*progress*'`, `'*.log'`
- Smart extension handling: `log`, `.log`, `*.log` all work
- Auto-selects fastest backend: `fd` > `fdfind` > `find`
- Pattern normalization for consistent behavior
- Three output formats: `pretty`, `paths`, `json`

**Usage Examples:**
```bash
# Find all .log files
fsearch '*.log' /var/log

# Files containing 'progress' in name
fsearch '*progress*' /home/user

# Agent-friendly JSON output
fsearch --output json '*token*' /project
```

### fcontent (v1.0.0) - Content Search

Search inside files using ripgrep with piped input support.

**Key Features:**
- Powered by `rg` (ripgrep) for fast content search
- Directory mode: recursive search under a path
- Piped mode: accepts file list from stdin (pairs with `fsearch --output paths`)
- Configurable match and file caps to prevent context overflow
- Pass-through for extra ripgrep flags

**Usage Examples:**
```bash
# Search directory for pattern
fcontent "ERROR" /var/log

# Pipeline: find logs, search inside them
fsearch --output paths '*.log' /var/log | fcontent "CRITICAL"

# JSON output for agents
fcontent --output json "api_key" /project
```

### flog (v1.0.0) - Socket Logger Viewer (NEW in 1.3.0)

Fusion socket logger viewer with clean/slim output for test monitoring.

**Key Features:**
- Commands: `tail`, `snapshot`, `errors`, `search`, `tower`, `info`
- Output modes: `pretty`, `slim`, `json`
- Filters verbose debug logs to show only test-relevant output
- Transforms verbose log lines into readable format
- Light tower status tracking (supports both `radi_status_plugin` and `light_tower_plugin`)

**Filter Patterns:**
- **Included:** test_framework.*, FAIL:/WARNING:/ERROR:, Device grade, LCD grade, CMC/MVDA endpoints, light tower status
- **Excluded:** cherrypy HTTP, fusion_modbus I/O, tntserver internals, state machine transitions

**Usage Examples:**
```bash
# Live stream filtered log
flog tail

# Last 50 filtered lines
flog snapshot 50

# Show errors/warnings only
flog errors 20

# Search for pattern
flog search "mic.*fail"

# Check tower status
flog tower

# JSON output for agents
flog snapshot 100 -o json
```

---

## Build Process

### Package Structure

```
fsuite_1.3.0_amd64/
├── DEBIAN/
│   ├── control          # Package metadata
│   ├── postinst         # Post-install script (chmod +x)
│   └── prerm            # Pre-remove script (cleanup)
├── usr/
│   ├── local/
│   │   └── bin/
│   │       ├── ftree    # Directory structure tool
│   │       ├── fsearch  # Filename search tool
│   │       ├── fcontent # Content search tool
│   │       ├── flog     # Socket logger viewer (NEW)
│   │       ├── rg       # Bundled ripgrep 15.1.0 (static musl)
│   │       └── fd       # Bundled fd 10.2.0 (static musl)
│   └── share/
│       └── doc/
│           └── fsuite/
│               ├── README.md
│               └── AGENT-ANALYSIS.md
```

### Bundled Binaries

Static musl-compiled binaries ensure compatibility across all Debian versions:

| Binary | Version | Source |
|--------|---------|--------|
| ripgrep (rg) | 15.1.0 | x86_64-unknown-linux-musl |
| fd | 10.2.0 | x86_64-unknown-linux-musl |

### Package Details

| Field | Value |
|-------|-------|
| Package | fsuite |
| Version | 1.3.0 |
| Architecture | amd64 |
| Installed-Size | 9900 KB |
| File Size | 2.6 MB |
| Section | utils |
| Priority | optional |
| Dependencies | tree, bash, coreutils |

### Build Commands

```bash
# Create package structure
mkdir -p fsuite_1.3.0_amd64/{DEBIAN,usr/local/bin,usr/share/doc/fsuite}

# Copy tools
cp ftree fsearch fcontent flog fsuite_1.3.0_amd64/usr/local/bin/
cp rg fd fsuite_1.3.0_amd64/usr/local/bin/

# Copy documentation
cp README.md AGENT-ANALYSIS.md fsuite_1.3.0_amd64/usr/share/doc/fsuite/

# Build .deb package
dpkg-deb --build fsuite_1.3.0_amd64
```

---

## Deployment

### Deployment Workflow

The deployment uses Bertta as an intermediary to reach RADi devices:

```
WSL (build) --> Bertta (shared mount) --> RADi (target)
```

### Deployment Commands

```bash
# Step 1: Copy package to Bertta shared mount
scp fsuite_1.3.0_amd64.deb bertta103:/var/db/fusion/

# Step 2: Install on RADi via SSH chain
ssh bertta103 "sshpass -p 'fusionproject' ssh fusion@<RADI_IP> \
    'echo fusionproject | sudo -S dpkg -i /mnt/bertta/fsuite_1.3.0_amd64.deb'"

# Alternative: Direct install on local machine
sudo dpkg -i fsuite_1.3.0_amd64.deb
```

### Mount Points

| Host | Mount Point | Purpose |
|------|-------------|---------|
| Bertta | /var/db/fusion/ | Package staging |
| RADi | /mnt/bertta/ | NFS mount to Bertta's /var/db/fusion |

---

## Testing Results

### Tested Environments

| Environment | Debian Version | Status |
|-------------|----------------|--------|
| radi117 | Debian 9 (Stretch) | PASS |
| bertta103 | Debian 12 (Bookworm) | PASS |
| WSL | Debian 12 (Bookworm) | PASS |

### Test Commands Executed

```bash
# Verify installation
dpkg -l | grep fsuite

# Test ftree
ftree --snapshot /home/fusion
ftree --recon -o json /opt/optofidelity

# Test fsearch
fsearch '*.py' /opt/optofidelity
fsearch --output json '*.log' /var/log

# Test fcontent
fcontent "ERROR" /var/log
fsearch -o paths '*.py' /opt | fcontent "import"

# Test flog
flog info
flog snapshot 50
flog tower
flog errors 20
```

### Tool Verification

All tools verified with `--version` and `--self-check`:

```bash
$ ftree --version
ftree 1.2.0

$ fsearch --version
fsearch 1.0.0

$ fcontent --version
fcontent 1.0.0

$ flog --version
flog 1.0.0

$ ftree --self-check
Self-check:
  Requires: tree. Uses: find, du, stat.
  ✓ tree available (/usr/bin/tree)
  ✓ tree supports --gitignore

$ fsearch --self-check
Self-check:
  ✓ fd backend available (/usr/local/bin/fd)
  ✓ rg (ripgrep) available (/usr/local/bin/rg)
```

---

## Files Created

### In fsuite Repository

| File | Description |
|------|-------------|
| `/home/player2vscpu/Desktop/agent/fsuite/flog` | Socket logger viewer script (NEW) |
| `/home/player2vscpu/Desktop/agent/fsuite/fsuite_1.3.0_amd64.deb` | Built Debian package |

### In Build Directory

| File | Description |
|------|-------------|
| `/home/player2vscpu/Desktop/agent/fsuite-deb-build/fsuite_1.3.0_amd64/` | Package build tree |
| `/home/player2vscpu/Desktop/agent/fsuite-deb-build/fsuite_1.3.0_amd64.deb` | Built package copy |
| `/home/player2vscpu/Desktop/agent/fsuite-deb-build/flog` | Working copy of flog |
| `/home/player2vscpu/Desktop/agent/fsuite-deb-build/ripgrep-15.1.0-x86_64-unknown-linux-musl/` | Extracted ripgrep |
| `/home/player2vscpu/Desktop/agent/fsuite-deb-build/fd-v10.2.0-x86_64-unknown-linux-musl/` | Extracted fd |

---

## Key Learnings

### Technical Discoveries

1. **Static musl binaries provide universal compatibility**
   - Binaries compiled against musl libc work across all Debian versions
   - No dependency on system glibc version

2. **Debian 9 grep limitations**
   - Debian 9's grep does not support `-P` (Perl regex)
   - Use `sed` with extended regex (`-E`) instead for compatibility

3. **Bash strict mode considerations**
   - `set -euo pipefail` requires careful variable initialization
   - Use `${var:-}` syntax to prevent unbound variable errors
   - Array access with `"${arr[@]+"${arr[@]}"}"` handles empty arrays safely

4. **RADi plugin differences**
   - radi117 (NPI): Uses `light_tower_plugin` with `LightState.YELLOW` format
   - Production RADis: Use `radi_status_plugin` with `'light_tower': 'yellow'` format
   - flog handles both formats for tower status detection

### Workflow Insights

1. **Agent reconnaissance pattern**
   ```
   BEFORE fsuite:
     Spawn Explore agent -> 10-15 internal tool calls -> still blind on structure

   AFTER fsuite:
     ftree --snapshot -o json  ->  fsearch -o paths  ->  fcontent -o json
     3-4 calls. Full understanding. ~70% fewer tool invocations.
   ```

2. **Pipeline composability**
   - `fsearch -o paths` produces clean output perfect for piping
   - `fcontent` accepts piped file lists via stdin
   - JSON output includes metadata (counts, truncation) for agent decision-making

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.3.0 | 2026-01-28 | Added flog socket logger viewer |
| 1.2.0 | 2026-01-XX | Added --snapshot mode to ftree |
| 1.1.0 | 2026-01-XX | ftree improvements (absolute paths, human_size rounding) |
| 1.0.1 | 2026-01-XX | Internal refactor, correctness fixes |
| 1.0.0 | 2026-01-XX | Initial release (ftree, fsearch, fcontent) |

---

## Next Steps

1. **Push flog to GitHub repository** - The flog tool needs to be committed and pushed
2. **Update README.md** - Add flog documentation to the main README
3. **Test on production RADis** - Verify radi_status_plugin tower detection
4. **Consider flog enhancements**:
   - Watch mode for specific test patterns
   - Summary statistics for test runs
   - Integration with CI/CD pipelines

---

*Document generated: January 28, 2026*
