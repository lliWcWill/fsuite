# fsuite Agent Guide

Use `fsuite` for filesystem reconnaissance before opening files blindly or spawning broad exploration loops.

## Mental Model

```text
ftree  ->  fsearch  ->  fmap / fcontent  ->  fread  ->  fmetrics
Scout     Find         Map / Search         Read       Measure
```

## Headless Defaults

- Prefer `-o json` for programmatic decisions.
- Prefer `-o paths` when piping into another tool.
- Prefer `pretty` only for human terminal output.
- Results go to `stdout`. Errors go to `stderr`.
- Use `-q` for existence checks and silent control flow.

## Recommended Workflow

```bash
# 1) Scout once
ftree --snapshot -o json /project

# 2) Narrow to candidate files
fsearch -o paths '*.py' /project/src

# 3a) Map structure
fsearch -o paths '*.py' /project/src | fmap -o json

# 3b) Search content
fsearch -o paths '*.py' /project/src | fcontent -o json "authenticate"

# 4) Read exact context
fread -o json /project/src/auth.py --around "def authenticate" -B 5 -A 20

# 5) Measure and predict
fmetrics import
fmetrics stats -o json
fmetrics predict /project
```

## Tool Selection

- Need project shape or likely hotspots: `ftree`
- Need candidate filenames: `fsearch`
- Need symbol skeleton without full reads: `fmap`
- Need text matches across files: `fcontent`
- Need bounded file context: `fread`
- Need runtime history or preflight cost: `fmetrics`

For detailed flags and examples, use each tool's `--help`.
