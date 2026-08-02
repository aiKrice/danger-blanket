require "rexml/document"
require "blanket/parsers/base"
require "blanket/report"

module Danger
  module Blanket
    module Parsers
      # Parses a Kover/JaCoCo-style XML report (Android).
      #
      # Options:
      #   :source_root (required) source root the report's package names are
      #                relative to, eg. "app/src/main/java".
      #   :html_dir    (optional) directory containing Kover's generated HTML
      #                report, used to resolve #html_link.
      class Kover < Base
        def initialize(options = {})
          super
          @source_root = options[:source_root]
          raise ArgumentError, "Parsers::Kover requires a :source_root option (eg. 'app/src/main/java')" if @source_root.nil?

          @html_dir = options[:html_dir]
        end

        def parse(report_file)
          root = REXML::Document.new(File.read(report_file)).root

          project_coverage = line_coverage(root.get_elements("counter"))

          files = {}
          root.get_elements("package").each do |package|
            package.get_elements("sourcefile").each do |sourcefile|
              coverage = line_coverage(sourcefile.get_elements("counter"))
              next if coverage.nil?

              path = "#{@source_root}/#{package.attributes['name']}/#{sourcefile.attributes['name']}"
              files[path] = FileCoverage.new(
                coverage: coverage,
                meta: {
                  package: package.attributes["name"].tr("/", "."),
                  sourcefile: sourcefile.attributes["name"],
                }
              )
            end
          end

          Report.new(project_coverage: project_coverage, files: files)
        end

        # Kover's HTML report is one page per package (`ns-X/index.html`),
        # itself linking to one page per source file
        # (`ns-X/sources/source-N.html`). Resolving a link means walking both
        # levels, keyed by class name rather than file name.
        def html_link(file_coverage, hosted_report_base_url)
          return nil unless @html_dir && hosted_report_base_url

          ns = package_to_ns[file_coverage.meta[:package]]
          return nil unless ns

          source_link = source_link_in_namespace(ns, file_coverage.meta[:sourcefile])
          return nil unless source_link

          "#{hosted_report_base_url}/#{ns}/#{source_link}"
        end

        private

        def line_coverage(counters)
          line_counter = counters.find { |counter| counter.attributes["type"] == "LINE" }
          return nil unless line_counter

          missed = line_counter.attributes["missed"].to_i
          covered = line_counter.attributes["covered"].to_i
          total = missed + covered
          return nil if total.zero?

          (covered.to_f / total * 100).round(2)
        end

        # Maps package name -> ns-X folder, parsed once from the report's root index.
        def package_to_ns
          @package_to_ns ||= begin
            index_file = File.join(@html_dir, "index.html")
            return {} unless File.file?(index_file)

            File.read(index_file)
                .scan(%r{<a href="(ns-[0-9a-f]+)/index\.html">([^<]+)</a>})
                .each_with_object({}) { |(ns, package_name), acc| acc[package_name] = ns }
          end
        end

        # Finds the source-N.html page for a given file within its package's
        # ns-X/index.html. Kover pages are keyed by class name, so tries the
        # file's own name first, then the Kotlin file-facade class name (eg.
        # "FooExtensions.kt" -> "FooExtensionsKt").
        def source_link_in_namespace(ns, source_file_name)
          unless ns_index_cache.key?(ns)
            ns_index_file = File.join(@html_dir, ns, "index.html")
            ns_index_cache[ns] = File.file?(ns_index_file) ? File.read(ns_index_file) : nil
          end
          ns_index_content = ns_index_cache[ns]
          return nil unless ns_index_content

          class_name = source_file_name.sub(/\.kt\z/, "")
          [class_name, "#{class_name}Kt"].each do |candidate|
            match = ns_index_content.match(%r{<a href="(sources/source-[0-9a-f]+\.html)">#{Regexp.escape(candidate)}</a>})
            return match[1] if match
          end

          nil
        end

        def ns_index_cache
          @ns_index_cache ||= {}
        end
      end
    end
  end
end
