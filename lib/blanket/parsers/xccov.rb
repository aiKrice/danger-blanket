require "json"
require "open3"
require "tmpdir"
require "blanket/parsers/base"
require "blanket/report"

module Danger
  module Blanket
    module Parsers
      # Parses Xcode's own coverage data (iOS/macOS) straight from an
      # `.xcresult` bundle, via `xcrun xccov`/`xcresulttool` — the CLI
      # front-end for the same LLVM source-based coverage engine as
      # `llvm-cov`. Raw `llvm-cov` can't read Xcode 16+'s `.xcresult`
      # directly (it's a proprietary indexed format only `xccov` decodes),
      # so this shells out rather than parsing a file directly.
      #
      # Options:
      #   :target          (required) the app target name as it appears in
      #                    `xccov`'s report, eg. "MyApp.app".
      #   :ignore_patterns (optional) Array<String> of case-insensitive
      #                    regex fragments; a file is excluded from the
      #                    report (and the coverage numbers) if its path
      #                    relative to the repo root matches any of them.
      #   :threads         (optional) worker count for the per-file xccov
      #                    calls, default 8.
      #   :runner          (optional) collaborator with #archive_id,
      #                    #export_archive, #report_json, #file_lines_json —
      #                    defaults to a real XcrunRunner. Inject a fake in
      #                    tests to avoid shelling out to Xcode tooling.
      class Xccov < Base
        DEFAULT_THREAD_COUNT = 8

        # Real `xcrun` invocations, isolated so #parse itself never shells
        # out directly and can be tested without Xcode installed.
        class XcrunRunner
          # The coverage archive backing an .xcresult isn't exposed
          # directly — it has to be located inside the bundle's own action
          # metadata first, then exported to a real directory before
          # per-file queries can run against it.
          def archive_id(xcresult_path)
            json = run_json("xcrun", "xcresulttool", "get", "--legacy", "--format", "json", "--path", xcresult_path)
            json.dig("actions", "_values", 0, "actionResult", "coverage", "archiveRef", "id", "_value")
          end

          def export_archive(xcresult_path, archive_id, output_dir)
            run!("xcrun", "xcresulttool", "export", "--legacy", "--type", "directory", "--id", archive_id, "--path", xcresult_path, "--output-path", output_dir)
          end

          # Per-target, per-file summary (coverage/coveredLines/executableLines
          # and, crucially, a per-function breakdown) — the only place
          # function-level data comes from, since the per-file archive query
          # below only has line-level granularity.
          def report_json(xcresult_path)
            run_json("xcrun", "xccov", "view", "--report", "--json", xcresult_path)
          end

          # Per-line detail (isExecutable/executionCount, plus sub-line
          # `subranges` for partially-executed lines) for one file, keyed by
          # its absolute path in the returned JSON. Some files legitimately
          # have nothing to report here (eg. generated code); tolerate a
          # failure by returning an empty result rather than raising.
          def file_lines_json(archive_dir, abs_path)
            stdout, _stderr, status = Open3.capture3("xcrun", "xccov", "view", "--archive", "--file", abs_path, "--json", archive_dir)
            return [] unless status.success?

            JSON.parse(stdout)[abs_path] || []
          rescue JSON::ParserError
            []
          end

          private

          def run_json(*command)
            JSON.parse(run!(*command))
          end

          def run!(*command)
            stdout, stderr, status = Open3.capture3(*command)
            raise "#{command.join(' ')} failed: #{stderr}" unless status.success?

            stdout
          end
        end

        def initialize(options = {})
          super
          @target = options[:target]
          raise ArgumentError, "Parsers::Xccov requires a :target option (eg. 'MyApp.app')" if @target.nil?

          @ignore_patterns = options[:ignore_patterns] || []
          @thread_count = options[:threads] || DEFAULT_THREAD_COUNT
          @runner = options[:runner] || XcrunRunner.new
        end

        def parse(xcresult_path)
          report = @runner.report_json(xcresult_path)
          target = (report["targets"] || []).find { |candidate| candidate["name"] == @target }
          return Report.new(project_coverage: nil, covered_lines: nil, executable_lines: nil, files: {}) if target.nil?

          candidate_files = relevant_files(target)

          files = Dir.mktmpdir("blanket-xccov") do |tmp_dir|
            archive_dir = export_archive(xcresult_path, tmp_dir)
            build_files(candidate_files, archive_dir)
          end

          covered_lines = files.values.sum { |file| file.covered_lines || 0 }
          executable_lines = files.values.sum { |file| file.executable_lines || 0 }

          Report.new(
            project_coverage: executable_lines.zero? ? 0.0 : (covered_lines.to_f / executable_lines * 100).round(2),
            covered_lines: covered_lines,
            executable_lines: executable_lines,
            files: files
          )
        end

        private

        # {relative_path => raw xccov file entry}, dropping anything with no
        # usable path or matching :ignore_patterns.
        def relevant_files(target)
          repo_root = Dir.pwd

          (target["files"] || []).each_with_object({}) do |file, acc|
            path = file["path"]
            next if path.nil?

            relative_path = path.delete_prefix("#{repo_root}/")
            next if ignored?(relative_path)

            acc[relative_path] = file
          end
        end

        def ignored?(relative_path)
          return false if @ignore_patterns.empty?

          ignore_regex.match?(relative_path)
        end

        def ignore_regex
          @ignore_regex ||= Regexp.new(@ignore_patterns.join("|"), Regexp::IGNORECASE)
        end

        def export_archive(xcresult_path, tmp_dir)
          archive_id = @runner.archive_id(xcresult_path)
          raise "No coverage archive found in #{xcresult_path}. Was codeCoverageEnabled set on the scheme?" if archive_id.nil?

          archive_dir = File.join(tmp_dir, "archive.xccovarchive")
          @runner.export_archive(xcresult_path, archive_id, archive_dir)
          archive_dir
        end

        # Fans the per-file xccov queries (the slow part — one `xcrun` call
        # per file) out across a small thread pool. Shelling out releases
        # the GIL for the duration of each subprocess, so plain threads
        # (stdlib only, no extra gem) parallelize this effectively.
        def build_files(candidate_files, archive_dir)
          queue = Queue.new
          candidate_files.each { |relative_path, file| queue << [relative_path, file] }

          files = {}
          mutex = Mutex.new
          worker_count = [@thread_count, candidate_files.size].min.clamp(1, @thread_count)

          Array.new(worker_count) do
            Thread.new do
              loop do
                relative_path, file =
                  begin
                    queue.pop(true)
                  rescue ThreadError
                    break
                  end

                file_coverage = build_file_coverage(archive_dir, file)
                mutex.synchronize { files[relative_path] = file_coverage }
              end
            end
          end.each(&:join)

          files
        end

        def build_file_coverage(archive_dir, file)
          lines = line_details(archive_dir, file["path"])
          functions = function_details(file)

          FileCoverage.new(
            coverage: (file["lineCoverage"].to_f * 100).round(2),
            covered_lines: file["coveredLines"],
            executable_lines: file["executableLines"],
            first_uncovered_line: lines.find { |line| line.status == :uncovered }&.number,
            lines: lines,
            functions: functions,
            meta: {}
          )
        end

        # xccov exposes only line/function granularity, no branch/region
        # data — except here: `subranges` on an executable line marks a
        # sub-line span (eg. a closure body) that never ran even though the
        # line itself did. This is the one place genuine sub-line coverage
        # is visible.
        def line_details(archive_dir, abs_path)
          @runner.file_lines_json(archive_dir, abs_path).map do |entry|
            executable = entry["isExecutable"]
            execution_count = entry["executionCount"] || 0

            status =
              if !executable
                :skipped
              elsif execution_count.positive?
                :covered
              else
                :uncovered
              end

            spans = (entry["subranges"] || [])
                    .select { |span| (span["length"] || 0).positive? && (span["executionCount"] || 0).zero? }
                    .map { |span| Span.new(column: span["column"], length: span["length"]) }

            LineCoverage.new(number: entry["line"], status: status, spans: spans)
          end
        end

        # Comes straight from `xccov view --report --json`'s per-file
        # `functions` array — no extra call needed. A function strictly
        # between 0% and 100% means some path through it never ran, even if
        # individual lines each look "executed" — the closest xccov gets to
        # branch coverage. Fully-covered functions are dropped, same as Kover.
        def function_details(file)
          (file["functions"] || [])
            .map { |fn| FunctionCoverage.new(name: fn["name"], line: fn["lineNumber"], coverage: (fn["lineCoverage"].to_f * 100).round(2)) }
            .select { |fn| fn.coverage < 100 }
            .sort_by(&:line)
        end
      end
    end
  end
end
