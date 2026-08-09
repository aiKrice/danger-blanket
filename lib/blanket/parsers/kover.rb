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
      class Kover < Base
        def initialize(options = {})
          super
          @source_root = options[:source_root]
          raise ArgumentError, "Parsers::Kover requires a :source_root option (eg. 'app/src/main/java')" if @source_root.nil?
        end

        def parse(report_file)
          root = REXML::Document.new(File.read(report_file)).root

          project_counts = counter_counts(root.get_elements("counter"))

          files = {}
          root.get_elements("package").each do |package|
            functions_by_sourcefile = functions_by_sourcefile(package)

            package.get_elements("sourcefile").each do |sourcefile|
              counts = counter_counts(sourcefile.get_elements("counter"))
              next if counts.nil?

              covered, total = counts
              lines = line_details(sourcefile)
              functions = (functions_by_sourcefile[sourcefile.attributes["name"]] || []).sort_by(&:line)

              path = "#{@source_root}/#{package.attributes['name']}/#{sourcefile.attributes['name']}"
              files[path] = FileCoverage.new(
                coverage: percentage(covered, total),
                covered_lines: covered,
                executable_lines: total,
                first_uncovered_line: lines.find { |line| line.status == :uncovered }&.number,
                lines: lines,
                functions: functions,
                meta: {}
              )
            end
          end

          Report.new(
            project_coverage: project_counts && percentage(*project_counts),
            covered_lines: project_counts&.first,
            executable_lines: project_counts&.last,
            files: files
          )
        end

        private

        # [covered, total] executable-line counts from a <counter type="LINE">
        # element, or nil if the element/total is missing/zero.
        def counter_counts(counters)
          line_counter = counters.find { |counter| counter.attributes["type"] == "LINE" }
          return nil unless line_counter

          missed = line_counter.attributes["missed"].to_i
          covered = line_counter.attributes["covered"].to_i
          total = missed + covered
          return nil if total.zero?

          [covered, total]
        end

        # Convenience for the (rarer) case where only a percentage is
        # needed, eg. per-method coverage.
        def line_coverage(counters)
          counts = counter_counts(counters)
          return nil unless counts

          percentage(*counts)
        end

        def percentage(covered, total)
          (covered.to_f / total * 100).round(2)
        end

        # Per-line status straight from JaCoCo's own <line nr mi ci> data —
        # mi/ci are missed/covered *instructions* on that line, so a line
        # with both can be "partial" (eg. an inline conditional where only
        # one branch ran) even though every individual line technically
        # "executed". JaCoCo only emits a <line> for lines with mi+ci>0, so
        # a line with no entry at all (mi==0 && ci==0, or simply absent) is
        # non-executable — surfaced to callers as :skipped by the shared
        # HTML report renderer, not here.
        def line_details(sourcefile)
          sourcefile.get_elements("line").map do |line|
            mi = line.attributes["mi"].to_i
            ci = line.attributes["ci"].to_i

            status =
              if mi.zero? && ci.zero?
                :skipped
              elsif mi.zero?
                :covered
              elsif ci.zero?
                :uncovered
              else
                :partial
              end

            LineCoverage.new(number: line.attributes["nr"].to_i, status: status, spans: nil)
          end
        end

        # Method-level coverage lives on <class sourcefilename="Foo.kt">,
        # a sibling of <sourcefile name="Foo.kt"> under the same <package>
        # — not nested under it. Multiple classes can share one sourcefile
        # (eg. two unrelated top-level classes in one Kotlin file), so this
        # groups by sourcefilename and merges their methods.
        def functions_by_sourcefile(package)
          result = Hash.new { |hash, key| hash[key] = [] }

          package.get_elements("class").each do |klass|
            sourcefile_name = klass.attributes["sourcefilename"]
            next if sourcefile_name.nil?

            klass.get_elements("method").each do |method|
              coverage = line_coverage(method.get_elements("counter"))
              next if coverage.nil? || coverage >= 100

              result[sourcefile_name] << FunctionCoverage.new(
                name: method.attributes["name"],
                line: method.attributes["line"].to_i,
                coverage: coverage
              )
            end
          end

          result
        end
      end
    end
  end
end
