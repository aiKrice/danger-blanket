require "blanket/report"
require "blanket/html_report"
require "blanket/parsers/base"
require "blanket/parsers/xccov"
require "blanket/parsers/kover"
require "blanket/parsers/json"

module Danger
  # Reports code coverage on a pull request, delegating the actual report
  # parsing to a pluggable parser so any coverage tool can be supported
  # without changing this class.
  #
  # @example Basic usage with a built-in parser
  #
  #          blanket.report_file = "MyApp.xcresult"
  #          blanket.parser = :xccov
  #          blanket.parser_options = { target: "MyApp.app" }
  #          blanket.project_threshold = 49
  #          blanket.file_threshold = 85
  #          blanket.file_threshold_overrides = { "Sources/Legacy.swift" => 0 }
  #          blanket.warn_on_stale_overrides = true
  #          blanket.warning_as_error = true
  #          blanket.html_report_dir = "coverage_report"
  #          blanket.hosted_report_base_url = "https://dashboard.example.com/coverage/ios/42/coverage_report"
  #          blanket.report
  #
  # @example Using a custom parser for an unsupported tool
  #
  #          blanket.report_file = "coverage/lcov.info"
  #          blanket.parser = MyLcovParser.new
  #          blanket.report
  #
  # @see Christopher Saez/danger-blanket
  # @tags coverage, xccov, kover, jacoco
  class DangerBlanket < Plugin
    # Built-in parsers, resolved when `parser` is set to a Symbol.
    PARSERS = {
      xccov: Blanket::Parsers::Xccov,
      kover: Blanket::Parsers::Kover,
      json: Blanket::Parsers::Json,
    }.freeze

    # Path to the coverage report to parse. When missing, {#report} is a
    # no-op (matches the pattern of coverage tooling not always running, eg.
    # skipped on docs-only PRs). For :xccov this is a path to an `.xcresult`
    # bundle (a directory); for the other built-in parsers, a regular file.
    # @return [String, nil]
    attr_accessor :report_file

    # Which parser to use: a Symbol (`:xccov`, `:kover`, `:json`) resolved
    # against {PARSERS}, or any object responding to `#parse` (and optionally
    # `#html_link`) for an unsupported tool.
    # @return [Symbol, Object, nil]
    attr_accessor :parser

    # Options forwarded to the parser class when {#parser} is a Symbol.
    # Ignored when {#parser} is already an instance.
    # @return [Hash]
    attr_accessor :parser_options

    # Minimum acceptable overall project line coverage (percentage). Skipped
    # when nil.
    # @return [Numeric, nil]
    attr_accessor :project_threshold

    # Default minimum acceptable per-file line coverage (percentage), applied
    # to every modified/added file found in the report. Skipped when nil.
    # @return [Numeric, nil]
    attr_accessor :file_threshold

    # Per-file threshold overrides, for files that can't reasonably reach
    # {#file_threshold} (eg. hard to unit test). Key is the file path as it
    # appears in `git.modified_files`/`git.added_files`.
    # @return [Hash<String, Numeric>]
    attr_accessor :file_threshold_overrides

    # When true, a changed file whose coverage now exceeds its
    # {#file_threshold_overrides} entry gets flagged with a *separate*
    # warning suggesting the override be raised — catches an override that
    # was left in place after the code it was excusing got real tests,
    # quietly becoming a permanent loophole. Always uses `warn`, regardless
    # of {#warning_as_error} (this is a suggestion, never a violation).
    # Off by default: opt in explicitly, since not every project wants the
    # extra noise.
    # @return [Boolean]
    attr_accessor :warn_on_stale_overrides

    # When true, violations are reported with `fail` (blocks the PR). When
    # false (default), they're reported with `warn`.
    # @return [Boolean]
    attr_accessor :warning_as_error

    # Base URL of the hosted HTML report, used to build clickable per-file
    # links. When {#html_report_dir} is set, links are resolved
    # deterministically against the report {#report} just generated there;
    # otherwise falls back to the parser's own `#html_link` (for a
    # pre-existing report generated some other way). When nil, or when
    # neither resolves a link, falls back to a plain GitHub link to the file.
    # @return [String, nil]
    attr_accessor :hosted_report_base_url

    # When set, {#report} also renders a static, browsable HTML coverage
    # site into this directory via {Danger::Blanket::HtmlReport} — the same
    # renderer regardless of which parser produced the {Danger::Blanket::Report}.
    # Only parsers that populate per-file line detail (`:kover`, `:xccov`)
    # can feed it. Deploying/hosting the written directory (eg. an S3 sync)
    # is left to your own CI, outside this gem's scope.
    # @return [String, nil]
    attr_accessor :html_report_dir

    # Title shown in the generated HTML report's top bar and browser tab.
    # Ignored when {#html_report_dir} is nil.
    # @return [String, nil]
    attr_accessor :html_report_title

    # A local image file path (svg/png/ico/jpg/gif/webp), copied into the
    # generated report, or an `http(s)://` URL, used as-is with no
    # download — to use as the report's browser-tab icon, instead of the
    # bundled default. Independent from {#html_report_logo} — set one,
    # both, or neither. Ignored when {#html_report_dir} is nil.
    # @return [String, nil]
    attr_accessor :html_report_favicon

    # Same as {#html_report_favicon} (local path or `http(s)://` URL), but
    # for the top-bar logo shown inside the generated report itself.
    # Ignored when {#html_report_dir} is nil.
    # @return [String, nil]
    attr_accessor :html_report_logo

    def initialize(dangerfile)
      super
      self.parser_options = {}
      self.file_threshold_overrides = {}
      self.warning_as_error = false
      self.warn_on_stale_overrides = false
    end

    # Parses {#report_file}, optionally renders {#html_report_dir}, and
    # reports project/file coverage violations. No-op when {#report_file} is
    # nil or missing on disk.
    def report
      return unless report_file && File.exist?(report_file)

      resolved_parser = resolve_parser
      parsed = resolved_parser.parse(report_file)

      generated_html_report = generate_html_report(parsed)

      check_project_threshold(parsed)
      check_file_thresholds(parsed, resolved_parser, generated_html_report)
    end

    private

    def resolve_parser
      case parser
      when Symbol
        klass = PARSERS[parser]
        raise ArgumentError, "Unknown blanket parser #{parser.inspect}, expected one of #{PARSERS.keys.inspect} or a custom parser instance" if klass.nil?

        klass.new(parser_options)
      when nil
        raise ArgumentError, "blanket.parser must be set (eg. :xccov, :kover, :json, or a custom parser instance)"
      else
        parser
      end
    end

    def generate_html_report(parsed)
      return false unless html_report_dir

      changed_files = git.modified_files + git.added_files
      Blanket::HtmlReport.generate(
        parsed, html_report_dir,
        changed_files: changed_files,
        title: html_report_title || "Coverage Report",
        favicon: html_report_favicon,
        logo: html_report_logo
      )
      true
    end

    def severity_method
      warning_as_error ? :fail : :warn
    end

    def check_project_threshold(parsed)
      return if project_threshold.nil? || parsed.project_coverage.nil?
      return if parsed.project_coverage >= project_threshold

      send(severity_method, "🔴 Project line coverage is #{parsed.project_coverage}%, below the required #{project_threshold}%.")
    end

    def check_file_thresholds(parsed, resolved_parser, generated_html_report)
      return if file_threshold.nil?

      below_threshold_rows = []
      stale_override_rows = []

      (git.modified_files + git.added_files).each do |file|
        entry = parsed.files[file]
        next if entry.nil?

        override = file_threshold_overrides[file]
        threshold = override || file_threshold

        if entry.coverage < threshold
          link = file_link(file, entry, resolved_parser, generated_html_report)
          below_threshold_rows << "#{link} | #{entry.coverage}% | #{threshold}%#{override ? ' (override)' : ''}"
        elsif warn_on_stale_overrides && override && entry.coverage > override
          link = file_link(file, entry, resolved_parser, generated_html_report)
          stale_override_rows << "#{link} | #{entry.coverage}% | #{override}%"
        end
      end

      report_below_threshold(below_threshold_rows)
      report_stale_overrides(stale_override_rows)
    end

    def report_below_threshold(rows)
      return if rows.empty?

      message = +"### 📊 Coverage below threshold\n\n"
      message << "File | Coverage | Threshold |\n"
      message << "| --- | --- | --- |\n"
      message << rows.join("\n")
      markdown(message)

      send(severity_method, "#{rows.size} file(s) below their coverage threshold, see table above.")
    end

    # Always `warn` (never `fail`, regardless of {#warning_as_error}) — a
    # file exceeding its override isn't a violation, just worth a nudge.
    def report_stale_overrides(rows)
      return if rows.empty?

      message = +"### 📈 Coverage override could be raised\n\n"
      message << "File | Coverage | Current override |\n"
      message << "| --- | --- | --- |\n"
      message << rows.join("\n")
      markdown(message)

      warn("⚠️ #{rows.size} file(s) now exceed their custom coverage threshold override in file_threshold_overrides, consider raising it, see table above.")
    end

    def file_link(file, entry, resolved_parser, generated_html_report)
      href = resolved_href(file, entry, resolved_parser, generated_html_report)
      href ? "[#{file}](#{href})" : scm_html_link(file)
    end

    # Bare URL for a file's deep link, or nil to let the caller fall back to
    # {#scm_html_link}. When {#html_report_dir} was just generated, this is
    # deterministic (no scraping needed — this module owns both the
    # generator and its addressing scheme); otherwise falls back to the
    # parser's own #html_link, for a report generated some other way.
    def resolved_href(file, entry, resolved_parser, generated_html_report)
      if generated_html_report && hosted_report_base_url
        Blanket::HtmlReport.link_for(file, hosted_report_base_url, first_uncovered_line: entry.first_uncovered_line)
      else
        resolved_parser.html_link(entry, hosted_report_base_url)
      end
    end

    # Host-provided fallback link (GitHub/GitLab/Bitbucket) for a file with
    # no resolved deep link. These host plugins only exist on `@dangerfile`
    # when running against a real PR/MR, so this is skipped entirely under
    # `danger dry_run`/`danger local` or an unsupported host — the plain
    # file path is used instead rather than crashing.
    SCM_HOST_PLUGINS = %i[github gitlab bitbucket_server bitbucket_cloud].freeze

    def scm_html_link(file)
      host = SCM_HOST_PLUGINS.find { |plugin_name| @dangerfile.respond_to?(plugin_name) }
      host ? @dangerfile.send(host).html_link(file) : file
    end
  end
end
