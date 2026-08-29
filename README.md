# mailkube-ruby

[![CI](https://github.com/mailkube/mailkube-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/mailkube/mailkube-ruby/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/mailkube.svg)](https://rubygems.org/gems/mailkube)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Code of Conduct](https://img.shields.io/badge/Contributor%20Covenant-2.1-purple.svg)](CODE_OF_CONDUCT.md)

The official Ruby SDK for [mailkube](https://mailkube.com).

Requires Ruby 3.4 or newer.

## Install

```bash
bundle add mailkube
```

**Zero runtime dependencies.** The gemspec has no `add_dependency`; the standard library covers
everything. That is deliberate — this gem is installed into other people's applications, where
every dependency is a version conflict waiting to happen.

## Usage

```ruby
require "mailkube"

client = Mailkube.new # reads MAILKUBE_API_KEY

email = client.emails.send(
  from: "Acme <hello@yourdomain.com>",
  to: "customer@example.com",
  subject: "Hello world",
  html: "<p>It works!</p>"
)

puts email.id
```

Create one client and reuse it.

### Configuration

| Option | Argument | Environment | Default |
|---|---|---|---|
| API key | `api_key:` | `MAILKUBE_API_KEY` | required |
| Base URL | `base_url:` | `MAILKUBE_BASE_URL` | `https://api.mailkube.com/mta/v1/` |
| Timeout | `timeout:` | | 30s |
| HTTP adapter | `http:` | | `Mailkube::NetHttpAdapter` |
| User-Agent suffix | `user_agent_suffix:` | | none |

If you are building something on top of this gem — a CLI, an internal service, a framework
integration — set `user_agent_suffix:` to your own `name/version`. It is appended after this SDK's
own token, so both are visible: `mailkube-ruby/1.1.0 my-cli/1.0.0`. Surrounding whitespace is
trimmed, and a value containing CR or LF is **ignored rather than sanitized** — a header value that
could split the request is not one this gem will send, and quietly repairing it would hide the bug.

Pass your own `http:` adapter — anything responding to
`#call(method:, url:, headers:, body:)` and returning a `Mailkube::HttpResponse` — to route
through a proxy, add instrumentation, or drive the client from a test.

There are deliberately **no built-in retries**. A `RateLimitError` carries `retry_after` and a
`ServerError` is safe to retry with backoff, so the calling application decides.

### Idempotency

Set an idempotency key on anything you might retry. The API replays the original response instead
of sending twice.

```ruby
client.emails.send(**params, idempotency_key: "order-1234-shipped")
```

Reusing a key with a *different* payload is a `ConflictError`, not a silent overwrite.

### Attachments and tags

```ruby
client.emails.send(
  from: "Acme <hello@yourdomain.com>",
  to: "customer@example.com",
  subject: "Your report",
  text: "Attached.",
  attachments: [Mailkube::Attachment.new(filename: "report.csv", content: File.binread("report.csv"))],
  tags: [Mailkube::Tag.new(name: "campaign", value: "welcome")]
)
```

`content` is raw bytes; the SDK base64-encodes them for you. Tags are denormalized onto the sending
log, so you can filter, export and dashboard by them, and they ride along on delivery webhooks.
**Tag values are not encrypted — never put personal data in one.**

## Scheduling

Pass `scheduled_at:` to schedule instead of sending now. The result reports `#scheduled?`.

```ruby
email = client.emails.send(**params, scheduled_at: Time.now.utc + 3600)
email.scheduled?    # => true
email.status        # => "scheduled"
```

A `Time` is rendered to ISO-8601 for you; a string is passed through untouched, so it must already
carry an offset. The instant must be in the future and within your plan's scheduling horizon.

### Managing scheduled emails

```ruby
client.scheduled_emails.get(email.id)
client.scheduled_emails.update(email.id, scheduled_at: later, batch_id: "welcome")
client.scheduled_emails.cancel(email.id)
```

The content of a scheduled email is immutable; only its due time and batch can change.

### Listing and pagination

```ruby
page = client.scheduled_emails.list(status: %w[scheduled canceled], page: 2)
page.data              # => [Mailkube::ScheduledEmail, ...]
page.pagination.total_count
page.more?             # => true when the server issued a next-page link
```

Filters: `status`, `batch_id`, `scheduled_at_gte`, `scheduled_at_lte`, `page`. An omitted filter is
never sent. Only `scheduled`, `canceled` and `failed` can be listed — a sent email has left the
collection, so `status: "sent"` is a validation error rather than an empty result.

For every page, use `iter_all`. It returns a lazy `Enumerator`, follows the server's `next` link
rather than counting pages, and makes no request until you iterate it:

```ruby
client.scheduled_emails.iter_all(status: "scheduled").each { |email| puts email.id }
client.scheduled_emails.iter_all.first(5)   # fetches only the pages it needs
```

`recipients` on a listed email is a **summary string** (`"a@b.com +2"`), not an array. The full
recipient list stays server-side.

### Batches

Group scheduled sends under a `batch_id:` and move or cancel them as a unit:

```ruby
client.emails.send(**params, scheduled_at: due, batch_id: "welcome-2026-08")
client.scheduled_emails.batches.update("welcome-2026-08", scheduled_at: later)
client.scheduled_emails.batches.cancel("welcome-2026-08")
```

An unknown batch is a no-op reporting `canceled_count: 0` rather than a 404, so a count of zero is
not a failure.

## Errors

Every error descends from `Mailkube::Error`, so rescue the category you care about:

```ruby
begin
  client.emails.send(from: ..., to: ..., subject: ...)
rescue Mailkube::RateLimitError => e
  sleep(e.retry_after || 1)
rescue Mailkube::APIError => e
  warn "#{e.status_code} #{e.error_name}: #{e.message} (request #{e.request_id})"
end
```

**Quote `request_id` when you report a failure.** Every API response carries an `X-Request-Id`, and
a mapped `APIError` exposes it. It is the only value that lets support find your exact call in the
server-side logs, so include it verbatim in the ticket. Setting `MAILKUBE_LOG=debug` also writes it
on the response line, which is what makes a failure traceable from your own logs.

Categories: `BadRequestError` (400), `AuthenticationError` (403), `NotFoundError` (404),
`ConflictError` (409), `InvalidRequestError` (422), `RateLimitError` (429), `ServerError` (5xx),
and `APIError` for anything else, which is also the parent of all of them. A transport failure
raises `ConnectionError` and is deliberately **not** an API error.

`Mailkube::ErrorName` lists the documented `name` values for discoverability. It is **not** a
closed set: `error_name` stays a plain String, so a value this release has never heard of is
reported verbatim rather than crashing. Scheduling adds `scheduling_not_included` (403),
`scheduled_email_not_found` (404) and `scheduled_email_not_pending` (422).

## Webhooks

`Mailkube::Webhooks.verify` checks the signature and returns a typed event:

```ruby
event = Mailkube::Webhooks.verify(
  payload: request.raw_post,      # the RAW bytes, never re-encoded JSON
  headers: request.headers,
  secret: ENV.fetch("MAILKUBE_WEBHOOK_SECRET")
)

case event
when Mailkube::Events::EmailBouncedEvent
  puts event.data.bounce.reason
when Mailkube::Events::UnknownEvent
  puts "newer than this SDK: #{event.type}"
end
```

Verify against the bytes you received. Never parse the body and re-encode it first: JSON
round-tripping reorders keys and normalizes whitespace, and the signature will not match. In Rails
that means `request.raw_post`, not `params`. `request.headers` works directly — the SDK accepts any
header mapping, including Rack's CGI-env spelling.

`Mailkube::Webhooks.verify_signature` is the signature check alone, if you want to parse yourself.
`X-Webhook-Id` is stable across retries; deduplicate on it.

`Mailkube::Webhooks.sign` is the mirror, so your own tests can build a valid request without
reimplementing the HMAC from this page:

```ruby
signature = Mailkube::Webhooks.sign(
  id: "wh_1", timestamp: Time.now.utc.iso8601, payload: body, secret: secret
)
```

### Endpoint registration

When you create an endpoint, or re-point an existing one, mailkube probes it with
`GET <url>?hub.mode=subscribe&hub.challenge=<token>` and persists it **only** if the body echoes
that token verbatim with a 200. Skip this and no event is ever delivered. Both webhook examples
implement it.

### Event types

| Type | Envelope | Nested block |
|---|---|---|
| `email.sent` | `EmailSentEvent` | `data.sent` |
| `email.delivered` | `EmailDeliveredEvent` | `data.delivery` |
| `email.bounced` | `EmailBouncedEvent` | `data.bounce` |
| `email.delivery_delayed` | `EmailDeliveryDelayedEvent` | `data.delay` |
| `email.suppressed` | `EmailSuppressedEvent` | `data.suppression` |
| `email.scheduled` | `EmailScheduledEvent` | `data.scheduled` |
| `email.failed` | `EmailFailedEvent` | `data.failed` |
| `email.opened` | `EmailOpenedEvent` | `data.open` |
| `email.clicked` | `EmailClickedEvent` | `data.click` |
| `domain.status` | `DomainStatusEvent` | `data.previous` |
| `webhook.status` | `WebhookStatusEvent` | `data.previous` |

Every `email.*` payload also carries the message context: `email_id`, `created_at`, `domain`,
`subject`, `to`, `from` and `tags`.

On the `data.open` and `data.click` blocks, `ip_address`, `country` and `user_agent` are recorded
only where the sending domain has elected them, and both settings are off by default. The server
omits the key rather than sending an empty value, so the accessor returns `nil` when it was not
recorded. `country` can be `nil` even where the address was recorded, because it is resolved at the
edge and is not available on every path.

Two guarantees hold for every released version, so a platform change never breaks a running
receiver:

- **An unknown event type is not an error.** It parses as `Mailkube::Events::UnknownEvent`, whose
  `data` is the raw hash.
- **Unknown fields are preserved**, at every nesting depth. `event[...]` and `event.data[...]`
  reach anything this release does not model, and `event.to_h` round-trips to exactly what the
  server sent.

## Logging

Silent by default. Turn it on with any object responding to `#write`:

```ruby
Mailkube.enable_logging                          # $stderr
Mailkube.enable_logging(device: Rails.logger)    # or your own
```

Or set `MAILKUBE_LOG`. It holds a **level**, not an on/off flag, exactly as in the python, node, Go
and PHP SDKs: `MAILKUBE_LOG=debug` (or `trace`, or `all`) turns the SDK on, and anything more
selective silences it — `MAILKUBE_LOG=warning` is a working way to say "logs, but not from the
SDK". This SDK emits one class of record, the request/response trace, and that record is
debug-level. An unrecognized value leaves logging off rather than raising, because this is read at
`require` time.

The `Authorization` and `Idempotency-Key` headers are redacted from every line, and no recipient
address, subject or body is ever written. The response line carries the server's request id when
one was sent.

This is a duck-typed sink rather than a stdlib `Logger` on purpose: `logger` stopped being a
default gem in Ruby 4.0, so requiring it here would break the zero-dependency claim — and a library
has no business installing handlers on its host's behalf.

## Concurrency

Create one client and reuse it. It is frozen after construction and safe to share across threads,
and across fibers where your application has installed a scheduler. Ruby releases the GVL around
socket I/O, so plain threads give you real HTTP concurrency with no setup.

Each request opens its own connection. That is deliberate: sharing one `Net::HTTP` across callers
does not raise, it lets two callers interleave on one socket and hands one of them the other's
response body. If you want pooling, inject an adapter that pools — and make it safe under threads
*and* under a fiber scheduler.

## Supported surface

These are covered by semantic versioning:

- `Mailkube.new`, `Mailkube.enable_logging`
- `client.emails`, `client.scheduled_emails` and their verbs
- the response models and `Mailkube::Attachment` / `Mailkube::Tag`
- the error hierarchy and `Mailkube::ErrorName`
- `Mailkube::Webhooks` and everything under `Mailkube::Events`
- the `http:` adapter contract: `#call(method:, url:, headers:, body:)` returning a
  `Mailkube::HttpResponse` and raising only `Mailkube::ConnectionError`

Everything else — `Transport`, `RequestSpec`, `Config`, and the internals of `NetHttpAdapter` — is
marked `@api private` and may change in any release. Build on the list above.

### Type signatures

RBS signatures ship in `sig/` and are packaged with the gem, so Steep and RBS-aware editors type
your calls without extra setup.

## More examples

Runnable scripts in [`examples/`](examples/):

- [`simple_send.rb`](examples/simple_send.rb) — the smallest useful program
- [`send_with_attachments.rb`](examples/send_with_attachments.rb) — attach a file from raw bytes
- [`send_with_tags.rb`](examples/send_with_tags.rb) — tag a send for filtering and reporting
- [`send_with_template.rb`](examples/send_with_template.rb) — send from a saved template
- [`schedule_send.rb`](examples/schedule_send.rb) — schedule a send, then inspect the ack
- [`manage_scheduled_emails.rb`](examples/manage_scheduled_emails.rb) — list, paginate, retrieve,
  reschedule and cancel
- [`schedule_batch.rb`](examples/schedule_batch.rb) — schedule a batch, then move or cancel it as
  a unit
- [`webhook_receiver_sinatra.rb`](examples/webhook_receiver_sinatra.rb) — verify and dispatch
  webhooks in Sinatra
- [`webhook_receiver_rails.rb`](examples/webhook_receiver_rails.rb) — the same in Rails, including
  `request.raw_post` and background dispatch

## Extending this SDK

Before adding a verb, a resource, a paginated listing or a webhook event, read
[`.rules/SDK_CONTRACT.md`](.rules/SDK_CONTRACT.md) (the decisions every mailkube SDK shares) and
[`.rules/SDK_DESIGN.md`](.rules/SDK_DESIGN.md) (how they are realized in Ruby). Both carry a
step-by-step checklist, and every checklist ends with adding a runnable example.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and the quality gates every change
must pass. Security issues: see [SECURITY.md](SECURITY.md).

## License

[Apache-2.0](LICENSE) © 2026 Mail Tactic Corporation
