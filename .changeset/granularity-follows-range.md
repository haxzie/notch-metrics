---
"@notch/mac": patch
---

Fix widget ranges erroring on the AI connectors. A widget froze its bucket
when it was created — the first one its metric listed, which is `hour` for
both OpenAI and Claude — and kept sending it as the range moved, so a
90-day tile asked for ninety days of hourly buckets and the connector
refused a walk it could not finish. The bucket now follows the range, the
way the server and the range picker already assumed.
