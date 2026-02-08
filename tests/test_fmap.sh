#!/usr/bin/env bash
# test_fmap.sh — comprehensive tests for fmap
# Run with: bash test_fmap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FMAP="${SCRIPT_DIR}/../fmap"
FSEARCH="${SCRIPT_DIR}/../fsearch"
TEST_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

setup() {
  TEST_DIR="$(mktemp -d)"

  # Python fixtures
  mkdir -p "${TEST_DIR}/src"
  cat > "${TEST_DIR}/src/auth.py" <<'PYEOF'
import os
from flask import Blueprint

API_KEY = "secret"
MAX_RETRIES = 3

class AuthService:
    def __init__(self):
        pass

    def authenticate(self, token):
        return True

def helper():
    pass
PYEOF

  # JavaScript fixtures
  cat > "${TEST_DIR}/src/app.js" <<'JSEOF'
import express from 'express';
const config = require('./config');

const MAX_CONNECTIONS = 100;

export default class App {
    constructor() {}
}

function startServer(port) {
    return express().listen(port);
}

export const handler = async (req, res) => {
    return res.json({});
};

module.exports = { startServer };
JSEOF

  # TypeScript fixtures
  cat > "${TEST_DIR}/src/types.ts" <<'TSEOF'
import { Request, Response } from 'express';

interface UserProfile {
    name: string;
    email: string;
}

type AuthResult = {
    success: boolean;
};

export enum Role {
    Admin = 'admin',
    User = 'user',
}

export const DEFAULT_TIMEOUT: number = 5000;

export function validateUser(user: UserProfile): boolean {
    return true;
}

abstract class BaseService {
    abstract connect(): void;
}
TSEOF

  # Rust fixtures
  cat > "${TEST_DIR}/src/main.rs" <<'RSEOF'
use std::collections::HashMap;
use crate::config::Config;

const MAX_SIZE: usize = 1024;
static INSTANCE_COUNT: u32 = 0;

pub struct Server {
    port: u16,
}

pub enum Status {
    Active,
    Inactive,
}

pub trait Handler {
    fn handle(&self);
}

pub fn start() {
    println!("starting");
}

fn private_helper() {}

pub mod routes;

type Result<T> = std::result::Result<T, Error>;
RSEOF

  # Go fixtures
  cat > "${TEST_DIR}/src/main.go" <<'GOEOF'
import "fmt"

const MaxRetries = 5

var defaultTimeout = 30

type Server struct {
    Port int
}

type Handler interface {
    Handle()
}

func NewServer(port int) *Server {
    return &Server{Port: port}
}

func (s *Server) Start() {
    fmt.Println("starting")
}
GOEOF

  # Bash fixtures (both function forms)
  cat > "${TEST_DIR}/src/deploy.sh" <<'SHEOF'
#!/usr/bin/env bash

source ./utils.sh
. ./config.sh

export APP_NAME="myapp"

readonly VERSION="1.0.0"
declare -r BUILD_DIR="/tmp/build"

setup_env() {
    echo "setting up"
}

function cleanup {
    echo "cleaning up"
}

function run_tests() {
    echo "testing"
}

deploy() {
    setup_env
    run_tests
    cleanup
}
SHEOF
  chmod +x "${TEST_DIR}/src/deploy.sh"

  # Ruby fixtures
  cat > "${TEST_DIR}/src/app.rb" <<'RBEOF'
require 'sinatra'
require_relative './helpers'

APP_VERSION = "2.0"

module MyApp
  class Server
    def initialize
    end

    def start
      puts "starting"
    end
  end
end

def helper_method
  true
end
RBEOF

  # Java fixtures
  cat > "${TEST_DIR}/src/Main.java" <<'JAVAEOF'
import java.util.List;
import java.util.Map;

public class Main {
    private static final int MAX = 100;

    public static void main(String[] args) {
        System.out.println("Hello");
    }

    private void helper() {}
}

interface Service {
    void process();
}
JAVAEOF

  # C fixtures
  cat > "${TEST_DIR}/src/server.c" <<'CEOF'
#include <stdio.h>
#include <stdlib.h>

#define MAX_CONNECTIONS 100
#define PORT 8080

typedef struct {
    int port;
    int max_conn;
} ServerConfig;

struct Server {
    ServerConfig config;
    int running;
};

enum Status {
    STOPPED,
    RUNNING,
    ERROR
};

int server_init(ServerConfig *config) {
    return 0;
}

static void cleanup(void) {
    printf("cleanup\n");
}

void server_start(struct Server *s) {
    s->running = 1;
}
CEOF

  # C++ fixtures
  cat > "${TEST_DIR}/src/app.cpp" <<'CPPEOF'
#include <iostream>
#include <string>

#define VERSION "2.0"

namespace MyApp {

class Application {
public:
    Application() {}
    void run();
    static int count();
};

struct Config {
    std::string name;
    int port;
};

template <typename T>
class Container {
    T value;
};

using StringVec = std::vector<std::string>;

constexpr int MAX_SIZE = 1024;

void Application::run() {
    std::cout << "running" << std::endl;
}

}
CPPEOF

  # Lua fixtures
  cat > "${TEST_DIR}/src/game.lua" <<'LUAEOF'
local json = require("json")
local utils = require("utils")

local function private_init()
    print("init")
end

function Game.new(name)
    return { name = name }
end

Game.start = function(self)
    print("starting " .. self.name)
end

local function helper()
    return true
end
LUAEOF

  # PHP fixtures
  cat > "${TEST_DIR}/src/Controller.php" <<'PHPEOF'
<?php

use App\Models\User;
require_once 'vendor/autoload.php';
include 'helpers.php';

const API_VERSION = "1.0";
define('MAX_RETRIES', 3);

abstract class BaseController {
    public function index() {
        return [];
    }

    protected static function validate($data) {
        return true;
    }

    private function helper() {}
}

interface Renderable {
    public function render();
}

trait Cacheable {
    public function cache() {}
}

final class UserController extends BaseController {
    public function show($id) {
        return User::find($id);
    }
}
PHPEOF

  # node_modules directory for ignore testing
  mkdir -p "${TEST_DIR}/node_modules/dep"
  cat > "${TEST_DIR}/node_modules/dep/index.js" <<'NMEOF'
export function depFunction() {
    return true;
}
NMEOF

  # JS dedup fixture — patterns that overlap multiple regexes
  cat > "${TEST_DIR}/src/controllers.js" <<'DEDUPEOF'
import express from 'express';

const registrationController = async (req, res) => {
    return res.json({});
};

const loginController = async (req, res) => {
    return res.json({});
};

const refreshController = async (req, res) => {
    return res.json({});
};

export const handler = async (req, res) => {
    return res.json({});
};

function plainFunction() {
    return true;
}

module.exports = { registrationController, loginController };
DEDUPEOF

  # Extensionless file with shebang
  cat > "${TEST_DIR}/src/run-script" <<'SEOF'
#!/bin/bash
run_main() {
    echo "running"
}
SEOF
  chmod +x "${TEST_DIR}/src/run-script"
}

teardown() {
  if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "${RED}✗${NC} $1"
  if [[ -n "${2:-}" ]]; then
    echo "  Details: $2"
  fi
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local test_name="$1"
  shift
  "$@" || true
}

# ============================================================================
# Basic Tests
# ============================================================================

test_version() {
  local output
  output=$("${FMAP}" --version 2>&1)
  if [[ "$output" =~ ^fmap[[:space:]]+(1\.[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    pass "Version output format is correct"
  else
    fail "Version output format is incorrect" "Got: $output"
  fi
}

test_help() {
  local output
  output=$("${FMAP}" --help 2>&1)
  if [[ "$output" =~ USAGE ]] && [[ "$output" =~ fmap ]]; then
    pass "Help output is displayed"
  else
    fail "Help output missing USAGE or fmap" "Got: $output"
  fi
}

test_self_check() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --self-check 2>&1)
  if [[ "$output" =~ "grep available" ]]; then
    pass "Self-check finds grep"
  else
    fail "Self-check did not find grep" "Got: $output"
  fi
}

test_install_hints() {
  local output
  output=$("${FMAP}" --install-hints 2>&1)
  if [[ "$output" =~ "grep" ]] && [[ "$output" =~ "apt" ]]; then
    pass "Install hints shows grep install"
  else
    fail "Install hints missing grep info" "Got: $output"
  fi
}

# ============================================================================
# Directory Mode Tests
# ============================================================================

test_dir_python_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "class: class AuthService" ]] && [[ "$output" =~ "function:" ]] && [[ "$output" =~ "import:" ]]; then
    pass "Directory mode extracts Python classes, functions, imports"
  else
    fail "Directory mode missing Python symbols" "Got: $output"
  fi
}

test_dir_js_exports() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "function: function startServer" ]]; then
    pass "Directory mode extracts JS functions"
  else
    fail "Directory mode missing JS function" "Got: $output"
  fi
}

test_dir_ts_interfaces() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "type: interface UserProfile" ]] || [[ "$output" =~ "type:" ]]; then
    pass "Directory mode extracts TS interfaces/types"
  else
    fail "Directory mode missing TS types" "Got: $output"
  fi
}

test_dir_bash_both_function_forms() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L bash "${TEST_DIR}/src/deploy.sh" 2>&1)
  # setup_env() form and function cleanup form
  if [[ "$output" =~ "function: setup_env()" ]] && [[ "$output" =~ "function: function cleanup" ]]; then
    pass "Bash extracts both function declaration forms"
  else
    fail "Bash missing one of the function forms" "Got: $output"
  fi
}

test_dir_bash_source_imports() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L bash "${TEST_DIR}/src/deploy.sh" 2>&1)
  if [[ "$output" =~ "import: source" ]] && [[ "$output" =~ "import: . ./config.sh" ]]; then
    pass "Bash extracts source and dot-source imports"
  else
    fail "Bash missing import patterns" "Got: $output"
  fi
}

test_dir_bash_constants() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L bash "${TEST_DIR}/src/deploy.sh" 2>&1)
  if [[ "$output" =~ "constant: readonly VERSION" ]]; then
    pass "Bash extracts readonly constants"
  else
    fail "Bash missing readonly constant" "Got: $output"
  fi
}

test_dir_rust_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L rust "${TEST_DIR}/src/main.rs" 2>&1)
  if [[ "$output" =~ "class: pub struct Server" ]] && [[ "$output" =~ "function: pub fn start()" ]] && [[ "$output" =~ "import: use std" ]]; then
    pass "Rust extracts struct, fn, use"
  else
    fail "Rust missing expected symbols" "Got: $output"
  fi
}

test_dir_go_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L go "${TEST_DIR}/src/main.go" 2>&1)
  if [[ "$output" =~ "function: func NewServer" ]] && [[ "$output" =~ "class: type Server struct" ]]; then
    pass "Go extracts func and type struct"
  else
    fail "Go missing expected symbols" "Got: $output"
  fi
}

test_dir_ruby_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L ruby "${TEST_DIR}/src/app.rb" 2>&1)
  if [[ "$output" =~ "class: module MyApp" ]] || [[ "$output" =~ "class: class Server" ]]; then
    pass "Ruby extracts class/module"
  else
    fail "Ruby missing class/module" "Got: $output"
  fi
}

test_dir_java_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L java "${TEST_DIR}/src/Main.java" 2>&1)
  if [[ "$output" =~ "class:" ]] && [[ "$output" =~ "import:" ]]; then
    pass "Java extracts class and import"
  else
    fail "Java missing class or import" "Got: $output"
  fi
}

# ============================================================================
# Single File Mode Tests
# ============================================================================

test_single_file_detect() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/auth.py" 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['mode']=='single_file'" 2>/dev/null; then
    pass "Single file mode detected correctly"
  else
    fail "Single file mode not detected" "Got: $output"
  fi
}

test_single_file_path_in_json() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/auth.py" 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'auth.py' in d['path']" 2>/dev/null; then
    pass "Single file JSON path contains filename"
  else
    fail "Single file JSON path missing filename" "Got: $output"
  fi
}

test_single_file_extract() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src/auth.py" 2>&1)
  if [[ "$output" =~ "class: class AuthService" ]] && [[ "$output" =~ "function:" ]]; then
    pass "Single file extracts symbols correctly"
  else
    fail "Single file missing expected symbols" "Got: $output"
  fi
}

# ============================================================================
# Stdin Mode Tests
# ============================================================================

test_stdin_mode() {
  local output
  output=$(echo "${TEST_DIR}/src/auth.py" | FSUITE_TELEMETRY=0 "${FMAP}" -o json 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['mode']=='stdin_files'" 2>/dev/null; then
    pass "Stdin mode detected correctly"
  else
    fail "Stdin mode not detected" "Got: $output"
  fi
}

test_stdin_multiple_files() {
  local output
  output=$(printf '%s\n%s\n' "${TEST_DIR}/src/auth.py" "${TEST_DIR}/src/app.js" | FSUITE_TELEMETRY=0 "${FMAP}" -o json 2>&1)
  local files_count
  files_count=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['total_files_with_symbols'])" 2>/dev/null) || files_count=0
  if (( files_count >= 2 )); then
    pass "Stdin processes multiple files"
  else
    fail "Stdin did not process multiple files" "Got files_count=$files_count"
  fi
}

# ============================================================================
# Output Format Tests
# ============================================================================

test_pretty_header() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "fmap (" ]] && [[ "$output" =~ "mode:" ]] && [[ "$output" =~ "files_scanned:" ]] && [[ "$output" =~ "symbols:" ]]; then
    pass "Pretty output has correct header"
  else
    fail "Pretty header missing expected fields" "Got: $(echo "$output" | head -5)"
  fi
}

test_paths_output() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o paths "${TEST_DIR}/src" 2>&1)
  # Should be clean file paths, no header
  if [[ ! "$output" =~ "fmap (" ]] && [[ "$output" =~ "${TEST_DIR}" ]]; then
    pass "Paths output is clean file list"
  else
    fail "Paths output has unexpected format" "Got: $output"
  fi
}

test_json_valid() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src" 2>&1)
  if echo "$output" | python3 -m json.tool >/dev/null 2>&1; then
    pass "JSON output is valid"
  else
    fail "JSON output is invalid" "Got: $output"
  fi
}

test_json_fields() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src" 2>&1)
  local check
  check=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
required = ['tool', 'version', 'mode', 'total_files_scanned', 'total_files_with_symbols',
            'total_symbols', 'shown_symbols', 'truncated', 'languages', 'files']
missing = [k for k in required if k not in d]
if missing:
    print('MISSING: ' + ','.join(missing))
else:
    print('OK')
" 2>&1) || check="ERROR"
  if [[ "$check" == "OK" ]]; then
    pass "JSON has all required top-level fields"
  else
    fail "JSON missing fields" "Got: $check"
  fi
}

test_json_file_structure() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src" 2>&1)
  local check
  check=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if not d['files']:
    print('EMPTY')
else:
    f = d['files'][0]
    required = ['path', 'language', 'symbol_count', 'symbols']
    missing = [k for k in required if k not in f]
    if missing:
        print('MISSING: ' + ','.join(missing))
    else:
        s = f['symbols'][0]
        sym_req = ['line', 'type', 'indent', 'text']
        sym_miss = [k for k in sym_req if k not in s]
        if sym_miss:
            print('SYM_MISSING: ' + ','.join(sym_miss))
        else:
            print('OK')
" 2>&1) || check="ERROR"
  if [[ "$check" == "OK" ]]; then
    pass "JSON file/symbol structure is correct"
  else
    fail "JSON file/symbol structure incorrect" "Got: $check"
  fi
}

# ============================================================================
# Filter Tests
# ============================================================================

test_no_imports() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --no-imports "${TEST_DIR}/src" 2>&1)
  if [[ ! "$output" =~ "import:" ]]; then
    pass "--no-imports removes import lines"
  else
    fail "--no-imports still shows imports" "Got: $output"
  fi
}

test_filter_function() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -t function "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "function:" ]] && [[ ! "$output" =~ "class:" ]] && [[ ! "$output" =~ "import:" ]]; then
    pass "-t function shows only functions"
  else
    fail "-t function shows non-function symbols" "Got: $output"
  fi
}

test_filter_class() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -t class "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "class:" ]] && [[ ! "$output" =~ "function:" ]]; then
    pass "-t class shows only classes"
  else
    fail "-t class shows non-class symbols" "Got: $output"
  fi
}

test_force_lang() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L bash "${TEST_DIR}/src/deploy.sh" 2>&1)
  if [[ "$output" =~ "deploy.sh (bash)" ]]; then
    pass "-L bash forces language detection"
  else
    fail "-L bash not effective" "Got: $output"
  fi
}

test_max_symbols_cap() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -m 5 "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "Showing 5 of" ]]; then
    pass "-m 5 caps shown symbols"
  else
    fail "-m 5 did not cap symbols" "Got: $output"
  fi
}

test_max_files_cap() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -n 2 -o json "${TEST_DIR}/src" 2>&1)
  local scanned
  scanned=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['total_files_scanned'])" 2>/dev/null) || scanned=999
  if (( scanned <= 2 )); then
    pass "-n 2 caps files processed"
  else
    fail "-n 2 did not cap files" "Got scanned=$scanned"
  fi
}

test_precedence_t_import_overrides_no_imports() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -t import --no-imports "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "import:" ]]; then
    pass "-t import overrides --no-imports"
  else
    fail "-t import did not override --no-imports" "Got: $output"
  fi
}

# ============================================================================
# Truncation Tests
# ============================================================================

test_json_truncated_field() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -m 3 -o json "${TEST_DIR}/src" 2>&1)
  local truncated
  truncated=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['truncated'])" 2>/dev/null) || truncated="error"
  if [[ "$truncated" == "True" ]]; then
    pass "JSON truncated=true when cap applies"
  else
    fail "JSON truncated field incorrect" "Got: $truncated"
  fi
}

test_pretty_truncation_warning() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -m 3 "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "Showing 3 of" ]]; then
    pass "Pretty shows truncation warning"
  else
    fail "Pretty missing truncation warning" "Got: $output"
  fi
}

# ============================================================================
# Negative Tests
# ============================================================================

test_bad_output_format() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o badformat "${TEST_DIR}" 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "Invalid --output" ]]; then
    pass "Bad --output rejected with exit 2"
  else
    fail "Bad --output not properly rejected" "rc=$rc, output=$output"
  fi
}

test_bad_type_filter() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -t badtype "${TEST_DIR}" 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "Invalid --type" ]]; then
    pass "Bad --type rejected with exit 2"
  else
    fail "Bad --type not properly rejected" "rc=$rc, output=$output"
  fi
}

test_unknown_flag() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --unknown-flag 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "Unknown option" ]]; then
    pass "Unknown flag rejected with exit 2"
  else
    fail "Unknown flag not properly rejected" "rc=$rc, output=$output"
  fi
}

test_non_integer_max_symbols() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -m abc "${TEST_DIR}" 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "integer" ]]; then
    pass "Non-integer -m rejected"
  else
    fail "Non-integer -m not rejected" "rc=$rc, output=$output"
  fi
}

test_nonexistent_path() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "/nonexistent/path" 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "does not exist" ]]; then
    pass "Non-existent path rejected"
  else
    fail "Non-existent path not rejected" "rc=$rc, output=$output"
  fi
}

# ============================================================================
# Telemetry Tests
# ============================================================================

test_telemetry_records_fmap() {
  # Isolate telemetry writes to a temp HOME so we don't pollute user's real data
  local fake_home
  fake_home="$(mktemp -d)"
  local telem_file="$fake_home/.fsuite/telemetry.jsonl"

  HOME="$fake_home" FSUITE_TELEMETRY=1 "${FMAP}" -o json "${TEST_DIR}/src" >/dev/null 2>&1

  if [[ -f "$telem_file" ]]; then
    local last_line
    last_line=$(tail -1 "$telem_file")
    if [[ "$last_line" =~ \"tool\":\"fmap\" ]] && [[ "$last_line" =~ \"backend\":\"grep\" ]]; then
      pass "Telemetry records tool=fmap and backend=grep"
    else
      fail "Telemetry entry incorrect" "Got: $last_line"
    fi
  else
    fail "Telemetry file not created" ""
  fi
  rm -rf "$fake_home"
}

# ============================================================================
# Default Ignore Tests
# ============================================================================

test_default_ignore_excludes_node_modules() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o paths "${TEST_DIR}" 2>&1)
  if [[ ! "$output" =~ "node_modules" ]]; then
    pass "Default ignore excludes node_modules"
  else
    fail "Default ignore did not exclude node_modules" "Got: $output"
  fi
}

test_no_default_ignore_includes_node_modules() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --no-default-ignore -o paths "${TEST_DIR}" 2>&1)
  if [[ "$output" =~ "node_modules" ]]; then
    pass "--no-default-ignore includes node_modules"
  else
    fail "--no-default-ignore did not include node_modules" "Got: $output"
  fi
}

# ============================================================================
# Shebang Detection Tests
# ============================================================================

test_shebang_detection() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src/run-script" 2>&1)
  if [[ "$output" =~ "function: run_main()" ]]; then
    pass "Shebang detection finds bash functions in extensionless files"
  else
    fail "Shebang detection failed" "Got: $output"
  fi
}

# ============================================================================
# Per-Language Exact Parsing Tests (JSON validation)
# ============================================================================

# Helper: validate symbols via JSON — checks types present, no dupes, min count
_validate_lang_json() {
  local file="$1"
  local lang="$2"
  local expected_types="$3"  # comma-separated: function,class,import
  local min_symbols="$4"
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$file" 2>&1)
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
f = d['files'][0] if d['files'] else None
if not f:
    print('NO_SYMBOLS')
    sys.exit(0)
# Check language
if f['language'] != '$lang':
    print(f'WRONG_LANG:{f[\"language\"]}')
    sys.exit(0)
# Check min count
if f['symbol_count'] < $min_symbols:
    print(f'LOW_COUNT:{f[\"symbol_count\"]}')
    sys.exit(0)
# Check no duplicate lines
lines = [s['line'] for s in f['symbols']]
dupes = len(lines) - len(set(lines))
if dupes > 0:
    print(f'DUPES:{dupes}')
    sys.exit(0)
# Check expected types
expected = set('$expected_types'.split(','))
found = set(s['type'] for s in f['symbols'])
missing = expected - found
if missing:
    print(f'MISSING_TYPES:{\",\".join(missing)}')
    sys.exit(0)
print('OK')
" 2>&1
}

test_parse_python_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/auth.py" "python" "function,class,import,constant" 6)
  if [[ "$result" == "OK" ]]; then
    pass "Python exact parse: all types found, no dupes, 6+ symbols"
  else
    fail "Python exact parse failed" "$result"
  fi
}

test_parse_javascript_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.js" "javascript" "function,class,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "JavaScript exact parse: all types found, no dupes, 4+ symbols"
  else
    fail "JavaScript exact parse failed" "$result"
  fi
}

test_parse_typescript_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/types.ts" "typescript" "import,type,class" 5)
  if [[ "$result" == "OK" ]]; then
    pass "TypeScript exact parse: all types found, no dupes, 5+ symbols"
  else
    fail "TypeScript exact parse failed" "$result"
  fi
}

test_parse_rust_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.rs" "rust" "function,class,import,constant,type" 8)
  if [[ "$result" == "OK" ]]; then
    pass "Rust exact parse: all types found, no dupes, 8+ symbols"
  else
    fail "Rust exact parse failed" "$result"
  fi
}

test_parse_go_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.go" "go" "function,class,import,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Go exact parse: all types found, no dupes, 5+ symbols"
  else
    fail "Go exact parse failed" "$result"
  fi
}

test_parse_java_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Main.java" "java" "function,class,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "Java exact parse: all types found, no dupes, 4+ symbols"
  else
    fail "Java exact parse failed" "$result"
  fi
}

test_parse_bash_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/deploy.sh" "bash" "function,import,export,constant" 7)
  if [[ "$result" == "OK" ]]; then
    pass "Bash exact parse: all types found, no dupes, 7+ symbols"
  else
    fail "Bash exact parse failed" "$result"
  fi
}

test_parse_ruby_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.rb" "ruby" "function,class,import" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Ruby exact parse: all types found, no dupes, 5+ symbols"
  else
    fail "Ruby exact parse failed" "$result"
  fi
}

test_parse_c_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/server.c" "c" "function,class,import,constant" 7)
  if [[ "$result" == "OK" ]]; then
    pass "C exact parse: all types found, no dupes, 7+ symbols"
  else
    fail "C exact parse failed" "$result"
  fi
}

test_parse_cpp_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.cpp" "cpp" "class,import,constant,export" 6)
  if [[ "$result" == "OK" ]]; then
    pass "C++ exact parse: all types found, no dupes, 6+ symbols"
  else
    fail "C++ exact parse failed" "$result"
  fi
}

test_parse_lua_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/game.lua" "lua" "function,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "Lua exact parse: all types found, no dupes, 4+ symbols"
  else
    fail "Lua exact parse failed" "$result"
  fi
}

test_parse_php_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Controller.php" "php" "function,class,import,constant" 8)
  if [[ "$result" == "OK" ]]; then
    pass "PHP exact parse: all types found, no dupes, 8+ symbols"
  else
    fail "PHP exact parse failed" "$result"
  fi
}

# ============================================================================
# Dedup Regression Tests
# ============================================================================

test_dedup_js_arrow_functions() {
  # This is the exact pattern that caused the LibreChat duplicate bug:
  # const fn = async (req, res) => {} matches BOTH function regex patterns
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/controllers.js" 2>&1)
  local result
  result=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
f = d['files'][0] if d['files'] else None
if not f:
    print('NO_SYMBOLS')
    sys.exit(0)
lines = [s['line'] for s in f['symbols']]
dupes = len(lines) - len(set(lines))
if dupes > 0:
    dup_lines = [l for l in lines if lines.count(l) > 1]
    print(f'DUPES:{dupes} on lines {sorted(set(dup_lines))}')
else:
    print(f'OK:{len(lines)} unique symbols')
" 2>&1)
  if [[ "$result" =~ ^OK: ]]; then
    pass "JS arrow function dedup: $result"
  else
    fail "JS arrow function dedup failed" "$result"
  fi
}

test_dedup_all_languages() {
  # Run fmap on entire test dir and verify zero duplicate lines across all files
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src" 2>&1)
  local result
  result=$(echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
total_dupes = 0
dup_files = []
for f in d['files']:
    lines = [s['line'] for s in f['symbols']]
    dupes = len(lines) - len(set(lines))
    if dupes > 0:
        total_dupes += dupes
        dup_files.append(f['path'].split('/')[-1])
if total_dupes > 0:
    print(f'DUPES:{total_dupes} in {dup_files}')
else:
    print(f'OK:{d[\"total_symbols\"]} symbols across {d[\"total_files_with_symbols\"]} files, 0 dupes')
" 2>&1)
  if [[ "$result" =~ ^OK: ]]; then
    pass "Cross-language dedup: $result"
  else
    fail "Cross-language dedup failed" "$result"
  fi
}

# ============================================================================
# Pipeline Test
# ============================================================================

test_pipeline_fsearch_to_fmap() {
  if [[ ! -x "${FSEARCH}" ]]; then
    pass "Pipeline test skipped (fsearch not found)"
    return
  fi
  local output
  output=$(FSUITE_TELEMETRY=0 "${FSEARCH}" -o paths '*.py' "${TEST_DIR}" | FSUITE_TELEMETRY=0 "${FMAP}" -o json 2>&1)
  if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['mode']=='stdin_files' and d['total_symbols']>0" 2>/dev/null; then
    pass "fsearch | fmap pipeline works"
  else
    fail "Pipeline produced unexpected output" "Got: $output"
  fi
}

# ============================================================================
# Quiet Mode Test
# ============================================================================

test_quiet_mode() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -q "${TEST_DIR}/src" 2>&1)
  if [[ ! "$output" =~ "fmap (" ]] && [[ ! "$output" =~ "mode:" ]]; then
    pass "-q suppresses header"
  else
    fail "-q did not suppress header" "Got: $(echo "$output" | head -3)"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  setup

  echo ""
  echo "======================================"
  echo "  fmap Test Suite"
  echo "======================================"
  echo ""
  echo "Test directory: ${TEST_DIR}"
  echo ""

  # Basic tests
  run_test "Version" test_version
  run_test "Help" test_help
  run_test "Self-check" test_self_check
  run_test "Install hints" test_install_hints

  # Directory mode — language extraction
  run_test "Python symbols" test_dir_python_symbols
  run_test "JS functions" test_dir_js_exports
  run_test "TS interfaces" test_dir_ts_interfaces
  run_test "Bash both forms" test_dir_bash_both_function_forms
  run_test "Bash source imports" test_dir_bash_source_imports
  run_test "Bash constants" test_dir_bash_constants
  run_test "Rust symbols" test_dir_rust_symbols
  run_test "Go symbols" test_dir_go_symbols
  run_test "Ruby symbols" test_dir_ruby_symbols
  run_test "Java symbols" test_dir_java_symbols

  # Single file mode
  run_test "Single file detect" test_single_file_detect
  run_test "Single file path" test_single_file_path_in_json
  run_test "Single file extract" test_single_file_extract

  # Stdin mode
  run_test "Stdin mode" test_stdin_mode
  run_test "Stdin multiple files" test_stdin_multiple_files

  # Output formats
  run_test "Pretty header" test_pretty_header
  run_test "Paths output" test_paths_output
  run_test "JSON valid" test_json_valid
  run_test "JSON fields" test_json_fields
  run_test "JSON file structure" test_json_file_structure

  # Filters
  run_test "No imports" test_no_imports
  run_test "Filter function" test_filter_function
  run_test "Filter class" test_filter_class
  run_test "Force lang" test_force_lang
  run_test "Max symbols" test_max_symbols_cap
  run_test "Max files" test_max_files_cap
  run_test "Precedence: -t import overrides --no-imports" test_precedence_t_import_overrides_no_imports

  # Truncation
  run_test "JSON truncated field" test_json_truncated_field
  run_test "Pretty truncation warning" test_pretty_truncation_warning

  # Negative tests
  run_test "Bad output format" test_bad_output_format
  run_test "Bad type filter" test_bad_type_filter
  run_test "Unknown flag" test_unknown_flag
  run_test "Non-integer max" test_non_integer_max_symbols
  run_test "Non-existent path" test_nonexistent_path

  # Telemetry
  run_test "Telemetry records" test_telemetry_records_fmap

  # Default ignore
  run_test "Default ignore node_modules" test_default_ignore_excludes_node_modules
  run_test "No default ignore" test_no_default_ignore_includes_node_modules

  # Per-language exact parsing
  run_test "Python exact parse" test_parse_python_exact
  run_test "JavaScript exact parse" test_parse_javascript_exact
  run_test "TypeScript exact parse" test_parse_typescript_exact
  run_test "Rust exact parse" test_parse_rust_exact
  run_test "Go exact parse" test_parse_go_exact
  run_test "Java exact parse" test_parse_java_exact
  run_test "Bash exact parse" test_parse_bash_exact
  run_test "Ruby exact parse" test_parse_ruby_exact
  run_test "C exact parse" test_parse_c_exact
  run_test "C++ exact parse" test_parse_cpp_exact
  run_test "Lua exact parse" test_parse_lua_exact
  run_test "PHP exact parse" test_parse_php_exact

  # Dedup regression
  run_test "JS arrow dedup" test_dedup_js_arrow_functions
  run_test "Cross-language dedup" test_dedup_all_languages

  # Shebang detection
  run_test "Shebang detection" test_shebang_detection

  # Pipeline
  run_test "fsearch | fmap pipeline" test_pipeline_fsearch_to_fmap

  # Quiet mode
  run_test "Quiet mode" test_quiet_mode

  teardown

  # Summary
  echo ""
  echo "======================================"
  echo "  Test Results"
  echo "======================================"
  echo -e "Total:  ${TESTS_RUN}"
  echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
  if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo ""
    exit 1
  else
    echo -e "${GREEN}All tests passed!${NC}"
    echo ""
    exit 0
  fi
}

main "$@"
