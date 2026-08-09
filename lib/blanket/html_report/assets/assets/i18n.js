(function () {
  "use strict";

  var SUPPORTED_LOCALES = ["en", "fr", "es", "de", "ru", "zh"];

  // Plural-aware keys are objects keyed by an Intl.PluralRules category
  // (one/few/many/other) rather than a single string - see tPlural below.
  // English/French/Spanish/German only ever produce "one"/"other" here;
  // Russian also produces "few"/"many"; Chinese only ever produces "other".
  var DICTIONARIES = {
    en: {
      filter_placeholder: "Filter files…",
      clear_search: "Clear search",
      toggle_theme: "Toggle light/dark theme",
      back_to_top: "Back to top",
      needs_attention_only: "Needs attention only",
      changed_in_pr: "Changed in this PR",
      folder_changed_title: "Contains changes in this PR",
      top_bar_stat: "{pct}% · {covered}/{executable} lines",
      welcome_stats: "{covered}/{executable} lines covered across {fileCount}.",
      welcome_hint: "Pick a file on the left to see a line-by-line breakdown.",
      file_count: { one: "{count} file", other: "{count} files" },
      loading: "Loading…",
      error_could_not_load: "Could not load {path}",
      empty_matches: 'No file matches "{query}"',
      empty_needs_attention: "No file needs attention",
      empty_changed_in_pr: "No file changed in this PR",
      empty_changed_in_pr_attention: "No file changed in this PR needs attention",
      copy_full_path: "Copy full path",
      table_function: "Function",
      table_line: "Line",
      table_coverage: "Coverage",
      uncovered_lines: { one: "{count} uncovered line", other: "{count} uncovered lines" },
    },
    fr: {
      filter_placeholder: "Filtrer les fichiers…",
      clear_search: "Effacer la recherche",
      toggle_theme: "Basculer thème clair/sombre",
      back_to_top: "Retour en haut",
      needs_attention_only: "À surveiller uniquement",
      changed_in_pr: "Modifiés dans cette PR",
      folder_changed_title: "Contient des modifications de cette PR",
      top_bar_stat: "{pct} % · {covered}/{executable} lignes",
      welcome_stats: "{covered}/{executable} lignes couvertes sur {fileCount}.",
      welcome_hint: "Sélectionnez un fichier à gauche pour voir le détail ligne par ligne.",
      file_count: { one: "{count} fichier", other: "{count} fichiers" },
      loading: "Chargement…",
      error_could_not_load: "Impossible de charger {path}",
      empty_matches: 'Aucun fichier ne correspond à « {query} »',
      empty_needs_attention: "Aucun fichier à surveiller",
      empty_changed_in_pr: "Aucun fichier modifié dans cette PR",
      empty_changed_in_pr_attention: "Aucun fichier modifié dans cette PR à surveiller",
      copy_full_path: "Copier le chemin complet",
      table_function: "Fonction",
      table_line: "Ligne",
      table_coverage: "Couverture",
      uncovered_lines: { one: "{count} ligne non couverte", other: "{count} lignes non couvertes" },
    },
    es: {
      filter_placeholder: "Filtrar archivos…",
      clear_search: "Borrar búsqueda",
      toggle_theme: "Cambiar tema claro/oscuro",
      back_to_top: "Volver arriba",
      needs_attention_only: "Solo los que necesitan atención",
      changed_in_pr: "Modificados en esta PR",
      folder_changed_title: "Contiene cambios de esta PR",
      top_bar_stat: "{pct} % · {covered}/{executable} líneas",
      welcome_stats: "{covered}/{executable} líneas cubiertas en {fileCount}.",
      welcome_hint: "Elige un archivo a la izquierda para ver el detalle línea por línea.",
      file_count: { one: "{count} archivo", other: "{count} archivos" },
      loading: "Cargando…",
      error_could_not_load: "No se pudo cargar {path}",
      empty_matches: 'Ningún archivo coincide con "{query}"',
      empty_needs_attention: "Ningún archivo necesita atención",
      empty_changed_in_pr: "Ningún archivo modificado en esta PR",
      empty_changed_in_pr_attention: "Ningún archivo modificado en esta PR necesita atención",
      copy_full_path: "Copiar ruta completa",
      table_function: "Función",
      table_line: "Línea",
      table_coverage: "Cobertura",
      uncovered_lines: { one: "{count} línea sin cubrir", other: "{count} líneas sin cubrir" },
    },
    de: {
      filter_placeholder: "Dateien filtern…",
      clear_search: "Suche löschen",
      toggle_theme: "Hell-/Dunkelmodus umschalten",
      back_to_top: "Nach oben",
      needs_attention_only: "Nur auffällige Dateien",
      changed_in_pr: "In diesem PR geändert",
      folder_changed_title: "Enthält Änderungen aus diesem PR",
      top_bar_stat: "{pct} % · {covered}/{executable} Zeilen",
      welcome_stats: "{covered}/{executable} Zeilen abgedeckt in {fileCount}.",
      welcome_hint: "Wähle links eine Datei für die zeilenweise Ansicht.",
      file_count: { one: "{count} Datei", other: "{count} Dateien" },
      loading: "Wird geladen…",
      error_could_not_load: "{path} konnte nicht geladen werden",
      empty_matches: 'Keine Datei entspricht „{query}“',
      empty_needs_attention: "Keine auffällige Datei",
      empty_changed_in_pr: "Keine geänderte Datei in diesem PR",
      empty_changed_in_pr_attention: "Keine auffällige geänderte Datei in diesem PR",
      copy_full_path: "Vollständigen Pfad kopieren",
      table_function: "Funktion",
      table_line: "Zeile",
      table_coverage: "Abdeckung",
      uncovered_lines: { one: "{count} nicht abgedeckte Zeile", other: "{count} nicht abgedeckte Zeilen" },
    },
    ru: {
      filter_placeholder: "Фильтр файлов…",
      clear_search: "Очистить поиск",
      toggle_theme: "Переключить светлую/тёмную тему",
      back_to_top: "Наверх",
      needs_attention_only: "Только требующие внимания",
      changed_in_pr: "Изменённые в этом PR",
      folder_changed_title: "Содержит изменения из этого PR",
      top_bar_stat: "{pct} % · {covered}/{executable} строк",
      welcome_stats: "Покрыто {covered}/{executable} строк в {fileCount}.",
      welcome_hint: "Выберите файл слева, чтобы увидеть построчную разбивку.",
      file_count: { one: "{count} файл", few: "{count} файла", many: "{count} файлов", other: "{count} файла" },
      loading: "Загрузка…",
      error_could_not_load: "Не удалось загрузить {path}",
      empty_matches: 'Нет файлов, соответствующих «{query}»',
      empty_needs_attention: "Нет файлов, требующих внимания",
      empty_changed_in_pr: "Нет изменённых файлов в этом PR",
      empty_changed_in_pr_attention: "Нет изменённых файлов в этом PR, требующих внимания",
      copy_full_path: "Скопировать полный путь",
      table_function: "Функция",
      table_line: "Строка",
      table_coverage: "Покрытие",
      uncovered_lines: {
        one: "{count} непокрытая строка",
        few: "{count} непокрытые строки",
        many: "{count} непокрытых строк",
        other: "{count} непокрытой строки",
      },
    },
    zh: {
      filter_placeholder: "筛选文件…",
      clear_search: "清除搜索",
      toggle_theme: "切换浅色/深色主题",
      back_to_top: "返回顶部",
      needs_attention_only: "仅显示需要关注的文件",
      changed_in_pr: "此 PR 中已更改",
      folder_changed_title: "包含此 PR 的更改",
      top_bar_stat: "{pct}% · {covered}/{executable} 行",
      welcome_stats: "已覆盖 {covered}/{executable} 行，共 {fileCount}。",
      welcome_hint: "在左侧选择一个文件查看逐行覆盖详情。",
      file_count: { other: "{count} 个文件" },
      loading: "加载中…",
      error_could_not_load: "无法加载 {path}",
      empty_matches: "没有文件匹配 “{query}”",
      empty_needs_attention: "没有需要关注的文件",
      empty_changed_in_pr: "此 PR 中没有已更改的文件",
      empty_changed_in_pr_attention: "此 PR 中没有需要关注的已更改文件",
      copy_full_path: "复制完整路径",
      table_function: "函数",
      table_line: "行号",
      table_coverage: "覆盖率",
      uncovered_lines: { other: "{count} 行未覆盖" },
    },
  };

  // Prefers an exact "xx-YY" match (none of our dictionaries are
  // region-specific today, but this keeps the door open) before falling
  // back to the bare language subtag, walking the browser's full
  // preference list rather than just navigator.language.
  function detectLocale() {
    var candidates = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];

    for (var i = 0; i < candidates.length; i++) {
      var code = String(candidates[i]).toLowerCase();
      if (DICTIONARIES[code]) return code;

      var short = code.split("-")[0];
      if (DICTIONARIES[short]) return short;
    }

    return "en";
  }

  var locale = detectLocale();

  function interpolate(template, params) {
    if (!params) return template;
    return template.replace(/\{(\w+)\}/g, function (match, name) {
      return Object.prototype.hasOwnProperty.call(params, name) ? params[name] : match;
    });
  }

  function t(key, params) {
    var template = (DICTIONARIES[locale] && DICTIONARIES[locale][key]) || DICTIONARIES.en[key] || key;
    return interpolate(template, params);
  }

  // Intl.PluralRules is built into every modern browser (no polyfill
  // needed) and is the only reliable way to get plural categories right
  // across languages this different - eg. Russian's one/few/many split, or
  // Chinese having no plural distinction at all.
  function tPlural(key, count, params) {
    var forms = (DICTIONARIES[locale] && DICTIONARIES[locale][key]) || DICTIONARIES.en[key];
    if (!forms) return String(count);

    var category;
    try {
      category = new Intl.PluralRules(locale).select(count);
    } catch (e) {
      category = count === 1 ? "one" : "other";
    }

    var allParams = { count: count };
    if (params) {
      for (var name in params) {
        if (Object.prototype.hasOwnProperty.call(params, name)) allParams[name] = params[name];
      }
    }

    return interpolate(forms[category] || forms.other, allParams);
  }

  // Applies every data-i18n* marker found under `root`. Used once for the
  // static shell on load, and again each time a per-file fragment
  // (generated server-side, in English, by Blanket::HtmlReport) gets
  // injected - that's why markers rather than a build step: one generated
  // report has to read correctly for any viewer's browser locale, not just
  // whoever's CI generated it.
  function applyTranslations(root) {
    root.querySelectorAll("[data-i18n]").forEach(function (el) {
      el.textContent = t(el.getAttribute("data-i18n"));
    });
    root.querySelectorAll("[data-i18n-title]").forEach(function (el) {
      el.title = t(el.getAttribute("data-i18n-title"));
    });
    root.querySelectorAll("[data-i18n-aria-label]").forEach(function (el) {
      el.setAttribute("aria-label", t(el.getAttribute("data-i18n-aria-label")));
    });
    root.querySelectorAll("[data-i18n-placeholder]").forEach(function (el) {
      el.placeholder = t(el.getAttribute("data-i18n-placeholder"));
    });
    root.querySelectorAll("[data-i18n-plural]").forEach(function (el) {
      var count = parseInt(el.getAttribute("data-i18n-count"), 10);
      el.textContent = tPlural(el.getAttribute("data-i18n-plural"), count);
    });
  }

  window.BlanketI18n = {
    locale: locale,
    supportedLocales: SUPPORTED_LOCALES,
    t: t,
    tPlural: tPlural,
    applyTranslations: applyTranslations,
  };
})();
