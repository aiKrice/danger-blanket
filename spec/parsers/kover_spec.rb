require File.expand_path("../spec_helper", __dir__)

module Danger
  describe Blanket::Parsers::Kover do
    it "requires a :source_root option" do
      expect { described_class.new }.to raise_error(ArgumentError, /:source_root/)
    end

    describe "#parse" do
      subject(:parser) { described_class.new(source_root: "app/src/main/java") }

      it "returns the project line coverage as a percentage" do
        report = parser.parse(fixture("kover_report.xml"))

        expect(report.project_coverage).to eq(40.0)
      end

      it "returns per-file coverage as a percentage, keyed by full source path" do
        report = parser.parse(fixture("kover_report.xml"))

        expect(report.files["app/src/main/java/com/example/foo/Bar.kt"].coverage).to eq(90.0)
        expect(report.files["app/src/main/java/com/example/foo/Baz.kt"].coverage).to eq(20.0)
      end
    end

    describe "#html_link" do
      it "walks the package -> ns-X -> source-N.html indexes to resolve a link" do
        parser = described_class.new(source_root: "app/src/main/java", html_dir: fixture("kover_html"))
        report = parser.parse(fixture("kover_report.xml"))

        link = parser.html_link(report.files["app/src/main/java/com/example/foo/Bar.kt"], "https://example.com/report")

        expect(link).to eq("https://example.com/report/ns-1a2b3c4d/sources/source-abcdef12.html")
      end

      it "returns nil when the package isn't found in the report's index" do
        parser = described_class.new(source_root: "app/src/main/java", html_dir: fixture("kover_html"))
        report = parser.parse(fixture("kover_report.xml"))
        report.files["unknown/Missing.kt"] = Blanket::FileCoverage.new(coverage: 0.0, meta: { package: "com.unknown", sourcefile: "Missing.kt" })

        expect(parser.html_link(report.files["unknown/Missing.kt"], "https://example.com/report")).to be_nil
      end

      it "returns nil when html_dir isn't configured" do
        parser = described_class.new(source_root: "app/src/main/java")
        report = parser.parse(fixture("kover_report.xml"))

        expect(parser.html_link(report.files["app/src/main/java/com/example/foo/Bar.kt"], "https://example.com/report")).to be_nil
      end
    end
  end
end
