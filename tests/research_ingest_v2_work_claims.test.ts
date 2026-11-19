// research-ingest-v2: next_firm / firm_done take the job and firm_id from the body and the bot from x-ingest-key.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_work_claims.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const KEY = "11111111-1111-1111-1111-111111111111";
const calls: { name: string; args: any }[] = [];
let nextReply: any = {
  ok: true, bot_id: "bot-a", job: "deal_gaps", held: false,
  firm: { firm_id: 186, name: "Paradigm", startups: 120, dated_or_staged: 10, next: { action: "deals", firm_id: 186, only_gaps: true } },
};
let doneReply: any = { ok: true, bot_id: "bot-a", job: "deal_gaps", firm_id: 186 };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok({ ok: true, key_id: KEY });
    if (m[1] === "v2_next_firm") return ok(nextReply);
    if (m[1] === "v2_firm_done") return ok(doneReply);
    if (m[1] === "v2_bot_notes_unread") return ok([]);
    return ok(null);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown) =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": "k" }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("next_firm: key from header, job passed, deals hint and notes", async () => {
  calls.length = 0;
  const r = await h(req({ action: "next_firm", job: "deal_gaps", bot_id: "someone-else" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "v2_next_firm")!.args, { p_key_id: KEY, p_job: "deal_gaps" }, "rpc args");
  const j = await r.json();
  eq([j.firm.firm_id, j.firm.next], [186, { action: "deals", firm_id: 186, only_gaps: true }], "firm");
  eq(Array.isArray(j.notes), true, "notes");
  eq(j.hint.includes('"action":"firm_done","job":"deal_gaps","firm_id":186'), true, "hint");
});

Deno.test("next_firm: none left returns firm null", async () => {
  nextReply = { ok: true, bot_id: "bot-a", job: "deal_gaps", firm: null };
  const r = await h(req({ action: "next_firm", job: "deal_gaps" }));
  eq(r.status, 200, "status");
  eq((await r.json()).firm, null, "firm null");
});

Deno.test("firm_done: key from header and firm_id", async () => {
  calls.length = 0;
  const r = await h(req({ action: "firm_done", job: "deal_gaps", firm_id: 186 }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "v2_firm_done")!.args, { p_key_id: KEY, p_job: "deal_gaps", p_firm_id: 186 }, "rpc args");
  eq((await r.json()).hint.includes('"action":"next_firm","job":"deal_gaps"'), true, "hint");
});

Deno.test("job left out: rpc gets null; hints name the job the database used", async () => {
  calls.length = 0;
  nextReply = { ok: true, bot_id: "bot-a", job: "missing_details", held: false, firm: { firm_id: 379, missing: ["hq_country"] } };
  const r = await h(req({ action: "next_firm" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "v2_next_firm")!.args, { p_key_id: KEY, p_job: null }, "rpc args");
  eq((await r.json()).hint.includes('"action":"firm_done","job":"missing_details","firm_id":379'), true, "hint");
  const old = await h(req({ action: "next_firm", job: "deal_gaps" }));
  eq((await old.json()).hint.includes('"job":"missing_details"'), true, "hint uses the job used, not the job sent");
  doneReply = { ok: true, bot_id: "bot-a", job: "missing_details", firm_id: 379 };
  const d = await h(req({ action: "firm_done", job: "deal_gaps", firm_id: 379 }));
  eq((await d.json()).hint.includes('"action":"next_firm","job":"missing_details"'), true, "done hint");
});

Deno.test("bad input, unknown job, other bot's firm", async () => {
  calls.length = 0;
  eq((await h(req({ action: "next_firm", job: "Deal Gaps" }))).status, 400, "bad job name");
  eq((await h(req({ action: "firm_done", job: "deal_gaps" }))).status, 400, "no firm_id");
  eq((await h(req({ action: "firm_done", job: "deal_gaps", firm_id: "186" }))).status, 400, "string firm_id");
  eq(calls.some((x) => x.name === "v2_next_firm" || x.name === "v2_firm_done"), false, "no rpc on bad input");
  nextReply = { ok: false, bot_id: "bot-a", error: "unknown job" };
  const u = await h(req({ action: "next_firm", job: "legal" }));
  eq([u.status, (await u.json()).error], [400, "unknown job"], "unknown job");
  doneReply = { ok: false, bot_id: "bot-a", error: "this firm is not claimed by you for this job" };
  eq((await h(req({ action: "firm_done", job: "deal_gaps", firm_id: 7 }))).status, 400, "not yours");
  nextReply = { ok: false, bot_id: "bot-a", error: "Key frozen: test, 2026-11-18 07:00 PT" };
  eq((await h(req({ action: "next_firm", job: "deal_gaps" }))).status, 403, "frozen");
});
