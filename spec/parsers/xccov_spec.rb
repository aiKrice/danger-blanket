require File.expand_path("../spec_helper", __dir__)

module Danger
  # A fake XcrunRunner — the whole point of extracting that collaborator is
  # so these specs never shell out to `xcrun`/Xcode.
  class FakeXccovRunner
    attr_reader :export_calls

    def initialize(foo_path, ignored_path)
      @foo_path = foo_path
      @ignored_path = ignored_path
      @export_calls = []
    end

    def archive_id(_xcresult_path)
      "archive-123"
    end

    def export_archive(xcresult_path, archive_id, output_dir)
      @export_calls << [xcresult_path, archive_id, output_dir]
    end

    def report_json(_xcresult_path)
      {
        "targets" => [
          {
            "name" => "MyApp.app",
            "files" => [
              {
                "path" => @foo_path,
                "name" => "Foo.swift",
                "lineCoverage" => 0.75,
                "coveredLines" => 3,
                "executableLines" => 4,
                "functions" => [
                  { "name" => "bar()", "lineNumber" => 10, "lineCoverage" => 0.5 },
                  { "name" => "baz()", "lineNumber" => 20, "lineCoverage" => 1.0 },
                ],
              },
              {
                "path" => @ignored_path,
                "name" => "Ignored.swift",
                "lineCoverage" => 0.0,
                "coveredLines" => 0,
                "executableLines" => 5,
                "functions" => [],
              },
            ],
          },
          { "name" => "OtherTarget.app", "files" => [] },
        ],
      }
    end

    def file_lines_json(_archive_dir, abs_path)
      return [] unless abs_path == @foo_path

      [
        { "line" => 1, "isExecutable" => false, "executionCount" => 0 },
        { "line" => 2, "isExecutable" => true, "executionCount" => 3 },
        { "line" => 3, "isExecutable" => true, "executionCount" => 0 },
        {
          "line" => 4,
          "isExecutable" => true,
          "executionCount" => 2,
          "subranges" => [
            { "column" => 5, "length" => 3, "executionCount" => 0 },
            { "column" => 9, "length" => 2, "executionCount" => 1 },
          ],
        },
      ]
    end
  end

  describe Blanket::Parsers::Xccov do
    let(:repo_root) { Dir.pwd }
    let(:foo_path) { "#{repo_root}/Sources/Foo.swift" }
    let(:ignored_path) { "#{repo_root}/Generated/Ignored.swift" }
    let(:fake_runner) { FakeXccovRunner.new(foo_path, ignored_path) }
    subject(:parser) { described_class.new(target: "MyApp.app", runner: fake_runner) }

    it "requires a :target option" do
      expect { described_class.new(runner: fake_runner) }.to raise_error(ArgumentError, /:target/)
    end

    describe "#parse" do
      it "returns per-file coverage keyed by path relative to the repo root" do
        report = parser.parse("/fake.xcresult")

        expect(report.files.keys).to contain_exactly("Sources/Foo.swift", "Generated/Ignored.swift")
        expect(report.files["Sources/Foo.swift"].coverage).to eq(75.0)
        expect(report.files["Sources/Foo.swift"].covered_lines).to eq(3)
        expect(report.files["Sources/Foo.swift"].executable_lines).to eq(4)
      end

      it "excludes files matching :ignore_patterns from both the file list and the coverage totals" do
        parser = described_class.new(target: "MyApp.app", runner: fake_runner, ignore_patterns: ["^Generated/"])

        report = parser.parse("/fake.xcresult")

        expect(report.files.keys).to eq(["Sources/Foo.swift"])
        expect(report.covered_lines).to eq(3)
        expect(report.executable_lines).to eq(4)
      end

      it "aggregates project coverage over the (non-ignored) files it just built, not xccov's own target total" do
        report = parser.parse("/fake.xcresult")

        expect(report.covered_lines).to eq(3)
        expect(report.executable_lines).to eq(9)
        expect(report.project_coverage).to eq(33.33)
      end

      it "derives per-line status from isExecutable/executionCount" do
        lines = parser.parse("/fake.xcresult").files["Sources/Foo.swift"].lines

        expect(lines.map(&:status)).to eq(%i[skipped covered uncovered covered])
      end

      it "resolves first_uncovered_line to the first executable-but-never-ran line" do
        expect(parser.parse("/fake.xcresult").files["Sources/Foo.swift"].first_uncovered_line).to eq(3)
      end

      it "turns never-executed subranges into Spans, ignoring ones that did run" do
        line4 = parser.parse("/fake.xcresult").files["Sources/Foo.swift"].lines.find { |line| line.number == 4 }

        expect(line4.spans).to eq([Blanket::Span.new(column: 5, length: 3)])
      end

      it "keeps only functions below 100% coverage, sorted by line" do
        functions = parser.parse("/fake.xcresult").files["Sources/Foo.swift"].functions

        expect(functions).to eq([Blanket::FunctionCoverage.new(name: "bar()", line: 10, coverage: 50.0)])
      end

      it "returns an empty report when the target isn't found" do
        report = described_class.new(target: "Nope.app", runner: fake_runner).parse("/fake.xcresult")

        expect(report.project_coverage).to be_nil
        expect(report.files).to eq({})
      end

      it "exports the coverage archive located via the runner's archive_id" do
        parser.parse("/fake.xcresult")

        expect(fake_runner.export_calls.size).to eq(1)
        xcresult_path, archive_id, = fake_runner.export_calls.first
        expect(xcresult_path).to eq("/fake.xcresult")
        expect(archive_id).to eq("archive-123")
      end

      it "raises a clear error when no coverage archive is found" do
        allow(fake_runner).to receive(:archive_id).and_return(nil)

        expect { parser.parse("/fake.xcresult") }.to raise_error(/No coverage archive found/)
      end
    end
  end
end
