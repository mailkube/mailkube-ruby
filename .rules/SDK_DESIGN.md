# SDK Design: the Ruby realization of the cross-SDK contract

Load this alongside [`SDK_CONTRACT.md`](SDK_CONTRACT.md) when adding a **resource, verb, response
model, paginated listing, or webhook event**.

`SDK_CONTRACT.md` is the shared, language-neutral constitution: configuration, layering, naming,
response-model rules, pagination, the error model, and the webhook contract, all of which every
mailkube SDK implements identically. It is synced from `repo-template/common/` and must not be
edited here.

**This file covers only what is specific to Ruby.** A deliberate deviation from the contract
belongs here, never in the shared file.

## The layers, in files

| Layer | Files | May know about |
|---|---|---|
| **Client / IO** | `net_http_adapter.rb` | `net/http`, `openssl`, `uri` |
| **Core** | `client.rb`, `config.rb`, `transport.rb` | the adapter contract, `json` |
| **Resources** | `resources/*.rb` | an object responding to the verb it calls |
| **Types** | `types.rb`, `errors.rb` | nothing |

`client.rb` is the composition root: it resolves config, wires the collaborators and exposes the
resources. It performs no I/O itself.

**Only `net_http_adapter.rb` requires `net/http`.** A resource or model that does is a bug.

## One client, and it is synchronous

This is the contract's **sync-only** case, and specifically its first clause: concurrency here is
the caller's concern rather than an API-surface decision.

Ruby has no async/await colouring. The same `client.emails.send` call is correct on a plain thread,
inside a `Fiber` with a scheduler installed, and inside an `async` block, because Ruby releases the
GVL around socket I/O and the scheduler hooks `Net::HTTP` at the same place. A second `AsyncClient`
would therefore duplicate every verb to deliver nothing the caller cannot already have.

What is unconditionally true is **threads**: they give real HTTP concurrency with no setup at all.
Fibers are the second story, not the first, because Ruby ships the `Fiber::Scheduler` *interface*
and no implementation: `Fiber.schedule` raises until the application installs one (`async` or
similar). Nothing in this gem depends on a scheduler being present, and nothing here promises that
every part of a request is scheduler-transparent: `getaddrinfo(3)` cannot be made non-blocking, and
`ruby/openssl` has a documented history of friction under fiber schedulers. Both are the installed
scheduler's business, not this gem's.

The deadline handle is per-request `open_timeout` / `read_timeout`, set from `Client.new(timeout:)`.

## Concurrency safety is proven, not asserted

`Client`, `Config`, `Transport`, `Resources::Emails` and `NetHttpAdapter` are all **frozen** at the
end of `initialize`. Nothing mutable survives construction, which turns a whole class of future
regression into a `FrozenError` at the moment someone introduces it.

**`spec/concurrency_spec.rb` proves it**, and it is worth understanding why it is shaped the way it
is before changing it:

- **It speaks over a real `TCPServer`.** WebMock replaces `Net::HTTP#request` and never opens a
  socket, so it can say nothing about what happens when several callers share one. The connection is
  the thing under test.
- **The server holds every request until all of them have arrived.** That proves the calls genuinely
  overlap (a client that serialized them would never fill the barrier, and the spec fails on the
  timeout rather than quietly passing on a client it never stressed), and releasing everyone at once
  makes them contend.
- **It asserts identity, not the absence of an exception.** Each request carries a distinct
  `Idempotency-Key`, the server echoes it back as the response `id`, and every caller must receive
  its own. Response cross-talk does not raise; it silently hands one caller another's body.

**The spec was proven to fail, twice, by breaking the client on purpose.** Giving `Transport` a
shared `@last` response slot (and dropping its `freeze`) produced exactly the failure the assertion
is written for: `idem-000 received the response for "idem-030"`. Sharing one started `Net::HTTP`
session across callers failed differently, with `IOError: stream closed in another thread`, because
`Net::HTTP` is not merely unsafe to share, it tears down its own socket state. Both are red; only
the first is the silent-in-production case, which is why the assertion is written the way it is.

The stub server speaks **keep-alive** for the same reason. A server that closed after one request
would turn a shared connection into an `IOError` instead of a mismatched id, which is a red test
for the wrong reason and would stop catching a *pooled* adapter with a race, the realistic version
of this bug.

`NetHttpAdapter` opens a fresh connection per request (`Net::HTTP.start` opens, yields, closes)
precisely because a shared `Net::HTTP` instance is how that cross-talk happens. **Connection pooling
is deliberately left to whoever needs it**, with the reason stated: a correct pool has to be safe
under threads *and* under a fiber scheduler, which is more than a scaffold should assume on a
caller's behalf. Inject an adapter through `Client.new(http:)` if you want one.

## Both seams, and why there are two

- **Public**: `Client.new(http:)` accepts anything responding to
  `#call(method:, url:, headers:, body:)`. This is the contract's "injectable through the
  constructor" requirement, and it is what the suite drives.
- **Internal**: a resource holds an object responding to the one verb it calls (`#send_email`).
  A new capability adds a method to `Transport`; it never widens an existing one.

WebMock alone would not satisfy the first: it is a global monkey-patch, not a seam a caller can pass
in, and a gem whose only test strategy is patching someone else's method has no injection point.

## Ruby idioms that realize the contract

- **Keyword arguments replace the other SDKs' parameter objects.** `emails.send` takes one keyword
  per API field, so a call is fully readable and typo-checked at the call site.
- **`Emails#send` deliberately shadows `Object#send` on that object.** Every mailkube SDK spells the
  verb `emails.send`, and a Ruby-only name would break that parity for a method almost nobody calls
  reflectively on a resource. `__send__` is unaffected.
- **The request body is one hash literal followed by `compact`**, never a chain of
  `body["x"] = x if x`. That keeps cyclomatic complexity at 1 as fields are added, and is why an
  unset field is absent from the wire rather than sent as null.
- **Models are `class X < Data.define(...)`**, frozen and value-comparable, ignoring unknown keys, so
  a server-side field addition can never break a released client.
- **`[bytes].pack("m0")` rather than `Base64.strict_encode64`.** `base64` became a bundled gem in
  Ruby 3.4, so requiring it without declaring it fails under Bundler, and declaring it would cost
  this gem its zero-dependency claim.
- **The version lives in `lib/mailkube/version.rb`** and the gemspec *reads* it. That is Ruby's
  own idiom and it satisfies the contract's rule as written: one source of truth, and the User-Agent
  reads that source. There is no second copy for release tooling to bump independently.

## Two tool frictions, and how they are settled

1. **Steep and `Data.define`.** Steep attributes the methods in a `Data.define(...) do ... end`
   block to the enclosing *module* rather than to the constant, and then cannot resolve the
   generated readers from inside them. Writing the models as `class X < Data.define(...)` gives it a
   real class body and type-checks cleanly. The generated readers are declared as `attr_reader` in
   `sig/`, and `Ruby::MethodDefinitionMissing` stays **off** in the `Steepfile` because Steep cannot
   see their implementations and would report every one as missing. Verified against Steep 2.0.0.
2. **RuboCop metrics versus the contract's shapes.** `Metrics/ParameterLists` counts keyword
   arguments by default, which fails the exact signature the contract asks for, so
   `CountKeywordArgs: false`. `Metrics/MethodLength` and `AbcSize` are raised for the flat body
   literal. `Metrics/CyclomaticComplexity` and `PerceivedComplexity` are *stated at 10* rather than
   inherited, because RuboCop's default of 7 is stricter than the house limit and would silently make
   Ruby the odd SDK out. Every relaxation carries its reason in `.rubocop.yml`; add yours the same
   way or not at all.

## Where the shared rules are enforced

| Contract rule | Enforced in |
|---|---|
| Key/base-URL resolution, default headers | `Config#initialize`, `Config#default_headers` |
| Origin guard and URL joining | `Config#build_url` |
| One place maps non-2xx to an exception | `Transport#perform` calling `#error_for` |
| Status-to-class table | `STATUS_ERRORS` / `.error_class_for` in `errors.rb` |
| Idempotency key lifted to a header | `Resources::Emails#send` |
| ISO-8601 rendering, base64 attachments, query values, path escaping | `Serialization` |
| Query-string assembly | `Config#build_url`, from `RequestSpec#params` |
| Opt-in logging and header redaction | `Logging`, called from `Transport#perform` |
| One version source, read by the User-Agent | `version.rb`, read by the gemspec and `Config#default_headers` |
| HTTP adapter injection | `Client.new(http:)` |
| Webhook signature verification | `webhooks.rb` (no client instance needed) |
| Concurrency safety, proven not asserted | `spec/concurrency_spec.rb` |

## Tests

The DI seam is the test seam: `spec/spec_helper.rb` builds clients over a `StubAdapter`, so the
suite makes zero network calls and still exercises the real config resolution, request building,
error mapping and response parsing. `concurrency_spec.rb` is the one exception, and it brings its
own server.

Coverage gates **line and branch at 90%**. `enable_coverage :branch` must stay in `spec_helper.rb`:
without it, `minimum_coverage branch:` silently gates nothing, which is how a repo ends up believing
it has a branch gate that it does not.

## Deliberate deviations from the contract, and why

Three, each a Ruby-specific answer to a rule the contract states language-neutrally.

### 1. Event models are not `Data.define`

Every other model here is `class X < Data.define(...)`, which ignores unknown keys. The contract
**inverts** that rule for inbound events: unknown fields must be *preserved*, at every depth, so a
receiver that logs or forwards an event keeps fields this release predates. A `Data` has fixed
members and drops them, with no way to opt out.

So `Events::Node` stores the decoded hash and each subclass declares one-line readers over it.
Nothing is copied, so nothing can be lost, and `#to_h` round-trips to exactly what the server sent.
Readers are written out as plain `def`s rather than generated by a macro, because Steep's
`UndeclaredMethodDefinition` gate reads what is in `lib/` and a generated reader is a method no
signature can be matched against. In `sig/` they are declared as `def`, not `attr_reader` —
`attr_reader` stays reserved for the readers `Data.define` actually generates.

### 2. `Tag` is what you construct; a hash is what you read

`Mailkube::Tag` is the send-side type. Inbound, tags stay plain hashes: building a `Tag` from a
webhook payload would silently drop an unknown key *inside* a tag, three levels down, where nothing
on the send side would notice. A second inbound tag class would preserve the keys but cost the SDK
family its one-tag-type story. A hash costs neither, and matches every other SDK.

### 3. Logging is a duck-typed sink, not a stdlib `Logger`

`logger` stopped being a default gem in Ruby 4.0, so `require "logger"` in `lib/` raises under
Bundler on a Ruby this gem supports, and declaring it would cost the zero-dependency claim. The
sink is therefore anything responding to `#write(String)` — which is also the better answer for a
host application that already has a logger.

**The general rule this is an instance of: before requiring any stdlib from `lib/`, confirm it is a
default gem on the *newest* supported Ruby, not just on the floor.** `base64`, `logger`, `ostruct`
and `cgi` are all traps here; `uri`, `time`, `openssl`, `json`, `net/http` and `erb` are safe.
