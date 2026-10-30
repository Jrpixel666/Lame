import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import '../controllers/theme_controller.dart';
import '../models/chat_model.dart';
import '../services/llm_service.dart';
import '../widgets/chat_sidebar.dart';
import 'chat_tab.dart';
import 'model_library_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatCtrl = Get.find<ChatController>();
  final _modelCtrl = Get.find<ModelController>();
  final _llm = Get.find<LlmService>();
  final _themeCtrl = Get.find<ThemeController>();
  bool _sidebarOpen = true;

  // Mobile bottom nav index: 0=Chat, 1=Dev, 2=Models, 3=Settings
  int _mobileTabIndex = 0;

  // Desktop chat mode toggle (Chat vs Development)
  ChatMode _desktopMode = ChatMode.chat;

  // Scaffold key for drawer
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  ChatMode? get _mobileChatMode {
    if (_mobileTabIndex == 0) return ChatMode.chat;
    if (_mobileTabIndex == 1) return ChatMode.development;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Stack(
      children: [
        if (isDesktop) _buildDesktopLayout() else _buildMobileLayout(),
        // ── Global model loading overlay ──
        _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Obx(() {
      if (!_modelCtrl.isImportingModel.value) return const SizedBox.shrink();

      final progress = _modelCtrl.loadingProgress.value;
      final percent = (progress * 100).clamp(0, 100).toInt();
      final msg = _modelCtrl.loadingStatusMsg.value;
      final filename = _modelCtrl.loadingModelFilename.value ?? 'Model';

      // Derive a short display name from the filename
      final displayName = filename.endsWith('.gguf')
          ? filename.substring(0, filename.length - 5)
          : filename;

      return Material(
        color: Colors.transparent,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: context.bgPanel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Circular progress
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: progress <= 0 ? null : progress.clamp(0.0, 1.0),
                            strokeWidth: 5,
                            backgroundColor: context.border,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.accent,
                            ),
                          ),
                        ),
                        if (percent > 0)
                          Text(
                            '$percent%',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.text,
                            ),
                          ),
                        if (percent <= 0)
                          Icon(
                            Icons.hourglass_empty_rounded,
                            size: 24,
                            color: context.textD,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Model name
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.text,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Status message
                  Text(
                    msg.isNotEmpty ? msg : 'Importing file...',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textM,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Hint for large models
                  if (progress == 0)
                    Text(
                      'Large models (5GB+) take about 30-50 seconds for Android to process. Please wait.',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.textD,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 20),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _modelCtrl.cancelImport(),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: BorderSide(
                          color: AppColors.red.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // MOBILE LAYOUT — Bottom nav with 4 tabs + drawer for chat history
  // ═══════════════════════════════════════════════════════════════
  Widget _buildMobileLayout() {
    final drawerMode = _mobileChatMode;

    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: context.bg,
      resizeToAvoidBottomInset: true,
      // ── Left drawer for chat history (only meaningful on the two chat tabs) ──
      drawer: Drawer(
        backgroundColor: context.bg,
        child: SafeArea(
          child: Column(
            children: [
              // Drawer header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.border, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        drawerMode == ChatMode.development
                            ? Icons.code_rounded
                            : Icons.bolt_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      drawerMode == ChatMode.development
                          ? 'Development History'
                          : 'Chat History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const Spacer(),
                    // New chat button in drawer header
                    IconButton(
                      icon: Icon(
                        Icons.edit_square,
                        size: 20,
                        color: context.textM,
                      ),
                      onPressed: () {
                        _chatCtrl.newChat(mode: drawerMode ?? ChatMode.chat);
                        Navigator.pop(context); // close drawer
                      },
                      tooltip: 'New Chat',
                    ),
                  ],
                ),
              ),
              // Chat list
              Expanded(
                child: ChatSidebar(
                  mode: drawerMode,
                  onNewChat: () {
                    _chatCtrl.newChat(mode: drawerMode ?? ChatMode.chat);
                    Navigator.pop(context);
                  },
                  onSelectChat: (id) {
                    _chatCtrl.switchChat(id);
                    Navigator.pop(context);
                  },
                  onDeleteChat: (id) => _chatCtrl.deleteChat(id),
                  showNewChatButton: false,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false, // let the bottom nav handle the safe area
        child: IndexedStack(
          index: _mobileTabIndex,
          children: [
            // Tab 0: Chat
            ChatTab(
              mode: ChatMode.chat,
              mobile: true,
              onOpenDrawer: () => _mobileScaffoldKey.currentState?.openDrawer(),
              onBrowseModels: () => setState(() => _mobileTabIndex = 2),
            ),
            // Tab 1: Development
            ChatTab(
              mode: ChatMode.development,
              mobile: true,
              onOpenDrawer: () => _mobileScaffoldKey.currentState?.openDrawer(),
              onBrowseModels: () => setState(() => _mobileTabIndex = 2),
            ),
            // Tab 2: Models
            const ModelLibraryScreen(embedded: true),
            // Tab 3: Settings
            const SettingsScreen(embedded: true),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.bg,
          border: Border(top: BorderSide(color: context.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _mobileTabIndex,
          onDestinationSelected: (i) => setState(() => _mobileTabIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AppColors.accent.withOpacity(0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.chat_outlined, color: context.textM),
              selectedIcon: const Icon(
                Icons.chat_rounded,
                color: AppColors.accent,
              ),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.code_outlined, color: context.textM),
              selectedIcon: const Icon(
                Icons.code_rounded,
                color: AppColors.accent,
              ),
              label: 'Dev',
            ),
            NavigationDestination(
              icon: Icon(Icons.widgets_outlined, color: context.textM),
              selectedIcon: const Icon(
                Icons.widgets_rounded,
                color: AppColors.accent,
              ),
              label: 'Models',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: context.textM),
              selectedIcon: const Icon(
                Icons.settings_rounded,
                color: AppColors.accent,
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT — Sidebar + Top bar
  // ═══════════════════════════════════════════════════════════════
  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: context.bg,
      body: Row(
        children: [
          // Sidebar
          if (_sidebarOpen)
            SizedBox(
              width: 260,
              child: Container(
                decoration: BoxDecoration(
                  color: context.bgSidebar,
                  border: Border(
                    right: BorderSide(color: context.border, width: 0.5),
                  ),
                ),
                child: ChatSidebar(
                  mode: _desktopMode,
                  onNewChat: () => _chatCtrl.newChat(mode: _desktopMode),
                  onSelectChat: (id) => _chatCtrl.switchChat(id),
                  onDeleteChat: (id) => _chatCtrl.deleteChat(id),
                ),
              ),
            ),

          // Main content
          Expanded(
            child: Column(
              children: [
                _buildDesktopTopBar(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: IndexedStack(
                        index: _desktopMode == ChatMode.chat ? 0 : 1,
                        children: const [
                          ChatTab(mode: ChatMode.chat, mobile: false),
                          ChatTab(mode: ChatMode.development, mobile: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.bgHover.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeSwitchButton('Chat', Icons.chat_bubble_outline_rounded, ChatMode.chat),
          _modeSwitchButton('Dev', Icons.code_rounded, ChatMode.development),
        ],
      ),
    );
  }

  Widget _modeSwitchButton(String label, IconData icon, ChatMode mode) {
    final selected = _desktopMode == mode;
    return InkWell(
      onTap: () => setState(() => _desktopMode = mode),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : context.textM),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.textM,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Sidebar toggle
          IconButton(
            icon: Icon(
              _sidebarOpen
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
              size: 20,
              color: context.textM,
            ),
            onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
            tooltip: 'Toggle sidebar',
          ),

          const SizedBox(width: 8),

          // Chat / Development switch
          _buildDesktopModeSwitch(),

          const SizedBox(width: 12),

          // Model selector dropdown
          Obx(() {
            final fname = _modelCtrl.selectedModelFilename.value;
            final info = fname != null ? _modelCtrl.getModelInfo(fname) : null;
            return InkWell(
              onTap: () => Get.toNamed('/models'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: context.bgHover.withOpacity(0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info?.name ?? (fname ?? 'Select Model'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: context.textM,
                    ),
                  ],
                ),
              ),
            );
          }),

          const Spacer(),

          // Engine status
          Obx(
            () => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _llm.isLoadingModel.value
                        ? AppColors.orange
                        : _llm.isLoaded.value
                        ? AppColors.green
                        : AppColors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _llm.isLoadingModel.value
                      ? 'Loading... ${(_llm.loadingProgress.value * 100).toInt()}%'
                      : _llm.isLoaded.value
                      ? 'Ready'
                      : 'No Model',
                  style: TextStyle(fontSize: 12, color: context.textD),
                ),
                if (_llm.isLoaded.value && !_llm.isLoadingModel.value) ...[
                  const SizedBox(width: 8),
                  // Unload button on desktop
                  InkWell(
                    onTap: () => _modelCtrl.unloadCurrentModel(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.eject_rounded,
                            size: 14,
                            color: AppColors.orange,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Unload',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textD,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_llm.isGenerating.value) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${_llm.tokensPerSecond.value.toStringAsFixed(1)} t/s',
                    style: TextStyle(fontSize: 12, color: context.textM),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Theme toggle
          Obx(
            () => IconButton(
              icon: Icon(
                _themeCtrl.isDarkMode
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 20,
                color: context.textM,
              ),
              onPressed: () => _themeCtrl.toggleTheme(),
              tooltip: 'Toggle theme',
            ),
          ),

          // Settings
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 20, color: context.textM),
            onPressed: () => Get.toNamed('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
