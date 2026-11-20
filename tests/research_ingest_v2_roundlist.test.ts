// research-ingest-v2: round list actions (add_round, claim_next_round, finish_round) take the bot from x-ingest-key.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_roundlist.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const KEY = "11111111-1111-1111-1111-111111111111";
const calls: { name: string; args: any }[] = [];
const replies: Record<string, any> = {
  roundlist_add_round: { ok: true, bot_id: "bot-a", added: true, round: { round_id: 7 } },
  roundlist_claim_next_round: { ok: true, bot_id: "bot-a", held: false, round: { round_id: 7, startup_name: "Zya" } },
  roundlist_finish_round: { ok: true, bot_id: "bot-a", round: { round_id: 7, status: "done" } },
};
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok({ ok: true, key_id: KEY });
    return ok(replies[m[1]] ?? null);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown) =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": "k" }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("add_round: key from header, round passed through", async () => {
  calls.length = 0;
  const round = { startup_name: "Zya", startup_website: "https://zya.co", round: "Series A", round_date: "2026-11-16", source_url: "https://x" };
  const r = await h(req({ action: "add_round", round, bot_id: "someone-else" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "roundlist_add_round")!.args, { p_key_id: KEY, p_round: round }, "rpc args");
});

Deno.test("add_round: a copy is 409 with the existing round", async () => {
  replies.roundlist_add_round = { ok: false, bot_id: "bot-a", duplicate: true, error: "this round is already on the list (round_id 7 ...)", existing_round_id: 7, existing_status: "open" };
  const r = await h(req({ action: "add_round", round: { startup_name: "Zya" } }));
  eq(r.status, 409, "status");
  eq((await r.json()).existing_round_id, 7, "existing id");
  eq((await h(req({ action: "add_round", round: [] }))).status, 400, "round must be an object");
});

Deno.test("claim_next_round: key only, finish hint", async () => {
  calls.length = 0;
  const r = await h(req({ action: "claim_next_round" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "roundlist_claim_next_round")!.args, { p_key_id: KEY }, "rpc args");
  eq((await r.json()).hint.includes('"action":"finish_round","round_id":7'), true, "hint");
});

Deno.test("finish_round: checks round_id, result and note before the database", async () => {
  calls.length = 0;
  eq((await h(req({ action: "finish_round", round_id: "7", result: "done", note: "x" }))).status, 400, "round_id");
  eq((await h(req({ action: "finish_round", round_id: 7, result: "skip", note: "x" }))).status, 400, "result");
  eq((await h(req({ action: "finish_round", round_id: 7, result: "done", note: " " }))).status, 400, "note");
  eq(calls.some((x) => x.name === "roundlist_finish_round"), false, "no rpc on bad input");
  const r = await h(req({ action: "finish_round", round_id: 7, result: "done", note: "saved 2 deals" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "roundlist_finish_round")!.args, { p_key_id: KEY, p_round_id: 7, p_result: "done", p_note: "saved 2 deals" }, "rpc args");
  replies.roundlist_finish_round = { ok: false, bot_id: "bot-a", error: "finish_round done refused: ..." };
  eq((await h(req({ action: "finish_round", round_id: 7, result: "done", note: "x" }))).status, 400, "refused done");
});
