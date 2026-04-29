---
title: Hooks & Enforcement
description: Block an agent's native Read/Write/Edit/Grep/Glob tools and force them to use fsuite instead.
sidebar:
  order: 2
---

<div class="fs-drone">
  <div class="fs-drone-head">
    <span class="fs-drone-call">HOOKS</span>
    <span class="fs-drone-tagline">The enforcement layer · block native primitives, force fsuite usage</span>
  </div>
  <div class="fs-drone-meta">
    <div><b>Type</b><span>Claude Code PreToolUse hooks</span></div>
    <div><b>Targets</b><span>Read · Write · Edit · Grep · Glob</span></div>
    <div><b>Effect</b><span>reject + redirect message</span></div>
    <div><b>Pairs with</b><span>MCP adapter</span></div>
  </div>
</div>

## The problem

By default, coding agents reach for their native tools — `Read`, `Write`, `Edit`, `Grep`, `Glob`, `Bash`. Those tools flood context, read entire files, and fail on whitespace drift. fsuite exists to fix that, but only if the agent actually uses fsuite.

If you install fsuite and don't enforce its use, the agent will reach for `Read` first because that's what its training reinforced. The MCP exposure tells it `fread` exists. The hooks layer is what makes `fread` the **default**.

## The solution

Claude Code hooks intercept tool calls **before** they run. A `PreToolUse` hook can inspect the tool name, reject the call with a message, and the agent sees that message in its tool result. Reject `Read` with `"Use fsuite fread instead"` and the agent immediately tries `fread` — exactly what you want.

The hook does not need to know anything about fsuite. It just needs to refuse the native primitive with a useful redirect message.

## Example hook configuration

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Use fsuite fread instead of native Read. Use fsuite structured reads with symbol/range control. Example: fread --symbol NAME path' >&2; exit 2"
          }
        ]
      }
    ]
  }
}
```

Apply the same pattern to `Write`, `Edit`, `Grep`, and `Glob`:

| Native tool | fsuite redirect | Why |
|-------------|----------------|-----|
| `Read` | `fread --symbol NAME path` | reads exactly one symbol |
| `Write` | `fwrite path` (MCP) or `fedit --create path` (CLI) | atomic with safety nets |
| `Edit` | `fedit --symbol NAME --replace x --with y` | symbol-scoped, dry-run by default |
| `Grep` | `fcontent "pattern"` | token-capped, ranked |
| `Glob` | `fsearch '*.py'` | fd-aware, suppresses noise dirs |

`Bash` you leave alone — `fbash` exists, but bash itself is occasionally still the right choice. Don't block it.

## Why hooks + MCP together

Hooks **block** native tools. They cannot route or translate calls. MCP **exposes** fsuite tools with schemas. An agent under both:

1. Reaches for `Read` → hook blocks → agent sees the error message
2. Agent tries again with `fread` from the fsuite MCP → succeeds

The two layers are complementary, not redundant. Hooks alone would block native tools without offering an alternative the agent can find. MCP alone would expose fsuite without preventing the agent from sliding back to its trained reflexes.

## The exit-2 pattern

The example above uses `exit 2` — that's the protocol. Exit code `2` from a `PreToolUse` hook tells Claude Code "block this call, but show the message to the agent instead of the user." Exit code `0` would silently allow it. Exit code `1` would fail with the message visible to the user.

Always use `2` for redirects. The agent reads the message, learns, and switches tools.

## Verification

After adding the hooks, ask your agent in a fresh session:

```
Read /tmp/test.txt
```

You should see the agent immediately try `fread /tmp/test.txt` instead. If it still uses native `Read`, the hook isn't loading — check `~/.claude/settings.json` syntax and restart the agent.

## Planned: install script

The plan is to ship `scripts/install-hooks.sh` that adds the correct hook config to `~/.claude/settings.json` idempotently — read existing config, merge in the five PreToolUse blocks, write back without clobbering anything else. Until then, hand-edit per the example above.

## Related

- [MCP adapter](/fsuite/architecture/mcp/) — exposes fsuite tools that the hook redirects to
- [First contact](/fsuite/getting-started/first-contact/) — verify your enforcement is live with a known prompt
