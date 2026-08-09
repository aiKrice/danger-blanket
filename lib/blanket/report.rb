module Danger
  module Blanket
    # A sub-line region within an uncovered (or partially covered) line, eg.
    # a closure body that never ran even though the line it sits on did.
    # Column/length are 1-indexed characters. xccov-specific — JaCoCo has no
    # sub-line granularity, so Kover never populates these.
    #
    # @!attribute column
    #   @return [Integer] 1-indexed starting column.
    # @!attribute length
    #   @return [Integer] span length in characters.
    Span = Struct.new(:column, :length, keyword_init: true)

    # Coverage of a single source line, as reported by a parser that
    # supports line-level detail (see {FileCoverage#lines}).
    #
    # @!attribute number
    #   @return [Integer] 1-indexed line number.
    # @!attribute status
    #   @return [Symbol] one of :covered, :uncovered, :partial, :skipped.
    #     :partial means some but not all of the line ran (eg. JaCoCo's
    #     mi>0 && ci>0). A line with no explicit entry at all defaults to
    #     :skipped (non-executable) when rendered.
    # @!attribute spans
    #   @return [Array<Span>, nil] sub-line uncovered regions, if the parser
    #     exposes them (xccov only).
    LineCoverage = Struct.new(:number, :status, :spans, keyword_init: true)

    # Coverage of a single function/method, as reported by a parser that
    # supports function-level detail (see {FileCoverage#functions}).
    #
    # @!attribute name
    #   @return [String]
    # @!attribute line
    #   @return [Integer] 1-indexed starting line.
    # @!attribute coverage
    #   @return [Float] line coverage percentage (0-100) for this function.
    FunctionCoverage = Struct.new(:name, :line, :coverage, keyword_init: true)

    # Coverage of a single file, as reported by a parser.
    #
    # @!attribute coverage
    #   @return [Float] line coverage percentage (0-100)
    # @!attribute covered_lines
    #   @return [Integer, nil] count of covered executable lines, if the
    #     parser tracks it. Required to feed {Danger::Blanket::HtmlReport}.
    # @!attribute executable_lines
    #   @return [Integer, nil] count of executable lines, if the parser
    #     tracks it. Required to feed {Danger::Blanket::HtmlReport}.
    # @!attribute first_uncovered_line
    #   @return [Integer, nil] line number of the first uncovered line, if
    #     known — used to deep-link straight to it.
    # @!attribute lines
    #   @return [Array<LineCoverage>, nil] per-line detail, if the parser
    #     supports it. nil means this file can't feed
    #     {Danger::Blanket::HtmlReport} (it'll still show up with just a
    #     percentage wherever one is enough, eg. the markdown table).
    # @!attribute functions
    #   @return [Array<FunctionCoverage>, nil] per-function detail, if the
    #     parser supports it.
    # @!attribute meta
    #   @return [Hash] parser-specific data (eg. package name) a custom
    #     parser's own #html_link may need.
    FileCoverage = Struct.new(
      :coverage, :covered_lines, :executable_lines, :first_uncovered_line,
      :lines, :functions, :meta, keyword_init: true
    )

    # Normalized output of any Parsers::Base#parse implementation.
    #
    # @!attribute project_coverage
    #   @return [Float, nil] overall project line coverage percentage, or nil
    #     if the tool/report does not expose one.
    # @!attribute covered_lines
    #   @return [Integer, nil] project-wide count of covered executable
    #     lines, if the parser tracks it. Required to feed
    #     {Danger::Blanket::HtmlReport}.
    # @!attribute executable_lines
    #   @return [Integer, nil] project-wide count of executable lines, if
    #     the parser tracks it. Required to feed
    #     {Danger::Blanket::HtmlReport}.
    # @!attribute files
    #   @return [Hash<String, FileCoverage>] per-file coverage, keyed by file
    #     path as it appears in `git.modified_files` / `git.added_files`.
    Report = Struct.new(:project_coverage, :covered_lines, :executable_lines, :files, keyword_init: true)
  end
end
