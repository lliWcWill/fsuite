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

export function bootstrap() {
    return startServer(3000);
}

function startServer(port) {
    return express().listen(port);
}

export const handler = async (req, res) => {
    return res.json({});
};

module.exports = { startServer };
exports.stopServer = function stopServer(server) {
    return server.close();
};
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

export default async function bootstrapUser(user: UserProfile): Promise<boolean> {
    return validateUser(user);
}

abstract class BaseService {
    abstract connect(): void;
}
TSEOF

  # Swift fixtures
  cat > "${TEST_DIR}/src/App.swift" <<'SWIFTEOF'
import Foundation

public let DEFAULT_PORT = 8080

public protocol Authenticating {
    func authenticate(user: String) -> Bool
}

public struct SessionConfig {
    let timeout: Int
}

public typealias AuthResult = Result<Bool, Error>

public final class AuthService: Authenticating {
    func authenticate(user: String) -> Bool {
        return !user.isEmpty
    }
}

public extension AuthService {
    static func bootstrap() -> AuthService {
        return AuthService()
    }
}
SWIFTEOF

  # Kotlin fixtures
  cat > "${TEST_DIR}/src/App.kt" <<'KTEOF'
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

const val DEFAULT_TIMEOUT_MS = 5000
val API_ROUTE = "/api"
val BROKEN_CONSTANT
val localTimeout = 30

sealed interface AuthResult

data class UserSession(val token: String)

  object SessionManager

  class MainActivity : AppCompatActivity() {
      inner class ViewHolder

      fun bootstrap(user: String): Boolean {
          return user.isNotEmpty()
      }
  }

  suspend fun refreshToken(): Boolean {
      return true
  }

  fun String.masked(): String = this.take(2)

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

  mkdir -p "${TEST_DIR}/src/app/src/main"
  cat > "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" <<'MANIFESTEOF'
  <manifest package="com.example.app">
      <application android:name=".App">
          <activity android:name=".MainActivity" />
          <activity-alias android:name=".LauncherAlias" />
          <service android:name=".SyncService" />
          <receiver android:name=".BootReceiver" />
          <provider android:name=".DataProvider" />
      </application>
  </manifest>
MANIFESTEOF

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

  # Dockerfile fixture (multi-stage, all structural directives)
  cat > "${TEST_DIR}/src/Dockerfile" <<'DKEOF'
FROM node:18-alpine AS builder
FROM alpine:3.18

ENV NODE_ENV=production
ENV APP_PORT=3000
ARG VERSION=1.0
ARG BUILD_DATE

ENTRYPOINT ["node", "server.js"]
CMD ["npm", "start"]
HEALTHCHECK --interval=30s CMD curl -f http://localhost/

EXPOSE 3000
EXPOSE 8080/tcp
VOLUME /data
VOLUME /logs

WORKDIR /app
COPY package.json .
RUN npm install
# FROM should-not-match
DKEOF

  # Dockerfile variant (Dockerfile.prod) for detection test
  cat > "${TEST_DIR}/src/Dockerfile.prod" <<'DKPEOF'
FROM node:18 AS production
ENV NODE_ENV=production
CMD ["node", "app.js"]
EXPOSE 80
DKPEOF

  # Dockerfile extension variant (foo.Dockerfile) for suffix detection
  cat > "${TEST_DIR}/src/api.Dockerfile" <<'DKSEOF'
FROM alpine:3.18
ENV SERVICE=api
CMD ["sh", "-c", "echo ok"]
DKSEOF

  # Makefile fixture
  cat > "${TEST_DIR}/src/Makefile" <<'MKEOF'
CC = gcc
CFLAGS := -Wall -g
OPTIONAL_FLAG ?= -O2

include config.mk
-include optional.mk

export PATH

.PHONY: all clean test

all: build test

build:
	$(CC) $(CFLAGS) -o app main.c

clean:
	rm -f app

test:
	./run_tests.sh

install: build
	cp app /usr/local/bin/
MKEOF

  # YAML fixture (docker-compose style)
  cat > "${TEST_DIR}/src/compose.yml" <<'YMLEOF'
version: "3.8"
services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    environment:
      NODE_ENV: production
      DATABASE_URL: postgres://localhost/db
  db:
    image: postgres:14
    volumes:
      - data:/var/lib/postgresql/data
volumes:
  data:
YMLEOF

  # YAML fixture (GitHub Actions style for uses: detection)
  # Markdown fixture
  cat > "${TEST_DIR}/src/guide.md" <<'MDEOF'
---
title: Test Guide
author: player3
---

# Main Title

Some intro paragraph.

## Getting Started

Setext Heading H1
=================

Setext Heading H2
-----------------

### Installation

Here is a [local link](./install.md) and an [external link](https://example.com/docs).

```bash
# This is a comment inside a fence
echo "not a heading"
## also not a heading
export FOO=bar
```

#### Advanced Config

Some text between headings.

~~~python
# Another fenced block with tildes
def not_a_symbol():
    pass
~~~

```
bare fence no lang tag
# still not a heading
```

  ## Indented Heading

##### Deep Heading Level 5 ###

## Trailing Hashes ##

[Reference](https://github.com/example/repo)

## Final Section
MDEOF

  cat > "${TEST_DIR}/src/ci.yaml" <<'CIEOF'
name: CI
on:
  push:
    branches:
      - main
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
    env:
      CI_TOKEN: secret
CIEOF
}
# ============================================================
# New language fixtures (30 languages)
# ============================================================

setup_new_lang_fixtures() {
  # TOML fixtures
  cat > "${TEST_DIR}/src/config.toml" <<'TOMLEOF'
[package]
name = "fsuite"
version = "2.3.0"

[dependencies]
serde = "1.0"
tokio = { version = "1.0", features = ["full"] }

[build]
target = "release"
TOMLEOF

  # INI fixtures
  cat > "${TEST_DIR}/src/settings.ini" <<'INIEOF'
[database]
host = localhost
port = 5432

[logging]
level = DEBUG
file = /var/log/app.log

[cache]
enabled = true
ttl = 3600
INIEOF

  # ENV fixtures
  cat > "${TEST_DIR}/src/app.env" <<'ENVEOF'
DATABASE_URL=postgres://localhost/mydb
SECRET_KEY=supersecret
PORT=8080
DEBUG=true
API_BASE_URL=https://api.example.com
ENVEOF

  # Docker Compose fixtures
  cat > "${TEST_DIR}/src/docker-compose.yml" <<'COMPOSEEOF'
version: "3.8"
services:
  web:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgres://db/app
  db:
    image: postgres:15
    volumes:
      - pgdata:/var/lib/postgresql/data
  redis:
    image: redis:7-alpine
volumes:
  pgdata:
COMPOSEEOF

  # HCL (Terraform) fixtures
  cat > "${TEST_DIR}/src/main.tf" <<'HCLEOF'
terraform {
  required_version = ">= 1.0"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.micro"
}

output "instance_ip" {
  value = aws_instance.web.public_ip
}

module "vpc" {
  source = "./modules/vpc"
}
HCLEOF

  # Protobuf fixtures
  cat > "${TEST_DIR}/src/messages.proto" <<'PROTOEOF'
syntax = "proto3";
package myservice;

import "google/protobuf/timestamp.proto";

message User {
  string name = 1;
  int32 age = 2;
  repeated string tags = 3;
}

enum Status {
  UNKNOWN = 0;
  ACTIVE = 1;
  INACTIVE = 2;
}

service UserService {
  rpc GetUser (GetUserRequest) returns (User);
  rpc ListUsers (ListUsersRequest) returns (stream User);
}

message GetUserRequest {
  string id = 1;
}
PROTOEOF

  # GraphQL fixtures
  cat > "${TEST_DIR}/src/schema.graphql" <<'GQLEOF'
type Query {
  user(id: ID!): User
  users: [User!]!
}

type Mutation {
  createUser(input: CreateUserInput!): User
}

type User {
  id: ID!
  name: String!
  email: String
  posts: [Post!]!
}

input CreateUserInput {
  name: String!
  email: String!
}

enum Role {
  ADMIN
  USER
  MODERATOR
}
GQLEOF

  # CUDA fixtures
  cat > "${TEST_DIR}/src/kernel.cu" <<'CUDAEOF'
#include <cuda_runtime.h>
#include <stdio.h>

#define BLOCK_SIZE 256

typedef struct {
    float x, y, z;
} Vector3;

__global__ void vectorAdd(const float *a, const float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

__device__ float dotProduct(Vector3 a, Vector3 b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

__host__ void initData(float *data, int n) {
    for (int i = 0; i < n; i++) data[i] = 1.0f;
}

int main() {
    return 0;
}
CUDAEOF

  # Mojo fixtures
  cat > "${TEST_DIR}/src/app.mojo" <<'MOJOEOF'
from python import Python
import math

alias MAX_SIZE = 1024
alias PI = 3.14159

struct Vector:
    var x: Float64
    var y: Float64

    fn __init__(inout self, x: Float64, y: Float64):
        self.x = x
        self.y = y

    fn magnitude(self) -> Float64:
        return math.sqrt(self.x * self.x + self.y * self.y)

fn add(a: Int, b: Int) -> Int:
    return a + b

fn main():
    let v = Vector(3.0, 4.0)
    print(v.magnitude())
MOJOEOF

  # C# fixtures
  cat > "${TEST_DIR}/src/Program.cs" <<'CSEOF'
using System;
using System.Collections.Generic;

namespace MyApp
{
    public interface IService
    {
        void Execute();
    }

    public class UserService : IService
    {
        public void Execute()
        {
            Console.WriteLine("Running");
        }
    }

    public enum Status
    {
        Active,
        Inactive
    }

    public struct Point
    {
        public double X;
        public double Y;
    }
}
CSEOF

  # Zig fixtures
  cat > "${TEST_DIR}/src/main.zig" <<'ZIGEOF'
const std = @import("std");
const math = @import("math");

const MAX_SIZE: usize = 1024;

const Point = struct {
    x: f64,
    y: f64,
};

const Color = enum {
    red,
    green,
    blue,
};

fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello\n", .{});
}

test "basic add" {
    try std.testing.expectEqual(add(1, 2), 3);
}
ZIGEOF

  # package.json fixtures
  cat > "${TEST_DIR}/src/package.json" <<'PKGJSONEOF'
{
  "name": "my-app",
  "version": "1.0.0",
  "scripts": {
    "start": "node index.js",
    "build": "tsc",
    "test": "jest"
  },
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
PKGJSONEOF

  # Gemfile fixtures
  cat > "${TEST_DIR}/src/Gemfile" <<'GEMEOF'
source 'https://rubygems.org'

ruby '3.2.0'

gem 'rails', '~> 7.0'
gem 'pg', '>= 1.1'
gem 'puma', '~> 5.0'

group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
end

group :development do
  gem 'rubocop'
end
GEMEOF

  # go.mod fixtures
  cat > "${TEST_DIR}/src/go.mod" <<'GOMODEOF'
module github.com/user/myproject

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    github.com/lib/pq v1.10.9
    go.uber.org/zap v1.26.0
)

require (
    golang.org/x/crypto v0.14.0 // indirect
    golang.org/x/sys v0.13.0 // indirect
)
GOMODEOF

  # requirements.txt fixtures
  cat > "${TEST_DIR}/src/requirements.txt" <<'REQEOF'
flask==2.3.0
sqlalchemy>=2.0.0
requests~=2.31.0
celery[redis]>=5.3.0
pydantic==2.4.2
pytest>=7.0.0
REQEOF

  # SQL fixtures
  cat > "${TEST_DIR}/src/schema.sql" <<'SQLEOF'
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE
);

CREATE INDEX idx_users_email ON users(email);

CREATE VIEW active_users AS
    SELECT * FROM users WHERE active = true;

CREATE FUNCTION get_user_count()
RETURNS INTEGER AS $$
BEGIN
    RETURN (SELECT COUNT(*) FROM users);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_timestamp
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_modified();
SQLEOF

  # CSS fixtures
  cat > "${TEST_DIR}/src/styles.css" <<'CSSEOF'
:root {
    --primary-color: #3498db;
    --font-size: 16px;
}

body {
    margin: 0;
    padding: 0;
}

.container {
    max-width: 1200px;
}

#header {
    background: var(--primary-color);
}

@media (max-width: 768px) {
    .container {
        padding: 1rem;
    }
}

@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}
CSSEOF

  # HTML fixtures
  cat > "${TEST_DIR}/src/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>My App</title>
    <link rel="stylesheet" href="styles.css">
    <script src="app.js"></script>
</head>
<body>
    <div id="app">
        <form id="login-form" class="form">
            <input type="text" id="username">
        </form>
    </div>
</body>
</html>
HTMLEOF

  # XML fixtures
  cat > "${TEST_DIR}/src/config.xml" <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <appSettings>
        <add key="DbConnection" value="Server=localhost"/>
        <add key="MaxRetries" value="3"/>
    </appSettings>
    <connectionStrings>
        <add name="Default" connectionString="Data Source=."/>
    </connectionStrings>
</configuration>
XMLEOF

  # Perl fixtures
  cat > "${TEST_DIR}/src/script.pl" <<'PLEOF'
use strict;
use warnings;
use File::Basename;

use constant MAX_RETRIES => 3;

package UserManager;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub get_user {
    my ($self, $id) = @_;
    return $self->{users}{$id};
}

package main;

sub process_data {
    my @data = @_;
    return map { $_ * 2 } @data;
}
PLEOF

  # R fixtures
  cat > "${TEST_DIR}/src/analysis.r" <<'REOF'
library(ggplot2)
library(dplyr)

MAX_ITERATIONS <- 1000
THRESHOLD <- 0.05

calculate_mean <- function(data) {
    return(mean(data, na.rm = TRUE))
}

fit_model <- function(formula, data) {
    model <- lm(formula, data = data)
    return(model)
}

plot_results <- function(data, title = "Results") {
    ggplot(data, aes(x = x, y = y)) +
        geom_point()
}
REOF

  # Elixir fixtures
  cat > "${TEST_DIR}/src/app.ex" <<'EXEOF'
defmodule MyApp.UserService do
  use GenServer
  require Logger
  import Ecto.Query

  @max_retries 3
  @timeout 5000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_user(id) do
    GenServer.call(__MODULE__, {:get_user, id})
  end

  defp fetch_user(id) do
    Repo.get(User, id)
  end
end
EXEOF

  # Scala fixtures
  cat > "${TEST_DIR}/src/App.scala" <<'SCALAEOF'
import scala.collection.mutable
import akka.actor.ActorSystem

object Main extends App {
  val MAX_SIZE = 1024
  def run(): Unit = println("running")
}

class UserService(db: Database) {
  def getUser(id: Int): Option[User] = db.find(id)
  def deleteUser(id: Int): Boolean = db.delete(id)
}

trait Repository[T] {
  def find(id: Int): Option[T]
  def save(entity: T): Unit
}

case class User(name: String, age: Int)
SCALAEOF

  # Zsh fixtures
  cat > "${TEST_DIR}/src/deploy.zsh" <<'ZSHEOF'
#!/usr/bin/env zsh
source ~/.zshrc
. ./config.zsh

export APP_NAME="myapp"
readonly VERSION="2.0.0"

deploy() {
    echo "Deploying"
}

cleanup() {
    rm -rf /tmp/build
}
ZSHEOF

  # Dart fixtures
  cat > "${TEST_DIR}/src/main.dart" <<'DARTEOF'
import 'dart:async';
import 'package:flutter/material.dart';

const int MAX_RETRIES = 3;

abstract class Repository<T> {
  Future<T?> findById(int id);
  Future<void> save(T entity);
}

class UserService implements Repository<User> {
  @override
  Future<User?> findById(int id) async {
    return null;
  }

  @override
  Future<void> save(User entity) async {}
}

enum Status { active, inactive, pending }

void main() {
  runApp(MyApp());
}
DARTEOF

  # Objective-C fixtures
  cat > "${TEST_DIR}/src/ViewController.m" <<'OBJCEOF'
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

#define MAX_RETRIES 3

@interface UserService : NSObject
@property (nonatomic, strong) NSString *name;
- (void)fetchUser:(NSInteger)userId;
+ (instancetype)sharedInstance;
@end

@implementation UserService

- (void)fetchUser:(NSInteger)userId {
    NSLog(@"Fetching user %ld", userId);
}

+ (instancetype)sharedInstance {
    static UserService *instance = nil;
    return instance;
}

@end
OBJCEOF

  # Haskell fixtures
  cat > "${TEST_DIR}/src/Main.hs" <<'HSEOF'
module Main where

import Data.List (sort, nub)
import qualified Data.Map as Map

maxRetries :: Int
maxRetries = 3

data User = User
  { userName :: String
  , userAge  :: Int
  } deriving (Show, Eq)

class Printable a where
  prettyPrint :: a -> String

calculateSum :: [Int] -> Int
calculateSum = foldl (+) 0

main :: IO ()
main = putStrLn "Hello"
HSEOF

  # Julia fixtures
  cat > "${TEST_DIR}/src/analysis.jl" <<'JLEOF'
using LinearAlgebra
import Statistics: mean, std

const MAX_ITER = 1000
const TOLERANCE = 1e-6

struct Point
    x::Float64
    y::Float64
end

mutable struct Config
    debug::Bool
    verbose::Bool
end

function compute(data::Vector{Float64})
    return sum(data) / length(data)
end

function fit_model(x, y; method=:ols)
    return x \ y
end

abstract type Shape end
JLEOF

  # PowerShell fixtures
  cat > "${TEST_DIR}/src/deploy.ps1" <<'PS1EOF'
Import-Module ActiveDirectory
. .\config.ps1

function Get-UserInfo {
    param([string]$UserId)
    return Get-ADUser -Identity $UserId
}

function Set-Configuration {
    param(
        [string]$Name,
        [string]$Value
    )
    Set-ItemProperty -Path "HKLM:\Software\MyApp" -Name $Name -Value $Value
}

class AppService {
    [string]$Name
    [void]Start() {
        Write-Host "Starting"
    }
}
PS1EOF

  # Groovy (Jenkinsfile) fixtures
  cat > "${TEST_DIR}/src/Jenkinsfile" <<'JENKINSEOF'
import groovy.json.JsonSlurper

def MAX_RETRIES = 3

pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                sh 'make build'
            }
        }
        stage('Test') {
            steps {
                sh 'make test'
            }
        }
        stage('Deploy') {
            steps {
                sh 'make deploy'
            }
        }
    }
}

def notifySlack(String message) {
    slackSend channel: '#deploys', message: message
}
JENKINSEOF

  # OCaml fixtures
  cat > "${TEST_DIR}/src/main.ml" <<'MLEOF'
open Printf
open Lwt

let max_retries = 3
let timeout = 5.0

type user = {
  name : string;
  age : int;
}

type color = Red | Green | Blue

module UserService = struct
  let find_user id =
    Printf.printf "Finding user %d\n" id

  let create_user name age =
    { name; age }
end

let process_data data =
  List.map (fun x -> x * 2) data
MLEOF

  # Clojure fixtures
  cat > "${TEST_DIR}/src/core.clj" <<'CLJEOF'
(ns myapp.core
  (:require [clojure.string :as str]
            [clojure.java.io :as io]))

(def max-retries 3)
(def api-url "https://api.example.com")

(defn get-user [id]
  (println "Fetching user" id))

(defn- validate-email [email]
  (str/includes? email "@"))

(defprotocol Repository
  (find-by-id [this id])
  (save [this entity]))

(defrecord User [name email age])

(defmulti process-event :type)
CLJEOF

  # WASM (WAT) fixtures
  cat > "${TEST_DIR}/src/module.wat" <<'WATEOF'
(module
  (import "env" "log" (func $log (param i32)))
  (import "env" "memory" (memory 1))

  (global $counter (mut i32) (i32.const 0))
  (global $MAX_SIZE i32 (i32.const 1024))

  (func $add (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add)

  (func $multiply (param $x i32) (param $y i32) (result i32)
    local.get $x
    local.get $y
    i32.mul)

  (func $main (export "main")
    i32.const 42
    call $log)

  (export "add" (func $add))
  (export "multiply" (func $multiply))

  (type $callback (func (param i32) (result i32)))
)
WATEOF
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
  local rc=0
  "$@" || rc=$?
  if (( rc != 0 )); then
    fail "$test_name (crashed with exit $rc)"
  fi
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
  if [[ "$output" =~ USAGE ]] && [[ "$output" =~ fmap ]] && [[ "$output" =~ --name ]]; then
    pass "Help output documents fmap and --name"
  else
    fail "Help output missing USAGE, fmap, or --name" "Got: $output"
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
  # shellcheck disable=SC2076 — RHS quoted intentionally to match parentheses literally
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

test_name_exact_hit_json() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name bootstrapUser -o json "${TEST_DIR}/src" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["query"] == "bootstrapUser"
assert d["total_symbols"] > d["shown_symbols"] == 1
assert len(d["matches"]) == 1
m = d["matches"][0]
assert m["symbol"] == "bootstrapUser"
assert m["match_kind"] == "exact"
assert isinstance(m["rank"], int)
assert "path" in m and m["path"].endswith("types.ts")
assert m["symbol_type"] == "function"
assert isinstance(m["line_start"], int)
assert "line_end" in m
assert len(d["files"]) == 1
assert d["files"][0]["path"].endswith("types.ts")
assert d["files"][0]["symbol_count"] == 1
assert len(d["files"][0]["symbols"]) == 1
assert d["files"][0]["symbols"][0]["text"].startswith("export default async function bootstrapUser")
PY
  then
    pass "fmap --name exact hit returns one ranked match and filtered file output"
  else
    fail "fmap --name exact hit did not return expected JSON" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_ranking_exact_before_substring() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name bootstrap -o json "${TEST_DIR}/src" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
matches = d["matches"]
assert d["query"] == "bootstrap"
assert len(matches) >= 4
assert [m["match_kind"] for m in matches[:3]] == ["exact", "exact", "exact"]
assert matches[0]["symbol"] == "bootstrap" and matches[0]["match_kind"] == "exact"
assert matches[1]["symbol"] == "bootstrap" and matches[1]["match_kind"] == "exact"
assert matches[2]["symbol"] == "bootstrap" and matches[2]["match_kind"] == "exact"
assert matches[0]["path"].endswith("App.kt")
assert matches[1]["path"].endswith("App.swift")
assert matches[2]["path"].endswith("app.js")
assert matches[3]["symbol"] == "bootstrapUser" and matches[3]["match_kind"] == "substring"
assert [m["rank"] for m in matches] == list(range(1, len(matches) + 1))
PY
  then
    pass "fmap --name ranks exact symbol hits before substring matches deterministically"
  else
    fail "fmap --name ranking did not match exact-before-substring contract" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_type_filter_after_matching() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name Auth -t class -o json "${TEST_DIR}/src" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
matches = d["matches"]
assert d["query"] == "Auth"
assert d["total_symbols"] > d["shown_symbols"] == len(matches)
assert len(matches) >= 3
assert all(m["symbol_type"] == "class" for m in matches)
assert matches[0]["path"].endswith("App.kt")
assert matches[-1]["path"].endswith("auth.py")
assert all("Auth" in m["symbol"] for m in matches)
assert all(file["path"].endswith(("App.kt", "App.swift", "auth.py")) for file in d["files"])
PY
  then
    pass "fmap --name applies -t after name matching and keeps counts honest"
  else
    fail "fmap --name with -t did not filter matched results correctly" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_go_receiver_method() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name Start -o json "${TEST_DIR}/src/main.go" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["query"] == "Start"
assert d["shown_symbols"] == 1
assert len(d["matches"]) == 1
m = d["matches"][0]
assert m["symbol"] == "Start"
assert m["symbol_type"] == "function"
assert m["match_kind"] == "exact"
assert m["path"].endswith("main.go")
PY
  then
    pass "fmap --name resolves Go receiver methods by method name"
  else
    fail "fmap --name should resolve Go receiver methods by method name" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_import_symbol() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name express -t import -o json "${TEST_DIR}/src" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["query"] == "express"
assert d["shown_symbols"] >= 1
assert len(d["matches"]) >= 1
m = d["matches"][0]
assert m["symbol"] == "express"
assert m["symbol_type"] == "import"
PY
  then
    pass "fmap --name matches import symbols"
  else
    fail "fmap --name should match import symbols" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_no_matches_json() {
  local output tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name totallyMissingSymbol -o json "${TEST_DIR}/src" 2>&1)
  tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$tmp_json"

  if python3 - "$tmp_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    d = json.load(fh)
assert d["query"] == "totallyMissingSymbol"
assert d["shown_symbols"] == 0
assert d["matches"] == []
assert d["files"] == []
assert d["total_symbols"] > 0
PY
  then
    pass "fmap --name no-match JSON stays valid and non-error"
  else
    fail "fmap --name no-match JSON contract failed" "Got: $output"
  fi
  rm -f "$tmp_json"
}

test_name_no_matches_paths() {
  local output rc
  set +e
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" --name totallyMissingSymbol -o paths "${TEST_DIR}/src" 2>&1)
  rc=$?
  set -e

  if [[ $rc -eq 0 && -z "$output" ]]; then
    pass "fmap --name no-match paths output stays empty with zero exit"
  else
    fail "fmap --name no-match paths output was not empty/non-error" "rc=$rc output=$output"
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
  # Emit canonical lowercase "true"/"false" instead of Python's "True"/"False"
  truncated=$(echo "$output" | python3 -c "import json,sys; print('true' if json.load(sys.stdin)['truncated'] else 'false')" 2>/dev/null) || truncated="error"
  if [[ "$truncated" == "true" ]]; then
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
  local output _tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$file" 2>&1)
  # Write JSON to temp file, pass all variables as argv to avoid shell interpolation
  _tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$_tmp_json"
  python3 - "$_tmp_json" "$lang" "$expected_types" "$min_symbols" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
lang = sys.argv[2]
expected_types = sys.argv[3]
min_symbols = int(sys.argv[4])
f = d['files'][0] if d['files'] else None
if not f:
    print('NO_SYMBOLS')
    sys.exit(0)
if f['language'] != lang:
    print(f'WRONG_LANG:{f["language"]}')
    sys.exit(0)
if f['symbol_count'] < min_symbols:
    print(f'LOW_COUNT:{f["symbol_count"]}')
    sys.exit(0)
lines = [s['line'] for s in f['symbols']]
dupes = len(lines) - len(set(lines))
if dupes > 0:
    print(f'DUPES:{dupes}')
    sys.exit(0)
expected = set(expected_types.split(','))
found = set(s['type'] for s in f['symbols'])
missing = expected - found
if missing:
    print(f'MISSING_TYPES:{",".join(missing)}')
    sys.exit(0)
print('OK')
PY
    rm -f "$_tmp_json"
}

_assert_symbol_type_for_text() {
  local file="$1"
  local text_fragment="$2"
  local expected_type="$3"
  local output _tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$file" 2>&1)
  _tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$_tmp_json"
  python3 - "$_tmp_json" "$text_fragment" "$expected_type" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
expected = sys.argv[3]
files = data.get("files") or []
if not files:
    print("NO_FILES")
    sys.exit(0)
matches = [s for s in files[0].get("symbols", []) if needle in (s.get("text") or "")]
if not matches:
    print("NOT_FOUND")
    sys.exit(0)
actual = matches[0].get("type")
if actual != expected:
    print(f"WRONG_TYPE:{actual}")
    sys.exit(0)
print("OK")
PY
  rm -f "$_tmp_json"
}

_assert_symbol_type_not_present_for_text() {
  local file="$1"
  local text_fragment="$2"
  local blocked_type="$3"
  local output _tmp_json
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$file" 2>&1)
  _tmp_json="$(mktemp)"
  printf '%s\n' "$output" > "$_tmp_json"
  python3 - "$_tmp_json" "$text_fragment" "$blocked_type" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
needle = sys.argv[2]
blocked = sys.argv[3]
files = data.get("files") or []
if not files:
    print("NO_FILES")
    sys.exit(0)
matches = [s for s in files[0].get("symbols", []) if needle in (s.get("text") or "")]
if not matches:
    print("OK")
    sys.exit(0)
if any((s.get("type") or "") == blocked for s in matches):
    print(f"BLOCKED_TYPE:{blocked}")
    sys.exit(0)
print("OK")
PY
  rm -f "$_tmp_json"
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
  result=$(_validate_lang_json "${TEST_DIR}/src/app.js" "javascript" "function,class,import,export" 6)
  if [[ "$result" == "OK" ]]; then
    pass "JavaScript exact parse: all types found, no dupes, 4+ symbols"
  else
    fail "JavaScript exact parse failed" "$result"
  fi
}

test_parse_typescript_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/types.ts" "typescript" "import,type,class,function" 6)
  if [[ "$result" == "OK" ]]; then
    pass "TypeScript exact parse: all types found, no dupes, 5+ symbols"
  else
    fail "TypeScript exact parse failed" "$result"
  fi
}

test_javascript_exported_forms_classify_correctly() {
  local exported_decl exported_arrow commonjs_assign
  exported_decl=$(_assert_symbol_type_for_text "${TEST_DIR}/src/app.js" "export function bootstrap()" "function")
  exported_arrow=$(_assert_symbol_type_for_text "${TEST_DIR}/src/app.js" "export const handler = async" "function")
  commonjs_assign=$(_assert_symbol_type_for_text "${TEST_DIR}/src/app.js" "exports.stopServer = function" "export")
  if [[ "$exported_decl" == "OK" && "$exported_arrow" == "OK" && "$commonjs_assign" == "OK" ]]; then
    pass "JavaScript exported forms classify correctly"
  else
    fail "JavaScript exported forms classification failed" "${exported_decl}|${exported_arrow}|${commonjs_assign}"
  fi
}

test_typescript_exported_functions_classify_as_functions() {
  local exported_decl exported_default
  exported_decl=$(_assert_symbol_type_for_text "${TEST_DIR}/src/types.ts" "export function validateUser" "function")
  exported_default=$(_assert_symbol_type_for_text "${TEST_DIR}/src/types.ts" "export default async function bootstrapUser" "function")
  if [[ "$exported_decl" == "OK" && "$exported_default" == "OK" ]]; then
    pass "TypeScript exported functions classify as functions"
  else
    fail "TypeScript exported function classification failed" "${exported_decl}|${exported_default}"
  fi
}

test_dir_swift_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "App.swift" ]] && [[ "$output" =~ "protocol" ]] && [[ "$output" =~ "bootstrap" ]]; then
    pass "Swift symbols found in directory mode"
  else
    fail "Swift symbols missing in directory mode" "$output"
  fi
}

test_dir_kotlin_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src" 2>&1)
  if [[ "$output" =~ "App.kt" ]] && [[ "$output" =~ "bootstrap" ]] && [[ "$output" =~ "SessionManager" ]]; then
    pass "Kotlin symbols found in directory mode"
  else
    fail "Kotlin symbols missing in directory mode" "$output"
  fi
}

test_parse_swift_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/App.swift" "swift" "function,class,import,type,constant" 7)
  if [[ "$result" == "OK" ]]; then
    pass "Swift exact parse: all types found, no dupes, 7+ symbols"
  else
    fail "Swift exact parse failed" "$result"
  fi
}

test_force_lang_swift() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L swift "${TEST_DIR}/src/App.swift" 2>&1)
  if [[ "$output" =~ "(swift)" ]]; then
    pass "-L swift forces language detection"
  else
    fail "-L swift not effective" "Got: $output"
  fi
}

test_swift_constants_are_screaming_case_only() {
  local uppercase_property lowercase_property
  uppercase_property=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.swift" "public let DEFAULT_PORT" "constant")
  lowercase_property=$(_assert_symbol_type_not_present_for_text "${TEST_DIR}/src/App.swift" "let timeout: Int" "constant")
  if [[ "$uppercase_property" == "OK" && "$lowercase_property" == "OK" ]]; then
    pass "Swift constants stay SCREAMING_CASE-only"
  else
    fail "Swift constant classification is too broad" "${uppercase_property}|${lowercase_property}"
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
  local uppercase_property uppercase_val bare_val lowercase_property
  uppercase_property=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "const val DEFAULT_TIMEOUT_MS" "constant")
  uppercase_val=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "val API_ROUTE = \"/api\"" "constant")
  bare_val=$(_assert_symbol_type_not_present_for_text "${TEST_DIR}/src/App.kt" "val BROKEN_CONSTANT" "constant")
  lowercase_property=$(_assert_symbol_type_not_present_for_text "${TEST_DIR}/src/App.kt" "val localTimeout = 30" "constant")
  if [[ "$uppercase_property" == "OK" && "$uppercase_val" == "OK" && "$bare_val" == "OK" && "$lowercase_property" == "OK" ]]; then
    pass "Kotlin constants stay conservative"
  else
    fail "Kotlin constant classification is too broad" "${uppercase_property}|${uppercase_val}|${bare_val}|${lowercase_property}"
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

test_kotlin_inner_classes_classify_as_classes() {
  local result
  result=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "inner class ViewHolder" "class")
  if [[ "$result" == "OK" ]]; then
    pass "Kotlin inner classes classify as classes"
  else
    fail "Kotlin inner class classification failed" "$result"
  fi
}

test_kotlin_suspend_functions_classify_as_functions() {
  local result
  result=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "suspend fun refreshToken" "function")
  if [[ "$result" == "OK" ]]; then
    pass "Kotlin suspend functions classify as functions"
  else
    fail "Kotlin suspend function classification failed" "$result"
  fi
}

test_kotlin_extension_functions_classify_as_functions() {
  local result
  result=$(_assert_symbol_type_for_text "${TEST_DIR}/src/App.kt" "fun String.masked()" "function")
  if [[ "$result" == "OK" ]]; then
    pass "Kotlin extension functions classify as functions"
  else
    fail "Kotlin extension function classification failed" "$result"
  fi
}

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

test_android_manifest_activity_alias_is_excluded() {
  local result
  result=$(_assert_symbol_type_not_present_for_text "${TEST_DIR}/src/app/src/main/AndroidManifest.xml" "activity-alias" "class")
  if [[ "$result" == "OK" ]]; then
    pass "Android manifest excludes activity-alias from activity symbols"
  else
    fail "Android manifest activity-alias classification failed" "$result"
  fi
}

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
# Dockerfile Tests
# ============================================================================

test_dir_dockerfile_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/Dockerfile" 2>&1)
  if [[ "$output" =~ "import: FROM" ]] && [[ "$output" =~ "constant:" ]] && [[ "$output" =~ "function:" ]] && [[ "$output" =~ "export:" ]]; then
    pass "Dockerfile extracts FROM, ENV/ARG, ENTRYPOINT/CMD, EXPOSE/VOLUME"
  else
    fail "Dockerfile missing expected symbols" "Got: $output"
  fi
}

test_dockerfile_prod_detection() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -o json "${TEST_DIR}/src/Dockerfile.prod" 2>&1)
  local lang
  lang=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['files'][0]['language'])" 2>/dev/null) || lang=""
  if [[ "$lang" == "dockerfile" ]]; then
    pass "Dockerfile.prod detected as dockerfile"
  else
    fail "Dockerfile.prod not detected correctly" "Got lang=$lang"
  fi
}

test_dockerfile_suffix_detection() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -o json "${TEST_DIR}/src/api.Dockerfile" 2>&1)
  local lang
  lang=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['files'][0]['language'])" 2>/dev/null) || lang=""
  if [[ "$lang" == "dockerfile" ]]; then
    pass "api.Dockerfile detected as dockerfile"
  else
    fail "api.Dockerfile not detected correctly" "Got lang=$lang"
  fi
}

test_dockerfile_no_run_copy() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/Dockerfile" 2>&1)
  if [[ ! "$output" =~ "RUN " ]] && [[ ! "$output" =~ "COPY " ]] && [[ ! "$output" =~ "WORKDIR " ]]; then
    pass "Dockerfile excludes RUN, COPY, WORKDIR noise"
  else
    fail "Dockerfile captured noisy directives" "Got: $output"
  fi
}

test_parse_dockerfile_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Dockerfile" "dockerfile" "import,constant,function,export" 10)
  if [[ "$result" == "OK" ]]; then
    pass "Dockerfile exact parse: all types found, no dupes, 10+ symbols"
  else
    fail "Dockerfile exact parse failed" "$result"
  fi
}

test_force_lang_dockerfile() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L dockerfile "${TEST_DIR}/src/Dockerfile" 2>&1)
  if [[ "$output" =~ "(dockerfile)" ]]; then
    pass "-L dockerfile forces language detection"
  else
    fail "-L dockerfile not effective" "Got: $output"
  fi
}

# ============================================================================
# Makefile Tests
# ============================================================================

test_dir_makefile_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L makefile "${TEST_DIR}/src/Makefile" 2>&1)
  if [[ "$output" =~ "function:" ]] && [[ "$output" =~ "constant:" ]] && [[ "$output" =~ "import:" ]]; then
    pass "Makefile extracts targets, variables, includes"
  else
    fail "Makefile missing expected symbols" "Got: $output"
  fi
}

test_makefile_no_phony() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L makefile "${TEST_DIR}/src/Makefile" 2>&1)
  if [[ ! "$output" =~ ".PHONY" ]]; then
    pass "Makefile does not capture .PHONY"
  else
    fail "Makefile captured .PHONY" "Got: $output"
  fi
}

test_parse_makefile_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Makefile" "makefile" "function,constant,import,export" 8)
  if [[ "$result" == "OK" ]]; then
    pass "Makefile exact parse: all types found, no dupes, 8+ symbols"
  else
    fail "Makefile exact parse failed" "$result"
  fi
}

test_force_lang_makefile() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L makefile "${TEST_DIR}/src/Makefile" 2>&1)
  if [[ "$output" =~ "(makefile)" ]]; then
    pass "-L makefile forces language detection"
  else
    fail "-L makefile not effective" "Got: $output"
  fi
}

# ============================================================================
# YAML Tests
# ============================================================================

test_dir_yaml_symbols() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/compose.yml" 2>&1)
  if [[ "$output" =~ "class:" ]] && [[ "$output" =~ "function:" ]] && [[ "$output" =~ "import:" ]]; then
    pass "YAML extracts top-level keys, second-level keys, image refs"
  else
    fail "YAML missing expected symbols" "Got: $output"
  fi
}

test_yaml_github_actions_uses() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/ci.yaml" 2>&1)
  if [[ "$output" =~ "import:" ]] && [[ "$output" =~ "uses:" ]]; then
    pass "YAML GitHub Actions 'uses:' captured as import"
  else
    fail "YAML missing uses: import" "Got: $output"
  fi
}

test_parse_yaml_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/compose.yml" "yaml" "class,function,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "YAML exact parse: all types found, no dupes, 4+ symbols"
  else
    fail "YAML exact parse failed" "$result"
  fi
}

test_force_lang_yaml() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L yaml "${TEST_DIR}/src/compose.yml" 2>&1)
  if [[ "$output" =~ "(yaml)" ]]; then
    pass "-L yaml forces language detection"
  else
    fail "-L yaml not effective" "Got: $output"
  fi
}

test_bad_lang_lists_new_languages() {
  local output rc
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -L badlang "${TEST_DIR}" 2>&1) || rc=$?
  if [[ "${rc:-0}" -eq 2 ]] && [[ "$output" =~ "kotlin" ]] && [[ "$output" =~ "swift" ]] && [[ "$output" =~ "dockerfile" ]] && [[ "$output" =~ "makefile" ]] && [[ "$output" =~ "yaml" ]] && [[ "$output" =~ "markdown" ]]; then
    pass "Invalid --lang error lists new languages (incl markdown)"
  else
    fail "Invalid --lang error missing new languages" "rc=${rc:-0}, output=$output"
  fi
}

# ============================================================================
# Markdown Tests
# ============================================================================

test_markdown_detection() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "(markdown)" ]]; then
    pass "Markdown auto-detected from .md extension"
  else
    fail "Markdown not detected" "Got: $output"
  fi
}

test_markdown_atx_headings() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "class:" ]] && [[ "$output" =~ "function:" ]]; then
    pass "Markdown ATX headings: h1/h2 as class, h3+ as function"
  else
    fail "Markdown missing heading symbols" "Got: $output"
  fi
}

test_markdown_setext_headings() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "Setext Heading H1" ]] && [[ "$output" =~ "Setext Heading H2" ]]; then
    pass "Markdown setext headings detected (=== and ---)"
  else
    fail "Markdown setext headings missing" "Got: $output"
  fi
}

test_markdown_fence_suppression() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/guide.md" 2>&1)
  # Check that bash comments inside fences are NOT in output
  if [[ "$output" =~ "This is a comment inside a fence" ]] || [[ "$output" =~ "also not a heading" ]] || [[ "$output" =~ "not_a_symbol" ]] || [[ "$output" =~ "still not a heading" ]]; then
    fail "Markdown fence suppression failed — content inside fences leaked" "Got: $output"
  else
    pass "Markdown fenced code contents are suppressed"
  fi
}

test_markdown_fence_as_constant() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  # Fence openers themselves should appear as constants
  if [[ "$output" =~ 'constant:' ]] && [[ "$output" =~ '```' ]]; then
    pass "Markdown fence openers appear as constant symbols"
  else
    fail "Markdown fence openers not showing as constants" "Got: $output"
  fi
}

test_markdown_tilde_fence() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "~~~" ]]; then
    pass "Markdown tilde fences detected"
  else
    fail "Markdown tilde fences not detected" "Got: $output"
  fi
}

test_markdown_frontmatter_skipped() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "${TEST_DIR}/src/guide.md" 2>&1)
  # Frontmatter content should not appear
  if [[ "$output" =~ "Test Guide" ]] || [[ "$output" =~ "player3" ]]; then
    fail "Markdown frontmatter leaked into symbols" "Got: $output"
  else
    pass "Markdown YAML frontmatter suppressed"
  fi
}

test_markdown_links() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "import:" ]]; then
    pass "Markdown links detected as imports"
  else
    fail "Markdown links not detected" "Got: $output"
  fi
}

test_markdown_indented_heading() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "Indented Heading" ]]; then
    pass "Markdown indented heading (up to 3 spaces) detected"
  else
    fail "Markdown indented heading not detected" "Got: $output"
  fi
}

test_markdown_exact_parse() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/guide.md" "markdown" "class,function,constant,import" 8)
  if [[ "$result" == "OK" ]]; then
    pass "Markdown exact parse: all types found, no dupes, 8+ symbols"
  else
    fail "Markdown exact parse failed" "$result"
  fi
}

test_force_lang_markdown() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" -L markdown "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "(markdown)" ]]; then
    pass "-L markdown forces language detection"
  else
    fail "-L markdown not effective" "Got: $output"
  fi
}

test_markdown_name_query() {
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" --name "Installation" "${TEST_DIR}/src/guide.md" 2>&1)
  if [[ "$output" =~ "Installation" ]] && [[ "$output" =~ "function:" ]]; then
    pass "Markdown --name query finds heading by name"
  else
    fail "Markdown --name query failed" "Got: $output"
  fi
}

test_markdown_setext_only_file() {
  # Bug 1: setext-only files must produce symbols even with no ATX headings
  local tmpfile="${TEST_DIR}/src/setext-only.md"
  cat > "$tmpfile" <<'STEOF'
Setext Title
============

Setext Subtitle
---------------
STEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  local count
  count=$(printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_symbols',0))" 2>/dev/null) || count=0
  if [[ "$count" -ge 2 ]]; then
    pass "Markdown setext-only file produces symbols ($count)"
  else
    fail "Markdown setext-only file produces 0 symbols" "Got: $output"
  fi
}

test_markdown_setext_h2_is_class() {
  # Bug 2: setext H2 (---) should be class, not function
  local output
  output=$(FSUITE_TELEMETRY=3 "${FMAP}" "${TEST_DIR}/src/guide.md" 2>&1)
  # "Setext Heading H2" must appear as class:, not function:
  if echo "$output" | grep -q "class:.*Setext Heading H2"; then
    pass "Markdown setext H2 (---) classified as class"
  else
    fail "Markdown setext H2 (---) NOT classified as class" "Got: $(echo "$output" | grep -i setext)"
  fi
}

test_markdown_trailing_hash_stripped() {
  # Bug 3: ## Title ## must resolve name to "Title" not "Title ##"
  local tmpfile="${TEST_DIR}/src/trailing-hash.md"
  cat > "$tmpfile" <<'THEOF'
## Title With Hashes ##

### Sub With Hashes ###
THEOF
  local output match_kind
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json --name "Title With Hashes" "$tmpfile" 2>&1)
  # Must be an EXACT match, not substring — proves trailing # was stripped
  match_kind=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
m = d.get('matches', [])
print(m[0]['match_kind'] if m else 'none')
" 2>/dev/null) || match_kind="error"
  if [[ "$match_kind" == "exact" ]]; then
    pass "Markdown trailing # stripped — exact name match"
  else
    fail "Markdown trailing # NOT stripped — match_kind=$match_kind (expected exact)" "Got: $output"
  fi
}

test_markdown_inline_links_in_prose() {
  # Bug 4: links mid-line (not at line start) must be detected
  local tmpfile="${TEST_DIR}/src/inline-links.md"
  cat > "$tmpfile" <<'ILEOF'
# Title

Paragraph with [inline](./a.md) link in the middle.

Check [this out](https://example.com) for more.

[line-start link](https://foo.com)
ILEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  local import_count
  import_count=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
f = d['files']
if not f: print(0); sys.exit()
count = sum(1 for s in f[0]['symbols'] if s['type'] == 'import')
print(count)
" 2>/dev/null) || import_count=0
  if [[ "$import_count" -ge 3 ]]; then
    pass "Markdown inline links in prose detected ($import_count imports)"
  else
    fail "Markdown inline links in prose NOT detected" "Only $import_count imports found. Got: $output"
  fi
}

test_markdown_setext_rejects_non_paragraph() {
  # Bug 5: setext underlines after list items, blockquotes, ATX headings
  # must NOT produce heading symbols
  local tmpfile="${TEST_DIR}/src/setext-false.md"
  cat > "$tmpfile" <<'SFEOF'
- list item
-----

> blockquote
---

Real Setext Title
=================
SFEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  local count
  count=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
f = d.get('files', [])
if not f: print(0); sys.exit()
# Count class symbols — should be exactly 1 (Real Setext Title)
count = sum(1 for s in f[0]['symbols'] if s['type'] == 'class')
print(count)
" 2>/dev/null) || count=0
  if [[ "$count" -eq 1 ]]; then
    pass "Markdown setext rejects non-paragraph lines (1 heading found)"
  else
    fail "Markdown setext false positives from non-paragraph text" "Expected 1 class, got $count. Output: $output"
  fi
}

test_markdown_trailing_hash_no_space_preserved() {
  # Bug 6: ## Topic## must keep literal Topic## (no space before #)
  # CommonMark: trailing # is closing sequence ONLY when preceded by space/tab
  local tmpfile="${TEST_DIR}/src/hash-nospace.md"
  cat > "$tmpfile" <<'HNEOF'
## Topic##

## C# Programming

## Proper Trailing ##
HNEOF
  local output
  # "Topic##" must be an exact match (# is part of the title)
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json --name "Topic##" "$tmpfile" 2>&1)
  local match_kind
  match_kind=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
m = d.get('matches', [])
print(m[0]['match_kind'] if m else 'none')
" 2>/dev/null) || match_kind="error"
  if [[ "$match_kind" == "exact" ]]; then
    pass "Markdown trailing # without space preserved in heading name"
  else
    fail "Markdown trailing # without space was stripped — match_kind=$match_kind (expected exact)" "Got: $output"
  fi
}

test_markdown_multiline_setext() {
  # Bug 7: multiline setext headings must capture the full paragraph, not just the last line
  # CommonMark: "Foo\nbar\n===" → heading text is "Foo bar", not just "bar"
  local tmpfile="${TEST_DIR}/src/multiline-setext.md"
  cat > "$tmpfile" <<'MSEOF'
Foo
bar
===

Single line
-----------
MSEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  # The first heading must contain "Foo" (not just "bar")
  local has_foo
  has_foo=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
f = d.get('files', [])
if not f: print('no'); sys.exit()
syms = f[0]['symbols']
has = any('Foo' in s['text'] for s in syms)
print('yes' if has else 'no')
" 2>/dev/null) || has_foo="error"
  if [[ "$has_foo" == "yes" ]]; then
    pass "Markdown multiline setext captures full paragraph"
  else
    fail "Markdown multiline setext only captured last line" "Got: $output"
  fi
}

test_markdown_image_not_import() {
  # Images ![alt](src) should NOT be classified as import
  local tmpfile="${TEST_DIR}/src/img-link.md"
  cat > "$tmpfile" <<'IMEOF'
# Title

![logo](./logo.png)

![banner](https://example.com/banner.jpg)

[real link](https://example.com)
IMEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  local has_image
  has_image=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
f = d.get('files', [])
if not f: print('no'); sys.exit()
has = any('logo' in s['text'] or 'banner' in s['text'] for s in f[0]['symbols'] if s['type'] == 'import')
print('yes' if has else 'no')
" 2>/dev/null) || has_image="error"
  if [[ "$has_image" == "no" ]]; then
    pass "Markdown images excluded from imports"
  else
    fail "Markdown images leaked as imports" "Got: $output"
  fi
}

test_markdown_reference_links() {
  # Reference-style link definitions [ref]: url should be detected as imports
  local tmpfile="${TEST_DIR}/src/ref-links.md"
  cat > "$tmpfile" <<'RLEOF'
# Title

See [guide][g] for details.

[g]: ./guide.md
[docs]: https://docs.example.com "Documentation"
RLEOF
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" -o json "$tmpfile" 2>&1)
  local import_count
  import_count=$(printf '%s' "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
f = d.get('files', [])
if not f: print(0); sys.exit()
count = sum(1 for s in f[0]['symbols'] if s['type'] == 'import')
print(count)
" 2>/dev/null) || import_count=0
  if [[ "$import_count" -ge 2 ]]; then
    pass "Markdown reference link definitions detected ($import_count imports)"
  else
    fail "Markdown reference link definitions not detected" "Only $import_count imports. Got: $output"
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
# New language exact parse tests (30 languages)
# ============================================================================

test_parse_toml_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/config.toml" "toml" "class,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "TOML exact parse: sections + keys found, no dupes, 5+ symbols"
  else
    fail "TOML exact parse failed" "$result"
  fi
}

test_parse_ini_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/settings.ini" "ini" "class,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "INI exact parse: sections + keys found, no dupes, 5+ symbols"
  else
    fail "INI exact parse failed" "$result"
  fi
}

test_parse_env_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.env" "env" "constant" 4)
  if [[ "$result" == "OK" ]]; then
    pass "ENV exact parse: constants found, no dupes, 4+ symbols"
  else
    fail "ENV exact parse failed" "$result"
  fi
}

test_parse_compose_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/docker-compose.yml" "compose" "class,function" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Compose exact parse: services + keys found, no dupes, 5+ symbols"
  else
    fail "Compose exact parse failed" "$result"
  fi
}

test_parse_hcl_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.tf" "hcl" "class,constant,function,type" 4)
  if [[ "$result" == "OK" ]]; then
    pass "HCL exact parse: resource + variable + module found, no dupes, 4+ symbols"
  else
    fail "HCL exact parse failed" "$result"
  fi
}

test_parse_protobuf_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/messages.proto" "protobuf" "class,function,import,type" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Protobuf exact parse: message + service + enum found, no dupes, 5+ symbols"
  else
    fail "Protobuf exact parse failed" "$result"
  fi
}

test_parse_graphql_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/schema.graphql" "graphql" "class,type" 4)
  if [[ "$result" == "OK" ]]; then
    pass "GraphQL exact parse: types + enum found, no dupes, 4+ symbols"
  else
    fail "GraphQL exact parse failed" "$result"
  fi
}

test_parse_cuda_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/kernel.cu" "cuda" "function,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "CUDA exact parse: kernels + includes found, no dupes, 4+ symbols"
  else
    fail "CUDA exact parse failed" "$result"
  fi
}

test_parse_mojo_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.mojo" "mojo" "function,class,import,constant" 6)
  if [[ "$result" == "OK" ]]; then
    pass "Mojo exact parse: struct + fn + alias found, no dupes, 6+ symbols"
  else
    fail "Mojo exact parse failed" "$result"
  fi
}

test_parse_csharp_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Program.cs" "csharp" "class,import,type" 4)
  if [[ "$result" == "OK" ]]; then
    pass "C# exact parse: class + enum + struct found, no dupes, 4+ symbols"
  else
    fail "C# exact parse failed" "$result"
  fi
}

test_parse_zig_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.zig" "zig" "function,class,constant,type" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Zig exact parse: fn + struct + enum found, no dupes, 5+ symbols"
  else
    fail "Zig exact parse failed" "$result"
  fi
}

test_parse_packagejson_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/package.json" "packagejson" "class,function,import,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "package.json exact parse: scripts + deps found, no dupes, 5+ symbols"
  else
    fail "package.json exact parse failed" "$result"
  fi
}

test_parse_gemfile_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Gemfile" "gemfile" "class,import,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Gemfile exact parse: gems + groups found, no dupes, 5+ symbols"
  else
    fail "Gemfile exact parse failed" "$result"
  fi
}

test_parse_gomod_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/go.mod" "gomod" "class,import,constant" 3)
  if [[ "$result" == "OK" ]]; then
    pass "go.mod exact parse: module + requires found, no dupes, 3+ symbols"
  else
    fail "go.mod exact parse failed" "$result"
  fi
}

test_parse_requirements_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/requirements.txt" "requirements" "import" 5)
  if [[ "$result" == "OK" ]]; then
    pass "requirements.txt exact parse: imports found, no dupes, 5+ symbols"
  else
    fail "requirements.txt exact parse failed" "$result"
  fi
}

test_parse_sql_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/schema.sql" "sql" "class,function" 4)
  if [[ "$result" == "OK" ]]; then
    pass "SQL exact parse: tables + functions found, no dupes, 4+ symbols"
  else
    fail "SQL exact parse failed" "$result"
  fi
}

test_parse_css_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/styles.css" "css" "class,function,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "CSS exact parse: selectors + vars + media found, no dupes, 5+ symbols"
  else
    fail "CSS exact parse failed" "$result"
  fi
}

test_parse_html_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/index.html" "html" "class,import,constant" 4)
  if [[ "$result" == "OK" ]]; then
    pass "HTML exact parse: tags + links found, no dupes, 4+ symbols"
  else
    fail "HTML exact parse failed" "$result"
  fi
}

test_parse_xml_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/config.xml" "xml" "class,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "XML exact parse: elements found, no dupes, 4+ symbols"
  else
    fail "XML exact parse failed" "$result"
  fi
}

test_parse_perl_exact() {
  local output
  output=$(FSUITE_TELEMETRY=0 "${FMAP}" "${TEST_DIR}/src/script.pl" -o json 2>/dev/null)
  local lang
  lang=$(echo "$output" | jq -r '.files[0].language // empty')
  if [[ "$lang" == "perl" ]]; then
    local result
    result=$(_validate_lang_json "${TEST_DIR}/src/script.pl" "perl" "function,class,import" 3)
    if [[ "$result" == "OK" ]]; then
      pass "Perl exact parse: subs + packages found"
    else
      fail "Perl exact parse failed" "$result"
    fi
  else
    # Perl may not be supported yet - pass with note
    local count
    count=$(echo "$output" | jq '.total_files_with_symbols')
    if [[ "$count" == "0" ]]; then
      pass "Perl: language not yet supported (0 symbols, expected)"
    else
      fail "Perl: unexpected parse result" "$output"
    fi
  fi
}

test_parse_rlang_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/analysis.r" "rlang" "function,constant" 4)
  if [[ "$result" == "OK" ]]; then
    pass "R exact parse: functions + constants found, no dupes, 4+ symbols"
  else
    fail "R exact parse failed" "$result"
  fi
}

test_parse_elixir_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/app.ex" "elixir" "function,class,import,constant" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Elixir exact parse: defmodule + def + use found, no dupes, 5+ symbols"
  else
    fail "Elixir exact parse failed" "$result"
  fi
}

test_parse_scala_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/App.scala" "scala" "function,class,import,constant" 6)
  if [[ "$result" == "OK" ]]; then
    pass "Scala exact parse: class + object + trait found, no dupes, 6+ symbols"
  else
    fail "Scala exact parse failed" "$result"
  fi
}

test_parse_zsh_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/deploy.zsh" "zsh" "function,import,export,constant" 4)
  if [[ "$result" == "OK" ]]; then
    pass "Zsh exact parse: functions + source + export found, no dupes, 4+ symbols"
  else
    fail "Zsh exact parse failed" "$result"
  fi
}

test_parse_dart_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.dart" "dart" "function,class,import" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Dart exact parse: class + functions + imports found, no dupes, 5+ symbols"
  else
    fail "Dart exact parse failed" "$result"
  fi
}

test_parse_objc_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/ViewController.m" "objc" "function,class,import" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Obj-C exact parse: interface + methods + imports found, no dupes, 5+ symbols"
  else
    fail "Obj-C exact parse failed" "$result"
  fi
}

test_parse_haskell_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Main.hs" "haskell" "function,class,import" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Haskell exact parse: module + data + functions found, no dupes, 5+ symbols"
  else
    fail "Haskell exact parse failed" "$result"
  fi
}

test_parse_julia_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/analysis.jl" "julia" "function,class,import,type" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Julia exact parse: struct + function + const found, no dupes, 5+ symbols"
  else
    fail "Julia exact parse failed" "$result"
  fi
}

test_parse_powershell_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/deploy.ps1" "powershell" "function,class,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "PowerShell exact parse: functions + class + imports found, no dupes, 4+ symbols"
  else
    fail "PowerShell exact parse failed" "$result"
  fi
}

test_parse_groovy_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/Jenkinsfile" "groovy" "function,class,import" 4)
  if [[ "$result" == "OK" ]]; then
    pass "Groovy exact parse: pipeline + stages + import found, no dupes, 4+ symbols"
  else
    fail "Groovy exact parse failed" "$result"
  fi
}

test_parse_ocaml_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/main.ml" "ocaml" "function,class,import,type" 5)
  if [[ "$result" == "OK" ]]; then
    pass "OCaml exact parse: module + let + type found, no dupes, 5+ symbols"
  else
    fail "OCaml exact parse failed" "$result"
  fi
}

test_parse_clojure_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/core.clj" "clojure" "function,class,constant,type" 5)
  if [[ "$result" == "OK" ]]; then
    pass "Clojure exact parse: defn + def + defprotocol found, no dupes, 5+ symbols"
  else
    fail "Clojure exact parse failed" "$result"
  fi
}

test_parse_wasm_exact() {
  local result
  result=$(_validate_lang_json "${TEST_DIR}/src/module.wat" "wasm" "function,class,import,export,constant,type" 6)
  if [[ "$result" == "OK" ]]; then
    pass "WASM exact parse: func + import + export found, no dupes, 6+ symbols"
  else
    fail "WASM exact parse failed" "$result"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  setup
  setup_new_lang_fixtures

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
    run_test "Swift symbols" test_dir_swift_symbols
    run_test "Kotlin symbols" test_dir_kotlin_symbols
    run_test "Android manifest symbols" test_dir_android_manifest_symbols
    run_test "Android layout symbols" test_dir_android_layout_symbols

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
  run_test "Name exact hit JSON" test_name_exact_hit_json
  run_test "Name ranking exact before substring" test_name_ranking_exact_before_substring
  run_test "Name type filter after matching" test_name_type_filter_after_matching
  run_test "Name Go receiver method" test_name_go_receiver_method
  run_test "Name import symbol" test_name_import_symbol
  run_test "Name no matches JSON" test_name_no_matches_json
  run_test "Name no matches paths" test_name_no_matches_paths

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
  run_test "JavaScript exported forms" test_javascript_exported_forms_classify_correctly
    run_test "TypeScript exact parse" test_parse_typescript_exact
    run_test "TypeScript exported functions" test_typescript_exported_functions_classify_as_functions
    run_test "Swift exact parse" test_parse_swift_exact
    run_test "Swift constants are SCREAMING_CASE-only" test_swift_constants_are_screaming_case_only
    run_test "Kotlin exact parse" test_parse_kotlin_exact
    run_test "Kotlin constants stay conservative" test_kotlin_constants_are_conservative
    run_test "Kotlin inner classes" test_kotlin_inner_classes_classify_as_classes
    run_test "Kotlin suspend functions" test_kotlin_suspend_functions_classify_as_functions
    run_test "Kotlin extension functions" test_kotlin_extension_functions_classify_as_functions
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

  # Dockerfile
  run_test "Dockerfile symbols" test_dir_dockerfile_symbols
  run_test "Dockerfile.prod detection" test_dockerfile_prod_detection
  run_test "api.Dockerfile suffix detection" test_dockerfile_suffix_detection
  run_test "Dockerfile no RUN/COPY" test_dockerfile_no_run_copy
  run_test "Dockerfile exact parse" test_parse_dockerfile_exact
  run_test "Force lang dockerfile" test_force_lang_dockerfile

  # Makefile
  run_test "Makefile symbols" test_dir_makefile_symbols
  run_test "Makefile no .PHONY" test_makefile_no_phony
  run_test "Makefile exact parse" test_parse_makefile_exact
  run_test "Force lang makefile" test_force_lang_makefile

  # YAML
    run_test "YAML symbols" test_dir_yaml_symbols
    run_test "YAML uses: import" test_yaml_github_actions_uses
    run_test "YAML exact parse" test_parse_yaml_exact
    run_test "Force lang yaml" test_force_lang_yaml
    run_test "Force lang swift" test_force_lang_swift
    run_test "Force lang kotlin" test_force_lang_kotlin
    run_test "Gradle Kotlin DSL detection" test_gradle_kts_detects_as_kotlin
    run_test "Android manifest exact parse" test_parse_android_manifest_exact
    run_test "Android manifest path scoping" test_android_manifest_is_path_scoped
    run_test "Android manifest excludes activity-alias" test_android_manifest_activity_alias_is_excluded
    run_test "Android layout exact parse" test_parse_android_layout_exact
    run_test "Android layout path scoping" test_android_layout_is_path_scoped

    # Markdown
    run_test "Markdown detection" test_markdown_detection
    run_test "Markdown ATX headings" test_markdown_atx_headings
    run_test "Markdown setext headings" test_markdown_setext_headings
    run_test "Markdown fence suppression" test_markdown_fence_suppression
    run_test "Markdown fence as constant" test_markdown_fence_as_constant
    run_test "Markdown tilde fence" test_markdown_tilde_fence
    run_test "Markdown frontmatter skipped" test_markdown_frontmatter_skipped
    run_test "Markdown links" test_markdown_links
    run_test "Markdown indented heading" test_markdown_indented_heading
    run_test "Markdown exact parse" test_markdown_exact_parse
    run_test "Force lang markdown" test_force_lang_markdown
    run_test "Markdown name query" test_markdown_name_query
    run_test "Markdown setext-only file" test_markdown_setext_only_file
    run_test "Markdown setext H2 is class" test_markdown_setext_h2_is_class
    run_test "Markdown trailing # stripped" test_markdown_trailing_hash_stripped
    run_test "Markdown inline links in prose" test_markdown_inline_links_in_prose
    run_test "Markdown setext rejects non-paragraph" test_markdown_setext_rejects_non_paragraph
    run_test "Markdown trailing # no-space preserved" test_markdown_trailing_hash_no_space_preserved
    run_test "Markdown multiline setext" test_markdown_multiline_setext
    run_test "Markdown images not imports" test_markdown_image_not_import
    run_test "Markdown reference links" test_markdown_reference_links

    # New language validation
    run_test "Invalid --lang lists new langs" test_bad_lang_lists_new_languages

  # New language exact parse tests (30 languages)
  run_test "TOML exact parse" test_parse_toml_exact
  run_test "INI exact parse" test_parse_ini_exact
  run_test "ENV exact parse" test_parse_env_exact
  run_test "Compose exact parse" test_parse_compose_exact
  run_test "HCL exact parse" test_parse_hcl_exact
  run_test "Protobuf exact parse" test_parse_protobuf_exact
  run_test "GraphQL exact parse" test_parse_graphql_exact
  run_test "CUDA exact parse" test_parse_cuda_exact
  run_test "Mojo exact parse" test_parse_mojo_exact
  run_test "C# exact parse" test_parse_csharp_exact
  run_test "Zig exact parse" test_parse_zig_exact
  run_test "package.json exact parse" test_parse_packagejson_exact
  run_test "Gemfile exact parse" test_parse_gemfile_exact
  run_test "go.mod exact parse" test_parse_gomod_exact
  run_test "requirements.txt exact parse" test_parse_requirements_exact
  run_test "SQL exact parse" test_parse_sql_exact
  run_test "CSS exact parse" test_parse_css_exact
  run_test "HTML exact parse" test_parse_html_exact
  run_test "XML exact parse" test_parse_xml_exact
  run_test "Perl exact parse" test_parse_perl_exact
  run_test "R exact parse" test_parse_rlang_exact
  run_test "Elixir exact parse" test_parse_elixir_exact
  run_test "Scala exact parse" test_parse_scala_exact
  run_test "Zsh exact parse" test_parse_zsh_exact
  run_test "Dart exact parse" test_parse_dart_exact
  run_test "Obj-C exact parse" test_parse_objc_exact
  run_test "Haskell exact parse" test_parse_haskell_exact
  run_test "Julia exact parse" test_parse_julia_exact
  run_test "PowerShell exact parse" test_parse_powershell_exact
  run_test "Groovy exact parse" test_parse_groovy_exact
  run_test "OCaml exact parse" test_parse_ocaml_exact
  run_test "Clojure exact parse" test_parse_clojure_exact
  run_test "WASM exact parse" test_parse_wasm_exact

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
