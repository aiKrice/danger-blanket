require File.expand_path("spec_helper", __dir__)
require "tmpdir"
require "json"

module Danger
  describe Blanket::HtmlReport do
    let(:bar_file) do
      Blanket::FileCoverage.new(
        coverage: 66.67,
        covered_lines: 2,
        executable_lines: 3,
        first_uncovered_line: 5,
        lines: [
          Blanket::LineCoverage.new(number: 3, status: :covered, spans: nil),
          Blanket::LineCoverage.new(number: 4, status: :partial, spans: nil),
          Blanket::LineCoverage.new(number: 5, status: :uncovered, spans: nil),
        ],
        functions: [Blanket::FunctionCoverage.new(name: "greet", line: 4, coverage: 50.0)],
        meta: {}
      )
    end

    let(:no_detail_file) do
      Blanket::FileCoverage.new(coverage: 100.0, covered_lines: nil, executable_lines: nil, lines: nil, functions: nil, meta: {})
    end

    let(:report) do
      Blanket::Report.new(
        project_coverage: 66.67,
        covered_lines: 2,
        executable_lines: 3,
        files: {
          "smoke_test/src/com/example/foo/Bar.kt" => bar_file,
          "smoke_test/src/no/such/file.rb" => no_detail_file,
        }
      )
    end

    around do |example|
      Dir.mktmpdir("blanket-html-report-spec") do |dir|
        @output_dir = File.join(dir, "coverage_report")
        example.run
      end
    end

    describe ".generate" do
      it "requires the report to carry covered_lines/executable_lines" do
        bare_report = Blanket::Report.new(project_coverage: 1.0, covered_lines: nil, executable_lines: nil, files: {})

        expect { described_class.generate(bare_report, @output_dir) }.to raise_error(ArgumentError, /covered_lines/)
      end

      it "writes report.json with project totals, per-file entries, and the changed flag" do
        described_class.generate(report, @output_dir, changed_files: ["smoke_test/src/com/example/foo/Bar.kt"])

        json = JSON.parse(File.read(File.join(@output_dir, "report.json")))

        expect(json["coveredLines"]).to eq(2)
        expect(json["executableLines"]).to eq(3)
        expect(json["lineCoverage"]).to be_within(0.001).of(2.0 / 3)

        bar = json["files"].find { |f| f["path"] == "smoke_test/src/com/example/foo/Bar.kt" }
        expect(bar).to include("coveredLines" => 2, "executableLines" => 3, "changed" => true)

        untouched = json["files"].find { |f| f["path"] == "smoke_test/src/no/such/file.rb" }
        expect(untouched).to include("changed" => false, "coveredLines" => 0, "executableLines" => 0)
      end

      it "copies the bundled SPA shell and patches the title into index.html" do
        described_class.generate(report, @output_dir, title: "My App Coverage")

        expect(File.read(File.join(@output_dir, "index.html"))).to include("My App Coverage")
        expect(File).to exist(File.join(@output_dir, "assets", "style.css"))
        expect(File).to exist(File.join(@output_dir, "assets", "app.js"))
      end

      it "writes a per-line HTML fragment for files with line detail, using their real source" do
        described_class.generate(report, @output_dir)

        fragment = File.read(File.join(@output_dir, "files", "smoke_test/src/com/example/foo/Bar.kt.html"))

        expect(fragment).to include('<tr id="L3" class="covered">')
        expect(fragment).to include('<tr id="L4" class="partial">')
        expect(fragment).to include('<tr id="L5" class="uncovered">')
        expect(fragment).to include('<tr id="L1" class="skipped">') # no explicit entry -> defaults to skipped
        expect(fragment).to include("1 uncovered line")
        expect(fragment).to include("greet")
        expect(fragment).to include("50.00%")
      end

      it "skips the fragment entirely for a file with no line detail" do
        described_class.generate(report, @output_dir)

        expect(File).not_to exist(File.join(@output_dir, "files", "smoke_test/src/no/such/file.rb.html"))
      end

      it "defaults the favicon link and the top-bar logo to their own bundled assets" do
        described_class.generate(report, @output_dir)

        index = File.read(File.join(@output_dir, "index.html"))
        expect(index).to include('<link rel="icon" href="assets/favicon.png" type="image/png">')
        expect(index).to include('<img src="assets/logo.png" class="top-bar-logo" alt="">')
      end

      it "copies a custom favicon under its own basename and links to it with the right mime type" do
        described_class.generate(report, @output_dir, favicon: fixture("custom_favicon.png"))

        expect(File).to exist(File.join(@output_dir, "assets", "custom_favicon.png"))
        index = File.read(File.join(@output_dir, "index.html"))
        expect(index).to include('<link rel="icon" href="assets/custom_favicon.png" type="image/png">')
        expect(index).to include('<img src="assets/logo.png" class="top-bar-logo" alt="">') # logo untouched
      end

      it "copies a custom logo independently from the favicon" do
        described_class.generate(report, @output_dir, favicon: fixture("custom_favicon.png"), logo: fixture("custom_logo.svg"))

        expect(File).to exist(File.join(@output_dir, "assets", "custom_logo.svg"))
        index = File.read(File.join(@output_dir, "index.html"))
        expect(index).to include('<link rel="icon" href="assets/custom_favicon.png" type="image/png">')
        expect(index).to include('<img src="assets/custom_logo.svg" class="top-bar-logo" alt="">')
      end

      it "raises a clear error when the given favicon/logo file doesn't exist" do
        expect { described_class.generate(report, @output_dir, favicon: fixture("does_not_exist.png")) }
          .to raise_error(ArgumentError, /does_not_exist\.png/)
      end

      it "uses a remote http(s):// favicon/logo URL as-is, with no download and no local copy" do
        described_class.generate(
          report, @output_dir,
          favicon: "https://cdn.example.com/icons/custom-remote-icon.png?v=2",
          logo: "https://cdn.example.com/brand/custom-remote-logo.svg"
        )

        index = File.read(File.join(@output_dir, "index.html"))
        expect(index).to include('<link rel="icon" href="https://cdn.example.com/icons/custom-remote-icon.png?v=2" type="image/png">')
        expect(index).to include('<img src="https://cdn.example.com/brand/custom-remote-logo.svg" class="top-bar-logo" alt="">')
        expect(Dir.glob(File.join(@output_dir, "assets", "*")))
          .not_to include(a_string_matching(/custom-remote-icon\.png|custom-remote-logo\.svg/))
      end
    end

    describe ".link_for" do
      it "builds a bare URL addressed by path via the hash router" do
        expect(described_class.link_for("Sources/Foo.swift", "https://example.com/report"))
          .to eq("https://example.com/report/index.html#Sources/Foo.swift")
      end

      it "appends the line anchor when first_uncovered_line is given" do
        expect(described_class.link_for("Sources/Foo.swift", "https://example.com/report", first_uncovered_line: 42))
          .to eq("https://example.com/report/index.html#Sources/Foo.swift:42")
      end
    end
  end
end
