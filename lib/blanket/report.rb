module Danger
  module Blanket
    # Coverage of a single file, as reported by a parser.
    #
    # @!attribute coverage
    #   @return [Float] line coverage percentage (0-100)
    # @!attribute meta
    #   @return [Hash] parser-specific data (eg. package name, html anchor)
    #     needed later to resolve a clickable link to the report.
    FileCoverage = Struct.new(:coverage, :meta, keyword_init: true)

    # Normalized output of any Parsers::Base#parse implementation.
    #
    # @!attribute project_coverage
    #   @return [Float, nil] overall project line coverage percentage, or nil
    #     if the tool/report does not expose one.
    # @!attribute files
    #   @return [Hash<String, FileCoverage>] per-file coverage, keyed by file
    #     path as it appears in `git.modified_files` / `git.added_files`.
    Report = Struct.new(:project_coverage, :files, keyword_init: true)
  end
end
