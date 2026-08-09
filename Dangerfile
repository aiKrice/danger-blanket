$LOAD_PATH.unshift(File.join(__dir__, "lib"))
require "danger_plugin"

blanket.report_file = "spec/fixtures/kover_report.xml"
blanket.parser = :kover
blanket.parser_options = { source_root: "smoke_test/src" }
blanket.project_threshold = 50
blanket.file_threshold = 85
blanket.warning_as_error = false
blanket.html_report_dir = "smoke_test/coverage_report"
blanket.html_report_title = "danger-blanket smoke test coverage"
blanket.hosted_report_base_url = "https://example.com/coverage_report"
blanket.report
