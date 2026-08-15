# Contributing to mailkube-ruby

Thanks for helping improve **mailkube-ruby**, a [mailkube](https://mailkube.com) SDK.
Contributions of all kinds are welcome: bug reports, fixes, docs, and features.

By contributing you agree that your contributions are licensed under the project's
[Apache License 2.0](LICENSE) (inbound = outbound). **No CLA and no sign-off are required.**
Please also read our [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

Requires [Ruby](https://www.ruby-lang.org/) 3.4+ and Node.js (for the `jscpd`
duplication check).

```bash
git clone https://github.com/mailkube/mailkube-ruby
cd mailkube-ruby

bundle install
pre-commit install                            # rubocop + steep + jscpd hooks
pre-commit install --hook-type commit-msg     # Conventional Commits hook
```

**Run the gates on Ruby 3.4, the supported floor.** The tooling is pinned exactly and is not
guaranteed to build against a newer Ruby, so a gate failing on a newer one is a property of your
machine rather than of this repo. That split is why CI runs the full gate set on 3.4 and only the
specs on 4.0 — the second job tests the *library* on the newest Ruby, which is a different claim
from "the pinned tooling works there".

If a gem's C extension will not build at all, check your compiler's target before anything else:
`ruby -rrbconfig -e 'p RbConfig::CONFIG["ARCH_FLAG"]'` against `cc -dumpmachine`. An x86_64 Ruby
with an empty `ARCH_FLAG` on an arm64 machine lets clang default to the wrong architecture, every
`mkmf` `have_func` probe then fails to *link* rather than to compile, and the extension falls back
to redeclaring functions the headers already declare. It surfaces as `static declaration of
'<something>' follows non-static declaration`, which reads like a Ruby-version incompatibility and
is not one.

## Quality gates

Every change must pass the same checks CI runs (see [.rules/SOLID_DRY_KISS.md](.rules/SOLID_DRY_KISS.md)):

```bash
bundle exec rubocop                            # complexity (KISS) + docs + style
bundle exec rake rbs                          # the signatures are coherent (rbs validate)
bundle exec steep check                        # the implementation matches them
bundle exec rspec                              # specs + the 90% line/branch coverage gate
npx --yes jscpd@4 --config .jscpd.json .       # duplication (DRY) gate, blocks at > 1%
npx --yes jscpd@4 --config .jscpd.examples.json examples/   # the same gate over examples/
for f in examples/*.rb; do ruby -c "$f" || exit 1; done     # every example parses
./scripts/check-rule-index.sh                  # every .rules/*.md indexed in AGENTS.md
```

`bundle exec rake` runs the first four in order. `pre-commit run --all-files` runs the lint/type/jscpd
hooks in one shot.

**`examples/` is in scope for RuboCop.** It is runnable documentation, which is the reason, not an
exception to it: customers copy those files. They are held to the same style and complexity limits
as `lib/`, must parse (`ruby -c`, CI's `examples` job), and are checked for duplication by
`.jscpd.examples.json` — a separate pass at `minTokens: 100` rather than the main run's 50, because
every example legitimately repeats the same scaffolding (require, read `MAILKUBE_FROM`, construct
the client) and extracting that into a shared helper would defeat the point of a file you can read
top to bottom. Examples stay out of **coverage**: nothing in CI executes them.

**Both halves of the type gate are required.** `rbs validate` never loads `lib/`, so it cannot tell
you the signatures match the code; `steep check` is what does. Running only the first is how a `sig/`
directory quietly stops describing reality.

## Commit & PR conventions

This project follows **[Conventional Commits](https://www.conventionalcommits.org/)**. A CI check
enforces the **PR title** (PRs are **squash-merged** using it), and it drives releases: only
`feat:`, `fix:`, and `perf:` cut a new version. See [.rules/RELEASE.md](.rules/RELEASE.md).

Suggested scopes: `client`, `models`, `ci`, `deps`, `docs`.

```
feat(client): add retry with exponential backoff
fix(models): correct optional field serialization
docs: document the pagination helper
```

## Reporting bugs / requesting features

Open an issue using the templates. For **security vulnerabilities**, do not open a public
issue — follow [SECURITY.md](SECURITY.md) instead.
