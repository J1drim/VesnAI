import 'concept.dart';

enum Severity { error, warning }

class ConformanceIssue {
  final String path;
  final Severity severity;
  final String message;
  ConformanceIssue(this.path, this.severity, this.message);
  @override
  String toString() => '[${severity.name}] $path: $message';
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

List<ConformanceIssue> checkConcept(String path, Concept concept) {
  final issues = <ConformanceIssue>[];
  final reserved = reservedFilenames.contains(_basename(path));
  if (!reserved) {
    final type = concept.type;
    if (type == null || type.trim().isEmpty) {
      issues.add(ConformanceIssue(
          path, Severity.error, "missing required non-empty 'type'"));
    }
    if (concept.title == null) {
      issues.add(ConformanceIssue(
          path, Severity.warning, "recommended field 'title' is absent"));
    }
  }
  return issues;
}

List<ConformanceIssue> checkBundle(Map<String, Concept> concepts) {
  final issues = <ConformanceIssue>[];
  final known = concepts.keys.toSet();
  concepts.forEach((path, concept) {
    issues.addAll(checkConcept(path, concept));
    for (final href in concept.explicitLinks()) {
      if (_isInternal(href) && !known.contains(resolveLink(path, href, true))) {
        issues.add(ConformanceIssue(
            path, Severity.warning, "broken cross-link to '$href'"));
      }
    }
    for (final href in concept.bodyLinks()) {
      if (_isInternal(href) && !known.contains(resolveLink(path, href, false))) {
        issues.add(ConformanceIssue(
            path, Severity.warning, "broken cross-link to '$href'"));
      }
    }
  });
  return issues;
}

bool _isInternal(String href) {
  if (href.contains('://') || href.startsWith('#') || href.startsWith('mailto:')) {
    return false;
  }
  return href.endsWith('.md') || href.contains('/') || !href.startsWith('http');
}

String resolveLink(String sourcePath, String href, bool explicit) {
  href = href.split('#').first;
  if (explicit) {
    return href.replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'^/'), '');
  }
  if (href.startsWith('/')) return href.replaceFirst('/', '');
  final baseParts = sourcePath.replaceAll('\\', '/').split('/');
  baseParts.removeLast();
  final parts = [...baseParts, ...href.split('/')];
  final resolved = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
      continue;
    }
    resolved.add(part);
  }
  return resolved.join('/');
}
