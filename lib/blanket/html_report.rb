require "fileutils"
require "json"
require "set"
require "uri"
require "blanket/report"

module Danger
  module Blanket
    # Renders a normalized Report into a static, browsable single-page-app
    # coverage site — the one thing every parser that supports line-level
    # detail (see FileCoverage#lines) can share, regardless of platform.
    # Adding a new platform/tool only means writing a parser that populates
    # FileCoverage#lines/#functions; this renderer doesn't change.
    #
    # Output layout (self-contained, ready to be hosted as static files):
    #   <output_dir>/report.json   summary consumed by app.js (sidebar + stats)
    #   <output_dir>/index.html    the SPA shell (static, copied as-is)
    #   <output_dir>/assets/       favicon, stylesheet, app.js (static, copied as-is)
    #   <output_dir>/files/<path>.html
    #                               one HTML fragment per file that has line
    #                               detail (a per-function breakdown + the
    #                               line-by-line table) - fetched and
    #                               injected into the shell's content pane,
    #                               not a standalone page.
    module HtmlReport
      ASSETS_DIR = File.expand_path("html_report/assets", __dir__)
      DEFAULT_FAVICON = "assets/favicon.png"
      DEFAULT_LOGO = "assets/logo.png"

      MIME_TYPES = {
        ".svg" => "image/svg+xml",
        ".png" => "image/png",
        ".ico" => "image/x-icon",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp",
      }.freeze

      REMOTE_URL = %r{\Ahttps?://}i.freeze

      class << self
        # @param report [Danger::Blanket::Report] must have covered_lines/
        #   executable_lines set (ie. came from a parser that supports
        #   line-level detail, eg. Parsers::Kover or Parsers::Xccov).
        # @param output_dir [String] wiped and rewritten on every call.
        # @param changed_files [Array<String>] paths (matching Report#files'
        #   keys) to mark with `changed: true`, powering the "changed in
        #   this PR" sidebar filter. Typically `git.modified_files + git.added_files`.
        # @param title [String] shown in the top bar and browser tab.
        # @param favicon [String, nil] a local image file path (svg/png/
        #   ico/jpg/gif/webp), copied into the report's own assets/ dir, or
        #   an `http(s)://` URL, used as-is with no download/copy — to use
        #   as the browser-tab icon, instead of the bundled default.
        #   Independent from `logo:` — set one, both, or neither.
        # @param logo [String, nil] same as `favicon:` (local path or
        #   `http(s)://` URL), but for the top-bar logo shown inside the
        #   report itself.
        # @return [String] output_dir
        def generate(report, output_dir, changed_files: [], title: "Coverage Report", favicon: nil, logo: nil)
          if report.covered_lines.nil? || report.executable_lines.nil?
            raise ArgumentError, "Blanket::HtmlReport.generate requires a Report with covered_lines/executable_lines set " \
                                  "(the parser must support line-level detail, eg. Parsers::Kover or Parsers::Xccov)"
          end

          changed = changed_files.to_set

          FileUtils.rm_rf(output_dir)
          FileUtils.mkdir_p(File.join(output_dir, "files"))
          FileUtils.cp_r(Dir.glob(File.join(ASSETS_DIR, "*")), output_dir)

          favicon_href = resolve_asset(favicon, output_dir) || DEFAULT_FAVICON
          logo_src = resolve_asset(logo, output_dir) || DEFAULT_LOGO
          patch_shell(output_dir, title: title, favicon_href: favicon_href, logo_src: logo_src)

          write_report_json(report, output_dir, changed)
          write_file_fragments(report, output_dir)

          output_dir
        end

        # Bare URL pointing at a file's section of a report written by
        # {generate} — deterministic, since this module owns both ends
        # (what it writes and how it's addressed), unlike a parser having
        # to scrape someone else's generated HTML for an anchor.
        def link_for(file_path, base_url, first_uncovered_line: nil)
          anchor = first_uncovered_line ? ":#{first_uncovered_line}" : ""
          "#{base_url}/index.html##{file_path}#{anchor}"
        end

        private

        # Resolves a custom favicon/logo source into the href/src to use —
        # nil (the caller falls back to its own default, DEFAULT_FAVICON or
        # DEFAULT_LOGO) when nothing was given, the URL itself as-is for an
        # http(s):// source (no download: keeps report generation
        # network-free, and the dev keeps full control over hosting), or a
        # local file copied into the report's own assets/ dir under its
        # original basename otherwise.
        def resolve_asset(source, output_dir)
          return nil if source.nil?
          return source if source.match?(REMOTE_URL)
          raise ArgumentError, "Blanket::HtmlReport.generate: no such file #{source.inspect}" unless File.file?(source)

          basename = File.basename(source)
          FileUtils.cp(source, File.join(output_dir, "assets", basename))
          "assets/#{basename}"
        end

        def patch_shell(output_dir, title:, favicon_href:, logo_src:)
          index_path = File.join(output_dir, "index.html")
          content = File.read(index_path)
          content = content.gsub("__BLANKET_TITLE__", html_escape(title))
          content = content.gsub("__BLANKET_FAVICON_HREF__", html_escape(favicon_href))
          content = content.gsub("__BLANKET_FAVICON_TYPE__", mime_type_for(favicon_href))
          content = content.gsub("__BLANKET_LOGO_SRC__", html_escape(logo_src))
          File.write(index_path, content)
        end

        # Best-effort guess from the extension — for a URL, extname has to
        # run against just the path component, or a query string like
        # "?v=2" would swallow it (".png?v=2" isn't a recognized extension).
        def mime_type_for(href)
          path = href.match?(REMOTE_URL) ? url_path(href) : href
          MIME_TYPES[File.extname(path).downcase] || "application/octet-stream"
        end

        def url_path(url)
          URI.parse(url).path
        rescue URI::InvalidURIError
          url
        end

        def write_report_json(report, output_dir, changed)
          files_json = report.files.map do |path, file_coverage|
            {
              path: path,
              coveredLines: file_coverage.covered_lines || 0,
              executableLines: file_coverage.executable_lines || 0,
              lineCoverage: (file_coverage.coverage || 0).to_f / 100,
              changed: changed.include?(path),
            }
          end

          project_line_coverage = report.executable_lines.zero? ? 0.0 : report.covered_lines.to_f / report.executable_lines

          payload = {
            coveredLines: report.covered_lines,
            executableLines: report.executable_lines,
            lineCoverage: project_line_coverage,
            files: files_json,
          }
          File.write(File.join(output_dir, "report.json"), JSON.generate(payload))
        end

        # Only files with line-level detail get a fragment - a file with
        # just a percentage (eg. from a parser that doesn't support the
        # detailed contract) still shows up in report.json/the sidebar, but
        # clicking it degrades to app.js's own "Could not load" message.
        def write_file_fragments(report, output_dir)
          report.files.each do |path, file_coverage|
            next if file_coverage.lines.nil?

            fragment_path = File.join(output_dir, "files", "#{path}.html")
            FileUtils.mkdir_p(File.dirname(fragment_path))
            File.write(fragment_path, file_fragment_html(path, file_coverage))
          end
        end

        def file_fragment_html(path, file_coverage)
          source_path = File.join(Dir.pwd, path)
          source_lines = File.file?(source_path) ? File.readlines(source_path) : []
          lines_by_number = file_coverage.lines.each_with_object({}) { |line, acc| acc[line.number] = line }

          +"" << file_header_html(path, file_coverage) \
            << function_breakdown_html(file_coverage.functions) \
            << "<table class=\"source-table\">\n" \
            << source_table_rows(source_lines, lines_by_number) \
            << "</table>\n"
        end

        def file_header_html(path, file_coverage)
          pct = file_coverage.coverage || 0
          uncovered_count = file_coverage.lines.count { |line| line.status == :uncovered }

          uncovered_link = ""
          if uncovered_count.positive? && file_coverage.first_uncovered_line
            suffix = uncovered_count == 1 ? "" : "s"
            # data-i18n-plural/-count let app.js re-render this in the
            # viewer's own locale after the fragment is injected; the
            # English text is only the pre-JS fallback.
            uncovered_link = "<a class=\"function-jump uncovered-count\" data-line=\"#{file_coverage.first_uncovered_line}\" " \
                              "data-i18n-plural=\"uncovered_lines\" data-i18n-count=\"#{uncovered_count}\">" \
                              "#{uncovered_count} uncovered line#{suffix}</a>"
          end

          "<div class=\"file-header\">" \
            "<span class=\"file-header-titles\">" \
            "<span class=\"file-header-name\">#{html_escape(File.basename(path))}" \
            "<button class=\"copy-path-btn\" data-path=\"#{html_escape(path)}\" " \
            "data-i18n-title=\"copy_full_path\" data-i18n-aria-label=\"copy_full_path\" title=\"Copy full path\" aria-label=\"Copy full path\">" \
            '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' \
            'stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"></rect>' \
            '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>' \
            "</button></span>" \
            "<span class=\"file-header-path\">#{html_escape(path)}</span>" \
            "</span>" \
            "<span class=\"file-header-right\">#{uncovered_link}" \
            "<span class=\"file-row-pct #{pct_class(pct)}\">#{format('%.2f', pct)}%</span></span>" \
            "</div>\n"
        end

        def function_breakdown_html(functions)
          return "" if functions.nil? || functions.empty?

          rows = functions.map do |fn|
            "<tr><td><a class=\"function-jump\" data-line=\"#{fn.line}\">#{html_escape(fn.name)}</a></td>" \
              "<td>L#{fn.line}</td><td class=\"#{pct_class(fn.coverage)}\">#{format('%.2f', fn.coverage)}%</td></tr>"
          end.join

          "<div class=\"function-breakdown\"><table><tr>" \
            "<th data-i18n=\"table_function\">Function</th>" \
            "<th data-i18n=\"table_line\">Line</th>" \
            "<th data-i18n=\"table_coverage\">Coverage</th>" \
            "</tr>#{rows}</table></div>\n"
        end

        def source_table_rows(source_lines, lines_by_number)
          rows = +""
          source_lines.each_with_index do |text, index|
            number = index + 1
            line = lines_by_number[number]
            status = line&.status || :skipped
            content = render_line_content(text.chomp, line&.spans)
            rows << "<tr id=\"L#{number}\" class=\"#{status}\"><td class=\"line-number\">#{number}</td><td>#{content}</td></tr>\n"
          end
          rows
        end

        # Renders a line's text, wrapping any never-executed sub-line spans
        # (xccov only — see Span) in their own highlight, on top of the
        # line's own covered/uncovered/partial/skipped background.
        def render_line_content(text, spans)
          return html_escape(text) if spans.nil? || spans.empty?

          result = +""
          pos = 1
          spans.sort_by(&:column).each do |span|
            result << html_escape(text[(pos - 1)...(span.column - 1)].to_s) if span.column > pos
            result << "<span class=\"uncovered-span\">#{html_escape(text[(span.column - 1)...(span.column - 1 + span.length)].to_s)}</span>"
            pos = span.column + span.length
          end
          result << html_escape(text[(pos - 1)..].to_s)
          result
        end

        def pct_class(pct)
          if pct >= 80
            "pct-good"
          elsif pct >= 45
            "pct-warning"
          else
            "pct-critical"
          end
        end

        def html_escape(text)
          text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        end
      end
    end
  end
end
