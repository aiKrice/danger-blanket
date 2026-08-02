require "json"
require "blanket/parsers/base"
require "blanket/report"

module Danger
  module Blanket
    module Parsers
      # Generic pass-through parser: reads a report already normalized to
      # Blanket's own schema, so any tool/language can plug in without
      # writing a Ruby parser class, as long as it can emit:
      #
      #   {
      #     "project_coverage": 62.5,
      #     "files": [
      #       { "path": "lib/foo.rb", "coverage": 91.2, "html_link": "https://.../foo.html" }
      #     ]
      #   }
      #
      # `html_link` is optional per file; when absent the plugin falls back
      # to a plain GitHub link.
      class Json < Base
        def parse(report_file)
          data = JSON.parse(File.read(report_file))

          files = (data["files"] || []).each_with_object({}) do |entry, acc|
            next if entry["path"].nil? || entry["coverage"].nil?

            acc[entry["path"]] = FileCoverage.new(
              coverage: entry["coverage"].to_f,
              meta: { html_link: entry["html_link"] }
            )
          end

          Report.new(project_coverage: data["project_coverage"]&.to_f, files: files)
        end

        def html_link(file_coverage, _hosted_report_base_url)
          file_coverage.meta[:html_link]
        end
      end
    end
  end
end
