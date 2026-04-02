#!/usr/bin/env bash
# test_fread_symbols.sh — Verify fread/fmap symbol resolution for TS class method modifiers
# Sprint: fread Symbol Resolution & Error UX
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FSUITE_DIR="$(dirname "$SCRIPT_DIR")"
FREAD="$FSUITE_DIR/fread"
FMAP="$FSUITE_DIR/fmap"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Setup test fixture ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/modifiers.tsx" << 'TSEOF'
import React from 'react';

interface AppProps {
  name: string;
}

export class App extends React.Component<AppProps> {
  private readonly handler = () => {
    console.log('handled');
  };

  public dispose(): void {
    this.handler();
  }

  static async create(): Promise<App> {
    return new App({name: 'test'});
  }

  protected getValue(): string {
    return this.props.name;
  }

  override render() {
    return <div>{this.props.name}</div>;
  }

  abstract compute(): number;

  async onLoad(): Promise<void> {
    await fetch('/api');
  }
}
TSEOF

cat > "$TMPDIR/static_methods.js" << 'JSEOF'
class Factory {
  static create() {
    return new Factory();
  }

  static async fetchData() {
    return await fetch('/api');
  }

  async process() {
    return true;
  }
}
JSEOF

echo "=== fmap: TypeScript modifier detection ==="

# Test that fmap detects all modifier-prefixed symbols
fmap_json="$("$FMAP" -o json "$TMPDIR/modifiers.tsx" 2>/dev/null)"
sym_count="$(echo "$fmap_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([s for s in d['files'][0]['symbols'] if s['type']=='function']))")"

if (( sym_count >= 7 )); then
  pass "fmap detects all 7 modifier-prefixed function symbols (found $sym_count)"
else
  fail "fmap should detect 7 modifier-prefixed function symbols, found $sym_count"
fi

echo ""
echo "=== fread --symbol: TypeScript modifiers ==="

# Test 1: override render()
if "$FREAD" --symbol render "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "override render()"; then
  pass "fread --symbol render finds 'override render()'"
else
  fail "fread --symbol render should find 'override render()'"
fi

# Test 2: static async create()
if "$FREAD" --symbol create "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "static async create()"; then
  pass "fread --symbol create finds 'static async create()'"
else
  fail "fread --symbol create should find 'static async create()'"
fi

# Test 3: public dispose()
if "$FREAD" --symbol dispose "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "public dispose()"; then
  pass "fread --symbol dispose finds 'public dispose()'"
else
  fail "fread --symbol dispose should find 'public dispose()'"
fi

# Test 4: private readonly handler =
if "$FREAD" --symbol handler "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "private readonly handler"; then
  pass "fread --symbol handler finds 'private readonly handler ='"
else
  fail "fread --symbol handler should find 'private readonly handler ='"
fi

# Test 5: protected getValue()
if "$FREAD" --symbol getValue "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "protected getValue()"; then
  pass "fread --symbol getValue finds 'protected getValue()'"
else
  fail "fread --symbol getValue should find 'protected getValue()'"
fi

# Test 6: abstract compute()
if "$FREAD" --symbol compute "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "abstract compute()"; then
  pass "fread --symbol compute finds 'abstract compute()'"
else
  fail "fread --symbol compute should find 'abstract compute()'"
fi

# Test 7: async onLoad()
if "$FREAD" --symbol onLoad "$TMPDIR/modifiers.tsx" 2>&1 | grep -q "async onLoad()"; then
  pass "fread --symbol onLoad finds 'async onLoad()'"
else
  fail "fread --symbol onLoad should find 'async onLoad()'"
fi

echo ""
echo "=== fread --symbol: JavaScript static/async methods ==="

# Test 8: static create() in JS
if "$FREAD" --symbol create "$TMPDIR/static_methods.js" 2>&1 | grep -q "static create()"; then
  pass "fread --symbol create finds JS 'static create()'"
else
  fail "fread --symbol create should find JS 'static create()'"
fi

# Test 9: static async fetchData() in JS
if "$FREAD" --symbol fetchData "$TMPDIR/static_methods.js" 2>&1 | grep -q "static async fetchData()"; then
  pass "fread --symbol fetchData finds JS 'static async fetchData()'"
else
  fail "fread --symbol fetchData should find JS 'static async fetchData()'"
fi

echo ""
echo "=== fmap --name: exact symbol name resolution ==="

# Test 10: fmap --name render resolves to exact match
match_count="$("$FMAP" -o json --name render "$TMPDIR/modifiers.tsx" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([m for m in d.get('matches',[]) if m['match_kind']=='exact']))")"
if (( match_count == 1 )); then
  pass "fmap --name render returns 1 exact match"
else
  fail "fmap --name render should return 1 exact match, got $match_count"
fi

# Test 11: fmap --name handler resolves to exact match
match_count="$("$FMAP" -o json --name handler "$TMPDIR/modifiers.tsx" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([m for m in d.get('matches',[]) if m['match_kind']=='exact']))")"
if (( match_count == 1 )); then
  pass "fmap --name handler returns 1 exact match"
else
  fail "fmap --name handler should return 1 exact match, got $match_count"
fi

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
if (( FAIL > 0 )); then
  exit 1
else
  echo "All tests passed."
  exit 0
fi
