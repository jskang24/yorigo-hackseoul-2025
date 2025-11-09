import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

class AppHeader extends StatelessWidget {
  final VoidCallback? onLoginPressed;

  const AppHeader({super.key, this.onLoginPressed});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.getBackground(brightness),
        border: Border(
          bottom: BorderSide(color: AppColors.getBorder(brightness), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/Yorigo_logo_transparent.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              const Text(
                '요리고',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          StreamBuilder<User?>(
            stream: authService.authStateChanges,
            builder: (context, snapshot) {
              final isLoggedIn = snapshot.data != null;

              if (isLoggedIn) {
                // Show profile icon when logged in
                return GestureDetector(
                  onTap: () {
                    // Navigate to profile tab in the navigation bar instead of a new page
                    final mainNavigator = MainNavigator.of(context);
                    if (mainNavigator != null) {
                      mainNavigator.navigateToProfile();
                    } else {
                      // Fallback to named route if MainNavigator not found
                      Navigator.pushNamed(context, '/profile');
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 24,
                      color: AppColors.primary,
                    ),
                  ),
                );
              } else if (onLoginPressed != null) {
                // Show login button when not logged in
                final l10n = AppLocalizations.of(context);
                return ElevatedButton(
                  onPressed: onLoginPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    l10n?.login ?? '로그인',
                    style: TextStyle(
                      color: AppColors.getBackground(brightness),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
    );
  }
}
