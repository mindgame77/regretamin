// PowerPoint and Keynote decks (founder, 27 Nov 2026: "we have to support those formats").
// The model that reads the deck takes PDF, not .pptx or .key, so a presentation is turned into a PDF first by CloudConvert
// (https://cloudconvert.com/api/v2). The founder puts the key in Cloudflare as CLOUDCONVERT_API_KEY; it never appears on the page.
// One synchronous job: import the deck from its 15-minute link, convert to PDF, hand back a link to the PDF. That link goes to the
// model in place of the deck's own link. Nothing is stored by us; CloudConvert deletes its copies itself (its documented behaviour is
// to remove files after a day; the founder should confirm this in his account settings).

export const isPresentation = (path) => /\.(pptx?|pps[xm]?|pot[xm]?|key)$/i.test(String(path || ''));

export async function toPdf(env, deckUrl, path, fetchFn = fetch) {
  const key = env && env.CLOUDCONVERT_API_KEY;
  if (!key) return { error: 'convert_not_configured' };
  const ext = (String(path).match(/\.([A-Za-z0-9]+)$/) || [])[1] || 'pptx';
  let r;
  try {
    r = await fetchFn('https://sync.api.cloudconvert.com/v2/jobs', {
      method: 'POST',
      headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
      body: JSON.stringify({ tag: 'regretamin-ready', tasks: {
        deck: { operation: 'import/url', url: deckUrl, filename: `deck.${ext.toLowerCase()}` },
        pdf: { operation: 'convert', input: 'deck', input_format: ext.toLowerCase(), output_format: 'pdf' },
        out: { operation: 'export/url', input: 'pdf' },
      } }),
    });
  } catch (e) { return { error: 'convert_unreachable' }; }
  if (!r.ok) return { error: `convert_${r.status}: ${(await r.text().catch(() => '')).slice(0, 300)}` };
  let j = null;
  try { j = await r.json(); } catch (e) { j = null; }
  const job = j && j.data, tasks = (job && job.tasks) || [];
  const bad = tasks.find((t) => t.status === 'error');
  if (bad || !job || job.status === 'error') return { error: `convert_failed: ${String((bad && (bad.message || bad.code)) || 'the converter refused the file').slice(0, 300)}` };
  const out = tasks.find((t) => t.operation === 'export/url' && t.status === 'finished');
  const url = out && out.result && out.result.files && out.result.files[0] && out.result.files[0].url;
  if (!url || !/^https:\/\//.test(url)) return { error: 'convert_failed: no PDF came back' };
  return { url };
}
