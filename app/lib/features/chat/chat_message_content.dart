/// Helpers for rendering assistant chat text (strip fake external image markdown).
library;

class ChatMessageDisplay {
  ChatMessageDisplay._();

  static final RegExp _externalImageMarkdown = RegExp(
    r'!\[[^\]]*\]\(\s*https?://[^)]+\)',
    caseSensitive: false,
  );

  static bool hasExternalImageMarkdown(String content) {
    return _externalImageMarkdown.hasMatch(content);
  }

  /// Text safe to show in a plain [Text] bubble (no raw ![...](http...) blocks).
  static String textForBubble(String content) {
    var out = content.replaceAll(_externalImageMarkdown, '');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  /// Spinner only while the server confirmed a local FLUX job (not for URL markdown).
  static bool shouldShowImagePending({
    required bool pendingImageGeneration,
    required bool hasImageAttachment,
  }) {
    return pendingImageGeneration && !hasImageAttachment;
  }
}
