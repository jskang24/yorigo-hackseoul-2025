import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();

  int _savedRecipesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedRecipesCount();
  }

  Future<void> _loadSavedRecipesCount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Get saved recipes count for display
    final savedRecipeIds = await _userService.getSavedRecipes(user.uid);
    if (mounted) {
      setState(() {
        _savedRecipesCount = savedRecipeIds.length;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppColors.getBackground(brightness),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              onLoginPressed: () {
                Navigator.pushNamed(context, '/login');
              },
            ),
            Expanded(
              child: StreamBuilder<User?>(
                stream: _authService.authStateChanges,
                builder: (context, snapshot) {
                  // Show loading while checking auth state
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  final user = snapshot.data;

                  if (user == null) {
                    return _buildLoginPrompt(brightness);
                  }

                  // Reload saved recipes count when user changes
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _loadSavedRecipesCount();
                  });

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildProfileCard(user, brightness),
                        _buildProfileMenuSection(brightness),
                        _buildMenuItems(brightness),
                        _buildFooter(brightness),
                        const SizedBox(height: 24),
                        _buildLogoutButton(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(Brightness brightness) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 64,
              color: AppColors.getTextTertiary(brightness),
            ),
            const SizedBox(height: 16),
            Text(
              '로그인이 필요합니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.getTextPrimary(brightness),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '프로필을 보려면 로그인해주세요',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.getTextSecondary(brightness),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                '로그인',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(User user, Brightness brightness) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.getBackgroundSecondary(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.getBorder(brightness), width: 1),
      ),
      child: Column(
        children: [
          // Profile header with avatar, name, email, and edit button
          Row(
            children: [
              // Avatar
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
              // Name and email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? '사용자',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.getTextPrimary(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Edit button
              IconButton(
                onPressed: () {
                  // TODO: Navigate to edit profile screen
                  Navigator.pushNamed(context, '/settings');
                },
                icon: Icon(
                  Icons.edit,
                  size: 20,
                  color: AppColors.getTextSecondary(brightness),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuSection(Brightness brightness) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.getBackgroundSecondary(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.getBorder(brightness), width: 1),
      ),
      child: Column(
        children: [
          _buildProfileMenuItem(
            icon: Icons.favorite_outline,
            iconColor: Colors.green,
            title: '건강 관리',
            subtitle: '건강 정보 관리',
            brightness: brightness,
            isDisabled: true,
          ),
          _buildDivider(brightness),
          _buildProfileMenuItem(
            icon: Icons.bookmark_outline,
            iconColor: Colors.blue,
            title: '저장한 레시피',
            subtitle: '$_savedRecipesCount개',
            brightness: brightness,
            isDisabled: true,
          ),
          _buildDivider(brightness),
          _buildProfileMenuItem(
            icon: Icons.star_outline,
            iconColor: Colors.orange,
            title: '내 리뷰',
            subtitle: '리뷰 작성하기',
            brightness: brightness,
            isDisabled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Brightness brightness,
    bool isDisabled = false,
  }) {
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // Icon with colored background
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: iconColor),
              ),
              const SizedBox(width: 16),
              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.getTextPrimary(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron icon
              Icon(
                Icons.chevron_right,
                size: 24,
                color: AppColors.getTextTertiary(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItems(Brightness brightness) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.getBackgroundSecondary(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.getBorder(brightness), width: 1),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.settings,
            iconColor: AppColors.getTextSecondary(brightness),
            title: '설정',
            brightness: brightness,
            onTap: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          _buildDivider(brightness),
          _buildMenuItem(
            icon: Icons.help_outline,
            iconColor: AppColors.getTextSecondary(brightness),
            title: '고객센터',
            brightness: brightness,
            onTap: () {
              // TODO: Navigate to customer center
            },
          ),
          _buildDivider(brightness),
          _buildMenuItem(
            icon: Icons.shield_outlined,
            iconColor: AppColors.getTextSecondary(brightness),
            title: '개인정보 처리방침',
            brightness: brightness,
            onTap: () {
              // TODO: Navigate to privacy policy
            },
          ),
          _buildDivider(brightness),
          _buildMenuItem(
            icon: Icons.description_outlined,
            iconColor: AppColors.getTextSecondary(brightness),
            title: '이용약관',
            brightness: brightness,
            onTap: () {
              // TODO: Navigate to terms of service
            },
          ),
          _buildDivider(brightness),
          _buildMenuItem(
            icon: Icons.info_outline,
            iconColor: AppColors.getTextSecondary(brightness),
            title: 'Yorigo 소개',
            brightness: brightness,
            onTap: () {
              // TODO: Navigate to about
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Brightness brightness,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.getTextPrimary(brightness),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: AppColors.getTextTertiary(brightness),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(Brightness brightness) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.getBorder(brightness),
      indent: 56, // Align with text after icon
    );
  }

  Widget _buildFooter(Brightness brightness) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            '버전 1.0.0',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.getTextTertiary(brightness),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '© 2025 Yorigo. All rights reserved.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.getTextTertiary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: _handleLogout,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '로그아웃',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
