import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart'; // 付費項目
import 'package:flutter_localizations/flutter_localizations.dart'; // 本地化
import '../../l10n/generated/app_localizations.dart'; // 語言
import '../../providers/locale_provider.dart'; // 本地化
import '../../providers/social_provider.dart';
import '../../providers/iap_provider.dart';
import '../../providers/auth_provider.dart'; // 登入系統
import '../../providers/weather_provider.dart';
import '../../services/audio_service.dart';
import '../widgets/farm_hud_message_bar.dart';
import '../overlay/tools_theme.dart'; // 定義顏色和底部按鈕
import '../../models/user_profile_model.dart';
import '../screens/tutorial_screen.dart'; // 教學
import '../../config/iap_products.dart'; // 商品
import '../../data/asset_paths.dart'; // 圖示路徑（credit 區塊用）
import '../../data/toast_messages.dart';

// ── ToolboxOverlay ────────────────────────────────────────────────────────────

class ToolboxOverlay extends ConsumerStatefulWidget {
  final Future<void> Function()? onLoad;
  final void Function(String message)? onToast;
  final bool initialShowSetting;

  const ToolboxOverlay(
      {super.key, this.onLoad, this.onToast, this.initialShowSetting = false});

  @override
  ConsumerState<ToolboxOverlay> createState() => _ToolboxOverlayState();
}

class _ToolboxOverlayState extends ConsumerState<ToolboxOverlay>
    with SingleTickerProviderStateMixin {
  AppLocalizations get l10n => AppLocalizations.of(context)!; // 本地化
  bool _isLoading = false;
  bool _isLoggingOut = false;
  bool _isDeletingAccount = false;
  bool _isMuted = AudioService().isMuted;
  bool _showCredit = false;
  bool _showAccount = false;
  bool _showSetting = false; // 大項目：Setting（收納 Music / Tutorial）
  bool _showChangeName = false;
  bool _showChangePassword = false;
  bool _showLanguage = false;
  final TextEditingController _nameController = TextEditingController();
  bool _isSavingName = false;
  String? _nameErrorMessage;
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isSavingPassword = false;
  String? _passwordErrorMessage;
  late final AnimationController _paperAnimController;

  @override
  void initState() {
    super.initState();
    _showSetting = widget.initialShowSetting;
    // 讀取目前 AudioService 的靜音狀態
    _isMuted = AudioService().isMuted;
    _paperAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _paperAnimController.forward();
    });
  }

  @override
  void dispose() {
    _paperAnimController.dispose();
    _nameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _handleLoad() async {
    AudioService().playButton(); // 播放按鈕音效
    if (_isLoading || widget.onLoad == null) return;

    // 1. 跳出確認彈窗
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.settingsLoadProgress,
      content: l10n.settingsConfirmLoadSavedData,
      cancelText: l10n.toastCancel,
      confirmText: l10n.settingsLoad,
      confirmColor: kAccent,
    );

    // 2. 檢查是否取消或頁面已卸載
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await widget.onLoad!();

      if (!mounted) return;
      setState(() => _isLoading = false);
      _showResultOverlay(l10n.settingsLoadSuccess, DateTime.now());
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onToast?.call(ToastMessages.failed(l10n, e));
      }
    }
  }

  Future<void> _handleLogout() async {
    AudioService().playButton(); // 播放按鈕音效
    if (_isLoggingOut) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.settingsLogOut,
      content: l10n.settingsConfirmLogOut,
      cancelText: l10n.toastCancel,
      confirmText: l10n.settingsLogOut,
      confirmColor: kAccent,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoggingOut = true);
    try {
      await ref.read(authProvider.notifier).signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  Future<void> _handleDeleteAccount() async {
    AudioService().playButton(); // 播放按鈕音效
    if (_isDeletingAccount) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.settingsDeleteAccount,
      content: l10n.settingsDeleteAccountWarning,
      cancelText: l10n.toastCancel,
      confirmText: l10n.settingsDelete,
      confirmColor: Colors.redAccent,
    );
    if (confirmed != true || !mounted) return;

    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(),
    );
    if (doubleConfirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  Future<void> _handleUpdateName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || _isSavingName) return;

    AudioService().playButton();
    setState(() {
      _isSavingName = true;
      _nameErrorMessage = null;
    });

    final result =
        await ref.read(authProvider.notifier).updateDisplayName(newName);

    if (!mounted) return;
    setState(() => _isSavingName = false);

    switch (result) {
      case UpdateNameResult.success:
        setState(() => _showAccount = false);
        widget.onToast?.call(l10n.settingsNameUpdated);
      case UpdateNameResult.tooSoon:
        setState(() => _nameErrorMessage = l10n.settingsNameChangeInterval);
      case UpdateNameResult.nameTaken:
        setState(() => _nameErrorMessage = l10n.settingsNameTaken);
      case UpdateNameResult.error:
        setState(() => _nameErrorMessage = ToastMessages.genericError(l10n));
    }
  }

  Future<void> _handleUpdatePassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty || _isSavingPassword) return;

    if (newPassword != confirmPassword) {
      setState(() => _passwordErrorMessage = l10n.settingsPasswordMismatch);
      return;
    }

    AudioService().playButton();
    setState(() {
      _isSavingPassword = true;
      _passwordErrorMessage = null;
    });

    final result =
        await ref.read(authProvider.notifier).updatePassword(newPassword);

    if (!mounted) return;
    setState(() => _isSavingPassword = false);

    switch (result) {
      case UpdatePasswordResult.success:
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        widget.onToast?.call(l10n.settingsPasswordUpdated);
      case UpdatePasswordResult.weakPassword:
        setState(() => _passwordErrorMessage = l10n.settingsWeakPassword);
      case UpdatePasswordResult.error:
        setState(
            () => _passwordErrorMessage = ToastMessages.genericError(l10n));
    }
  }

  void _showResultOverlay(String message, DateTime time) {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) {
        // 1. 設定 2 秒後自動關閉
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });

        // 2. 必須使用 return 回傳 Widget
        return Center(
          child: Material(
            color: Colors.transparent, // 移除黃色底線的關鍵
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: FarmHudMessageBar(
                borderRadius: BorderRadius.zero,
                onTap: () => Navigator.pop(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          message,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                            color: Colors.green, // 綠色標題
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}",
                      style:
                          const TextStyle(color: Colors.black45, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PaperOverlayShell(
      animation: _paperAnimController,
      alignment: Alignment.center,
      onBackgroundTap: () => Navigator.of(context).pop(),
      tabHeight: 0.0,
      headerHeight: OverlayLayoutTheme.headerHeight,
      bottomBarHeight: 0.0,
      heightRatio: OverlayLayoutTheme.heightRatio,
      maxHeight: OverlayLayoutTheme.maxOverlayHeight,
      tabs: const SizedBox.shrink(),
      header: _buildHeader(),
      content: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Material(
            type: MaterialType.transparency,
            child: _buildButtons(),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: OverlayLayoutTheme.headerPadding,
      child: Center(
        child: HeaderFitText(
          text: l10n.toastSettings,
          style: kFontTitle,
        ),
      ),
    );
  }

  Widget _buildButtons() {
    final saveConflict = ref.watch(socialProvider).saveConflict;
    final lastSaveAt = ref.watch(socialProvider).lastSaveAt;
    final localLastSaveAt = lastSaveAt?.toLocal();
    // 或起薪點數
    final points = ref.watch(socialProvider).profile?.points ?? 0;

    // 格式化時間顯示（例如：2024-05-04 14:30）
    final saveTimeString = localLastSaveAt != null
        ? "${localLastSaveAt.year}-${localLastSaveAt.month.toString().padLeft(2, '0')}-${localLastSaveAt.day.toString().padLeft(2, '0')} ${localLastSaveAt.hour.toString().padLeft(2, '0')}:${localLastSaveAt.minute.toString().padLeft(2, '0')}:${localLastSaveAt.second.toString().padLeft(2, '0')}"
        : l10n.settingsNoCloudSaveFound;
    if (_showLanguage) {
      final currentCode = ref.watch(localeProvider).languageCode;

      Widget buildLangOption(String code, String label) {
        final isSelected = currentCode == code;
        return _ToolboxBtn(
          label: isSelected ? '✓ $label' : label,
          enabled: true,
          textColor: isSelected ? kSubtle : null,
          borderColor: isSelected ? kSubtle : null,
          onTap: () {
            AudioService().playButton();
            ref.read(localeProvider.notifier).setLocale(code);
            setState(() {}); // 刷新勾選狀態
          },
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsLanguage,
              style: const TextStyle(
                  fontSize: 15, color: kAccent, fontFamily: kFont)),
          const SizedBox(height: 8),
          buildLangOption('en', 'English'),
          const SizedBox(height: 8),
          buildLangOption('ja', '日本語'),
          const SizedBox(height: 8),
          // buildLangOption('zh', l10n.settingsTraditionalChinese),
          // const SizedBox(height: 8),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() => _showLanguage = false),
          ),
        ],
      );
    }

    if (_showChangeName) {
      final currentName = ref.watch(socialProvider).profile?.displayName ?? '';
      final newName = _nameController.text.trim();
      final nameChanged = newName.isNotEmpty && newName != currentName;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsCurrentName,
              style: const TextStyle(
                  fontSize: 15, color: kAccent, fontFamily: kFont)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            style: const TextStyle(
                color: kAccent, fontFamily: kFont, fontSize: 15),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.settingsEnterNewName,
              hintStyle:
                  TextStyle(color: kAccent.withOpacity(0.3), fontFamily: kFont),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle.withOpacity(0.3))),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle)),
            ),
          ),
          if (_nameErrorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_nameErrorMessage!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 15, fontFamily: kFont)),
          ],
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: _isSavingName ? l10n.settingsSaving : l10n.settingsSaveName,
            enabled: !_isSavingName && nameChanged,
            onTap: _handleUpdateName,
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() {
              _showChangeName = false;
              _nameErrorMessage = null;
            }),
          ),
        ],
      );
    }

    if (_showChangePassword) {
      final hasPassword = ref.watch(authProvider.notifier).hasPasswordLogin;
      final passwordFilled = _newPasswordController.text.isNotEmpty &&
          _confirmPasswordController.text.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              hasPassword
                  ? l10n.settingsChangePassword
                  : l10n.settingsSetPassword,
              style: const TextStyle(
                  fontSize: 15, color: kAccent, fontFamily: kFont)),
          if (!hasPassword) ...[
            const SizedBox(height: 4),
            Text(l10n.settingsPasswordSignInHint,
                style: TextStyle(
                    fontSize: 12,
                    color: kAccent.withOpacity(0.6),
                    fontFamily: kFont)),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
                color: kAccent, fontFamily: kFont, fontSize: 15),
            decoration: InputDecoration(
              hintText: l10n.settingsNewPassword,
              hintStyle:
                  TextStyle(color: kAccent.withOpacity(0.3), fontFamily: kFont),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle.withOpacity(0.3))),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
                color: kAccent, fontFamily: kFont, fontSize: 15),
            decoration: InputDecoration(
              hintText: l10n.settingsConfirmNewPassword,
              hintStyle:
                  TextStyle(color: kAccent.withOpacity(0.3), fontFamily: kFont),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle.withOpacity(0.3))),
              focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: kSubtle)),
            ),
          ),
          if (_passwordErrorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_passwordErrorMessage!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 15, fontFamily: kFont)),
          ],
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: _isSavingPassword
                ? l10n.settingsSaving
                : (hasPassword
                    ? l10n.settingsChangePassword
                    : l10n.settingsSetPasswordButton),
            enabled: !_isSavingPassword && passwordFilled,
            onTap: _handleUpdatePassword,
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() {
              _showChangePassword = false;
              _passwordErrorMessage = null;
              _newPasswordController.clear();
              _confirmPasswordController.clear();
            }),
          ),
        ],
      );
    }

    if (_showAccount) {
      final hasPassword = ref.watch(authProvider.notifier).hasPasswordLogin;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ToolboxBtn(
            label: l10n.settingsLanguage,
            enabled: true,
            onTap: () => setState(() => _showLanguage = true),
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: l10n.settingsChangeName,
            enabled: true,
            onTap: () => setState(() {
              _nameController.text =
                  ref.read(socialProvider).profile?.displayName ?? '';
              _showChangeName = true;
            }),
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: hasPassword
                ? l10n.settingsChangePassword
                : l10n.settingsSetPassword,
            enabled: true,
            onTap: () => setState(() => _showChangePassword = true),
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label:
                _isLoggingOut ? l10n.settingsLoggingOut : l10n.settingsLogOut,
            enabled: !_isLoggingOut,
            onTap: _handleLogout,
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: _isDeletingAccount
                ? l10n.settingsDeleting
                : l10n.settingsDeleteAccount,
            enabled: !_isDeletingAccount,
            onTap: _handleDeleteAccount,
            danger: true,
          ),
          const SizedBox(height: 64),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() => _showAccount = false),
          ),
        ],
      );
    }

    // ── 新增大項目：Setting（收納原本的 Music On/Off 與 Tutorial） ──────────
    if (_showSetting) {
      final weather = ref.watch(weatherProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: '${weather.temperature?.toStringAsFixed(1) ?? "--"}°C  '
                '${weather.humidity?.toStringAsFixed(0) ?? "--"}%',
            enabled: false, // 暫時停用手動更新，保留天氣數值顯示。
            onTap: () async {
              AudioService().playButton();
              await ref.read(weatherProvider.notifier).refresh();
              if (!mounted) return;
              final error = ref.read(weatherProvider).errorMessage;
              if (error != null) widget.onToast?.call(error);
            },
          ),
          const SizedBox(height: 8),
          _ToolboxBtn(
            label: l10n.settingsTutorial,
            enabled: true,
            onTap: () {
              AudioService().playButton();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TutorialScreen(
                    onFinish: () => Navigator.of(context).pop(), // 教學結束就關掉這頁
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          _ToolboxBtn(
            label: _isMuted ? l10n.settingsMusicOff : l10n.settingsMusicOn,
            enabled: true,
            onTap: () async {
              await AudioService().toggleMute();
              setState(() => _isMuted = AudioService().isMuted);
            },
          ),
          const SizedBox(height: 32),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() => _showSetting = false),
          ),
        ],
      );
    }

    if (_showCredit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Just one person behind this app\nno big team, no fancy office, just me and my laptop\nEvery purchase you make is basically buying me another coffee to stay awake and keep improving things\n\nI\'ll keep updating so it stays awesome! ♡',
            style: const TextStyle(
              fontSize: 15,
              color: kAccent,
              fontFamily: kFont,
            ),
          ),
          const SizedBox(height: 10),
          Text('Producer: Elena Chen',
              style:
                  TextStyle(color: kAccent, fontSize: 15, fontFamily: kFont)),
          const SizedBox(height: 12),
          // ── 聯絡方式（Web / Discord / Mail，橫排三個圖示按鈕） ──────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CreditIconButton(
                iconPath: AssetPaths.creditWeb,
                onTap: () =>
                    launchUrl(Uri.parse('https://www.dollarbasellc.com/')),
              ),
              const SizedBox(width: 24),
              _CreditIconButton(
                iconPath: AssetPaths.creditDiscord,
                onTap: () =>
                    launchUrl(Uri.parse('https://discord.gg/fK7VvhY2Mc')),
              ),
              const SizedBox(width: 24),
              _CreditIconButton(
                iconPath: AssetPaths.creditMail,
                onTap: () =>
                    launchUrl(Uri.parse('mailto:404chenhavefun@gmail.com')),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Music: のる',
              style:
                  TextStyle(color: kAccent, fontSize: 15, fontFamily: kFont)),
          GestureDetector(
            onTap: () =>
                launchUrl(Uri.parse('https://dova-s.jp/bgm?composers=432')),
            child: Text('https://dova-s.jp/bgm?composers=432',
                style: TextStyle(
                    color: kSubtle,
                    fontSize: 12,
                    fontFamily: kFont,
                    decoration: TextDecoration.underline)),
          ),
          const SizedBox(height: 32),
          _ToolboxBtn(
            label: l10n.settingsBack,
            enabled: true,
            onTap: () => setState(() => _showCredit = false),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 點數錢包
        Text(
          l10n.settingsCollectFlowers,
          style: kFontContent,
        ),
        const SizedBox(height: 5),
        _ToolboxBtn(
          label: RedeemMessages.pointsLabel(l10n, points),
          textColor: kAccent, // 文字顏色
          borderColor: kSubtle, // 自訂底色
          enabled: true,
          onTap: () async {
            final List<ProductDetails> products =
                await ref.read(iapProductsProvider.future);
            showPointsStoreDialog(context, ref, products);
          },
        ),
        const SizedBox(height: 8),
        // Setting 大項目收納 Music / Tutorial
        _ToolboxBtn(
          label: l10n.settingsSetting,
          enabled: true,
          onTap: () => setState(() => _showSetting = true),
        ),
        const SizedBox(height: 8),
        _ToolboxBtn(
          label: l10n.settingsAccount,
          enabled: true,
          onTap: () => setState(() => _showAccount = true),
        ),
        const SizedBox(height: 8),
        _ToolboxBtn(
          label: l10n.settingsCredits,
          enabled: true,
          onTap: () => setState(() => _showCredit = true),
        ),
        const SizedBox(height: 8),

        // LOAD 按鈕 並顯示讀取狀態或最後存檔時間
        _ToolboxBtn(
          label: _isLoading
              ? l10n.settingsLoading
              : saveConflict
                  ? '⚠ ${l10n.settingsLoadSave(saveTimeString)}'
                  : saveTimeString.isNotEmpty
                      ? l10n.settingsLoadSave(saveTimeString)
                      : l10n.settingsLoad,
          enabled: widget.onLoad != null && !_isLoading,
          onTap: _handleLoad,
        ),
      ],
    );
  }
}

// ── _ToolboxBtn ───────────────────────────────────────────────────────────────

class _ToolboxBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;
  final Color? backgroundColor; // 自訂底色
  final Color? textColor; // 自訂文字色
  final Color? borderColor; // 自訂邊框色

  const _ToolboxBtn({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = danger ? Colors.redAccent : kAccent;
    final resolvedBorderColor = borderColor ?? defaultColor;
    final resolvedTextColor = textColor ?? defaultColor;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: CustomPaint(
        painter: enabled
            ? SolidBorderPainter(color: resolvedBorderColor)
            : DashedBorderPainter(color: resolvedBorderColor),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: backgroundColor, // 沒給就維持透明
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: enabled
                  ? resolvedTextColor
                  : resolvedTextColor.withOpacity(0.4),
              fontFamily: kFont,
            ),
          ),
        ),
      ),
    );
  }
}

// ── _CreditIconButton ─────────────────────────────────────────────────────────
// Credit 頁面用的圖示按鈕（Web / Discord / Mail），點擊後開啟對應連結
class _CreditIconButton extends StatelessWidget {
  final String iconPath;
  final VoidCallback onTap;
  final double size;

  const _CreditIconButton({
    required this.iconPath,
    required this.onTap,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Image.asset(
        iconPath,
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
        fit: BoxFit.contain,
      ),
    );
  }
}

// ── _DeleteConfirmDialog ──────────────────────────────────────────────────────

class _DeleteConfirmDialog extends StatefulWidget {
  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  AppLocalizations get l10n => AppLocalizations.of(context)!; // 本地化
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: const Color(0xFF2a1a1a),
      title: Text(l10n.settingsAreYouSure,
          style: TextStyle(color: Color(0xFFe8a0a0))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsTypeDeleteConfirm,
              style: TextStyle(color: Color(0xFFc0a0a0))),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFFe8a0a0)),
            decoration: InputDecoration(
              hintText: 'DELETE',
              hintStyle: const TextStyle(color: Color(0xFF6a4a4a)),
              filled: true,
              fillColor: const Color(0xFF1a0a0a),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: const BorderSide(color: Color(0xFF6a3a3a)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: const BorderSide(color: Color(0xFF6a3a3a)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: const BorderSide(color: Colors.redAccent, width: 2),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.toastCancel,
              style: TextStyle(color: Color(0xFF8aaa60))),
        ),
        TextButton(
          onPressed: () {
            if (_controller.text.trim() != 'DELETE') return;
            Navigator.of(context).pop(true);
          },
          child: Text(l10n.settingsConfirmDelete,
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }
}

//  ── 付款付費區 ──────────────────────────────────────────────────────
void showPointsStoreDialog(
    BuildContext context, WidgetRef ref, List<ProductDetails> products) {
  AudioService().playButton();
  final l10n = AppLocalizations.of(context)!; // 本地化
  final price100 = getProductPrice(products, 'points_pack_100');
  final price350 = getProductPrice(products, 'points_pack_350');

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: kPaperBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          l10n.settingsShop,
          style: TextStyle(
              color: kAccent,
              fontFamily: kFont,
              fontWeight: FontWeight.bold,
              letterSpacing: letterSpacing),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.settingsShopDescription,
              style: TextStyle(
                  color: kAccent,
                  fontFamily: kFont,
                  fontSize: 15,
                  letterSpacing: letterSpacing,
                  height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            _buildStoreOption(
              ctx,
              ref,
              title: RedeemMessages.pointsLabel(l10n, 100),
              subtitle: l10n.settingsBasicRefillPack,
              priceLabel: price100,
              productId: 'points_pack_100',
              rewardPoints: 100,
            ),
            const SizedBox(height: 8),
            _buildStoreOption(
              ctx,
              ref,
              title: RedeemMessages.pointsLabel(l10n, 350),
              subtitle: l10n.settingsValuePack,
              priceLabel: price350,
              productId: 'points_pack_350',
              rewardPoints: 350,
              isBestValue: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.toastCancel.toUpperCase(),
                style: TextStyle(
                    color: kSubtle,
                    fontFamily: kFont,
                    fontWeight: FontWeight.bold,
                    letterSpacing: letterSpacing)),
          ),
        ],
      );
    },
  );
}

// 點數商品選項
Widget _buildStoreOption(
  BuildContext dialogContext,
  WidgetRef ref, {
  required String title,
  required String subtitle,
  required String priceLabel,
  required String productId,
  required int rewardPoints,
  bool isBestValue = false,
}) {
  return GestureDetector(
    onTap: () {
      Navigator.of(dialogContext).pop();
      _triggerInAppPurchase(dialogContext, ref, productId, rewardPoints);
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kPaperBg,
        border: Border.all(
            color: isBestValue ? kSubtle : kAccent,
            width: isBestValue ? 2.0 : 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: kFont,
                      letterSpacing: letterSpacing)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: kSubtle,
                      fontSize: 11,
                      fontFamily: kFont,
                      letterSpacing: letterSpacing)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isBestValue ? kSubtle : kAccent,
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              priceLabel,
              style: TextStyle(
                color: isBestValue ? kAccent : kPaperBg,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                fontFamily: kFont,
                letterSpacing: letterSpacing,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// 觸發 Google 金流核心
Future<void> _triggerInAppPurchase(
  BuildContext context,
  WidgetRef ref,
  String productId,
  int pointsToGrant,
) async {
  final l10n = AppLocalizations.of(context)!; // 本地化
  final InAppPurchase iap = InAppPurchase.instance;

  void showRetroToast(String message) {
    showCenterToast(context, message);
  }

  if (!await iap.isAvailable()) {
    showRetroToast(l10n.settingsGooglePlayUnavailable);
    return;
  }

  final ProductDetailsResponse response =
      await iap.queryProductDetails({productId});
  if (response.productDetails.isNotEmpty) {
    await iap.buyConsumable(
      purchaseParam:
          PurchaseParam(productDetails: response.productDetails.first),
      autoConsume: false,
    );
  } else {
    showRetroToast(l10n.settingsProductNotFound);
  }
}
