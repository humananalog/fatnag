/**
 * Lightweight assertions for weekly plan limits + ISO week helper.
 * Run: node workers/grok-proxy/test/limits.test.mjs
 */
import assert from "node:assert/strict";
import { isoWeekId, weeklyLimitForPlan } from "../src/index.js";

assert.equal(weeklyLimitForPlan("free"), 5);
assert.equal(weeklyLimitForPlan("plus"), 28);
assert.equal(weeklyLimitForPlan("pro"), 120);
assert.equal(weeklyLimitForPlan("unknown"), 5);
assert.equal(weeklyLimitForPlan(""), 5);

// 2026-09-27 is ISO week 2026-W39
const sample = new Date(Date.UTC(2026, 8, 27));
assert.equal(isoWeekId(sample), "2026-W39");

// Monday of that week
assert.equal(isoWeekId(new Date(Date.UTC(2026, 8, 21))), "2026-W39");

console.log("limits.test.mjs: ok");
