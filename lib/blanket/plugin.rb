require "blanket/report"
require "blanket/parsers/base"
require "blanket/parsers/xcov"
require "blanket/parsers/kover"
require "blanket/parsers/json"

module Danger
  # Reports code coverage on a pull request, delegating the actual report
  # parsing to a pluggable parser so any coverage tool can be supported
  # without changing this class.
  #
  # @example Basic usage with a built-in parser
  #
  #          blanket.report_file = "xcov_report/report.json"
  #          blanket.parser = :xcov
  #          blanket.parser_options = { target: "MyApp.app", html_dir: "xcov_report" }
  #          blanket.project_threshold = 49
  #          blanket.file_threshold = 85
  #          blanket.file_threshold_overrides = { "Sources/Legacy.swift" => 0 }
  #          blanket.warning_as_error = true
  #          blanket.hosted_report_base_url = "https://dashboard.example.com/coverage/ios/42/xcov_report"
  #          blanket.report
  #
  # @example Using a custom parser for an unsupported tool
  #
  #          blanket.report_file = "coverage/lcov.info"
  #          blanket.parser = MyLcovParser.new
  #          blanket.report
  #
  # @see Christopher Saez/danger-blanket
  # @tags coverage, xcov, kover, jacoco
  class DangerBlanket < Plugin
    # Built-in parsers, resolved when `parser` is set to a Symbol.
    PARSERS = {
      xcov: Blanket::Parsers::Xcov,
      kover: Blanket::Parsers::Kover,
      json: Blanket::Parsers::Json,
    }.freeze

    # Path to the coverage report to parse. When missing, {#report} is a no-op
    # (matches the pattern of coverage tooling not always running, eg. skipped
    # on docs-only PRs).
    # @return [String, nil]
    attr_accessor :report_file

    # Which parser to use: a Symbol (`:xcov`, `:kover`, `:json`) resolved
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

    # When true, violations are reported with `fail` (blocks the PR). When
    # false (default), they're reported with `warn`.
    # @return [Boolean]
    attr_accessor :warning_as_error

    # Base URL of the hosted HTML report, forwarded to the parser to build
    # clickable per-file links. When nil, or when the parser can't resolve a
    # link, falls back to a plain GitHub link to the file.
    # @return [String, nil]
    attr_accessor :hosted_report_base_url

    def initialize(dangerfile)
      super
      self.parser_options = {}
      self.file_threshold_overrides = {}
      self.warning_as_error = false
    end

    # Parses {#report_file} and reports project/file coverage violations.
    # No-op when {#report_file} is nil or missing on disk.
    def report
      return unless report_file && File.file?(report_file)

      resolved_parser = resolve_parser
      parsed = resolved_parser.parse(report_file)

      check_project_threshold(parsed)
      check_file_thresholds(parsed, resolved_parser)
    end

    private

    def resolve_parser
      case parser
      when Symbol
        klass = PARSERS[parser]
        raise ArgumentError, "Unknown blanket parser #{parser.inspect}, expected one of #{PARSERS.keys.inspect} or a custom parser instance" if klass.nil?

        klass.new(parser_options)
      when nil
        raise ArgumentError, "blanket.parser must be set (eg. :xcov, :kover, :json, or a custom parser instance)"
      else
        parser
      end
    end

    def severity_method
      warning_as_error ? :fail : :warn
    end

    def check_project_threshold(parsed)
      return if project_threshold.nil? || parsed.project_coverage.nil?
      return if parsed.project_coverage >= project_threshold

      send(severity_method, "🔴 Project line coverage is #{parsed.project_coverage}%, below the required #{project_threshold}%.")
    end

    def check_file_thresholds(parsed, resolved_parser)
      return if file_threshold.nil?

      changed_files = git.modified_files + git.added_files
      rows = changed_files.filter_map { |file| file_violation_row(file, parsed, resolved_parser) }

      return if rows.empty?

      message = +"### 📊 Coverage below threshold\n\n"
      message << "File | Coverage | Threshold |\n"
      message << "| --- | --- | --- |\n"
      message << rows.join("\n")
      markdown(message)

      send(severity_method, "#{rows.size} file(s) below their coverage threshold, see table above.")
    end

    def file_violation_row(file, parsed, resolved_parser)
      entry = parsed.files[file]
      return nil if entry.nil?

      override = file_threshold_overrides.key?(file)
      threshold = override ? file_threshold_overrides[file] : file_threshold
      return nil if entry.coverage >= threshold

      href = resolved_parser.html_link(entry, hosted_report_base_url)
      link = href ? "[#{file}](#{href})" : scm_html_link(file)
      "#{link} | #{entry.coverage}% | #{threshold}%#{override ? ' (override)' : ''}"
    end

    # Host-provided fallback link (GitHub/GitLab/Bitbucket) for a file with
    # no parser-resolved deep link. These host plugins only exist on
    # `@dangerfile` when running against a real PR/MR, so this is skipped
    # entirely under `danger dry_run`/`danger local` or an unsupported host
    # — the plain file path is used instead rather than crashing.
    SCM_HOST_PLUGINS = %i[github gitlab bitbucket_server bitbucket_cloud].freeze

    def scm_html_link(file)
      host = SCM_HOST_PLUGINS.find { |plugin_name| @dangerfile.respond_to?(plugin_name) }
      host ? @dangerfile.send(host).html_link(file) : file
    end
  end
end
