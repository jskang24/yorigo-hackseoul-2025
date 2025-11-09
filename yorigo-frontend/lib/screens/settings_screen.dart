import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;
    final l10n = AppLocalizations.of(context);
    final localeService = LocaleProvider.of(context);
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppColors.getBackground(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.getBackground(brightness),
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.getTextPrimary(brightness),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n?.settings ?? '설정',
          style: TextStyle(
            color: AppColors.getTextPrimary(brightness),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // User Profile Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.getBackgroundSecondary(brightness),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Profile Icon
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 32,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // User Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? (l10n?.user ?? '사용자'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.getTextPrimary(brightness),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.getTextSecondary(
                                      brightness,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Settings Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: AppColors.getBackgroundSecondary(brightness),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildSettingsItem(
                            context: context,
                            brightness: brightness,
                            icon: Icons.language,
                            title: l10n?.language ?? '언어',
                            subtitle: localeService.currentLanguageName,
                            onTap: () =>
                                _handleLanguageChange(context, localeService),
                          ),
                          Divider(
                            height: 1,
                            color: AppColors.getBorder(brightness),
                          ),
                          _buildSettingsItem(
                            context: context,
                            brightness: brightness,
                            icon: Icons.dark_mode,
                            title: '다크 모드',
                            subtitle: '곧 출시 예정',
                            onTap: () {
                              // Disabled - coming soon
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('곧 출시 예정입니다'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            isDisabled: true,
                          ),
                          Divider(
                            height: 1,
                            color: AppColors.getBorder(brightness),
                          ),
                          _buildSettingsItem(
                            context: context,
                            brightness: brightness,
                            icon: Icons.logout,
                            title: l10n?.logout ?? '로그아웃',
                            onTap: () =>
                                _handleLogout(context, authService, l10n),
                            isDestructive: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required Brightness brightness,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isDisabled = false,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: isDestructive
                    ? Colors.red
                    : AppColors.getTextPrimary(brightness),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDestructive
                            ? Colors.red
                            : AppColors.getTextPrimary(brightness),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDestructive
                              ? Colors.red.withOpacity(0.7)
                              : AppColors.getTextSecondary(brightness),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing
              else
                Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: isDestructive
                      ? Colors.red
                      : AppColors.getTextSecondary(brightness),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLanguageChange(
    BuildContext context,
    LocaleService localeService,
  ) async {
    final currentLanguage = localeService.currentLanguageCode;
    final newLanguage = currentLanguage == 'ko' ? 'en' : 'ko';

    await localeService.setLocale(Locale(newLanguage));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newLanguage == 'ko'
                ? '언어가 한국어로 변경되었습니다'
                : 'Language changed to English',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleLogout(
    BuildContext context,
    AuthService authService,
    AppLocalizations? l10n,
  ) async {
    final brightness = Theme.of(context).brightness;
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.logout ?? '로그아웃'),
        content: Text(l10n?.logoutConfirm ?? '정말 로그아웃 하시겠습니까?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              l10n?.cancel ?? '취소',
              style: TextStyle(color: AppColors.getTextSecondary(brightness)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n?.logout ?? '로그아웃',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true && context.mounted) {
      try {
        await authService.signOut();
        if (context.mounted) {
          // Navigate back to home
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n?.logoutError(e.toString()) ?? '로그아웃 중 오류가 발생했습니다: $e',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
