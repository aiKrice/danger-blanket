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
  **Kover** (Android/JVM, JaCoCo-XML-shaped) and **xccov** (iOS, Apple's own
  `xcrun xccov`/`xcresulttool`, read straight from an `.xcresult` bundle —
  not the third-party `xcov` gem, which turned out to be broken against
  modern Xcode projects, see "Real-world validation" below). More parsers
  can follow, but ship with just these two first.
- **Feature parity**: must be able to reproduce, through this plugin's
  options, everything the two reference Dangerfiles this was extracted from
  do — project-wide threshold, per-file threshold with overrides, warn-vs-fail
  severity, and clickable per-file deep links into a hosted HTML report.
  (One reference Dangerfile is Kover/Android-flavored, the other is
  xccov/iOS-flavored — same behavior, different report format.) The two
  reference Dangerfiles originally linked into two *different-looking*
  per-tool HTML reports (Kover's own Gradle-generated HTML, a bespoke
  xccov-fed static site); danger-blanket instead owns **one shared HTML
  report renderer** (`Blanket::HtmlReport`) that both parsers — and any
  future one — feed through, so every platform gets the same browsable,
  line-by-line report, not a per-tool lookalike.
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
  `rexml` (Ruby stdlib) instead of `nokogiri` deliberately; the Xccov parser
  shells out to `xcrun` via `Open3` and parses its JSON with stdlib `json`
  directly (no `jq` dependency, unlike the bash pipeline it replaces). Think
  twice before adding any gem — prefer stdlib over a new dependency.

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
    report.rb                # Report / FileCoverage / LineCoverage / FunctionCoverage / Span value structs (parser output contract)
    html_report.rb            # Blanket::HtmlReport — shared SPA renderer, any parser with line-level detail can feed it
    html_report/
      assets/                  # bundled SPA shell: index.html, assets/{style.css,app.js,i18n.js,favicon.svg}
    plugin.rb                 # Danger::DangerBlanket — the Plugin subclass Danger loads
    parsers/
      base.rb                 # Parsers::Base — documents the #parse/#html_link contract
      kover.rb                 # Android/JaCoCo-XML parser (rexml) — line- and method-level detail from <line>/<class><method>
      xccov.rb                  # iOS parser — shells to `xcrun xccov`/`xcresulttool` against an .xcresult bundle
      json.rb                  # generic pre-normalized JSON pass-through (bridge for unsupported tools)
```

- **`Parsers::Base#parse(report_file) -> Report`** is the whole contract.
  Duck-typing is enough — a custom parser doesn't need to subclass `Base`, it
  just needs `#parse` and (optionally) `#html_link`.
- **`Report`** (`project_coverage`, `covered_lines`, `executable_lines`,
  `files: Hash<path, FileCoverage>`) and **`FileCoverage`** (`coverage`,
  `covered_lines`, `executable_lines`, `first_uncovered_line`, `lines`,
  `functions`, `meta`) are the normalized shape every parser must produce.
  Only `coverage`/`meta` are required — `lines`/`functions`/the raw line
  counts are additive and optional, but populating them (as Kover and Xccov
  both do) is what unlocks {Danger::Blanket::HtmlReport} for that parser.
  `meta` is parser-private, for a custom parser's own `#html_link`.
- **`Danger::DangerBlanket`** (`plugin.rb`) is the only class Danger
  instantiates. It resolves `parser` (a `Symbol` in `PARSERS` or a
  duck-typed instance), then does three things with the normalized `Report`:
  optionally renders it via `Blanket::HtmlReport.generate` (when
  `html_report_dir` is set), `check_project_threshold`, and
  `check_file_thresholds`. It intersects the report's files with
  `git.modified_files + git.added_files` — only changed files get flagged, so
  legacy untested code doesn't block unrelated PRs (that's what
  `file_threshold_overrides` is *for*, for the intentional case).
- Per-file link resolution is a three-tier fallback: (1) if `html_report_dir`
  was just generated and `hosted_report_base_url` is set, the link is
  deterministic — `Blanket::HtmlReport.link_for` builds it straight from the
  file path (no scraping, since this module owns both the generator and the
  addressing scheme); (2) otherwise the parser's own `#html_link` gets a
  chance (for a report generated some other way — may return `nil`); (3)
  falls back to a plain `scm_html_link` (github/gitlab/bitbucket, or a bare
  file path if no host plugin is registered, eg. under `dry_run`). Nothing
  breaks if hosted HTML reports aren't set up at all; deep links are a
  nice-to-have layered on top.
- **`Blanket::HtmlReport.generate(report, output_dir, changed_files:, title:, favicon:, logo:)`**
  is the shared renderer: writes `report.json` + copies the bundled SPA shell
  + writes one `files/<path>.html` fragment per file that has `.lines`
  populated (a per-function breakdown table + a line-by-line source table,
  covered/uncovered/partial/skipped, with xccov's sub-line `Span`s rendered
  as nested highlights). Adding a new platform/tool later means writing a
  parser that populates `FileCoverage#lines`/`#functions` — this renderer
  doesn't change. `favicon:`/`logo:` (also exposed as `blanket.html_report_favicon`/
  `blanket.html_report_logo` on the plugin) are independent optional local
  file paths — favicon is the browser-tab icon, logo is the top-bar image
  shown inside the report; either, both, or neither can be overridden, each
  defaulting to the bundled `assets/favicon.svg` otherwise. The custom file
  is copied into the output's `assets/` under its own basename; MIME type
  for the `<link rel="icon">` is derived from the extension
  (`HtmlReport::MIME_TYPES`).
- **Sidebar is a folder tree, not a flat list** — built client-side in
  `app.js` (`buildTree`/`finalizeTree`) from `report.json`'s flat file
  array; `report.json`'s schema itself never changed for this. Folders sort
  alphabetically, files within a folder sort worst-coverage-first; each
  folder shows a rolled-up `coveredLines`/`executableLines` badge computed
  once over *all* files (filters only ever hide nodes at render time via
  `prune()`, never recompute a badge). The "Changed in this PR" filter
  defaults to **checked** whenever the report has any changed file — a
  link from a PR comment should land on "what did I touch", not the whole
  tree.
- **i18n**: `assets/i18n.js` (loaded before `app.js`) exposes
  `window.BlanketI18n` — a small dictionary (`en`/`fr`/`es`/`de`/`ru`/`zh`)
  keyed by UI string, `t(key, params)`/`tPlural(key, count, params)` for
  interpolation (`Intl.PluralRules`-driven, so Russian's one/few/many and
  Chinese's no-plural-at-all both come out right), and
  `applyTranslations(root)`. Locale is auto-detected from
  `navigator.languages` — no manual switcher (not asked for). The subtlety:
  per-file fragments are pre-rendered **once, in English, server-side** by
  `Blanket::HtmlReport` (see above) and then just fetched/injected as
  static HTML — so `html_report.rb` emits `data-i18n*` markers (with the
  English text as the pre-JS fallback) instead of baking text in, and
  `app.js` calls `applyTranslations` both on the static shell at load *and*
  again on `content` every time a fragment is injected in `loadFile()`.
  This is what makes one generated report read correctly for any viewer's
  browser locale, not just whoever's CI generated it.

## Testing

- `bundle exec rspec` — 58 examples currently, all green under local Ruby
  4.0.6. `spec/blanket_spec.rb` covers the plugin's orchestration logic end to
  end via a stubbed `Dangerfile`/`git`; `spec/parsers/*_spec.rb` cover each
  parser against fixture reports in `spec/fixtures/`; `spec/html_report_spec.rb`
  covers the shared renderer directly (using `smoke_test/src/**` as real
  on-disk source to render fragments against). `spec/parsers/xccov_spec.rb`
  never shells out to `xcrun` — it injects a fake `XcrunRunner` (see
  `Parsers::Xccov::XcrunRunner`) with canned JSON, so the suite runs without
  Xcode installed.
- `.rspec` sets `--format documentation --color` — keep it that way, the
  spec descriptions are meant to double as living documentation of behavior.
- No CI config yet (no `.github/workflows`, no `.travis.yml` equivalent) —
  this is still local-only, pre-publish.

### End-to-end smoke test via `danger dry_run` (no push, no PR needed)

`smoke_test/` + the root `Dangerfile` are a minimal fixture project used to
exercise the plugin exactly as Danger would on a real PR, entirely offline:

```
bundle exec danger dry_run --base=<commit before the change> --head=<commit with the change>
```

Notes specific to this repo/plugin:

- Danger's local-only diffing (`LocalOnlyGitRepo`) compares **committed**
  refs (`merge_base..HEAD`), not working-tree edits — `--base`/`--head` (or
  the defaults `origin/master`/`HEAD`) must both resolve to real commits, so
  there always has to be at least one commit to diff against.
- `danger dry_run` (and `danger local`) never call `refresh_plugins` on the
  `Dangerfile` (`env_manager.pr?` is false for `LocalOnlyGitRepo`), so host
  plugins (`github`, `gitlab`, `bitbucket_server`, `bitbucket_cloud`) are
  **not defined at all** in this mode — calling `github.html_link` directly
  raises `NoMethodError`. This is why `plugin.rb`'s fallback link goes
  through `scm_html_link`, which probes `@dangerfile.respond_to?(...)` for
  each known host plugin and falls back to a plain file path if none is
  registered, instead of assuming GitHub is always present.
- Get the `--base`/`--head` order right: it's `<commit BEFORE the change>`
  then `<commit WITH the change>` — swapping them (or picking a `--base`
  that's actually a *descendant* of `--head`) silently yields an empty (or
  wrong) `git.modified_files`/`added_files`, so every diff-scoped check
  (file thresholds, the HTML report's `changed` flags) quietly no-ops
  instead of erroring. If a dry run produces suspiciously little output,
  check `git diff --name-only <base> <head>` directly first.
- The root `Dangerfile` also sets `blanket.html_report_dir =
  "smoke_test/coverage_report"` (gitignored) — a dry run regenerates a real,
  browsable static site there, exercising `Blanket::HtmlReport` end to end
  against the Kover fixture without needing Xcode.
- **Don't `open index.html` directly (`file://`) to preview a generated
  report** — `app.js` loads `report.json` and each file fragment via
  `fetch()`, which browsers silently refuse on `file://` (no error surfaced
  to the user, the page just renders empty/stuck on "…"). Serve the output
  dir over plain HTTP first, eg. `python3 -m http.server <port>` from inside
  it, then open `http://localhost:<port>/index.html`.

### Real-world validation (production-scale reports, not just fixtures)

Both parsers have been run against genuine coverage reports from real,
large codebases (not committed here — see "never reference any employer or
private codebase" above; this section only records the findings, not the
data). Method: point the parser directly at a real report via a throwaway
Ruby one-liner (`Danger::Blanket::Parsers::Kover.new(...).parse(path)`),
outside of any Dangerfile.

- **Kover**: validated against a ~915-file report from a large production
  Android codebase (Kotlin + legacy GreenDAO Java classes). At the time,
  `Parsers::Kover` resolved deep links by scraping Kover's own
  Gradle-generated HTML index — that mechanism found and fixed a real bug
  (`.kt`-only suffix stripping missed every legacy `.java` sourcefile,
  898/915 → 908/915 resolved), and hit a structural limit for files where
  the real class name doesn't derive from the filename at all (eg. a
  `FooHelper.kt` that actually defines `DefaultFooHelper`, or one file
  defining two unrelated top-level classes) — unresolvable without parsing
  Kotlin source for declared class names. **Both are now moot**: since
  danger-blanket owns HTML generation itself (see `Blanket::HtmlReport`),
  linking is deterministic path-based and no longer scrapes any generated
  HTML at all. The underlying real-world file/coverage-count validation
  (915 files, correct percentages) still stands; only the link-resolution
  mechanism it was validating has since been replaced.
- **xccov (formerly the `xcov` gem)**: the *previous* `Parsers::Xcov` (which
  read the third-party `xcov` gem's `report.json`) was validated against a
  735-file target from a real iOS app's test run — the `xcov` gem itself
  (1.9.0, via its `xcodeproj` 1.28.1 dependency) **could not run at all**
  against that real project (crashes parsing a modern Xcode "Synchronized
  Groups" project attribute xcodeproj 1.28.1 doesn't handle — an
  xcov/xcodeproj ecosystem bug, unrelated to danger-blanket). Worked around
  at the time by generating the real report data straight from Apple's own
  `xcrun xccov view --report --json <xcresult>` and reshaping it by hand
  into the xcov gem's schema. That workaround is exactly why `Parsers::Xcov`
  was replaced outright with `Parsers::Xccov`, which shells out to
  `xcrun xccov`/`xcresulttool` directly instead of going through the gem —
  no more reshaping needed.

  **`Parsers::Xccov` itself has now been validated** against a real
  `.xcresult` from the same app's target (same 735-file target the old
  workaround used; an ignore-file trims it to 566 files actually parsed —
  boilerplate view/cell/controller files, same idea as `file_threshold_overrides`
  but at parse time). Full `#parse` (`archive_id` → `export_archive` →
  per-file threaded `xccov` calls) ran clean: 63s wall time across 566
  files/8 threads, 16,405/34,312 lines covered (47.81% post-ignore, vs the
  raw target's 31.85% — expected, the ignored files skew low), 463 real
  sub-line `Span`s found (partial-execution highlighting works), 2,585
  sub-100% functions detected across 374 files, zero files with an
  inconsistent line-status tally vs. xccov's own summary, zero crashes. Also
  fed the resulting `Report` through `Blanket::HtmlReport.generate` against
  the real source tree (into a throwaway tmp dir, deleted immediately,
  content never inspected/printed here) — all 566 fragments rendered
  without error, confirming the HTML escaping/rendering path holds up
  against real (not fixture) Swift source. No bugs found.

## Current status (as of this session)

Local testing of the plugin, including real-world validation (see above).
Branch renamed `main` → `master`. Homepage in the gemspec:
`https://github.com/christophersaez/danger-blanket`, MIT licensed. Not yet
pushed to GitHub.

This session: replaced the iOS `xcov`-gem parser with `Parsers::Xccov`
(reads an `.xcresult` bundle directly via `xcrun xccov`/`xcresulttool`, no
third-party gem), and added `Blanket::HtmlReport` — a shared, platform-
agnostic renderer that both `Parsers::Kover` and `Parsers::Xccov` now feed
(via new optional `lines`/`functions`/raw line-count fields on
`Report`/`FileCoverage`), producing one consistent browsable coverage site
regardless of platform. This also removed the old Kover HTML-scraping link
resolution (and its `.java`/`.kt` bug class) entirely, in favor of
deterministic path-based linking. `bundle exec rspec` (58 examples) and
`bundle exec danger dry_run` (which now also regenerates a real static
report under `smoke_test/coverage_report/`, gitignored) both green.
`Parsers::Xccov` was also validated end-to-end against a real `.xcresult`
(see "Real-world validation" above) — no bugs found.

## Open items / things to watch

- Confirm and tighten `required_ruby_version` in the gemspec once the Ruby
  3.5 floor is verified for real (not just by inspection).
- No `.rubocop.yml` / linter config yet — decide if one gets added before
  first publish.
- No README yet.
- Real GitHub-flow validation (real PR, real `github.html_link`, not just
  `dry_run`) is the next planned validation step, once local report-parsing
  validation is done.
