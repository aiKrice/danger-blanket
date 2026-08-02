module Danger
  module Blanket
    module Parsers
      # Contract every coverage parser must follow. Not required to be
      # subclassed (duck-typing is enough: any object responding to #parse
      # works), but inheriting from it documents the interface and gives you
      # a no-op #html_link for free.
      class Base
        def initialize(options = {})
          @options = options || {}
        end

        # @param report_file [String] path to the coverage report to parse.
        # @return [Danger::Blanket::Report]
        def parse(report_file)
          raise NotImplementedError, "#{self.class} must implement #parse"
        end

        # Resolve a bare URL pointing at this file's section of the hosted
        # HTML report (the plugin wraps it in markdown link syntax). Return
        # nil to let the plugin fall back to a plain GitHub link to the file.
        #
        # @param file_coverage [Danger::Blanket::FileCoverage]
        # @param hosted_report_base_url [String, nil]
        # @return [String, nil]
        def html_link(file_coverage, hosted_report_base_url)
          nil
        end
      end
    end
  end
end
