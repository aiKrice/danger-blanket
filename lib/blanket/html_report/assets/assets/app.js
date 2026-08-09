(function () {
  "use strict";

  var sidebar = document.getElementById("sidebar");
  var content = document.getElementById("content");
  var projectStat = document.getElementById("project-stat");
  var topBarBrand = document.getElementById("top-bar-brand");
  var searchWrapper = document.getElementById("search-wrapper");
  var searchInput = document.getElementById("search-input");
  var searchClear = document.getElementById("search-clear");
  var themeToggle = document.getElementById("theme-toggle");
  var attentionFilter = document.getElementById("needs-attention-filter");
  var changedOnlyFilter = document.getElementById("changed-only-filter");
  var changedOnlyRow = document.getElementById("changed-only-row");

  // Translates the static shell (search/filters/toolbar - see their
  // data-i18n* attributes in index.html) up front. Per-file fragments get
  // their own pass in loadFile(), once fetched.
  BlanketI18n.applyTranslations(document);

  var currentReport = null;
  var currentFilter = "";
  var currentAttentionOnly = false;
  var currentChangedOnly = false;
  var fileTree = null; // built once from report.json, folder rollups computed over ALL files (filters only hide, never recompute, a node)

  // Matches the pct-good boundary used for the sidebar badge color, so
  // "needs attention" means exactly "not already green".
  var ATTENTION_THRESHOLD = 0.8;
  var THEME_STORAGE_KEY = "blanket-coverage-theme";
  var SUN_ICON = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"></path></svg>';
  var MOON_ICON = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"></path></svg>';

  function effectiveTheme() {
    var stored = null;
    try {
      stored = localStorage.getItem(THEME_STORAGE_KEY);
    } catch (e) {}
    if (stored === "light" || stored === "dark") return stored;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function renderThemeIcon() {
    themeToggle.innerHTML = effectiveTheme() === "dark" ? SUN_ICON : MOON_ICON;
  }

  themeToggle.addEventListener("click", function () {
    var next = effectiveTheme() === "dark" ? "light" : "dark";
    try {
      localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch (e) {}
    document.documentElement.setAttribute("data-theme", next);
    renderThemeIcon();
  });

  renderThemeIcon();

  function pctClass(pct) {
    if (pct >= 80) return "pct-good";
    if (pct >= 45) return "pct-warning";
    return "pct-critical";
  }

  function escapeHtml(text) {
    var div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  function basename(path) {
    var parts = path.split("/");
    return parts[parts.length - 1];
  }

  // Builds a folder tree from report.json's flat file list, one node per
  // path segment. Rollup stats (coveredLines/executableLines/lineCoverage,
  // whether any descendant changed) are computed bottom-up once here, over
  // every file — filters only ever hide nodes at render time, they never
  // change what a folder's badge says.
  function buildTree(files) {
    var root = { name: "", path: "", type: "folder", children: {} };

    files.forEach(function (f) {
      var parts = f.path.split("/");
      var node = root;
      var pathSoFar = "";

      parts.forEach(function (part, i) {
        pathSoFar = pathSoFar ? pathSoFar + "/" + part : part;
        var isFile = i === parts.length - 1;

        if (!node.children[part]) {
          node.children[part] = isFile
            ? { name: part, path: pathSoFar, type: "file", file: f }
            : { name: part, path: pathSoFar, type: "folder", children: {} };
        }
        node = node.children[part];
      });
    });

    finalizeTree(root);
    return root;
  }

  // Folders sort alphabetically (a predictable, browsable order); files
  // within a folder sort worst-coverage-first (same "what needs attention"
  // priority the flat list used to have, kept where it matters most - the
  // leaves).
  function finalizeTree(node) {
    var childArray = Object.keys(node.children).map(function (key) {
      var child = node.children[key];
      return child.type === "folder" ? finalizeTree(child) : child;
    });

    childArray.sort(function (a, b) {
      if (a.type !== b.type) return a.type === "folder" ? -1 : 1;
      return a.type === "folder" ? a.name.localeCompare(b.name) : a.file.lineCoverage - b.file.lineCoverage;
    });

    var covered = 0;
    var executable = 0;
    var changed = false;
    childArray.forEach(function (child) {
      var stats = child.type === "file" ? child.file : child;
      covered += stats.coveredLines;
      executable += stats.executableLines;
      changed = changed || stats.changed;
    });

    node.children = childArray;
    node.coveredLines = covered;
    node.executableLines = executable;
    node.lineCoverage = executable === 0 ? 0 : covered / executable;
    node.changed = changed;
    return node;
  }

  function fileMatchesFilter(f) {
    if (currentAttentionOnly && f.lineCoverage >= ATTENTION_THRESHOLD) return false;
    if (currentChangedOnly && !f.changed) return false;
    if (currentFilter && f.path.toLowerCase().indexOf(currentFilter.toLowerCase()) === -1) return false;
    return true;
  }

  // Returns a pruned copy of `node` containing only branches with at least
  // one matching file, or null if nothing under it matches. Rollup stats
  // are carried over as-is (unfiltered) so a folder's badge always reflects
  // its true coverage, not just the visible subset.
  function prune(node) {
    if (node.type === "file") {
      return fileMatchesFilter(node.file) ? node : null;
    }

    var visibleChildren = node.children.map(prune).filter(Boolean);
    if (visibleChildren.length === 0) return null;

    return {
      name: node.name,
      path: node.path,
      type: "folder",
      children: visibleChildren,
      coveredLines: node.coveredLines,
      executableLines: node.executableLines,
      lineCoverage: node.lineCoverage,
      changed: node.changed,
    };
  }

  function fileRowHtml(f) {
    var pct = (f.lineCoverage * 100).toFixed(2);
    var changedDot = f.changed ? '<span class="file-row-changed-dot" title="' + escapeHtml(BlanketI18n.t("changed_in_pr")) + '"></span>' : "";
    return (
      '<a class="file-row" data-path="' +
      escapeHtml(f.path) +
      '" href="#' +
      escapeHtml(f.path) +
      '">' +
      changedDot +
      '<span class="file-row-path" title="' +
      escapeHtml(f.path) +
      '">' +
      escapeHtml(basename(f.path)) +
      '</span><span class="file-row-pct ' +
      pctClass(pct) +
      '">' +
      pct +
      "%</span></a>"
    );
  }

  // `forceOpen` is true while a search/filter is active (every rendered
  // folder already contains a match, so reveal it outright); otherwise only
  // the top level starts expanded and deeper folders wait to be clicked.
  function renderTreeChildren(children, forceOpen, depth) {
    return children
      .map(function (node) {
        if (node.type === "file") return fileRowHtml(node.file);

        var pct = (node.lineCoverage * 100).toFixed(2);
        var changedDot = node.changed
          ? '<span class="file-row-changed-dot" title="' + escapeHtml(BlanketI18n.t("folder_changed_title")) + '"></span>'
          : "";
        var openAttr = forceOpen || depth === 0 ? " open" : "";

        return (
          '<details class="tree-folder"' +
          openAttr +
          '><summary class="tree-folder-header">' +
          '<svg class="tree-toggle-icon" width="10" height="10" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5l8 7-8 7z"></path></svg>' +
          changedDot +
          '<span class="tree-folder-name" title="' +
          escapeHtml(node.path) +
          '">' +
          escapeHtml(node.name) +
          '</span><span class="file-row-pct ' +
          pctClass(pct) +
          '">' +
          pct +
          "%</span></summary>" +
          '<div class="tree-children">' +
          renderTreeChildren(node.children, forceOpen, depth + 1) +
          "</div></details>"
        );
      })
      .join("");
  }

  function renderSidebar() {
    var visibleRoot = prune(fileTree);

    if (!visibleRoot) {
      var message = currentFilter
        ? BlanketI18n.t("empty_matches", { query: currentFilter })
        : currentChangedOnly
          ? BlanketI18n.t(currentAttentionOnly ? "empty_changed_in_pr_attention" : "empty_changed_in_pr")
          : BlanketI18n.t("empty_needs_attention");
      sidebar.innerHTML = '<div class="sidebar-empty">' + escapeHtml(message) + "</div>";
      return;
    }

    var isFiltering = !!(currentFilter || currentAttentionOnly || currentChangedOnly);
    sidebar.innerHTML = renderTreeChildren(visibleRoot.children, isFiltering, 0);

    setActiveRow(parseHash().path);
  }

  function statLine(report) {
    return BlanketI18n.t("top_bar_stat", {
      pct: (report.lineCoverage * 100).toFixed(2),
      covered: report.coveredLines.toLocaleString(),
      executable: report.executableLines.toLocaleString(),
    });
  }

  // Marks the active row, and - since a file can now be nested several
  // folders deep - expands every ancestor <details> so it's actually
  // visible, then scrolls it into view. Needed both for a sidebar click and
  // for landing directly on a deep-linked #<path> URL.
  function setActiveRow(path) {
    var rows = sidebar.querySelectorAll(".file-row");
    for (var i = 0; i < rows.length; i++) {
      rows[i].classList.toggle("active", rows[i].getAttribute("data-path") === path);
    }

    if (!path) return;

    var activeRow = sidebar.querySelector(".file-row.active");
    if (!activeRow) return;

    var ancestor = activeRow.parentElement ? activeRow.parentElement.closest(".tree-folder") : null;
    while (ancestor) {
      ancestor.open = true;
      ancestor = ancestor.parentElement ? ancestor.parentElement.closest(".tree-folder") : null;
    }

    activeRow.scrollIntoView({ block: "nearest" });
  }

  function showWelcome() {
    setActiveRow(null);
    var pct = (currentReport.lineCoverage * 100).toFixed(2);
    var stats = BlanketI18n.t("welcome_stats", {
      covered: currentReport.coveredLines.toLocaleString(),
      executable: currentReport.executableLines.toLocaleString(),
      fileCount: BlanketI18n.tPlural("file_count", currentReport.files.length),
    });
    content.innerHTML =
      '<div class="welcome"><h1>' + pct + "%</h1><p>" + escapeHtml(stats) + " " + escapeHtml(BlanketI18n.t("welcome_hint")) + "</p></div>";
  }

  function jumpToLine(line) {
    var previous = content.querySelector(".target-line");
    if (previous) previous.classList.remove("target-line");

    var row = document.getElementById("L" + line);
    if (!row) return;
    row.scrollIntoView({ block: "center" });
    row.classList.add("target-line");
  }

  function loadFile(path, line) {
    setActiveRow(path);
    content.innerHTML = '<div class="loading">' + escapeHtml(BlanketI18n.t("loading")) + "</div>";

    fetch("files/" + path + ".html")
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.text();
      })
      .then(function (html) {
        content.innerHTML = html;
        // The fragment was rendered server-side, in English, by
        // Blanket::HtmlReport - it carries data-i18n* markers instead of
        // baked-in strings for exactly this reason, so it reads correctly
        // for whoever's viewing it now, regardless of who generated it.
        BlanketI18n.applyTranslations(content);
        if (line) {
          jumpToLine(line);
        } else {
          content.scrollTop = 0;
        }
      })
      .catch(function () {
        content.innerHTML = '<div class="error">' + escapeHtml(BlanketI18n.t("error_could_not_load", { path: path })) + "</div>";
      });
  }

  // Function-breakdown rows link to their starting line via a plain
  // data-line attribute (not href="#L17") so clicking them can't be
  // mistaken by the router for a `#<path>:<line>` navigation.
  content.addEventListener("click", function (event) {
    var jumpLink = event.target.closest(".function-jump");
    if (jumpLink) {
      event.preventDefault();
      jumpToLine(jumpLink.getAttribute("data-line"));
      return;
    }

    var copyBtn = event.target.closest(".copy-path-btn");
    if (copyBtn) {
      var path = copyBtn.getAttribute("data-path");
      navigator.clipboard.writeText(path).then(function () {
        copyBtn.classList.add("copied");
        setTimeout(function () {
          copyBtn.classList.remove("copied");
        }, 1200);
      });
    }
  });

  function parseHash() {
    var raw = location.hash.slice(1);
    if (!raw) return { path: null, line: null };

    var idx = raw.lastIndexOf(":");
    if (idx === -1) return { path: raw, line: null };

    var line = raw.slice(idx + 1);
    if (/^\d+$/.test(line)) return { path: raw.slice(0, idx), line: line };

    return { path: raw, line: null };
  }

  function route() {
    var parsed = parseHash();
    if (!parsed.path) {
      showWelcome();
      return;
    }
    loadFile(parsed.path, parsed.line);
  }

  searchInput.addEventListener("input", function () {
    currentFilter = searchInput.value;
    searchWrapper.classList.toggle("has-value", currentFilter.length > 0);
    renderSidebar();
  });

  searchClear.addEventListener("click", function () {
    searchInput.value = "";
    currentFilter = "";
    searchWrapper.classList.remove("has-value");
    renderSidebar();
    searchInput.focus();
  });

  attentionFilter.addEventListener("change", function () {
    currentAttentionOnly = attentionFilter.checked;
    renderSidebar();
  });

  changedOnlyFilter.addEventListener("change", function () {
    currentChangedOnly = changedOnlyFilter.checked;
    renderSidebar();
  });

  fetch("report.json")
    .then(function (res) {
      return res.json();
    })
    .then(function (report) {
      currentReport = report;
      fileTree = buildTree(report.files);
      projectStat.textContent = statLine(report);

      // Only worth showing when the report actually has changed-file data
      // to filter on (see the `changed_files:` option to
      // Blanket::HtmlReport.generate) — otherwise every file is
      // `changed: false` and the checkbox would just be dead weight. When
      // it is available, default the view to it: a link from a PR comment
      // should land on "what did I touch", not the whole tree.
      var hasChangedFiles = report.files.some(function (f) {
        return f.changed;
      });
      changedOnlyRow.style.display = hasChangedFiles ? "" : "none";
      if (hasChangedFiles) {
        changedOnlyFilter.checked = true;
        currentChangedOnly = true;
      }

      renderSidebar();
      route();
      window.addEventListener("hashchange", route);
    });

  topBarBrand.addEventListener("click", function () {
    content.scrollTop = 0;
  });
})();
