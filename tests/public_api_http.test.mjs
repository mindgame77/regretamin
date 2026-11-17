import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { handle, matchRoute, sha256Hex } from "../supabase/functions/public-api/handler.mjs";

const KEY = "rg_" + "ab".repeat(32);

function deps(over = {}) {
  const calls = [];
  const base = {
    calls,
    enabled: async () => true,
    authorize: async (hash) => {
      calls.push(["authorize", hash]);
      return { ok: true, key_id: "11111111-1111-1111-1111-111111111111", limit: 1000, remaining: 999, reset_at: "2026-11-18T00:00:00Z" };
    },
    firms: async (q) => {
      calls.push(["firms", q]);
      return { ok: true, firms: [{ id: 1, slug: "sequoia", name: "Sequoia", website: "https://sequoia.com", country: "US", activity: "Active", email: "hidden@example.com" }], next_cursor: null };
    },
    firm: async (q) => {
      calls.push(["firm", q]);
      return { ok: true, firm: { id: 1, slug: q.slug, name: "Sequoia", website: null, country: "US", activity: "Active", team: [{ name: "Ada", title: "CEO", founder: true, person_id: 9 }], legal: [{ title: "Case v. Sequoia", status: "Active", case_type: "civil", filed_year: 2024, court: "Court", summary: "Summary", source_url: "https://example.com/case", submission_id: 4 }] } };
    },
    deals: async (q) => {
      calls.push(["deals", q]);
      return { ok: true, deals: [{ startup: "Acme", round: "Seed", date: null, source_url: "https://example.com/deal", deal_id: 99 }], next_cursor: "d.cursor" };
    },
    updated: async (q) => {
      calls.push(["updated", q]);
      return { ok: true, firms: [{ id: 2, slug: "a16z", name: "A16z", website: null, country: null, activity: "Not checked yet", updated_at: "2026-11-01T00:00:00Z" }], next_cursor: null };
    },
    log: async (row) => { calls.push(["log", row]); },
  };
  return Object.assign(base, over);
}

async function call(path, d, headers = { "x-api-key": KEY }) {
  const res = await handle(new Request("https://example.test" + path, { headers }), d);
  const text = await res.text();
  return { status: res.status, text, json: text ? JSON.parse(text) : null, headers: res.headers };
}

test("routes ignore the function prefix and keep the update list off firm slugs", () => {
  assert.deepEqual(matchRoute("/functions/v1/public-api/v1/firms"), { name: "firms" });
  assert.deepEqual(matchRoute("/public-api/v1/updated"), { name: "updated" });
  assert.deepEqual(matchRoute("/v1/firms/sequoia/deals"), { name: "deals", slug: "sequoia" });
  assert.deepEqual(matchRoute("/functions/v1/public-api/v1/firms/sequoia"), { name: "firm", slug: "sequoia" });
  assert.equal(matchRoute("/v1/firms/updated").name, "firm");
  assert.equal(matchRoute("/v1/updated").name, "updated");
});

test("hash matches sha256 and is what authorize receives", async () => {
  const hash = await sha256Hex(KEY);
  assert.equal(hash, createHash("sha256").update(KEY).digest("hex"));
  const d = deps();
  const res = await call("/v1/firms?q=sequoia&country=US&activity=active&limit=1000", d);
  assert.equal(res.status, 200);
  assert.equal(d.calls[0][1], hash);
  assert.equal(d.calls[1][0], "firms");
  assert.equal(d.calls[1][1].limit, 100);
  assert.equal(res.json.firms[0].email, undefined);
  assert.equal(res.text.includes(KEY), false);
  assert.equal(res.headers.get("x-ratelimit-remaining"), "999");
});

test("switched off does not authorize, read, or log", async () => {
  const d = deps({ enabled: async () => false });
  const res = await call("/v1/firms", d);
  assert.equal(res.status, 503);
  assert.equal(res.json.error, "API is turned off");
  assert.deepEqual(d.calls, []);
  const posted = await handle(new Request("https://example.test/v1/firms", { method: "POST", headers: { "x-api-key": KEY } }), d);
  assert.equal(posted.status, 503);
});

test("unknown and inactive keys are 401 and do not read firms", async () => {
  const d = deps({ authorize: async () => ({ ok: false, error: "unauthorized" }) });
  const res = await call("/v1/firms/sequoia", d);
  assert.equal(res.status, 401);
  assert.equal(d.calls.some((c) => c[0] === "firm"), false);
  const missing = await call("/v1/updated", deps(), {});
  assert.equal(missing.status, 401);
});

test("over the daily limit is 429 with reset and does not read deals", async () => {
  const d = deps({
    authorize: async () => ({ ok: false, error: "rate_limited", key_id: "11111111-1111-1111-1111-111111111111", limit: 2, remaining: 0, reset_at: "2099-01-01T00:00:00Z" }),
  });
  const res = await call("/v1/firms/sequoia/deals", d);
  assert.equal(res.status, 429);
  assert.equal(res.json.error, "daily limit reached");
  assert.equal(res.json.reset_at, "2099-01-01T00:00:00Z");
  assert.equal(res.headers.get("retry-after") > "0", true);
  assert.equal(d.calls.some((c) => c[0] === "deals"), false);
  assert.equal(d.calls.some((c) => c[0] === "log" && c[1].status === 429), true);
  assert.equal(res.text.includes(KEY), false);
});

test("firm and deals responses keep only public fields", async () => {
  const d = deps();
  const firm = await call("/v1/firms/sequoia", d);
  assert.equal(firm.status, 200);
  assert.equal(firm.json.firm.team[0].person_id, undefined);
  assert.equal(firm.json.firm.team[0].name, "Ada");
  assert.equal(firm.json.firm.legal[0].submission_id, undefined);
  assert.equal(firm.json.firm.legal[0].source_url, "https://example.com/case");
  const deals = await call("/v1/firms/sequoia/deals", deps());
  assert.equal(deals.json.deals[0].deal_id, undefined);
  assert.equal(deals.json.deals[0].date, null);
  assert.equal(deals.json.next_cursor, "d.cursor");
});

test("a key in the query string is refused and not authorized", async () => {
  const d = deps();
  const res = await call("/v1/firms?api_key=" + KEY, d, {});
  assert.equal(res.status, 400);
  assert.equal(res.text.includes(KEY), false);
  assert.deepEqual(d.calls, []);
});
