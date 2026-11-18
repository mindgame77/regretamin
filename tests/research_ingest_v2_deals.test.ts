// research-ingest-v2: action deals is read-only, keyed from x-ingest-key, and validates its input.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_deals.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
let dealsReply: any = {
  ok: true, firm_id: 186, firm: "Paradigm", only_gaps: false, total: 1, limit: 500, offset: 0,
  deals: [{ deal_id: 42, startup_id: 7, startup_name: "Example", round: null, deal_date: null }],
};
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok({ ok: true, key_id: "11111111-1111-1111-1111-111111111111" });
    if (m[1] === "v2_research_firm_deals") return ok(dealsReply);
    return ok(null);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown) =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": "k" }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("deals: key from header, defaults, shape", async () => {
  calls.length = 0;
  const r = await h(req({ action: "deals", firm_id: 186, bot_id: "someone-else" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "v2_research_firm_deals")!.args,
    { p_key: "11111111-1111-1111-1111-111111111111", p_firm_id: 186, p_only_gaps: false, p_limit: 500, p_offset: 0 }, "rpc args");
  const j = await r.json();
  eq([j.ok, j.firm, j.total, j.deals[0].deal_id], [true, "Paradigm", 1, 42], "shape");
  calls.length = 0;
  await h(req({ action: "deals", firm_id: 186, only_gaps: true, limit: 50, offset: 100 }));
  eq(calls.find((x) => x.name === "v2_research_firm_deals")!.args,
    { p_key: "11111111-1111-1111-1111-111111111111", p_firm_id: 186, p_only_gaps: true, p_limit: 50, p_offset: 100 }, "rpc args 2");
});

Deno.test("deals: bad input and unknown firm", async () => {
  eq((await h(req({ action: "deals" }))).status, 400, "no firm_id");
  eq((await h(req({ action: "deals", firm_id: "186" }))).status, 400, "string firm_id");
  eq((await h(req({ action: "deals", firm_id: 0 }))).status, 400, "zero firm_id");
  eq((await h(req({ action: "deals", firm_id: 186, only_gaps: "yes" }))).status, 400, "only_gaps");
  eq((await h(req({ action: "deals", firm_id: 186, limit: 501 }))).status, 400, "limit 501");
  eq((await h(req({ action: "deals", firm_id: 186, offset: -1 }))).status, 400, "offset -1");
  dealsReply = { ok: false, error: "firm not found" };
  eq((await h(req({ action: "deals", firm_id: 999999999 }))).status, 404, "unknown firm");
});
