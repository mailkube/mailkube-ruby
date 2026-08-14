# Project Rules

`mailkube-ruby` is a public (Apache-2.0) mailkube SDK distributed as the
`mailkube` gem on rubygems.org. Load the relevant rule file from `.rules/` based on the task.

## Rule Index

> **Index every rule (required).** Every file in `.rules/` MUST have a row in the table below. When you
> add or rename a `.rules/` file, add or update its row in the **same change** — an unindexed rule is
> invisible, because this index is what drives progressive disclosure. The `docs` CI job (`scripts/check-rule-index.sh`)
> fails the build if `.rules/` and this index drift. This convention holds for every mailkube repo.

| Rule File | Load When |
|---|---|
| `.rules/SOLID_DRY_KISS.md` | Writing or changing any code — the enforced engineering standards (SOLID, DRY, KISS, coverage, docs) and how to run each gate locally. |
| `.rules/SDK_CONTRACT.md` | Adding a resource, verb, response model, paginated listing, or webhook event: the cross-SDK decisions (config, layering, naming, errors, pagination, webhooks) every mailkube SDK implements identically. Shared verbatim across every SDK; edit it in `repo-template/common/`. |
| `.rules/SDK_DESIGN.md` | The same tasks, for the **Ruby realization**: the layer-to-file map, the adapter injection seam, the sync-only decision, and how Steep and RuboCop are settled. |
| `.rules/RELEASE.md` | Touching `release.yml`, `.releaserc.json`, `version.rb`, or the RubyGems publish flow. |

## Key Conventions (always apply)

- **Standard gem layout** — the library lives in `lib/mailkube/`, its signatures in `sig/`, its specs in `spec/`.
- **RuboCop** for lint and style; **RBS + Steep** for types; **RSpec** for specs. All pinned exactly.
- **Line length ≤ 120**.
- **Document every class and module** (`Style/Documentation`), and every public method with YARD tags.
- **≥ 90% coverage, line + branch** — enforced by SimpleCov in `spec/spec_helper.rb`; never lower the gate to make a change pass.
- **Max cyclomatic / perceived complexity 10** — split, don't waive.
- **No duplication** — the `jscpd` gate blocks at > 1% duplicated code; extract shared logic.
- **Zero runtime dependencies.** This gem is installed into other people's applications; everything it needs is stdlib. Check stdlib before adding one.
- **The version is never written twice** — `version.rb` holds it, the gemspec reads it, the User-Agent reads it.
- **Depend on the narrowest thing** — a resource holds an object responding to the one verb it calls; the HTTP adapter is injected, never constructed inside a resource.
- **Conventional Commits** for PR titles (squash-merged); only `feat:`/`fix:`/`perf:` cut a release.
- **No secrets in the repo** — local config lives in a git-ignored `.env`, excluded from the built gem.
- **Keep the `README` current** with user-visible changes. There is no `CHANGELOG.md`; the release
  notes on the GitHub Releases page are the changelog (see `.rules/RELEASE.md`).
