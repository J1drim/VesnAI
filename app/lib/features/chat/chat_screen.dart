import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api_client.dart';
import '../../data/chat_attachment.dart';
import '../../data/chat_attachment_cache.dart';
import '../../data/chat_tts_service.dart';
import '../../data/notifications_feed.dart';
import '../../data/speech_input.dart';
import '../../app.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../utils/external_url.dart';
import '../../widgets/chat_attachment_actions.dart';
import '../../widgets/chat_attachment_image.dart';
import '../../widgets/unpaired_banner.dart';
import '../../widgets/vesnai_logo.dart';
import '../note_detail/note_detail_screen.dart';
import 'chat_message_content.dart';
import 'chat_message_format.dart';
import 'chat_sessions.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<SpeechResult>? _speechSub;
  bool _sending = false;
  bool _listening = false;
  String? _lastAutoSpokenId;
  final List<PendingChatAttachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speechSub?.cancel();
    super.dispose();
  }

  void _scrollToBottom({bool animate = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  void _onChatStateChanged(ChatState? prev, ChatState next) {
    if (prev?.activeId != next.activeId) {
      _lastAutoSpokenId = null;
    }
    _onChatMessagesChanged(prev, next);
    if (prev?.activeId != next.activeId ||
        (next.messages.isNotEmpty &&
            prev?.messages.length != next.messages.length)) {
      _scrollToBottom();
    }
  }

  ChatMessageView? _findById(List<ChatMessageView> messages, String id) {
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _onChatMessagesChanged(ChatState? prev, ChatState next) {
    final before = prev?.messages ?? const <ChatMessageView>[];
    final turnJustFinished = prev?.hasThinking == true && !next.hasThinking;
    for (final m in next.messages.reversed) {
      if (m.role != 'assistant') continue;
      if (m.isThinking || m.content.trim().isEmpty) continue;
      if (m.id.isEmpty || m.id == _lastAutoSpokenId) continue;
      final oldMsg = _findById(before, m.id);
      if (oldMsg == null) continue;
      if (oldMsg.content.trim().isNotEmpty) continue;
      if (!turnJustFinished && !oldMsg.isThinking) continue;
      unawaited(_autoSpeak(m.id));
      break;
    }
  }

  Future<void> _autoSpeak(String messageId) async {
    await ref.read(chatTtsServiceProvider).stop();
    final latest = _findById(ref.read(chatControllerProvider).messages, messageId);
    if (latest == null ||
        latest.content.trim().isEmpty ||
        latest.isThinking) {
      return;
    }
    final ok = await ref.read(chatTtsServiceProvider).speak(
          latest,
          auto: true,
          onError: (msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg)),
              );
            }
          },
        );
    if (ok) _lastAutoSpokenId = messageId;
  }

  Future<void> _send([String? text]) async {
    final message = (text ?? _controller.text).trim();
    if (message.isEmpty && _pendingAttachments.isEmpty) return;
    await ref.read(chatTtsServiceProvider).stop();
    _controller.clear();
    final attachments = List<PendingChatAttachment>.from(_pendingAttachments);
    final assistantLanguage = ref.read(assistantLanguageProvider).apiValue;
    setState(() => _sending = true);
    var clearedAttachments = false;
    try {
      await ref.read(chatControllerProvider.notifier).send(
            message,
            assistantLanguage: assistantLanguage,
            attachments: attachments,
            onBubbleVisible: () {
              if (!clearedAttachments && mounted) {
                setState(() {
                  _pendingAttachments.clear();
                  clearedAttachments = true;
                });
              }
            },
          );
      if (!clearedAttachments && mounted) {
        setState(() => _pendingAttachments.clear());
      }
      _scrollToBottom(animate: true);
    } on ChatAttachmentUploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on ChatSendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotSendMessage('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retrySend(String messageId) async {
    final assistantLanguage = ref.read(assistantLanguageProvider).apiValue;
    setState(() => _sending = true);
    try {
      await ref.read(chatControllerProvider.notifier).retrySend(
            messageId,
            assistantLanguage: assistantLanguage,
          );
      _scrollToBottom(animate: true);
    } on ChatAttachmentUploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on ChatSendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).couldNotSendMessage('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _speak(ChatMessageView message) async {
    await ref.read(chatTtsServiceProvider).speak(
          message,
          onError: (msg) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            }
          },
        );
  }

  String _localeId() {
    final lang = Localizations.localeOf(context).languageCode;
    return lang == 'pl' ? 'pl_PL' : 'en_US';
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await ref.read(speechInputProvider).stop();
      return;
    }
    final speech = ref.read(speechInputProvider);
    if (!await speech.initialize()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).speechUnavailable),
        ));
      }
      return;
    }
    setState(() => _listening = true);
    _speechSub = speech.listen(localeId: _localeId()).listen(
      (result) {
        _controller.value = TextEditingValue(
          text: result.text,
          selection: TextSelection.collapsed(offset: result.text.length),
        );
        if (result.isFinal) _finishListening(result.text);
      },
      onError: (_) => _stopListening(),
      onDone: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
    );
  }

  Future<void> _stopListening() async {
    await ref.read(speechInputProvider).stop();
    await _speechSub?.cancel();
    _speechSub = null;
    if (mounted) setState(() => _listening = false);
  }

  void _finishListening(String text) {
    _speechSub?.cancel();
    _speechSub = null;
    if (mounted) setState(() => _listening = false);
    _controller.clear();
    _send(text);
  }

  void _addPending(PendingChatAttachment attachment) {
    setState(() => _pendingAttachments.add(attachment));
  }

  Future<void> _pickImage(ImageSource source) async {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (x == null) return;
    final name = x.name.trim().isNotEmpty
        ? x.name
        : 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
    _addPending(PendingChatAttachment(
      filename: name,
      bytes: await x.readAsBytes(),
      kind: 'image',
    ));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    final file = result?.files.singleOrNull;
    if (file?.bytes == null) return;
    _addPending(PendingChatAttachment(filename: file!.name, bytes: file.bytes!));
  }

  Future<void> _pickVoiceNote() async {
    final result = await FilePicker.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.bytes == null) return;
    _addPending(PendingChatAttachment(
      filename: file!.name,
      bytes: file.bytes!,
      kind: 'audio',
    ));
  }

  Future<void> _showAttachSheet() async {
    final l = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l.camera),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.gallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(l.file),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: Text(l.voiceNote),
              onTap: () {
                Navigator.pop(ctx);
                _pickVoiceNote();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _activeTitle(BuildContext context, ChatState chat) {
    final l = AppLocalizations.of(context);
    if (chat.activeId == null) return l.talkToVesnai;
    final match = chat.sessions.where((s) => s.id == chat.activeId);
    return match.isEmpty
        ? l.talkToVesnai
        : displaySessionTitle(l, match.first.title);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, _onChatStateChanged);
    ref.listen<String?>(noteSavedPathProvider, (prev, path) {
      if (path == null || path.isEmpty || !mounted) return;
      ref.read(noteSavedPathProvider.notifier).state = null;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).noteSaved),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: AppLocalizations.of(context).open,
            onPressed: () {
              messenger.hideCurrentSnackBar();
              appNavigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(path: path),
                ),
              );
            },
          ),
        ),
      );
    });
    final l = AppLocalizations.of(context);
    final chat = ref.watch(chatControllerProvider);
    final paired = ref.watch(serverConnectionProvider).isPaired;
    final client = ref.watch(apiClientProvider);
    final cache = ref.watch(chatAttachmentCacheProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_activeTitle(context, chat)),
        actions: [
          if (paired)
            IconButton(
              key: const Key('chat-new'),
              tooltip: l.newChat,
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: chat.isCreatingChat
                  ? null
                  : () => ref.read(chatControllerProvider.notifier).newChat(),
            ),
        ],
      ),
      drawer: paired ? _SessionsDrawer(chat: chat) : null,
      body: Column(
        children: [
          const UnpairedBanner(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: chat.messages.length,
              itemBuilder: (context, i) {
                final m = chat.messages[i];
                return _MessageBubble(
                  message: m,
                  sessionId: chat.activeId ?? '',
                  client: client,
                  cache: cache,
                  onSpeak: () => _speak(m),
                  onRetryImage: m.canRetryImage
                      ? () => ref
                          .read(chatControllerProvider.notifier)
                          .retryImageGeneration(m.id)
                      : null,
                  onRetrySend: m.isPendingSend && m.id.isNotEmpty
                      ? () => _retrySend(m.id)
                      : null,
                );
              },
            ),
          ),
          if (_pendingAttachments.isNotEmpty)
            _PendingAttachmentsStrip(
              attachments: _pendingAttachments,
              onRemove: (i) => setState(() => _pendingAttachments.removeAt(i)),
            ),
          if (_listening) _StatusBar(icon: Icons.mic, label: l.listening),
          if (chat.isCreatingChat)
            _StatusBar(icon: Icons.add_comment_outlined, label: l.startingNewChat),
          if (_sending) _StatusBar(icon: Icons.upload, label: l.sendingStatus),
          if (!_sending && !chat.isCreatingChat && chat.hasThinking)
            _StatusBar(avatar: true, label: l.vesnaiThinking),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (paired)
                    IconButton(
                      key: const Key('chat-attach'),
                      tooltip: l.attach,
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _sending || chat.isCreatingChat ? null : _showAttachSheet,
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('chat-input'),
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: l.chatInputHint,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (paired)
                    IconButton(
                      key: const Key('chat-mic'),
                      tooltip: _listening ? l.stopAndSend : l.speak,
                      color: _listening ? Theme.of(context).colorScheme.error : null,
                      icon: Icon(_listening ? Icons.stop : Icons.mic),
                      onPressed: _sending || chat.isCreatingChat ? null : _toggleListen,
                    ),
                  IconButton(
                    key: const Key('chat-send'),
                    icon: const Icon(Icons.send),
                    onPressed: _sending || _listening || chat.isCreatingChat ? null : () => _send(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  final ChatMessageView message;
  final String sessionId;
  final VesnaiApiClient? client;
  final ChatAttachmentCache? cache;
  final VoidCallback onSpeak;
  final VoidCallback? onRetryImage;
  final VoidCallback? onRetrySend;

  const _MessageBubble({
    required this.message,
    required this.sessionId,
    required this.client,
    required this.cache,
    required this.onSpeak,
    this.onRetryImage,
    this.onRetrySend,
  });

  Future<void> _openImageActions(
    WidgetRef ref,
    BuildContext context,
    ChatAttachmentMeta attachment,
  ) async {
    final cached = cache;
    Uint8List? bytes;
    if (cached != null) {
      bytes = await cached.readBytes(sessionId, attachment.path);
    }
    final api = client;
    if (bytes == null && api != null) {
      try {
        bytes = await api.downloadChatAttachment(sessionId, attachment.path);
        await cached?.write(sessionId, attachment.path, bytes);
      } catch (_) {}
    }
    if (bytes == null || !context.mounted) return;
    await showChatImageActions(
      context: context,
      ref: ref,
      sessionId: sessionId,
      attachment: attachment,
      bytes: bytes,
      client: client,
    );
  }

  Future<void> _openFileActions(
    WidgetRef ref,
    BuildContext context,
    ChatAttachmentMeta attachment,
  ) async {
    final cached = cache;
    Uint8List? bytes;
    if (cached != null) {
      bytes = await cached.readBytes(sessionId, attachment.path);
    }
    final api = client;
    if (bytes == null && api != null) {
      try {
        bytes = await api.downloadChatAttachment(sessionId, attachment.path);
        await cached?.write(sessionId, attachment.path, bytes);
      } catch (_) {}
    }
    if (bytes == null || !context.mounted) return;
    await showChatFileActions(
      context: context,
      ref: ref,
      sessionId: sessionId,
      attachment: attachment,
      bytes: bytes,
      client: client,
    );
  }

  IconData _documentIcon(ChatAttachmentMeta a) {
    final lower = a.filename.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.pptx')) return Icons.slideshow_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isUser = message.role == 'user';
    final displayText = ChatMessageDisplay.textForBubble(message.content);
    final hasImageAttachment = message.attachments.any((a) => a.isImage);
    final showImagePending = ChatMessageDisplay.shouldShowImagePending(
      pendingImageGeneration: message.pendingImageGeneration,
      hasImageAttachment: hasImageAttachment,
    );
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        color: isUser
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (displayText.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: MarkdownBody(
                    data: displayText,
                    onTapLink: (text, href, title) {
                      if (href != null && isExternalUrl(href)) {
                        openExternalUrl(href, context: context);
                      }
                    },
                  ),
                ),
                if (!isUser && message.id.isNotEmpty)
                  IconButton(
                    key: Key('speak-${message.id}'),
                    tooltip: message.hasTts ? l.replay : l.speak,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      message.hasTts ? Icons.replay : Icons.volume_up,
                      size: 18,
                    ),
                    onPressed: onSpeak,
                  ),
              ],
            ),
            if (message.isSending)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.sendingStatus,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (message.isPendingSend)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.notSent,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            if (message.isPendingSend && onRetrySend != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: onRetrySend,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.retry),
                ),
              ),
            for (final a in message.attachments) ...[
              const SizedBox(height: 8),
              if (a.isImage && sessionId.isNotEmpty)
                ChatAttachmentImage(
                  sessionId: sessionId,
                  attachment: a,
                  client: client,
                  cache: cache,
                  height: 160,
                  width: double.infinity,
                  onTap: () => _openImageActions(ref, context, a),
                )
              else if (a.isAudio)
                _AttachmentChip(icon: Icons.mic, label: a.filename)
              else if (a.isDocument && sessionId.isNotEmpty)
                InkWell(
                  onTap: () => _openFileActions(ref, context, a),
                  borderRadius: BorderRadius.circular(8),
                  child: _AttachmentChip(icon: _documentIcon(a), label: a.filename),
                )
              else
                _AttachmentChip(icon: Icons.insert_drive_file_outlined, label: a.filename),
            ],
            if (message.isThinking)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l.thinking),
                  ],
                ),
              ),
            if (showImagePending)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l.generatingImage),
                  ],
                ),
              ),
            if (message.imageActionFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.imageGenerationFailed,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            if (message.canRetryImage && onRetryImage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: onRetryImage,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l.retryImage),
                ),
              ),
            if (message.sentAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  formatChatMessageSentAt(context, message.sentAt!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
    );
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, right: 6),
              child: VesnaiAvatar(radius: 14),
            ),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AttachmentChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _PendingAttachmentsStrip extends StatelessWidget {
  final List<PendingChatAttachment> attachments;
  final void Function(int index) onRemove;

  const _PendingAttachmentsStrip({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = attachments[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: a.kind == 'image'
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          Uint8List.fromList(a.bytes),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Icon(
                          a.kind == 'audio' ? Icons.mic : Icons.insert_drive_file_outlined,
                        ),
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.cancel, size: 20),
                  onPressed: () => onRemove(i),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionsDrawer extends ConsumerWidget {
  final ChatState chat;
  const _SessionsDrawer({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final notifier = ref.read(chatControllerProvider.notifier);
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l.newChat),
              enabled: !chat.isCreatingChat,
              onTap: chat.isCreatingChat
                  ? null
                  : () {
                      Navigator.pop(context);
                      notifier.newChat();
                    },
            ),
            const Divider(height: 1),
            Expanded(
              child: chat.sessions.isEmpty
                  ? Center(child: Text(l.noConversationsYet))
                  : ListView.builder(
                      itemCount: chat.sessions.length,
                      itemBuilder: (context, i) {
                        final s = chat.sessions[i];
                        return ListTile(
                          selected: s.id == chat.activeId,
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(displaySessionTitle(l, s.title),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => notifier.deleteSession(s.id),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            notifier.switchTo(s.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final IconData? icon;
  final bool avatar;
  final String label;
  const _StatusBar({
    this.icon,
    this.avatar = false,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          if (avatar)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: VesnaiAvatar(radius: 10),
            )
          else if (icon != null)
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          if (!avatar && icon != null) const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 12),
          const Expanded(child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
