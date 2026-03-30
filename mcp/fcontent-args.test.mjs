import test from "node:test";
import assert from "node:assert/strict";

import { buildFcontentArgs } from "./fcontent-args.js";

test("buildFcontentArgs uses fixed-string search by default", () => {
  assert.deepEqual(buildFcontentArgs({ query: "foo(bar)", path: "/tmp/project" }), [
    "-o", "json",
    "--rg-args", "-F",
    "--",
    "foo(bar)",
    "/tmp/project",
  ]);
});

test("buildFcontentArgs combines fixed-string and case-insensitive flags", () => {
  assert.deepEqual(
    buildFcontentArgs({
      query: "ERROR",
      path: "/tmp/project",
      max_matches: 25,
      case_insensitive: true,
    }),
    [
      "-o", "json",
      "-m", "25",
      "--rg-args", "-F -i",
      "--",
      "ERROR",
      "/tmp/project",
    ]
  );
});

test("buildFcontentArgs preserves dash-prefixed literal queries", () => {
  assert.deepEqual(buildFcontentArgs({ query: "--test" }), [
    "-o", "json",
    "--rg-args", "-F",
    "--",
    "--test",
  ]);
});
