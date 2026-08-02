require File.expand_path("spec_helper", __dir__)

module Danger
  describe Danger::DangerBlanket do
    it "is a plugin" do
      expect(Danger::DangerBlanket.new(nil)).to be_a Danger::Plugin
    end

    describe "with Dangerfile" do
      before do
        @dangerfile = testing_dangerfile
        @blanket = @dangerfile.blanket
      end

      it "defaults parser_options, file_threshold_overrides and warning_as_error" do
        expect(@blanket.parser_options).to eq({})
        expect(@blanket.file_threshold_overrides).to eq({})
        expect(@blanket.warning_as_error).to eq(false)
      end

      describe "#report" do
        it "does nothing when report_file is nil" do
          @blanket.report_file = nil
          @blanket.parser = :json

          @blanket.report

          expect(@dangerfile.status_report[:errors]).to eq([])
          expect(@dangerfile.status_report[:warnings]).to eq([])
        end

        it "does nothing when report_file doesn't exist on disk" do
          @blanket.report_file = fixture("does_not_exist.json")
          @blanket.parser = :json

          @blanket.report

          expect(@dangerfile.status_report[:errors]).to eq([])
          expect(@dangerfile.status_report[:warnings]).to eq([])
        end

        it "raises when no parser is configured" do
          @blanket.report_file = fixture("coverage_report.json")

          expect { @blanket.report }.to raise_error(ArgumentError, /blanket\.parser must be set/)
        end

        it "raises for an unknown parser symbol" do
          @blanket.report_file = fixture("coverage_report.json")
          @blanket.parser = :lcov

          expect { @blanket.report }.to raise_error(ArgumentError, /Unknown blanket parser/)
        end

        it "accepts a custom parser instance instead of a built-in symbol" do
          custom_parser = Class.new(Blanket::Parsers::Base) do
            def parse(_report_file)
              Blanket::Report.new(project_coverage: 99.0, files: {})
            end
          end.new

          @blanket.report_file = fixture("coverage_report.json")
          @blanket.parser = custom_parser
          @blanket.project_threshold = 100

          @blanket.report

          expect(@dangerfile.status_report[:warnings]).to eq(["🔴 Project line coverage is 99.0%, below the required 100%."])
        end

        describe "project threshold" do
          before do
            @blanket.report_file = fixture("coverage_report.json")
            @blanket.parser = :json
            allow(@blanket.git).to receive(:modified_files).and_return([])
            allow(@blanket.git).to receive(:added_files).and_return([])
          end

          it "is skipped when project_threshold is nil" do
            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "warns by default when project coverage is below the threshold" do
            @blanket.project_threshold = 50

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq(["🔴 Project line coverage is 42.5%, below the required 50%."])
            expect(@dangerfile.status_report[:errors]).to eq([])
          end

          it "fails instead of warning when warning_as_error is true" do
            @blanket.project_threshold = 50
            @blanket.warning_as_error = true

            @blanket.report

            expect(@dangerfile.status_report[:errors]).to eq(["🔴 Project line coverage is 42.5%, below the required 50%."])
            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "doesn't fire when project coverage is at or above the threshold" do
            @blanket.project_threshold = 42.5

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
          end
        end

        describe "file thresholds" do
          before do
            @blanket.report_file = fixture("coverage_report.json")
            @blanket.parser = :json
            @blanket.file_threshold = 85
            allow(@blanket.git).to receive(:modified_files).and_return(["lib/foo.rb"])
            allow(@blanket.git).to receive(:added_files).and_return(["lib/bar.rb"])
          end

          it "ignores files that aren't in the report" do
            allow(@blanket.git).to receive(:modified_files).and_return(["lib/not_in_report.rb"])
            allow(@blanket.git).to receive(:added_files).and_return([])

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "ignores files in the report that weren't modified or added" do
            allow(@blanket.git).to receive(:modified_files).and_return([])
            allow(@blanket.git).to receive(:added_files).and_return([])

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "flags modified/added files below the threshold, using the parser's html_link when available" do
            @blanket.report

            markdown = @dangerfile.status_report[:markdowns].first.to_s
            expect(markdown).to include("[lib/foo.rb](https://reports.example.com/coverage/foo.html) | 60.0% | 85%")
            expect(@dangerfile.status_report[:warnings]).to eq(["1 file(s) below their coverage threshold, see table above."])
          end

          it "falls back to a plain GitHub link when the parser has none" do
            @blanket.file_threshold = 95 # also puts lib/bar.rb (90.0%) below threshold
            allow(@blanket.github).to receive(:html_link).with("lib/bar.rb").and_return("[lib/bar.rb](https://github.com/org/repo/blob/sha/lib/bar.rb)")

            @blanket.report

            markdown = @dangerfile.status_report[:markdowns].first.to_s
            expect(markdown).to include("[lib/bar.rb](https://github.com/org/repo/blob/sha/lib/bar.rb) | 90.0% | 95%")
          end

          it "fails instead of warning when warning_as_error is true" do
            @blanket.warning_as_error = true

            @blanket.report

            expect(@dangerfile.status_report[:errors]).to eq(["1 file(s) below their coverage threshold, see table above."])
            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "is skipped entirely when file_threshold is nil" do
            @blanket.file_threshold = nil

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
            expect(@dangerfile.status_report[:markdowns]).to eq([])
          end

          it "uses file_threshold_overrides instead of the default threshold, and labels it as an override" do
            @blanket.file_threshold_overrides = { "lib/foo.rb" => 50 }

            @blanket.report

            expect(@dangerfile.status_report[:warnings]).to eq([])
          end

          it "still flags a file below its override threshold, and marks the row as an override" do
            @blanket.file_threshold_overrides = { "lib/foo.rb" => 70 }

            @blanket.report

            markdown = @dangerfile.status_report[:markdowns].first.to_s
            expect(markdown).to include("60.0% | 70% (override)")
          end
        end
      end

      describe "#scm_html_link (private)" do
        # Host plugins (github/gitlab/bitbucket_*) are only registered on the
        # Dangerfile when running against a real PR/MR (see
        # Dangerfile#initialize's `refresh_plugins if env_manager.pr?`), so
        # these tests use a bare double instead of the shared @dangerfile to
        # simulate that absence, eg. under `danger dry_run`/`danger local`.
        it "delegates to whichever host plugin is registered, not just github" do
          fake_dangerfile = double("Dangerfile")
          allow(fake_dangerfile).to receive(:respond_to?) { |name| name == :gitlab }
          gitlab = double("gitlab", html_link: "https://gitlab.example.com/org/repo/-/blob/sha/lib/foo.rb")
          allow(fake_dangerfile).to receive(:gitlab).and_return(gitlab)

          blanket = Danger::DangerBlanket.new(fake_dangerfile)

          expect(blanket.send(:scm_html_link, "lib/foo.rb")).to eq("https://gitlab.example.com/org/repo/-/blob/sha/lib/foo.rb")
        end

        it "falls back to the plain file path when no host plugin is registered" do
          fake_dangerfile = double("Dangerfile")
          allow(fake_dangerfile).to receive(:respond_to?).and_return(false)

          blanket = Danger::DangerBlanket.new(fake_dangerfile)

          expect(blanket.send(:scm_html_link, "lib/foo.rb")).to eq("lib/foo.rb")
        end
      end
    end
  end
end
