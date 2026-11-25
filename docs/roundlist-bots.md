# Round list: instructions for the bots

This is the hand-out of funding rounds (schema `roundlist`). Bots claim a round, save its deals through the door, then finish it. Do not apply a tighter done check live until Alex says "make it live".

Use your existing key, only in the `x-ingest-key` header. Never put the key in the body, chat, files or URLs.

## Door actions

- `{"action":"notes"}` first, and do what any note says.
- `{"action":"add_round","round":{"startup_name","startup_website","country","round","round_date":"YYYY-MM-DD","source_url"}}` adds a round. A copy (same startup + round + date) is refused (409).
- `{"action":"claim_next_round","count":1}` gives the oldest open rounds, up to 10 held at once, for 2 hours each.
- Save each named investor that is already in our list with `submit` (one `v2_deals` row per firm, exact date, amount when the source gives one, `lead: "yes"` on the lead, and the announcement as `source_url`). Look the firm up first. Do not create firms.
- `{"action":"finish_round","round_id":N,"result":"done","note":"...","source_url":"https://...","amount":N,"investors":[{"firm_id":N},{"name":"...","website":"https://...","lead":true}]}`
  - `source_url` is required.
  - `amount` is required when the announcement gives one. If it does not, set `amount_not_in_source` to true instead.
  - `investors` must list every named investor: `firm_id` when the firm is already in our list (and you have already saved its deal), or `name` and `website` when it is not. Those new names are saved for Alex's OK. If a name is already in our list, finish is refused: save the deal with that `firm_id` instead.
  - Mark the lead deal (`lead: "yes"`), or if the lead is not in our list set `lead` true on that investor, or if the source names no lead write `no lead named in the source` in the note and set `no_lead_named` to true.
- A round can only be marked done when there is a matching event for that startup and round with an exact date, the amount (when the source gives one), a source URL, the lead rule above, and every named investor either linked as a current deal or listed as not in our list.
- `{"action":"finish_round","round_id":N,"result":"rejected","note":"...","source_url":"https://..."}` when the row is wrong or you found nothing. The note says why, and `source_url` is required (the announcement, or the page that shows you found nothing).

A bot holds at most 10 rounds. Finish one before asking for more. After 2 hours an unfinished round goes back to the list.

## Paste message

```
To <bot_id>:
New task. Work the existing round list. Claim open rounds, save every named investor already in our list, and finish each round only when the deals are complete. Use your existing key, only in the x-ingest-key header. Never print it or put it in chat, files or URLs.

1. Send {"action":"notes"} first, and do what any note says.
2. If you find a 2026 funding round that is not on the list, add it with {"action":"add_round","round":{"startup_name":"...","startup_website":"https://...","country":"...","round":"Series A","round_date":"YYYY-MM-DD","source_url":"https://..."}}. If it is already on the list, skip it.
3. Claim open rounds with {"action":"claim_next_round","count":3}. You can hold at most 10, and each goes back to the list after 2 hours. Finish one before you ask for more.
4. For each claimed round, open the official announcement (the source_url on the round, or a better official source if you find one). Fill in the amount, the exact date, and the lead. Use that exact date on every deal you save.
5. Look up every named investor. For each firm already in our list, save the deal with submit: the exact date, the amount when the source gives one, lead "yes" on the lead, and the announcement as source_url. One deal per investor. Do not create firms.
6. If an investor is not in our list, do not add the firm. You will name it on finish (name and website). If the door says that name is already in our list, save the deal with that firm_id instead.
7. When every named investor is saved or listed as not in our list, finish the round with {"action":"finish_round","round_id":N,"result":"done","note":"...","source_url":"https://...","amount":N,"investors":[{"firm_id":N},{"name":"...","website":"https://..."}]}. The note says what you saved. If the source does not give an amount, set "amount_not_in_source":true instead of amount. If the source names no lead, write "no lead named in the source" in the note and set "no_lead_named":true. If the lead is not in our list, set "lead":true on that investor. A round cannot be marked done until there is a matching event with the exact date, the amount when the source gives one, a source URL, a lead (or that no-lead note), and every named investor either linked as a current deal or listed with name and website.
8. If the row is wrong or you found nothing, finish with {"action":"finish_round","round_id":N,"result":"rejected","note":"...","source_url":"https://..."}. The note says why, and source_url is required (the announcement, or the page that shows you found nothing).
9. Then claim the next open rounds.

Use helpers.
```
