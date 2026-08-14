# Engineering Standards: SOLID · DRY · KISS · Coverage · Docs

These are **enforced by CI** — a PR that violates them cannot merge. This file tells you the exact
thresholds and how to satisfy each gate locally *before* pushing.

## The gates

| Gate | Rule | Enforced by |
|---|---|---|
| **Coverage** | ≥ 90% **line and branch** | SimpleCov `minimum_coverage` in `spec/spec_helper.rb` (the `test` CI job) |
| **DRY** | ≤ 1% duplicated code | `jscpd` (the `dry` CI job) |
| **KISS** | cyclomatic ≤ 10, perceived ≤ 10 per method | RuboCop `Metrics/*` (the `test` CI job) |
| **Documentation** | every class and module documented | RuboCop `Style/Documentation` (the `test` CI job) |
| **Typing** | signatures coherent **and** matched by the code | `rbs validate` **plus** `steep check` (the `test` CI job) |
| **SOLID** | see below — approximated by lint + review | RuboCop + PR checklist |
| **Formatting** | RuboCop-clean | `bundle exec rubocop` (the `test` CI job) |

> **Both halves of the type gate are required.** `rbs validate` never loads `lib/`: it proves the
> signatures are internally coherent and would happily pass a `sig/` describing methods that do not
> exist. `steep check` is what compares the two. Running only the first is the failure mode this
> repo exists to avoid, not a shortcut.

## Run the gates locally

```bash
bundle exec rubocop                            # complexity (KISS), docs, style
bundle exec rake rbs                          # the signatures are coherent (rbs validate)
bundle exec steep check                        # the implementation matches them
bundle exec rspec                              # specs + the 90% line/branch coverage gate
npx --yes jscpd@4 --config .jscpd.json .       # duplication (DRY) gate
./scripts/check-rule-index.sh                  # every .rules/*.md indexed in AGENTS.md
```

`bundle exec rake` runs the first four in order. `pre-commit run --all-files` runs the RuboCop +
Steep + jscpd + commitlint hooks in one shot.

**Run the gates on Ruby 3.4, the supported floor.** The tooling is pinned exactly and is not
guaranteed to build against a newer Ruby; a gate that will not build on a newer one is a property of
your machine rather than of this repo. CI therefore runs the full gate set on 3.4 and only the specs
on 4.0, which is also what proves the gem itself works on both. See
[CONTRIBUTING.md](../CONTRIBUTING.md) before blaming a failed C-extension build on the Ruby version.

## SOLID, concretely (paradigm-neutral guidance)

SOLID is not a single lint rule; keep these in mind and confirm them in the PR checklist:

- **S**ingle responsibility — a method/class does one thing; if you need "and" to describe it, split it.
- **O**pen/closed — extend by adding a class or a method, not by editing a stable call site.
- **L**iskov — an injected collaborator honours the documented contract (return shape, raised errors).
- **I**nterface segregation — depend on the narrowest thing you need. In Ruby that means a resource
  depends on an object responding to the one verb it calls, not on the whole transport.
- **D**ependency inversion — the HTTP adapter is injected through `Client.new(http:)`, never
  constructed inside a resource. That is also why the suite runs without network access.

## Requesting a waiver

If a threshold is genuinely wrong for a specific line, add a **scoped, commented** disable
(e.g. `# rubocop:disable Metrics/AbcSize -- flat dispatch table, no branches`) and call it out in
the PR. Blanket config relaxations (lowering the coverage floor, disabling a cop globally) require
maintainer sign-off. The relaxations already in `.rubocop.yml` each carry their reason; add yours
the same way or not at all.
