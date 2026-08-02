require "json"
require "blanket/parsers/base"
require "blanket/report"

module Danger
  module Blanket
    module Parsers
      # Parses xcov's report.json (iOS/Xcode).
      #
      # Options:
      #   :target   (required) the app target name as it appears in
      #             report.json, eg. "MyApp.app".
      #   :html_dir (optional) directory containing xcov's generated
      #             index.html, used to resolve #html_link.
      class Xcov < Base
        def initialize(options = {})
          super
          @target = options[:target]
          raise ArgumentError, "Parsers::Xcov requires a :target option (eg. 'MyApp.app')" if @target.nil?

          @html_dir = options[:html_dir]
        end

        def parse(report_file)
          report = JSON.parse(File.read(report_file))
          target = report["targets"]&.find { |t| t["name"] == @target }
          return Report.new(project_coverage: nil, files: {}) if target.nil?

          project_coverage = (target["coverage"].to_f * 100).round(2)
          repo_root = Dir.pwd

          files = (target["files"] || []).each_with_object({}) do |file, acc|
            next if file["path"].nil?

            relative_path = file["path"].sub("#{repo_root}/", "")
            acc[relative_path] = FileCoverage.new(
              coverage: (file["coverage"].to_f * 100).round(2),
              meta: { name: file["name"] }
            )
          end

          Report.new(project_coverage: project_coverage, files: files)
        end

        # xcov renders every file behind a random-per-run `file-id` anchor on
        # a single HTML page (no per-file pages, unlike Kover). Keyed by base
        # file name only, since xcov's HTML never renders the full path.
        def html_link(file_coverage, hosted_report_base_url)
          return nil unless @html_dir && hosted_report_base_url

          file_id = file_id_index[file_coverage.meta[:name]]
          return nil unless file_id

          "#{hosted_report_base_url}/index.html##{file_id}"
        end

        private

        def file_id_index
          @file_id_index ||= begin
            index_file = File.join(@html_dir, "index.html")
            return {} unless File.file?(index_file)

            File.read(index_file)
                .scan(/file-id="([0-9a-f]+)">.*?<\/span>\s*([^<\n]+?)\s*<\/div>/m)
                .each_with_object({}) { |(file_id, name), acc| acc[name] ||= file_id }
          end
        end
      end
    end
  end
end
