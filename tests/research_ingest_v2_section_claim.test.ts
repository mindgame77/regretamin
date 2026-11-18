// Section claim uses the same ingest key. Plain claim and submit stay on their own RPCs.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_section_claim.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
const keyId = "11111111-1111-1111-1111-111111111111";
let authReply: any = { ok: true, key_id: keyId };
let claimReply: any = { ok: true, bot_id: "bot-a", firm_id: 7, slug: "plug-and-play", name: "Plug and Play", website: "https://www.plugandplaytechcenter.com" };
let sectionReply: any = { ok: true, bot_id: "bot-a", section: "legal", firm_id: 20, slug: "firm-20", name: "Twenty", website: "https://firm-20.example" };
let doneReply: any = { ok: true, bot_id: "bot-a", firm_id: 7, done: true };
let sectionDoneReply: any = { ok: true, bot_id: "bot-a", section: "legal", firm_id: 20, done: true };
let submitReply: any = { ok: true, bot_id: "bot-a", accepted: 1, rejected: 0, held: 0, results: [{ index: 0, status: "Accepted" }] };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok(authReply);
    if (m[1] === "v2_research_claim") return ok(claimReply);
    if (m[1] === "v2_section_claim") return ok(sectionReply);
    if (m[1] === "v2_research_done") return ok(doneReply);
    if (m[1] === "v2_section_done") return ok(sectionDoneReply);
    if (m[1] === "v2_research_submit") return ok(submitReply);
    return ok(null);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown, key: string | null = "k") =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", ...(key ? { "x-ingest-key": key } : {}) }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("plain claim and done stay on the research queue", async () => {
  calls.length = 0;
  const claimed = await h(req({ action: "claim" }));
  eq(claimed.status, 200, "claim status");
  eq((await claimed.json()).firm_id, 7, "plain firm");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_claim", "v2_bot_notes_unread"], "plain claim rpcs");
  eq(calls[1].args, { p_key_id: keyId }, "plain claim args");
  calls.length = 0;
  const finished = await h(req({ action: "done", firm_id: 7 }));
  eq(finished.status, 200, "done status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_done"], "plain done rpcs");
  eq(calls[1].args, { p_key_id: keyId, p_firm_id: 7 }, "plain done args");
});

Deno.test("section claim and done use the same key and do not call the research queue", async () => {
  calls.length = 0;
  const claimed = await h(req({ action: "claim", block: "legal" }));
  const body = await claimed.json();
  eq(claimed.status, 200, "status");
  eq(body.firm_id, 20, "firm");
  eq(body.section, "legal", "section");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_section_claim", "v2_bot_notes_unread"], "rpcs");
  eq(calls[1].args, { p_key_id: keyId, p_section: "legal" }, "args");
  calls.length = 0;
  const finished = await h(req({ action: "done", block: "reviews", firm_id: 20 }));
  eq(finished.status, 200, "done status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_section_done"], "done rpcs");
  eq(calls[1].args, { p_key_id: keyId, p_section: "reviews", p_firm_id: 20 }, "done args");
});

Deno.test("a bad block is refused and does not claim a whole firm", async () => {
  calls.length = 0;
  eq((await h(req({ action: "claim", block: "news" }))).status, 400, "bad claim block");
  eq((await h(req({ action: "claim", block: null }))).status, 400, "null block");
  eq((await h(req({ action: "done", block: "youtube" }))).status, 400, "missing firm");
  eq(calls.filter((c) => c.name !== "ingest_auth").map((c) => c.name), [], "no queue rpc");
});

Deno.test("submit is unchanged", async () => {
  calls.length = 0;
  const items = [{ firm_id: 7, box: "F4", table: "v2_legal_items", fact: { source_url: "https://example.com/a" } }];
  const r = await h(req({ action: "submit", items }));
  eq(r.status, 200, "status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_submit"], "rpcs");
  eq(calls[1].args.p_key_id, keyId, "same key");
  eq(calls[1].args.p_items, items, "items");
});

Deno.test("a frozen section key is 403", async () => {
  sectionReply = { ok: false, bot_id: "bot-a", error: "Key frozen: too many, 2026-11-17 13:00 PT" };
  try {
    const r = await h(req({ action: "claim", block: "youtube" }));
    eq(r.status, 403, "status");
    eq((await r.json()).error.startsWith("Key frozen"), true, "error");
  } finally {
    sectionReply = { ok: true, bot_id: "bot-a", section: "legal", firm_id: 20, slug: "firm-20", name: "Twenty", website: "https://firm-20.example" };
  }
});
