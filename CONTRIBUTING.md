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

**Run the gates on Ruby 3.4, the supported floor.** The pinned tooling is not guaranteed to build
against a newer Ruby: `steep 2.0.0` resolves `strscan 3.1.8`, whose C extension does not compile
against Ruby 4.0 headers. That is why CI runs the full gate set on 3.4 and only the specs on 4.0.

## Quality gates

Every change must pass the same checks CI runs (see [.rules/SOLID_DRY_KISS.md](.rules/SOLID_DRY_KISS.md)):

```bash
bundle exec rubocop                            # complexity (KISS) + docs + style
bundle exec rake rbs                          # the signatures are coherent (rbs validate)
bundle exec steep check                        # the implementation matches them
bundle exec rspec                              # specs + the 90% line/branch coverage gate
npx --yes jscpd@4 --config .jscpd.json .       # duplication (DRY) gate, blocks at > 1%
./scripts/check-rule-index.sh                  # every .rules/*.md indexed in AGENTS.md
```

`bundle exec rake` runs the first four in order. `pre-commit run --all-files` runs the lint/type/jscpd
hooks in one shot.

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
