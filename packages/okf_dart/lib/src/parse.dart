import 'package:yaml/yaml.dart';

import 'concept.dart';

const _delim = '---';

class OkfParseException implements Exception {
  final String message;
  OkfParseException(this.message);
  @override
  String toString() => 'OkfParseException: $message';
}

Concept parseConcept(String text) {
  var normalized = text;
  if (normalized.startsWith('\uFEFF')) {
    normalized = normalized.substring(1);
  }
  normalized = normalized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  if (!normalized.startsWith('$_delim\n') && normalized.trim() != _delim) {
    throw OkfParseException("document does not start with a '---' delimiter");
  }

  final lines = normalized.split('\n');
  int? closing;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i] == _delim) {
      closing = i;
      break;
    }
  }
  if (closing == null) {
    throw OkfParseException("frontmatter not closed with a '---' line");
  }

  final fmText = lines.sublist(1, closing).join('\n');
  var body = lines.sublist(closing + 1).join('\n');
  if (body.startsWith('\n')) body = body.substring(1);

  dynamic loaded;
  try {
    loaded = fmText.trim().isEmpty ? <String, dynamic>{} : loadYaml(fmText);
  } on YamlException catch (e) {
    throw OkfParseException('invalid YAML frontmatter: $e');
  }

  loaded ??= <String, dynamic>{};
  if (loaded is! Map) {
    throw OkfParseException('frontmatter must be a YAML mapping');
  }
  return Concept(frontmatter: _deepMap(loaded), body: body);
}

Map<String, dynamic> _deepMap(Map map) {
  final out = <String, dynamic>{};
  map.forEach((k, v) => out[k.toString()] = _deepValue(v));
  return out;
}

dynamic _deepValue(dynamic v) {
  if (v is Map) return _deepMap(v);
  if (v is List) return v.map(_deepValue).toList();
  return v;
}

String dumpConcept(Concept concept) {
  final ordered = <String, dynamic>{};
  for (final key in recommendedOrder) {
    if (concept.frontmatter.containsKey(key)) {
      ordered[key] = concept.frontmatter[key];
    }
  }
  concept.frontmatter.forEach((k, v) {
    if (!ordered.containsKey(k)) ordered[k] = v;
  });

  final fm = StringBuffer();
  _emitMap(fm, ordered, 0);
  final fmText = fm.toString().trimRight();
  return '$_delim\n$fmText\n$_delim\n${concept.body}';
}

void _emitMap(StringBuffer buf, Map<String, dynamic> map, int indent) {
  final pad = '  ' * indent;
  map.forEach((key, value) {
    if (value is Map) {
      buf.writeln('$pad$key:');
      _emitMap(buf, value.cast<String, dynamic>(), indent + 1);
    } else if (value is List) {
      if (value.isEmpty) {
        buf.writeln('$pad$key: []');
      } else {
        buf.writeln('$pad$key:');
        for (final item in value) {
          if (item is Map) {
            buf.writeln('$pad-');
            _emitMap(buf, item.cast<String, dynamic>(), indent + 2);
          } else {
            buf.writeln('$pad- ${_scalar(item)}');
          }
        }
      }
    } else {
      buf.writeln('$pad$key: ${_scalar(value)}');
    }
  });
}

String _scalar(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.toString();
  final s = value.toString();
  // Quote when the scalar could be misread as YAML structure.
  final needsQuote = s.isEmpty ||
      RegExp(r'^[\s]|[\s]$').hasMatch(s) ||
      RegExp(r'[:#\[\]{}&*!|>%@`,]').hasMatch(s) ||
      RegExp(r'^(true|false|null|~|\d)').hasMatch(s);
  if (needsQuote) {
    return "'${s.replaceAll("'", "''")}'";
  }
  return s;
}
