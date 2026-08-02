require File.expand_path("../spec_helper", __dir__)
require "tempfile"
require "json"

module Danger
  describe Blanket::Parsers::Json do
    subject(:parser) { described_class.new }

    describe "#parse" do
      it "returns the project coverage as-is" do
        report = parser.parse(fixture("coverage_report.json"))

        expect(report.project_coverage).to eq(42.5)
      end

      it "returns per-file coverage keyed by path" do
        report = parser.parse(fixture("coverage_report.json"))

        expect(report.files["lib/foo.rb"].coverage).to eq(60.0)
        expect(report.files["lib/bar.rb"].coverage).to eq(90.0)
      end

      it "skips entries missing a path or a coverage value" do
        Tempfile.create(["report", ".json"]) do |file|
          file.write({ files: [{ path: "lib/foo.rb" }, { coverage: 10 }] }.to_json)
          file.flush

          report = parser.parse(file.path)

          expect(report.files).to eq({})
        end
      end
    end

    describe "#html_link" do
      it "returns the html_link carried in the report, when present" do
        report = parser.parse(fixture("coverage_report.json"))

        expect(parser.html_link(report.files["lib/foo.rb"], nil)).to eq("https://reports.example.com/coverage/foo.html")
      end

      it "returns nil when the report didn't provide one" do
        report = parser.parse(fixture("coverage_report.json"))

        expect(parser.html_link(report.files["lib/bar.rb"], nil)).to be_nil
      end
    end
  end
end
