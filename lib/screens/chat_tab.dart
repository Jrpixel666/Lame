import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import '../models/chat_model.dart';
import '../services/llm_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';

/// A self-contained chat pane: history is scoped to [mode], so the Chat
/// screen and the Development screen each keep their own conversation.
/// When [mobile] is true it also renders its own top bar (menu + model
/// selector + new chat) and the model-loading progress banner; on desktop
/// those live in the surrounding shell instead.
class ChatTab extends StatefulWidget {
  final ChatMode mode;
  final bool mobile;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onBrowseModels;

  const ChatTab({
    super.key,
    required this.mode,
    required this.mobile,
    this.onOpenDrawer,
    this.onBrowseModels,
  });

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _chatCtrl = Get.find<ChatController>();
  final _modelCtrl = Get.find<ModelController>();
  final _llm = Get.find<LlmService>();
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  bool _autoScrollToBottom = true;
  String? _lastRenderedChatId;

  bool get _isDev => widget.mode == ChatMode.development;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleChatScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleChatScroll);
    _scrollController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  void _handleChatScroll() {
    if (!_scrollController.hasClients) return;
    _autoScrollToBottom = _isNearBottom();
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 120;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_autoScrollToBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (!force && !_autoScrollToBottom) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (_chatCtrl.activeChatFor(widget.mode) == null) {
      _chatCtrl.newChat(mode: widget.mode);
    }

    _msgController.clear();
    _autoScrollToBottom = true;
    _chatCtrl.sendMessage(
      text,
      modelFilename: _modelCtrl.selectedModelFilename.value,
    );
    _scrollToBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.mobile) {
      return _buildChatArea();
    }

    return Column(
      children: [
        SafeArea(bottom: false, child: _buildMobileTopBar()),
        Obx(() {
          if (!_modelCtrl.isLoadingModel.value) return const SizedBox.shrink();
          final progress = _modelCtrl.loadingProgress.value;
          final percent = (progress * 100).clamp(0, 100).toInt();
          final msg = _modelCtrl.loadingStatusMsg.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: AppColors.orange.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.orange),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        msg.isNotEmpty ? msg : 'Loading model...',
                        style: TextStyle(fontSize: 12, color: context.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: context.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.orange),
                  ),
                ),
              ],
            ),
          );
        }),
        Expanded(child: _buildChatArea()),
      ],
    );
  }

  Widget _buildMobileTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.menu_rounded, size: 22, color: context.textM),
            onPressed: widget.onOpenDrawer,
            tooltip: _isDev ? 'Development History' : 'Chat History',
          ),

          // Model selector dropdown
          Expanded(
            child: Center(
              child: Obx(() {
                final fname = _modelCtrl.selectedModelFilename.value;
                final info = fname != null
                    ? _modelCtrl.getModelInfo(fname)
                    : null;
                final loaded = _llm.isLoaded.value;
                final isLoading = _llm.isLoadingModel.value;
                final label = isLoading
                    ? 'Loading...'
                    : loaded
                    ? (info?.name ?? fname ?? 'Model')
                    : 'No model selected';

                return GestureDetector(
                  onTap: () => _showModelPicker(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLoading
                              ? AppColors.orange
                              : loaded
                              ? AppColors.green
                              : AppColors.red,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: loaded
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: loaded ? context.text : context.textD,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: context.textM,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

          IconButton(
            icon: Icon(Icons.edit_square, size: 20, color: context.textM),
            onPressed: () => _chatCtrl.newChat(mode: widget.mode),
            tooltip: 'New Chat',
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    final downloaded = _modelCtrl.downloadedModels;
    if (downloaded.isEmpty) {
      widget.onBrowseModels?.call();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.textD,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Select Model',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const Spacer(),
                    Obx(() {
                      if (_llm.isLoaded.value) {
                        return TextButton.icon(
                          onPressed: () {
                            _modelCtrl.unloadCurrentModel();
                            Navigator.pop(context);
                          },
                          icon: const Icon(
                            Icons.eject_rounded,
                            size: 16,
                            color: AppColors.orange,
                          ),
                          label: const Text(
                            'Unload',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.orange,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onBrowseModels?.call();
                      },
                      child: const Text(
                        'Browse All',
                        style: TextStyle(fontSize: 13, color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              ...downloaded.map((filename) {
                final info = _modelCtrl.getModelInfo(filename);
                final isActive =
                    _modelCtrl.selectedModelFilename.value == filename &&
                    _llm.isLoaded.value;
                final isLoading =
                    _modelCtrl.loadingModelFilename.value == filename;
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.green.withValues(alpha: 0.15)
                          : isLoading
                          ? AppColors.orange.withValues(alpha: 0.15)
                          : context.bgHover,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.orange,
                            ),
                          )
                        : Icon(
                            isActive
                                ? Icons.check_rounded
                                : Icons.smart_toy_outlined,
                            size: 16,
                            color: isActive ? AppColors.green : context.textM,
                          ),
                  ),
                  title: Text(
                    info?.name ?? filename,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: context.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: info != null
                      ? Text(
                          '${info.sizeGb} GB • Min ${info.minRamGb} GB RAM',
                          style: TextStyle(fontSize: 11, color: context.textD),
                        )
                      : null,
                  trailing: isActive
                      ? const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : isLoading
                      ? const Text(
                          'Loading...',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (!isActive && !isLoading) {
                      _modelCtrl.loadModel(filename);
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SHARED — chat message list + input, used by both layouts
  // ═══════════════════════════════════════════════════════════════
  Widget _buildChatArea() {
    return Column(
      children: [
        Expanded(
          child: Obx(() {
            final chat = _chatCtrl.activeChatFor(widget.mode);
            if (chat == null || chat.messages.isEmpty) {
              return _buildWelcome();
            }

            if (_lastRenderedChatId != chat.id) {
              _lastRenderedChatId = chat.id;
              _autoScrollToBottom = true;
              _scrollToBottom(force: true);
            }

            _scrollToBottom();

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount:
                  chat.messages.length + (_chatCtrl.isGenerating.value ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < chat.messages.length) {
                  final msg = chat.messages[index];
                  final isLastAi =
                      msg.isAssistant && index == chat.messages.length - 1;
                  return ChatBubble(message: msg, showSpeed: isLastAi);
                }
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TypingIndicator(),
                  ),
                );
              },
            );
          }),
        ),

        _buildInputArea(),
      ],
    );
  }

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _isDev ? Icons.code_rounded : Icons.bolt_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isDev ? 'What are we building?' : 'How can I help you?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
            ),
            const SizedBox(height: 8),
            Obx(
              () => Text(
                _llm.isLoaded.value
                    ? (_isDev
                        ? 'Ask a coding, debugging, or architecture question below.'
                        : 'Type a message below to get started.')
                    : 'Select a model first to begin chatting.',
                style: TextStyle(fontSize: 14, color: context.textM),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgInput,
          border: Border.all(color: context.border),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.15 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _msgController,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  fontSize: 15,
                  color: context.text,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: _isDev ? 'Ask a coding question...' : 'Ask anything...',
                  hintStyle: TextStyle(color: context.textD),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(24, 14, 8, 14),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: Obx(
                () => _chatCtrl.isGenerating.value
                    ? _circleButton(
                        icon: Icons.stop_rounded,
                        color: AppColors.red,
                        onTap: _chatCtrl.stopGeneration,
                        tooltip: 'Stop',
                      )
                    : _circleButton(
                        icon: Icons.arrow_upward_rounded,
                        color: AppColors.accent,
                        onTap: _send,
                        tooltip: 'Send',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
