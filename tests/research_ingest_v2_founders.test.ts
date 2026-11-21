// research-ingest-v2: add_founder, founder lookup, and the founder hand-out.
// The bot comes from x-ingest-key. No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_founders.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const KEY = "11111111-1111-1111-1111-111111111111";
const calls: { name: string; args: any }[] = [];
const replies: Record<string, any> = {
  v2_founder_add: { ok: true, bot_id: "bot-a", founder_id: 7, created: true, role: { fact_id: 1, startup_id: 10 } },
  v2_founder_lookup: { ok: true, kind: "founder", found: true, total: 1, matches: [{ founder_id: 7, name: "Ada Lovelace", linkedin_url: "https://www.linkedin.com/in/ada", startups: [{ id: 10, name: "Analytical Engines" }], past_jobs: [{ company: "Babbage Co", job_role: "Mathematician" }], founded_before: [{ value: "yes: Analytical Kids", exit_outcome: "acquired", exit_acquirer: "Babbage Co", exit_source_url: "https://news.example/ada" }], match_reason: "linkedin" }] },
  founderlist_claim_next_founder_startups: { ok: true, bot_id: "bot-a", startup: { startup_id: 10, startup_name: "Analytical Engines" }, startups: [{ startup_id: 10 }], claimed_count: 1, held_count: 1 },
  founderlist_finish_founder_startup: { ok: true, bot_id: "bot-a", startup: { startup_id: 10, status: "done" } },
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

const good = {
  action: "add_founder",
  startup_id: 10,
  founder: { name: "Ada Lovelace", linkedin_url: "https://www.linkedin.com/in/ada" },
  role: { value: "CEO", source_url: "https://example.com/ada" },
  facts: [
    { fact: "current_country", value: "GB", source_url: "https://example.com/ada" },
    { fact: "past_job", value: "Babbage Co", role: "Mathematician", company_website: "https://babbage.example", source_url: "https://news.example/ada" },
    { fact: "founded_before", value: "yes: Analytical Kids", source_url: "https://news.example/ada" },
  ],
  bot_id: "someone-else",
};

Deno.test("add_founder: key from the header, body passed through, bot_id in the body ignored", async () => {
  calls.length = 0;
  const r = await h(req(good));
  eq(r.status, 200, "status");
  eq((await r.json()).founder_id, 7, "id");
  eq(calls.find((x) => x.name === "v2_founder_add")!.args, {
    p_key_id: KEY,
    p_startup_id: 10,
    p_founder: good.founder,
    p_role: good.role,
    p_facts: good.facts,
  }, "rpc args");
});

Deno.test("add_founder: refused before the database", async () => {
  calls.length = 0;
  const cases: [unknown, string][] = [
    [{ ...good, startup_id: "10" }, "startup_id is required"],
    [{ ...good, founder: [] }, "founder must be an object"],
    [{ ...good, role: { value: "CEO" } }, "role source_url is required"],
    [{ ...good, facts: [{ fact: "current_city", value: "London" }] }, "needs a source_url"],
    [{ ...good, facts: [{ fact: "past_job", value: "  ", source_url: "https://x" }] }, "past_job needs a company name"],
    [{ ...good, facts: [{ fact: "past_job", value: "Babbage Co", role: "x".repeat(301), source_url: "https://x" }] }, "past_job role must be text up to 300"],
    [{ ...good, facts: [{ fact: "current_city", value: "London", role: "Mayor", source_url: "https://x" }] }, "role on a fact is only for past_job"],
    [{ ...good, facts: [{ fact: "current_country", value: "England", source_url: "https://x" }] }, "2-letter country code"],
    [{ ...good, facts: [{ fact: "salary", value: "1", source_url: "https://x" }] }, "unknown fact type"],
    [{ ...good, facts: [{ fact: "role", value: "CEO", source_url: "https://x" }] }, "send the startup role in role"],
    [{ ...good, founder: { name: "Ada", linkedin_url: "https://example.com/not-linkedin" } }, "LinkedIn profile"],
    [{ ...good, facts: [{ fact: "founded_before", value: "maybe", source_url: "https://x" }] }, "founded_before"],
    [{ ...good, facts: [{ fact: "past_job", value: "Babbage Co", exit_outcome: "acquired", exit_source_url: "https://x", source_url: "https://x" }] }, "exit_outcome is only for founded_before"],
    [{ ...good, facts: [{ fact: "current_city", value: "London", exit_acquirer: "Buyer", source_url: "https://x" }] }, "exit_acquirer is only for founded_before"],
    [{ ...good, facts: [{ fact: "university", value: "London", exit_source_url: "https://x", source_url: "https://x" }] }, "exit_source_url is only for founded_before"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: "merged", source_url: "https://x" }] }, "exit_outcome must be acquired, ipo or shut_down"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: 1, source_url: "https://x" }] }, "exit_outcome must be acquired, ipo or shut_down"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: "ipo", exit_acquirer: "Buyer", exit_source_url: "https://x", source_url: "https://x" }] }, "exit_acquirer is only allowed when exit_outcome is acquired"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: "acquired", exit_acquirer: "x".repeat(301), exit_source_url: "https://x", source_url: "https://x" }] }, "exit_acquirer must be text up to 300"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: "shut_down", source_url: "https://x" }] }, "exit_source_url is required when exit_outcome is set"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_outcome: "ipo", exit_source_url: "notaurl", source_url: "https://x" }] }, "exit_source_url is required when exit_outcome is set"],
    [{ ...good, facts: [{ fact: "founded_before", value: "yes", exit_source_url: "https://x", source_url: "https://x" }] }, "exit_source_url is only allowed when exit_outcome is set"],
  ];
  for (const [body, needle] of cases) {
    const r = await h(req(body));
    eq(r.status, 400, needle);
    const err = (await r.json()).error as string;
    if (!err.includes(needle)) throw new Error(`expected ${needle}\n got ${err}`);
  }
  eq(calls.some((x) => x.name === "v2_founder_add"), false, "no rpc");
});

Deno.test("add_founder: exit fields on founded_before are passed through", async () => {
  calls.length = 0;
  const facts = [
    { fact: "founded_before", value: "yes: Analytical Kids", exit_outcome: "ACQUIRED", exit_acquirer: "Babbage Co", exit_source_url: "https://news.example/ada", source_url: "https://news.example/ada" },
    { fact: "founded_before", value: "no", exit_outcome: "shut_down", exit_source_url: "http://news.example/shut", source_url: "https://news.example/ada" },
    { fact: "founded_before", value: "yes", source_url: "https://news.example/ada" },
  ];
  const r = await h(req({ ...good, facts }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "v2_founder_add")!.args.p_facts, facts, "facts");
});

Deno.test("add_founder: startup missing is 404, a duplicate LinkedIn is 409, a frozen key is 403", async () => {
  replies.v2_founder_add = { ok: false, error: "startup_id 99 not found" };
  eq((await h(req({ ...good, startup_id: 99 }))).status, 404, "missing startup");
  replies.v2_founder_add = { ok: false, duplicate: true, founder_id: 7, error: "a founder with this LinkedIn already exists (founder_id 7: Ada Lovelace); send founder_id 7 to reuse that person" };
  const dup = await h(req(good));
  eq(dup.status, 409, "duplicate");
  eq((await dup.json()).founder_id, 7, "existing id");
  replies.v2_founder_add = { ok: false, error: "Key frozen: test, 2026-11-20 17:00 PT" };
  eq((await h(req(good))).status, 403, "frozen");
  replies.v2_founder_add = { ok: true, bot_id: "bot-a", founder_id: 7, created: true };
});

Deno.test("lookup founder: name and linkedin passed through, firm lookup unchanged", async () => {
  calls.length = 0;
  const r = await h(req({ action: "lookup", founder: { name: "José Müller", linkedin_url: "https://www.linkedin.com/in/Jose-Muller/" }, key_id: "nope" }));
  eq(r.status, 200, "status");
  const b = await r.json();
  eq(b.matches[0].founder_id, 7, "id");
  eq(b.matches[0].startups[0].name, "Analytical Engines", "startup");
  eq(b.matches[0].past_jobs[0], { company: "Babbage Co", job_role: "Mathematician" }, "job");
  eq(b.matches[0].founded_before[0], { value: "yes: Analytical Kids", exit_outcome: "acquired", exit_acquirer: "Babbage Co", exit_source_url: "https://news.example/ada" }, "exit");
  if (!String(b.hint).includes("reuse a founder_id")) throw new Error("hint should say when to reuse");
  eq(calls.find((x) => x.name === "v2_founder_lookup")!.args, {
    p_key: KEY, p_name: "José Müller", p_linkedin: "https://www.linkedin.com/in/Jose-Muller/",
  }, "rpc");
  calls.length = 0;
  replies.v2_founder_lookup = { ok: true, kind: "founder", found: false, total: 0, matches: [] };
  const empty = await (await h(req({ action: "lookup", founder: { name: "Nobody" } }))).json();
  if (!String(empty.hint).includes("not stored yet")) throw new Error("empty hint");
  for (const body of [
    { action: "lookup", founder: {} },
    { action: "lookup", founder: { name: "A" }, firm: { name: "B" } },
    { action: "lookup", founder: "Ada" },
    { action: "lookup" },
  ]) eq((await h(req(body))).status, 400, JSON.stringify(body).slice(0, 80));
});

Deno.test("claim_next_founder_startups and finish_founder_startup", async () => {
  calls.length = 0;
  const r = await h(req({ action: "claim_next_founder_startups" }));
  eq(r.status, 200, "status");
  eq(calls.find((x) => x.name === "founderlist_claim_next_founder_startups")!.args, { p_key_id: KEY, p_count: 1 }, "default count");
  if (!(await r.json()).hint.includes('"startup_id":10')) throw new Error("hint should name the startup");
  calls.length = 0;
  eq((await h(req({ action: "claim_next_founder_startups", count: 10 }))).status, 200, "count 10");
  eq(calls.at(-1)!.args.p_count, 10, "count passed");
  calls.length = 0;
  for (const bad of [0, 11, 2.5, "3"]) eq((await h(req({ action: "claim_next_founder_startups", count: bad }))).status, 400, `count ${bad}`);
  eq(calls.some((x) => x.name === "founderlist_claim_next_founder_startups"), false, "no rpc on bad count");
  replies.founderlist_claim_next_founder_startups = {
    ok: false, held_count: 10, held_startup_ids: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    error: "you already hold 10 startups (the most is 10): 1, 2, 3, 4, 5, 6, 7, 8, 9, 10. Finish one with finish_founder_startup before you ask for more.",
  };
  const full = await h(req({ action: "claim_next_founder_startups" }));
  eq(full.status, 409, "at 10");
  eq((await full.json()).held_startup_ids.length, 10, "ids");
  calls.length = 0;
  eq((await h(req({ action: "finish_founder_startup", startup_id: "10", result: "done", note: "x" }))).status, 400, "startup_id");
  eq((await h(req({ action: "finish_founder_startup", startup_id: 10, result: "skip", note: "x" }))).status, 400, "result");
  eq((await h(req({ action: "finish_founder_startup", startup_id: 10, result: "done", note: " " }))).status, 400, "note");
  eq(calls.some((x) => x.name === "founderlist_finish_founder_startup"), false, "no rpc");
  const done = await h(req({ action: "finish_founder_startup", startup_id: 10, result: "done", note: "saved Ada" }));
  eq(done.status, 200, "done");
  eq(calls.find((x) => x.name === "founderlist_finish_founder_startup")!.args, { p_key_id: KEY, p_startup_id: 10, p_result: "done", p_note: "saved Ada" }, "finish args");
  replies.founderlist_finish_founder_startup = { ok: false, error: "finish_founder_startup done refused: you have no founder role saved for this startup since you took it." };
  eq((await h(req({ action: "finish_founder_startup", startup_id: 10, result: "done", note: "x" }))).status, 400, "refused");
});
