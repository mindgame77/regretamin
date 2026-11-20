// research-ingest-v2: add_firm is a separate action. Submit and verdict stay on their own RPCs.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_add_firm.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
const reads: { table: string; url: string }[] = [];
let firmRows: any[] = [];
let v2Rows: any[] = [];
let authReply: any = { ok: true, key_id: "11111111-1111-1111-1111-111111111111" };
let addReply: any = { ok: true, bot_id: "bot-a", firm_id: 41, created: true, slug: "example-ventures" };
let claimReply: any = { ok: true, bot_id: "bot-a", firm_id: 7, slug: "plug-and-play", name: "Plug and Play", website: "https://www.plugandplaytechcenter.com" };
let doneReply: any = { ok: true, bot_id: "bot-a", firm_id: 7, done: true };
let submitReply: any = { ok: true, bot_id: "bot-a", accepted: 1, rejected: 0, held: 0, results: [{ index: 0, status: "Accepted" }] };
let verdictReply: any = { ok: true, bot_id: "checker" };
let guardReply: any = { ok: true, block_on: true, strong: [], weak: [] };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok(authReply);
    if (m[1] === "v2_research_add_firm") return ok(addReply);
    if (m[1] === "v2_research_claim") return ok(claimReply);
    if (m[1] === "v2_research_done") return ok(doneReply);
    if (m[1] === "v2_research_submit") return ok(submitReply);
    if (m[1] === "v2_checker_action") return ok(verdictReply);
    if (m[1] === "v2_firm_guard") return ok(guardReply);
    return ok(null);
  }
  const table = u.pathname.match(/\/rest\/v1\/([a-z0-9_]+)$/);
  if (table) {
    reads.push({ table: table[1], url: u.pathname + u.search });
    if (table[1] === "v2_firms") return ok(v2Rows);
    if (table[1] === "firms") return ok(firmRows);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown, key: string | null = "k") =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", ...(key ? { "x-ingest-key": key } : {}) }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("add_firm returns firm_id and does not call submit", async () => {
  calls.length = 0;
  const firm = { name: "Example Ventures", website: "https://example-ventures.com", registry_id: "vc-000123" };
  const r = await h(req({ action: "add_firm", firm }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.firm_id, 41, "firm_id");
  eq(j.created, true, "created");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_firm_guard", "v2_research_add_firm"], "rpcs");
  eq(calls[2].args.p_key_id, authReply.key_id, "key");
  eq(calls[2].args.p_firm, firm, "firm");
});

Deno.test("add_firm again is the same call shape", async () => {
  calls.length = 0;
  addReply = { ok: true, bot_id: "bot-a", firm_id: 41, created: false, slug: "example-ventures" };
  const r = await h(req({ action: "add_firm", firm: { name: "Example Ventures", website: "https://example-ventures.com", registry_id: "vc-000123" } }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.firm_id, 41, "firm_id");
  eq(j.created, false, "created");
  eq(calls.filter((c) => c.name === "v2_research_submit").length, 0, "no submit");
});

Deno.test("submit still calls v2_research_submit only", async () => {
  calls.length = 0;
  const items = [{ firm_id: 41, box: "F28", table: "v2_news_items", fact: { source_url: "https://example.com/a", source_level: "2", source_date: "2026-11-01", source_type: "news" } }];
  const r = await h(req({ action: "submit", items }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.accepted, 1, "accepted");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_submit"], "rpcs");
  eq(calls[1].args.p_items, items, "items");
});

Deno.test("verdict still calls v2_checker_action", async () => {
  calls.length = 0;
  const r = await h(req({ action: "verdict", id: 9, verdict: "pass" }));
  eq(r.status, 200, "status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_checker_action"], "rpcs");
  eq(calls[1].args.p_action, "verdict", "action");
});

Deno.test("no key -> 401", async () => {
  calls.length = 0;
  const r = await h(req({ action: "add_firm", firm: { name: "X", website: "https://x.com", registry_id: "vc-1" } }, null));
  eq(r.status, 401, "status");
  eq(calls.length, 0, "no rpc");
});

Deno.test("duplicate domain is refused and a new domain is still accepted", async () => {
  const plugId = "52752433-ef2f-4fbe-b79b-ea881d8755fa";
  const noFirms = () => { if (reads.some((r) => r.table === "firms")) throw new Error(`looked at public.firms\n${JSON.stringify(reads)}`); };
  calls.length = 0;
  reads.length = 0;
  firmRows = [{ id: plugId, slug: "plugandplay", primary_domain: "plugandplaytechcenter.com" }];
  v2Rows = [{ firm_id: 7, slug: "plug-and-play", website_url: "https://www.plugandplaytechcenter.com", archived: false }];
  const dup = await h(req({ action: "add_firm", firm: { name: "Plug and Play", website: "https://www.PlugAndPlayTechCenter.com/about", registry_id: "vc-999" } }));
  const dupBody = await dup.json();
  eq(dup.status, 409, "dup status");
  eq(dupBody.error, "a firm with this website already exists", "dup error");
  eq(dupBody.slug, "plug-and-play", "dup slug");
  eq(dupBody.id, 7, "dup id");
  eq(calls.map((c) => c.name), ["ingest_auth"], "no create");
  eq(reads.map((r) => r.table), ["v2_firms"], "v2 only");
  noFirms();
  const v2Url = reads[0].url;
  if (!v2Url.includes("plugandplaytechcenter.com")) throw new Error(`query missed normalized domain\n${v2Url}`);
  if (v2Url.includes("/about") || v2Url.includes("PlugAndPlay")) throw new Error("query kept the path or original case");

  calls.length = 0;
  reads.length = 0;
  firmRows = [{ id: plugId, slug: "plugandplay", primary_domain: "only-on-firms.example" }];
  v2Rows = [];
  addReply = { ok: true, bot_id: "bot-a", firm_id: 42, created: true, slug: "only-on-firms" };
  const firmsOnly = { name: "Only On Firms", website: "https://www.only-on-firms.example/about", registry_id: "vc-firms" };
  const firmsRes = await h(req({ action: "add_firm", firm: firmsOnly }));
  const firmsBody = await firmsRes.json();
  eq(firmsRes.status, 200, "firms-only status");
  eq(firmsBody.firm_id, 42, "firms-only id");
  eq(firmsBody.created, true, "firms-only created");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_firm_guard", "v2_research_add_firm"], "firms-only rpcs");
  eq(calls[2].args.p_firm, firmsOnly, "firms-only firm");
  noFirms();

  calls.length = 0;
  reads.length = 0;
  firmRows = [];
  v2Rows = [{ firm_id: 7, slug: "plug-and-play", website_url: "https://www.plugandplaytechcenter.com", archived: false }];
  addReply = { ok: true, bot_id: "bot-a", firm_id: 43, created: true, slug: "brand-new-firm" };
  const firm = { name: "Brand New Firm", website: "https://www.brand-new-firm.example/about", registry_id: "vc-new" };
  const created = await h(req({ action: "add_firm", firm }));
  const createdBody = await created.json();
  eq(created.status, 200, "new status");
  eq(createdBody.firm_id, 43, "new firm_id");
  eq(createdBody.created, true, "created");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_firm_guard", "v2_research_add_firm"], "new rpcs");
  eq(calls[2].args.p_firm, firm, "firm unchanged");
  noFirms();
  firmRows = [];
  v2Rows = [];
});

Deno.test("claim returns one firm and does not read firms or submit", async () => {
  calls.length = 0;
  reads.length = 0;
  const r = await h(req({ action: "claim" }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.firm_id, 7, "firm_id");
  eq(j.slug, "plug-and-play", "slug");
  eq(j.name, "Plug and Play", "name");
  eq(j.website, "https://www.plugandplaytechcenter.com", "website");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_claim", "v2_bot_notes_unread"], "rpcs");
  eq(calls[1].args.p_key_id, authReply.key_id, "key");
  eq(reads.length, 0, "no table read");
});

Deno.test("done finishes the claimed firm and submit is unchanged", async () => {
  calls.length = 0;
  reads.length = 0;
  const missing = await h(req({ action: "done" }));
  eq(missing.status, 400, "missing firm_id");
  eq(calls.map((c) => c.name), ["ingest_auth"], "no done rpc");
  calls.length = 0;
  const r = await h(req({ action: "done", firm_id: 7 }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.done, true, "done");
  eq(j.firm_id, 7, "firm_id");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_done"], "rpcs");
  eq(calls[1].args.p_firm_id, 7, "firm");
  calls.length = 0;
  const items = [{ firm_id: 7, box: "F5", table: "v2_investor_principles", fact: { source_url: "https://example.com/a" } }];
  const submitted = await h(req({ action: "submit", items }));
  eq(submitted.status, 200, "submit status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_submit"], "submit rpc");
  eq(reads.some((row) => row.table === "firms"), false, "firms not read");
});

Deno.test("frozen key -> 403", async () => {
  addReply = { ok: false, bot_id: "bot-a", error: "Key frozen: too many rejections, 2026-11-07 10:00 PT" };
  const r = await h(req({ action: "add_firm", firm: { name: "X", website: "https://example.com", registry_id: "vc-1" } }));
  eq(r.status, 403, "status");
  const j = await r.json();
  eq(j.error.startsWith("Key frozen"), true, "error");
});

// Required lookup (migration 20261120090000_v2_required_lookup)
const resetAdd = () => { addReply = { ok: true, bot_id: "bot-a", firm_id: 41, created: true, slug: "example-ventures" }; };
Deno.test("add_firm: same name found by lookup -> 409 with the ids, add_firm not called", async () => {
  v2Rows = []; calls.length = 0;
  guardReply = { ok: true, block_on: true, strong: [{ id: 343, name: "RTP Global Management", website: "https://rtp.vc", match_reason: "legal name" }], weak: [] };
  const r = await h(req({ action: "add_firm", firm: { name: "RTP Global", website: "https://rtp.global", registry_id: "x" } }));
  eq(r.status, 409, "status");
  const b = await r.json();
  eq(b.same_as, [343], "same_as");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_firm_guard"], "rpcs");
  eq(calls[1].args, { p_key: "11111111-1111-1111-1111-111111111111", p_name: "RTP Global", p_website: "https://rtp.global" }, "guard args");
});

Deno.test("add_firm: override with not_same_as + reason goes through and is logged", async () => {
  v2Rows = []; calls.length = 0; resetAdd();
  guardReply = { ok: true, block_on: true, strong: [{ id: 343, name: "RTP Global Management", match_reason: "name" }], weak: [] };
  let r = await h(req({ action: "add_firm", firm: { name: "RTP Global", website: "https://rtp.global", registry_id: "x" }, not_same_as: [343] }));
  eq(r.status, 409, "no reason -> still refused");
  calls.length = 0;
  r = await h(req({ action: "add_firm", firm: { name: "RTP Global", website: "https://rtp.global", registry_id: "x" }, not_same_as: [343], not_same_reason: "different firm, Berlin" }));
  eq(r.status, 200, "status");
  const b = await r.json();
  eq(b.firm_id, 41, "firm id");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_firm_guard", "v2_research_add_firm", "v2_lookup_override_log"], "rpcs");
  eq(calls[3].args.p_ids, [343], "logged ids");
  eq(calls[3].args.p_reason, "different firm, Berlin", "logged reason");
  r = await h(req({ action: "add_firm", firm: { name: "X", website: "x.example", registry_id: "x" }, not_same_as: ["343"] }));
  eq(r.status, 400, "bad not_same_as");
});

Deno.test("add_firm: partial match only -> allowed with similar_firms; switch off -> allowed", async () => {
  v2Rows = []; calls.length = 0; resetAdd();
  guardReply = { ok: true, block_on: true, strong: [], weak: [{ id: 11, name: "Founders Fund", match_reason: "partial name" }] };
  let r = await h(req({ action: "add_firm", firm: { name: "Founders Fund Growth", website: "ffg.example", registry_id: "x" } }));
  eq(r.status, 200, "status");
  eq((await r.json()).similar_firms.map((m: any) => m.id), [11], "similar");
  guardReply = { ok: true, block_on: false, strong: [{ id: 343, name: "RTP Global Management", match_reason: "name" }], weak: [] };
  r = await h(req({ action: "add_firm", firm: { name: "RTP Global", website: "rtp.global", registry_id: "x" } }));
  eq(r.status, 200, "switch off");
  eq((await r.json()).similar_firms.map((m: any) => m.id), [343], "listed");
  guardReply = { ok: true, block_on: true, strong: [], weak: [] };
});

Deno.test("submit: every item refused as an existing startup -> 409", async () => {
  submitReply = { ok: true, bot_id: "bot-a", accepted: 0, rejected: 1, held: 0, results: [{ index: 0, status: "Rejected: same startup already exists: startup_id 5614", same_as: [5614] }] };
  let r = await h(req({ action: "submit", items: [{ firm_id: 2, box: "F12", table: "v2_startups", fact: {} }] }));
  eq(r.status, 409, "409");
  submitReply = { ok: true, bot_id: "bot-a", accepted: 0, rejected: 1, held: 0, results: [{ index: 0, status: "Rejected: other" }] };
  r = await h(req({ action: "submit", items: [{ firm_id: 2, box: "F12", table: "v2_startups", fact: {} }] }));
  eq(r.status, 422, "422");
  submitReply = { ok: true, bot_id: "bot-a", accepted: 1, rejected: 0, held: 0, results: [{ index: 0, status: "Accepted" }] };
});
