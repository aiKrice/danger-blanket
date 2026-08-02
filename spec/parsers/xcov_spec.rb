require File.expand_path("../spec_helper", __dir__)

module Danger
  describe Blanket::Parsers::Xcov do
    it "requires a :target option" do
      expect { described_class.new }.to raise_error(ArgumentError, /:target/)
    end

    describe "#parse" do
      subject(:parser) { described_class.new(target: "MyApp.app") }

      it "returns the project coverage as a percentage" do
        report = parser.parse(fixture("xcov_report.json"))

        expect(report.project_coverage).to eq(42.5)
      end

      it "returns per-file coverage as a percentage, keyed by path" do
        report = parser.parse(fixture("xcov_report.json"))

        expect(report.files["Sources/Foo.swift"].coverage).to eq(60.0)
        expect(report.files["Sources/Bar.swift"].coverage).to eq(90.0)
      end

      it "returns an empty report when the target isn't found" do
        other_parser = described_class.new(target: "DoesNotExist.app")

        report = other_parser.parse(fixture("xcov_report.json"))

        expect(report.project_coverage).to be_nil
        expect(report.files).to eq({})
      end
    end

    describe "#html_link" do
      it "resolves the file-id anchor scraped from the report's index.html" do
        parser = described_class.new(target: "MyApp.app", html_dir: fixture("xcov_html"))
        report = parser.parse(fixture("xcov_report.json"))

        link = parser.html_link(report.files["Sources/Foo.swift"], "https://example.com/report")

        expect(link).to eq("https://example.com/report/index.html#a1b2c3")
      end

      it "returns nil when html_dir isn't configured" do
        parser = described_class.new(target: "MyApp.app")
        report = parser.parse(fixture("xcov_report.json"))

        expect(parser.html_link(report.files["Sources/Foo.swift"], "https://example.com/report")).to be_nil
      end

      it "returns nil when hosted_report_base_url isn't given" do
        parser = described_class.new(target: "MyApp.app", html_dir: fixture("xcov_html"))
        report = parser.parse(fixture("xcov_report.json"))

        expect(parser.html_link(report.files["Sources/Foo.swift"], nil)).to be_nil
      end
    end
  end
end
