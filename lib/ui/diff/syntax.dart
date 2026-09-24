/// Syntax highlighting for diffs and file previews (optional, off by
/// default: highlighting large files costs time).
library;

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/clojure.dart';
import 'package:re_highlight/languages/cmake.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/elixir.dart';
import 'package:re_highlight/languages/erlang.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/graphql.dart';
import 'package:re_highlight/languages/groovy.dart';
import 'package:re_highlight/languages/haskell.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/nginx.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/perl.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/languages/protobuf.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/r.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scala.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// Texts longer than this are shown without highlighting.
const maxHighlightChars = 400 * 1024;

final _languages = {
  'bash': langBash,
  'c': langC,
  'clojure': langClojure,
  'cmake': langCmake,
  'cpp': langCpp,
  'csharp': langCsharp,
  'css': langCss,
  'dart': langDart,
  'dockerfile': langDockerfile,
  'elixir': langElixir,
  'erlang': langErlang,
  'go': langGo,
  'gradle': langGradle,
  'graphql': langGraphql,
  'groovy': langGroovy,
  'haskell': langHaskell,
  'ini': langIni,
  'java': langJava,
  'javascript': langJavascript,
  'json': langJson,
  'kotlin': langKotlin,
  'less': langLess,
  'lua': langLua,
  'makefile': langMakefile,
  'markdown': langMarkdown,
  'nginx': langNginx,
  'objectivec': langObjectivec,
  'perl': langPerl,
  'php': langPhp,
  'powershell': langPowershell,
  'protobuf': langProtobuf,
  'python': langPython,
  'r': langR,
  'ruby': langRuby,
  'rust': langRust,
  'scala': langScala,
  'scss': langScss,
  'sql': langSql,
  'swift': langSwift,
  'typescript': langTypescript,
  'xml': langXml,
  'yaml': langYaml,
};

const _byExtension = {
  'sh': 'bash', 'bash': 'bash', 'zsh': 'bash', //
  'c': 'c', 'h': 'c',
  'clj': 'clojure', 'cljs': 'clojure', 'edn': 'clojure',
  'cmake': 'cmake',
  'cc': 'cpp', 'cpp': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp', 'hh': 'cpp',
  'cs': 'csharp',
  'css': 'css',
  'dart': 'dart',
  'ex': 'elixir', 'exs': 'elixir',
  'erl': 'erlang', 'hrl': 'erlang',
  'go': 'go',
  'gradle': 'gradle',
  'graphql': 'graphql', 'gql': 'graphql',
  'groovy': 'groovy',
  'hs': 'haskell',
  'ini': 'ini', 'toml': 'ini', 'cfg': 'ini', 'properties': 'ini',
  'java': 'java',
  'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
  'jsx': 'javascript',
  'json': 'json', 'arb': 'json',
  'kt': 'kotlin', 'kts': 'kotlin',
  'less': 'less',
  'lua': 'lua',
  'mk': 'makefile',
  'md': 'markdown', 'markdown': 'markdown',
  'm': 'objectivec', 'mm': 'objectivec',
  'pl': 'perl', 'pm': 'perl',
  'php': 'php',
  'ps1': 'powershell',
  'proto': 'protobuf',
  'py': 'python', 'pyi': 'python',
  'r': 'r',
  'rb': 'ruby', 'gemspec': 'ruby',
  'rs': 'rust',
  'scala': 'scala', 'sc': 'scala',
  'scss': 'scss',
  'sql': 'sql',
  'swift': 'swift',
  'ts': 'typescript', 'tsx': 'typescript', 'mts': 'typescript',
  'xml': 'xml', 'html': 'xml', 'htm': 'xml', 'svg': 'xml', 'xib': 'xml',
  'plist': 'xml', 'entitlements': 'xml', 'xcscheme': 'xml',
  'yaml': 'yaml', 'yml': 'yaml',
};

const _byName = {
  'Dockerfile': 'dockerfile',
  'Makefile': 'makefile',
  'GNUmakefile': 'makefile',
  'CMakeLists.txt': 'cmake',
  'Gemfile': 'ruby',
  'Rakefile': 'ruby',
  'nginx.conf': 'nginx',
};

/// The highlight.js language for a file path, or null if unsupported.
String? languageForPath(String path) {
  final name = p.basename(path);
  final byName = _byName[name];
  if (byName != null) return byName;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return _byExtension[name.substring(dot + 1).toLowerCase()];
}

Highlight? _engine;
Highlight get _highlight =>
    _engine ??= Highlight()..registerLanguages(_languages);

/// Theme without the root background (the diff colors its own rows).
final Map<String, TextStyle> _theme = {
  for (final e in atomOneDarkTheme.entries)
    e.key: e.value.copyWith(backgroundColor: null),
};

/// Highlights [text] as [language] and returns one list of spans per line
/// (`text.split('\n')` order). Spans carry only the highlight style; the
/// caller provides the base font. Returns null if the text is too large or
/// highlighting fails.
List<List<TextSpan>>? highlightLines(String text, String language) {
  if (text.length > maxHighlightChars) return null;
  try {
    final result = _highlight.highlight(code: text, language: language);
    final renderer = TextSpanRenderer(null, _theme);
    result.render(renderer);
    final root = renderer.span;
    final lines = <List<TextSpan>>[[]];
    void walk(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) return;
      final style = inherited == null
          ? span.style
          : (span.style == null ? inherited : inherited.merge(span.style));
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        final parts = t.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) lines.add([]);
          if (parts[i].isNotEmpty) {
            lines.last.add(TextSpan(text: parts[i], style: style));
          }
        }
      }
      for (final c in span.children ?? const <InlineSpan>[]) {
        walk(c, style);
      }
    }

    if (root != null) walk(root, null);
    return lines;
  } catch (_) {
    return null;
  }
}
