import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

/// Converts note bodies between stored markdown and [Document] for [QuillEditor].
///
/// Notes are persisted as markdown (OKF); Quill is used only while editing.
class NoteMarkdownCodec {
  NoteMarkdownCodec()
      : _mdToDelta = MarkdownToDelta(
          markdownDocument: md.Document(
            encodeHtml: false,
            extensionSet: md.ExtensionSet.gitHubFlavored,
          ),
        ),
        _deltaToMd = DeltaToMarkdown(
          customEmbedHandlers: {
            BlockEmbed.imageType: (embed, out) {
              final src = embed.value.data?.toString() ?? '';
              out.write('![]($src)');
            },
          },
        );

  final MarkdownToDelta _mdToDelta;
  final DeltaToMarkdown _deltaToMd;

  /// Loads markdown into a Quill [Document], falling back to plain text.
  Document markdownToDocument(String markdown) {
    if (markdown.trim().isEmpty) {
      return Document();
    }
    try {
      final delta = _mdToDelta.convert(markdown);
      if (delta.isEmpty) {
        return _plainDocument(markdown);
      }
      return Document.fromDelta(delta);
    } catch (_) {
      return _plainDocument(markdown);
    }
  }

  /// Serializes a Quill [Document] back to markdown for storage/sync.
  String documentToMarkdown(Document document) {
    try {
      final markdown = _deltaToMd.convert(document.toDelta());
      return markdown.trimRight();
    } catch (_) {
      return document.toPlainText().trimRight();
    }
  }

  Document _plainDocument(String text) {
    return Document.fromJson([
      {'insert': text},
      {'insert': '\n'},
    ]);
  }
}
