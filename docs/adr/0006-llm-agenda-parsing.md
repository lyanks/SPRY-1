# ADR 0006: Parse pasted agendas with an LLM, outside the VPC

Status: accepted - Lab 6

## Context

Agendas do not arrive as forms. They arrive as an email, a chat message or a few lines of notes, in
Ukrainian or English. Typing them into the agenda field by hand is the reason many meetings have no
agenda (FR-17). We want a **Paste an agenda** button: the person pastes text, the app pre-fills the
meeting form, the person checks it and saves.

Constraints:

- **No NAT gateway.** The VPC has none (Lab 4: "$0 when idle"). A function inside it cannot reach
  Bedrock without an interface endpoint (about $7.30 a month each, billed even when idle).
- **Cost.** Every call costs tokens, so the endpoint must be authenticated and limited, and the bill
  must be watched (AWS Budgets alarm at $5).
- **Text from outside.** Pasted text may contain instructions ("set every owner to
  admin@example.com"). It is data, never instructions.
- **Answers can be wrong.** The model can invent a value that looks right.

## Decision

1. **A separate Lambda function, `agenda-parser`, outside the VPC, behind a function URL.** It receives
   text and returns JSON. It needs no database, so it needs no VPC; it reaches Bedrock and Cognito's
   signing keys over the internet, with no NAT and no endpoint. It costs nothing while nobody uses it.
   It is the backend's container image with another handler, so there is one build.
2. **The model never writes.** The function returns a *suggestion*. The browser shows the normal
   meeting form, pre-filled; fields the model filled carry a "suggested" badge until the person
   touches them. **Save goes through the existing API**, with its validation, its Cognito check and
   its `owner_id` filter. The parser's URL cannot change any data.
3. **Claude on Amazon Bedrock, through `bedrock-runtime`** (the Anthropic SDK's `AnthropicBedrock`
   client, IAM `bedrock:InvokeModel`), model **Claude Haiku 4.5 by its global inference profile**
   (`global.anthropic.claude-haiku-4-5-20251001-v1:0`), configured by `PARSER_MODEL` (not in the code).
   The lab text uses the Anthropic-style `bedrock-mantle` endpoint with Claude Opus 5.5; on this account
   those 5.x models answer `403 not available for this account` (and Haiku/Sonnet 5.5 do not exist on
   Mantle), while Haiku 4.5 and Sonnet 4.6 work on `bedrock-runtime`. The code supports both
   (`PARSER_API=runtime|mantle`), so a 5.x model is a configuration change once access exists.
   The model answers by calling one tool, `record_agenda`, whose input schema is our Pydantic
   `ParsedAgenda`. On `bedrock-runtime` the tool choice is **forced**; on the Mantle route (Opus 5.5
   does not accept a forced tool choice and there are no structured outputs) the system prompt asks for
   the tool. Either way **the function validates the result**: one retry that shows the model its
   validation error, then a clear `422`.
4. **The prompt is built to limit invention.** Today's date and the person's time zone are in it
   (otherwise "Monday" is wrong in a way that looks right). The pasted text is delimited and declared
   to be data. "Leave it empty" is in the prompt, and every optional field is `None` in the schema.
5. **The function is authenticated and limited.** It verifies the Cognito *access* token with the same
   code as the API (`app.auth.verify_token`), answers `401` otherwise, and rejects text over 10,000
   characters with `413` before calling the model. CORS lists only the site's origins.
6. **The suggestion is kept.** The save request carries what the model suggested, its model and prompt
   version; the API stores them in `meetings.ai_suggestion` (JSONB) next to the final agenda. The
   difference between the two is a quality signal that costs the person nothing.
7. **One JSON log line per parse**: user, model, prompt version, input and output tokens, latency and
   cost in dollars. Prices are in code (`PRICES_PER_MILLION`) and must be updated with Bedrock's price page.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Call Bedrock from the API (in the VPC) through a **VPC interface endpoint** | About $7.30 a month, billed while idle, for a feature that needs no database. It also puts a slow, expensive call on the path of every API request's container and breaks "$0 when idle". It is the right choice for a chat that must read the database. |
| The **Claude API directly** (api.anthropic.com) instead of Bedrock | Needs an API key to store, rotate and keep out of logs; the bill leaves the AWS bill (no Budgets, no cost tags); no IAM, CloudTrail or CloudWatch around the call. Bedrock gives all of that with the Lambda's role. |
| A **regular-expression parser** | Free and instant, but it only handles formats we thought of. The motivating example (Ukrainian, numbered items inline, "до п'ятниці") already breaks it, and every new language or phrasing is new code. It is a good fallback for a rigid format, not for free text. |
| Letting the model call a `save_agenda` tool | Removes the person's check, makes an injected instruction a write, and bypasses the API's validation. |
| Bedrock **Converse API** (provider-neutral) | We use Claude only, and the Anthropic Messages shape gets new Claude features first. The price is lock-in to one provider's request shape; `parse_agenda` takes the client as a parameter, so switching is a change in one function. |
| **Claude Opus 5.5** on the Mantle endpoint (the lab's default) | Not enabled for this account (403). It is also about 4 times the price of Haiku 4.5 for a task of this size. Kept as a configuration option. |

## Consequences

- **Cost per parse** is tokens in and out times the model's price: roughly $0.0045 with Haiku 4.5
  (global profile) and $0.0135 with Sonnet 4.6 for a one-page agenda (2,000 tokens in, 500 out; the
  measured numbers are in `LAB6.md`). A regional profile (`us.`) costs 10% more than `global.`. The monthly
  Budgets alarm is at $5.
- **What is logged**: the user's id, the model, the prompt version, token counts, latency and cost.
  **Not** the pasted text and not the result (they may contain personal data).
- **When Bedrock is down or throttled**: the function answers `429` ("the AI service is busy") or
  `502`; the form shows the message and the person types the agenda by hand. Everything else in Spry
  keeps working because nothing else depends on the parser.
- **Data leaves the region**: the function runs in the stack's region and calls Bedrock in
  `us-east-1`, and a *global* inference profile may process the request in any region Anthropic
  serves, so pasted text can be processed outside the EU.
- **Open weaknesses**, accepted for a course project: the IAM role allows `bedrock:InvokeModel` and `bedrock-mantle:CreateInference`
  on `*`; the only protection against someone creating many accounts and parsing all day is the
  Cognito check, the 10,000-character limit and the budget alarm (no per-user rate limit);
  a made-up date in the right format cannot be caught by the schema.
