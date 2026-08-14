# Release & Publishing

Load this when touching `release.yml`, `.releaserc.json`, `version.rb`, or the RubyGems publish flow.

## The contract

1. **Conventional Commits drive the version.** On push to `main`, `semantic-release` reads the commit
   history since the last tag: `fix:` → patch, `feat:` → minor, `feat!:`/`BREAKING CHANGE:` → major.
   `perf:` also releases. Anything else (`chore`, `docs`, `ci`, `refactor`, `test`) does **not** release.
2. **It creates the tag `vX.Y.Z` and the GitHub Release, and commits nothing.** No `chore(release):`
   commit, no `CHANGELOG.md`, no version bump landed in the tree. See "Why nothing is committed back
   to `main`".
3. **The tag IS the version.** `@semantic-release/exec`'s `prepareCmd` rewrites
   `lib/mailkube/version.rb` **in the release runner's working copy**, immediately before the gem is
   built, and that edit is never committed. The gemspec reads `Mailkube::VERSION`, so the built
   gem carries the released version by construction.
   The value committed to this repo is a permanent `0.0.0` placeholder. A checkout therefore reports
   `0.0.0` and an installed gem reports the real version: **that is intended.** Do not "fix" it by
   hardcoding a number, and do not add a second constant.
4. **`publishCmd` builds and pushes the gem, over OIDC trusted publishing.**
   `rubygems/configure-rubygems-credentials` exchanges the job's `id-token` for a short-lived
   RubyGems credential, then `gem build` + `gem push` run from `.releaserc.json`. **No long-lived API
   key is stored in this repo.**

## Why nothing is committed back to `main`

`main` is covered by a ruleset requiring a pull request and the gated checks. A `chore(release):`
commit pushed straight to `main` by the workflow violates it, and the obvious fix does not exist:
**`github-actions[bot]` cannot be added to a ruleset bypass list.** Bypass is available to admins,
the maintain/write role, teams, GitHub Apps and Dependabot, and the built-in Actions identity is none
of those. Making the commit work would mean introducing a separate identity — a GitHub App or a
deploy key — purely to write a version number that the tag already carries.

So `.releaserc.json` loads neither `@semantic-release/git` nor `@semantic-release/changelog`. It
keeps `@semantic-release/exec`, which is a different thing: `prepareCmd` edits the runner's working
copy and never touches git. **The generated release notes are the changelog**; there is no
`CHANGELOG.md` in this repo, which is why `changelog_uri` in the gemspec points at the Releases page.

Two consequences worth knowing before you rearrange this workflow:

- **`rubygems/release-gem` cannot be used here, and that is not a preference.** That action runs
  `bundle exec rake release`, which aborts on a dirty working tree and then creates and pushes its
  own `vX.Y.Z` tag. Here the tree is dirty on purpose (the uncommitted `version.rb`) and the tag
  already exists. The workflow therefore performs the action's OIDC credential exchange itself and
  leaves the build and push to `publishCmd`.
- **The push lives in `publishCmd`, not in a following workflow step, on purpose.** A step after
  `semantic-release` runs on *every* push to `main`, including the ones that release nothing — and
  it would then build and push the `0.0.0` placeholder. `publishCmd` runs only when a release is
  actually cut.

## Required GitHub setup (one-time, per repo)

- GitHub **environment** `release` should exist (Settings → Environments) with protection rules; the
  `release` job runs in it.
- On rubygems.org: register this repository as a **trusted publisher** for the
  `mailkube` gem (RubyGems → the gem → Trusted publishers), naming the org, the repo, the
  `release.yml` workflow, and the `release` environment.
- **A gem that does not exist yet is not a special case.** RubyGems.org supports **pending**
  trusted publishers: register one under your *profile* (rather than under a gem), naming the gem
  name you intend to claim. It reserves the name, and converts to a normal trusted publisher — with
  you as owner — on its first successful push. So the very first release goes out over OIDC like
  every other one, and there is never a hand-rolled `gem push`.

  This matters beyond convenience. Hand-publishing creates no git tag, and `tagFormat` is
  `v${version}`; with no matching tag `semantic-release` computes `FIRST_RELEASE = 1.0.0` on the
  next push regardless of history, pushes that tag, then fails at `gem push` because the version
  already exists — aborting before `@semantic-release/github` writes the release notes. Since the
  Releases page *is* this repo's changelog, that loses the entry permanently.

  If you ever do publish by hand anyway, create and push the matching tag and Release in the same
  sitting: `git tag -a vX.Y.Z -m vX.Y.Z <sha> && git push origin vX.Y.Z && gh release create vX.Y.Z
  --generate-notes`.
- `rubygems_mfa_required` is set in the gemspec metadata. Keep it.

## Do not

- Do not bump `VERSION` by hand or commit a rewritten `version.rb`, and do not add a `CHANGELOG.md`,
  `@semantic-release/git` or `@semantic-release/changelog`. All of those reintroduce the commit to
  `main` that this setup exists to avoid.
- Do not move the `gem push` out of `publishCmd` into a workflow step — see above.
- Do not add a `Gemfile.lock` to the repo. A gem's lockfile pins its *consumers'* resolution
  problem, not its own; `.gitignore` already excludes it.
- Do not add a RubyGems API key as a repository secret. If OIDC is failing, fix the trusted-publisher
  registration rather than reaching for a key.
- Do not gate `release.yml` on anything weaker than the full `ci.yml` (`test` + `dry` + `docs`).
