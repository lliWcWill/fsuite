---
title: 🗺️ fmap
description: Symbol cartography — functions, classes, imports, constants
sidebar:
  order: 6
---

## Symbol cartography — functions, classes, imports, constants

`fmap` is part of the fsuite toolkit — a set of fourteen CLI tools built for AI coding agents.

## Help output

The content below is the **live** `--help` output of `fmap`, captured at build time from the tool binary itself. It cannot drift from the source — regenerating the docs regenerates this section.

```text
fmap — code cartography: extract structural skeleton from source files (agent-friendly)

USAGE
  fmap [OPTIONS] [path]

MODES
  1) Directory mode:
     fmap /project
     - Scans all recognized source files under /project

  2) Single file mode:
     fmap /project/file.js
     - Extracts symbols from one file

  3) Piped file-list mode (best with fsearch):
     fsearch -o paths '*.py' /project | fmap -o json
     - Reads file paths from stdin

OPTIONS
  -o, --output pretty|paths|json
      pretty: human-readable grouped by file (default)
      paths:  unique file paths with symbols, one per line
      json:   structured JSON with symbol metadata

  -m, --max-symbols N
      Cap total symbols shown. Default: 500

  -n, --max-files N
      Cap files processed. Default: 500 (directory), 2000 (stdin)

  -L, --lang <lang>
      Force language (auto-detect by default).
                   Supported: python, javascript, typescript, kotlin, swift, rust, go, java,
                   c, cpp, ruby, lua, php, bash, dockerfile, makefile, yaml, toml, ini, cuda,
                   mojo, hcl, protobuf, graphql, csharp, zig, env, compose, packagejson,
                   gemfile, gomod, requirements, sql, css, html, xml, perl, rlang, elixir,
                   scala, zsh, dart, objc, haskell, julia, powershell, groovy, ocaml,
                   clojure, wasm, markdown

  -t, --type <type>
      Filter symbol types: function, class, import, type, export, constant

  --name <symbol>
      Rank/filter extracted symbols by exact then substring symbol-name match.

  --no-imports
      Skip import lines. Overridden by -t import.

  --no-default-ignore
      Disable built-in ignore list in directory mode.

  -q, --quiet
      Suppress header lines in pretty mode.

  --project-name <name>
      Override project name in telemetry.

  --self-check
      Verify grep is available.

  --install-hints
      Print how to install grep and exit.

  -h, --help
      Show help and exit.

  --version
      Print version and exit.

  SUPPORTED LANGUAGES
    Python, JavaScript, TypeScript, Kotlin, Swift, Rust, Go, Java, C, C++,
    Ruby, Lua, PHP, Bash/Shell, Dockerfile, Makefile, YAML, Markdown

HEADLESS / AI AGENT USAGE
  fmap -o json /project
  fmap --name authenticate -o json /project/src
  fsearch -o paths '*.py' /project | fmap -o json
  fmap -t function -o json /project
```

## See also

- [fsuite mental model](/getting-started/mental-model/) — how fmap fits into the toolchain
- [Cheat sheet](/reference/cheatsheet/) — one-line recipes for every tool
- [View source on GitHub](https://github.com/lliWcWill/fsuite/blob/master/fmap)
