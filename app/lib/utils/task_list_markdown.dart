/// GitHub-flavored task list line: optional indent, `- [ ]` or `- [x]`.
final taskListLinePattern = RegExp(r'^(\s*)- \[([ xX])\] (.*)$');

/// Counts task-list items in [markdown] (lines matching `- [ ]` / `- [x]`).
int countTaskListItems(String markdown) {
  var count = 0;
  for (final line in markdown.split('\n')) {
    if (taskListLinePattern.hasMatch(line)) count++;
  }
  return count;
}

/// Toggles the task item at [index] (0-based among task lines only).
///
/// Returns [markdown] unchanged if [index] is out of range. Checked markers
/// are normalized to lowercase `[x]`.
String toggleTaskListItem(String markdown, int index) {
  if (index < 0) return markdown;
  final lines = markdown.split('\n');
  var seen = 0;
  for (var i = 0; i < lines.length; i++) {
    final match = taskListLinePattern.firstMatch(lines[i]);
    if (match == null) continue;
    if (seen == index) {
      final indent = match.group(1)!;
      final text = match.group(3)!;
      final wasChecked = match.group(2)!.toLowerCase() == 'x';
      lines[i] = '$indent- [${wasChecked ? ' ' : 'x'}] $text';
      return lines.join('\n');
    }
    seen++;
  }
  return markdown;
}
