require File.expand_path("../spec_helper", __dir__)
require "tempfile"

module Danger
  describe Blanket::Parsers::Kover do
    it "requires a :source_root option" do
      expect { described_class.new }.to raise_error(ArgumentError, /:source_root/)
    end

    describe "#parse" do
      subject(:parser) { described_class.new(source_root: "app/src/main/java") }
      let(:report) { parser.parse(fixture("kover_report.xml")) }

      it "returns the project line coverage as a percentage, plus raw line counts" do
        expect(report.project_coverage).to eq(50.0)
        expect(report.covered_lines).to eq(3)
        expect(report.executable_lines).to eq(6)
      end

      it "returns per-file coverage as a percentage, keyed by full source path" do
        expect(report.files["app/src/main/java/com/example/foo/Bar.kt"].coverage).to eq(66.67)
        expect(report.files["app/src/main/java/com/example/foo/Baz.kt"].coverage).to eq(0.0)
        expect(report.files["app/src/main/java/com/example/foo/Legacy.java"].coverage).to eq(100.0)
      end

      it "returns per-file raw line counts" do
        bar = report.files["app/src/main/java/com/example/foo/Bar.kt"]
        expect(bar.covered_lines).to eq(2)
        expect(bar.executable_lines).to eq(3)
      end

      it "returns per-line status straight from the report's <line> data" do
        bar = report.files["app/src/main/java/com/example/foo/Bar.kt"]

        expect(bar.lines).to contain_exactly(
          Blanket::LineCoverage.new(number: 3, status: :covered, spans: nil),
          Blanket::LineCoverage.new(number: 4, status: :partial, spans: nil),
          Blanket::LineCoverage.new(number: 5, status: :uncovered, spans: nil)
        )
      end

      it "classifies a mi>0/ci==0 line as :uncovered" do
        baz = report.files["app/src/main/java/com/example/foo/Baz.kt"]

        expect(baz.lines.map(&:status)).to eq([:uncovered, :uncovered])
      end

      it "resolves first_uncovered_line to the first fully-uncovered line, not a partial one" do
        expect(report.files["app/src/main/java/com/example/foo/Bar.kt"].first_uncovered_line).to eq(5)
        expect(report.files["app/src/main/java/com/example/foo/Baz.kt"].first_uncovered_line).to eq(3)
      end

      it "is nil when every line is covered" do
        expect(report.files["app/src/main/java/com/example/foo/Legacy.java"].first_uncovered_line).to be_nil
      end

      it "returns per-function coverage from the sibling <class> element, dropping fully-covered methods" do
        bar = report.files["app/src/main/java/com/example/foo/Bar.kt"]
        baz = report.files["app/src/main/java/com/example/foo/Baz.kt"]

        expect(bar.functions).to eq([Blanket::FunctionCoverage.new(name: "greet", line: 4, coverage: 50.0)])
        expect(baz.functions).to eq([Blanket::FunctionCoverage.new(name: "greet", line: 4, coverage: 0.0)])
      end

      it "returns an empty functions array when no <class> matches the sourcefile" do
        expect(report.files["app/src/main/java/com/example/foo/Legacy.java"].functions).to eq([])
      end

      it "merges methods from multiple classes that share one sourcefile (eg. two top-level Kotlin classes)" do
        xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <report name="report">
            <counter type="LINE" missed="0" covered="2"/>
            <package name="com/example/foo">
              <class name="com/example/foo/First" sourcefilename="Shared.kt">
                <method name="first" line="1">
                  <counter type="LINE" missed="1" covered="0"/>
                </method>
              </class>
              <class name="com/example/foo/Second" sourcefilename="Shared.kt">
                <method name="second" line="5">
                  <counter type="LINE" missed="0" covered="1"/>
                </method>
              </class>
              <sourcefile name="Shared.kt">
                <line nr="1" mi="1" ci="0"/>
                <line nr="5" mi="0" ci="1"/>
                <counter type="LINE" missed="1" covered="1"/>
              </sourcefile>
            </package>
          </report>
        XML

        Tempfile.create(["kover", ".xml"]) do |file|
          file.write(xml)
          file.flush

          merged = parser.parse(file.path).files["app/src/main/java/com/example/foo/Shared.kt"]
          expect(merged.functions).to eq([Blanket::FunctionCoverage.new(name: "first", line: 1, coverage: 0.0)])
        end
      end
    end
  end
end
