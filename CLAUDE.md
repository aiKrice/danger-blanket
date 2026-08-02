# danger-blanket

## What this is

An open-source [Danger](https://danger.systems/ruby/) plugin for reporting code
coverage on pull requests, for **any platform, any coverage tool** — not tied
to one company or one language. This is a personal open-source project
(author's own time), so **never reference any employer or private codebase in
code, comments, docs, or commit messages.** The plugin was seeded from a
Dangerfile the author wrote at work, but the port must stand on its own with
no trace of where the idea came from.

## Vision / product requirements

- **Universal**: same plugin, same API, works for iOS and Android coverage
  reports (and, longer-term, anything else — JS/lcov, Python/coverage.py,
  JVM/Jacoco, etc.).
- **MVP parsers**: the two most popular per platform —
  **Kover** (Android/JVM, JaCoCo-XML-shaped) and **xcov** (iOS, JSON-shaped).
  More parsers can follow, but ship with just these two first.
- **Feature parity**: must be able to reproduce, through this plugin's
  options, everything the two reference Dangerfiles this was extracted from
  do — project-wide threshold, per-file threshold with overrides, warn-vs-fail
  severity, and clickable per-file deep links into a hosted HTML report.
  (One reference Dangerfile is Kover/Android-flavored, the other is
  xcov/iOS-flavored — same behavior, different report format.)
- **Friendly by default, powerful when needed**: a developer adopting this for
  the first time should get useful output from ~4 lines of Dangerfile config.
  Power users need an escape hatch for everything: custom parser objects
  (duck-typed, no subclassing required), per-file threshold overrides, a
  pluggable HTML-link resolver, warn vs. fail toggle, etc. Every "advanced"
  knob should be optional and defaulted sensibly — never required for the
  basic path.
- **Minimal dependencies, on purpose**: fewer transitive deps = smaller attack
  surface and faster CI installs. Currently the *only* runtime dependency is
  `danger` itself (see `danger-blanket.gemspec`). The Kover parser uses
  `rexml` (Ruby stdlib) instead of `nokogiri` deliberately. Think twice before
  adding any gem — prefer stdlib (`json`, `rexml`) over a new dependency.

## Ruby version constraint — read before writing any code

- **Must run on Ruby 3.5.** `danger-blanket.gemspec` currently declares
  `required_ruby_version = ">= 2.7"` — tighten this once the actual minimum is
  confirmed, but never write code that requires Ruby 4-only syntax/stdlib
  features.
- **Local environment only has Ruby 4.0.6 installed** (Homebrew `ruby` formula;
  the `ruby@3.4` opt-symlink on this machine is stale and resolves to the same
  4.0.6 Cellar entry, not an actual 3.4/3.5 install — don't trust
  `/opt/homebrew/opt/ruby@3.4/bin/ruby -v` at face value, verify with
  `readlink` if this matters again). There is no rbenv/rvm/asdf on this
  machine either.
- **Practical implication**: since there's no real Ruby 3.5 to test against
  locally, the only defense is *not writing Ruby 4-only syntax in the first
  place* — no pattern-matching features or stdlib APIs introduced after 3.5,
  nothing gated on `RUBY_VERSION >= "4"`. If a Ruby-version matrix in CI is set
  up later, that becomes the real safety net; until then, be conservative by
  hand.

## Architecture

```
lib/
  danger_blanket.rb        # requires blanket/gem_version (gem entrypoint)
  danger_plugin.rb          # requires blanket/plugin (Danger plugin entrypoint)
  blanket/
    gem_version.rb          # Blanket::VERSION
    report.rb                # Report / FileCoverage value structs (parser output contract)
    plugin.rb                 # Danger::DangerBlanket — the Plugin subclass Danger loads
    parsers/
      base.rb                 # Parsers::Base — documents the #parse/#html_link contract
      kover.rb                 # Android/JaCoCo-XML parser (rexml)
      xcov.rb                  # iOS/xcov JSON parser
      json.rb                  # generic pre-normalized JSON pass-through (bridge for unsupported tools)
```

- **`Parsers::Base#parse(report_file) -> Report`** is the whole contract.
  Duck-typing is enough — a custom parser doesn't need to subclass `Base`, it
  just needs `#parse` and (optionally) `#html_link`.
- **`Report`** (`project_coverage`, `files: Hash<path, FileCoverage>`) and
  **`FileCoverage`** (`coverage`, `meta`) are the normalized shape every parser
  must produce. `meta` is parser-private — it's whatever that parser's own
  `#html_link` needs later (e.g. Kover stashes `package`/`sourcefile` to walk
  its two-level HTML index; xcov stashes the file `name` to look up its
  per-run anchor).
- **`Danger::DangerBlanket`** (`plugin.rb`) is the only class Danger
  instantiates. It resolves `parser` (a `Symbol` in `PARSERS` or a
  duck-typed instance) with `resolve_parser`, then does exactly two things
  with the normalized `Report`: `check_project_threshold` and
  `check_file_thresholds`. It intersects the report's files with
  `git.modified_files + git.added_files` — only changed files get flagged, so
  legacy untested code doesn't block unrelated PRs (that's what
  `file_threshold_overrides` is *for*, for the intentional case).
- Every parser's `#html_link` may return `nil` — `plugin.rb` then falls back
  to a plain `github.html_link(file)`. Nothing breaks if hosted HTML reports
  aren't set up yet; deep links are a nice-to-have layered on top.

## Testing

- `bundle exec rspec` — 37 examples currently, all green under local Ruby
  4.0.6. `spec/blanket_spec.rb` covers the plugin's orchestration logic end to
  end via a stubbed `Dangerfile`/`git`; `spec/parsers/*_spec.rb` cover each
  parser against fixture reports in `spec/fixtures/`.
- `.rspec` sets `--format documentation --color` — keep it that way, the
  spec descriptions are meant to double as living documentation of behavior.
- No CI config yet (no `.github/workflows`, no `.travis.yml` equivalent) —
  this is still local-only, pre-publish.

## Current status (as of this session)

Local testing of the plugin. Branch renamed `main` → `master` (no commits yet
— everything is currently untracked working tree). Homepage in the gemspec:
`https://github.com/christophersaez/danger-blanket`, MIT licensed.

## Open items / things to watch

- Confirm and tighten `required_ruby_version` in the gemspec once the Ruby
  3.5 floor is verified for real (not just by inspection).
- No `.rubocop.yml` / linter config yet — decide if one gets added before
  first publish.
- No README yet.
