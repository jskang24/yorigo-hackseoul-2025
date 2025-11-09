import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/recipe_service.dart';
import '../widgets/app_header.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final RecipeService _recipeService = RecipeService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Cached recipe lists
  List<Map<String, dynamic>> _allTimePopular = [];
  List<Map<String, dynamic>> _weeklyPopular = [];
  List<Map<String, dynamic>> _monthlyPopular = [];
  List<Map<String, dynamic>> _recentlyAdded = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecipes();

    // Add listener to search controller
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Run migration in background (it's safe to run multiple times)
      // It will skip recipes that already have the fields
      _recipeService.migrateExistingRecipes().catchError((e) {
        print('Migration error (may have already run): $e');
        // Continue even if migration fails
      });

      // Load all recipe lists in parallel
      final results = await Future.wait([
        _recipeService.getAllTimePopularRecipes(limit: 10),
        _recipeService.getWeeklyPopularRecipes(limit: 10),
        _recipeService.getMonthlyPopularRecipes(limit: 10),
        _recipeService.getRecentlyAddedRecipes(limit: 10),
      ]);

      setState(() {
        _allTimePopular = results[0];
        _weeklyPopular = results[1];
        _monthlyPopular = results[2];
        _recentlyAdded = results[3];
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading recipes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Check if recipe matches search query and return priority score
  // Returns: -1 if no match, 0+ for match priority (higher = better match)
  int _getSearchMatchPriority(Map<String, dynamic> recipe, String query) {
    if (query.isEmpty) return 0; // No search query, no priority

    final queryLower = query.toLowerCase();

    // Priority 3: Title match (highest priority)
    final title = recipe['title'] as String? ?? '';
    if (title.toLowerCase().contains(queryLower)) {
      return 3;
    }

    // Priority 2: Tags match
    final tags = recipe['tags'] as List? ?? [];
    for (var tag in tags) {
      final tagStr = tag.toString().toLowerCase();
      if (tagStr.contains(queryLower)) {
        return 2;
      }
    }

    // Priority 1: Categories match
    final categories = recipe['categories'] as Map<String, dynamic>? ?? {};
    for (var categoryList in categories.values) {
      if (categoryList is List) {
        for (var category in categoryList) {
          final categoryStr = category.toString().toLowerCase();
          if (categoryStr.contains(queryLower)) {
            return 1;
          }
        }
      }
    }

    // Priority 1: Ingredients match
    final recipeData = recipe['recipe'] as Map<String, dynamic>? ?? {};
    final ingredients = recipeData['ingredients'] as List? ?? [];
    for (var ingredient in ingredients) {
      if (ingredient is Map) {
        final item = ingredient['item']?.toString().toLowerCase() ?? '';
        if (item.contains(queryLower)) {
          return 1;
        }
      }
    }

    // No match
    return -1;
  }

  // Build search results with home page card format
  Widget _buildSearchResults(Brightness brightness) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _recipeService.getAllRecipes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.getTextTertiary(brightness),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '오류가 발생했습니다: ${snapshot.error}',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final allRecipes = snapshot.data ?? [];

        // Filter and sort with all recipes from database
        final recipesWithPriority = allRecipes
            .map((recipe) {
              final searchPriority = _getSearchMatchPriority(
                recipe,
                _searchQuery,
              );
              if (searchPriority == -1) {
                return {'recipe': recipe, 'priority': -1};
              }
              return {'recipe': recipe, 'priority': searchPriority};
            })
            .where((item) => item['priority'] != -1)
            .toList();

        // Sort by priority
        recipesWithPriority.sort((a, b) {
          final priorityA = a['priority'] as int;
          final priorityB = b['priority'] as int;
          if (priorityA != priorityB) {
            return priorityB.compareTo(priorityA);
          }
          final titleA =
              (a['recipe'] as Map<String, dynamic>)['title'] as String? ?? '';
          final titleB =
              (b['recipe'] as Map<String, dynamic>)['title'] as String? ?? '';
          return titleA.compareTo(titleB);
        });

        final filteredResults = recipesWithPriority
            .map((item) => item['recipe'] as Map<String, dynamic>)
            .toList();

        if (filteredResults.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: AppColors.getTextTertiary(brightness),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '검색 결과가 없습니다',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '검색 결과 (${filteredResults.length}개)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.getTextPrimary(brightness),
                  ),
                ),
                const SizedBox(height: 16),
                ...filteredResults.map(
                  (recipe) => _buildHomePageRecipeCard(recipe, brightness),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            // Search bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.getBackground(brightness),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.getBorder(brightness),
                    width: 1,
                  ),
                ),
              ),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.getBackgroundTertiary(brightness),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '레시피 검색...',
                          hintStyle: TextStyle(
                            color: AppColors.getTextTertiary(brightness),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.search,
                      size: 20,
                      color: AppColors.getTextTertiary(brightness),
                    ),
                  ],
                ),
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _searchQuery.isNotEmpty
                  ? _buildSearchResults(brightness)
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          // All time Popular
                          _buildSection(
                            title: '인기 최고',
                            recipes: _allTimePopular,
                            brightness: brightness,
                          ),
                          const SizedBox(height: 24),
                          // 주간 베스트
                          _buildSection(
                            title: '주간 베스트',
                            recipes: _weeklyPopular,
                            brightness: brightness,
                          ),
                          const SizedBox(height: 24),
                          // 월간 베스트
                          _buildSection(
                            title: '월간 베스트',
                            recipes: _monthlyPopular,
                            brightness: brightness,
                          ),
                          const SizedBox(height: 24),
                          // 가장 최근 추가된
                          _buildSection(
                            title: '가장 최근 추가된',
                            recipes: _recentlyAdded,
                            brightness: brightness,
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> recipes,
    required Brightness brightness,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
        ),
        const SizedBox(height: 12),
        recipes.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.getBackgroundSecondary(brightness),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '레시피가 없습니다',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                  ),
                ),
              )
            : SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: recipes.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildRecipeCard(recipes[index], brightness),
                    );
                  },
                ),
              ),
      ],
    );
  }

  Widget _buildRecipeCard(Map<String, dynamic> recipe, Brightness brightness) {
    final title = recipe['title'] as String? ?? '레시피';
    final thumbnailUrl = recipe['thumbnailUrl'] as String? ?? '';
    final calories = recipe['calories'] as num? ?? 0;
    final recipeId = recipe['id'] as String;

    // Calculate cooking time from steps
    final recipeData = recipe['recipe'] as Map<String, dynamic>? ?? {};
    final steps = recipeData['steps'] as List? ?? [];
    int totalMinutes = 0;
    for (var step in steps) {
      if (step is Map && step['est_minutes'] != null) {
        totalMinutes += (step['est_minutes'] as num).toInt();
      }
    }
    if (totalMinutes == 0) totalMinutes = 15;

    // Get first tag
    final tags = recipe['tags'] as List? ?? [];
    final firstTag = tags.isNotEmpty ? tags[0].toString() : '';

    return GestureDetector(
      onTap: () async {
        final parseResponse = await _recipeService.getRecipeById(recipeId);
        if (parseResponse != null && mounted) {
          Navigator.pushNamed(
            context,
            '/recipe-detail',
            arguments: {'parseResponse': parseResponse, 'recipeId': recipeId},
          );
        }
      },
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: AppColors.getBackground(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.getBorder(brightness), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                height: 100,
                width: double.infinity,
                color: AppColors.getBackgroundTertiary(brightness),
                child: thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.restaurant,
                            size: 32,
                            color: AppColors.getTextTertiary(brightness),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          );
                        },
                      )
                    : Icon(
                        Icons.restaurant,
                        size: 32,
                        color: AppColors.getTextTertiary(brightness),
                      ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recipe name
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.getTextPrimary(brightness),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Kcal, time, tag
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 12,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${calories.toInt()}kcal',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.getTextSecondary(brightness),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${totalMinutes}분',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.getTextSecondary(brightness),
                        ),
                      ),
                    ],
                  ),
                  if (firstTag.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        firstTag,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build recipe card in home page format (vertical list)
  Widget _buildHomePageRecipeCard(
    Map<String, dynamic> recipe,
    Brightness brightness,
  ) {
    final title = recipe['title'] as String? ?? '레시피';
    final recipeData = recipe['recipe'] as Map<String, dynamic>? ?? {};
    final ingredients = recipeData['ingredients'] as List? ?? [];
    final steps = recipeData['steps'] as List? ?? [];
    final calories = recipe['calories'] as num? ?? 0;
    final recipeId = recipe['id'] as String;
    final thumbnailUrl = recipe['thumbnailUrl'] as String? ?? '';

    // Calculate cooking time from steps
    int totalMinutes = 0;
    for (var step in steps) {
      if (step is Map && step['est_minutes'] != null) {
        totalMinutes += (step['est_minutes'] as num).toInt();
      }
    }
    // Default to 15 minutes if no time data
    if (totalMinutes == 0) totalMinutes = 15;

    // Get creator/username from source data
    final source = recipe['source'] as Map<String, dynamic>? ?? {};
    String creatorUsername = '@ChefAntoine'; // Default placeholder

    // Try to get creator from various possible fields
    if (source['uploader'] != null &&
        source['uploader'].toString().isNotEmpty) {
      final uploader = source['uploader'].toString();
      creatorUsername = uploader.startsWith('@') ? uploader : '@$uploader';
    } else if (source['channel'] != null &&
        source['channel'].toString().isNotEmpty) {
      final channel = source['channel'].toString();
      creatorUsername = channel.startsWith('@') ? channel : '@$channel';
    } else if (source['uploader_id'] != null &&
        source['uploader_id'].toString().isNotEmpty) {
      final uploaderId = source['uploader_id'].toString();
      creatorUsername = uploaderId.startsWith('@')
          ? uploaderId
          : '@$uploaderId';
    } else if (recipe['chefHandle'] != null &&
        recipe['chefHandle'].toString().isNotEmpty) {
      final chefHandle = recipe['chefHandle'].toString();
      creatorUsername = chefHandle.startsWith('@')
          ? chefHandle
          : '@$chefHandle';
    }

    final chefImageUrl = recipe['chefImageUrl'] as String?;

    return InkWell(
      onTap: () async {
        // Fetch full recipe data and navigate to detail screen
        final parseResponse = await _recipeService.getRecipeById(recipeId);
        if (parseResponse != null && mounted) {
          Navigator.pushNamed(
            context,
            '/recipe-detail',
            arguments: {'parseResponse': parseResponse, 'recipeId': recipeId},
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('레시피를 불러올 수 없습니다'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F1E8), // Light beige background
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left section - Image (30%)
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: thumbnailUrl.isNotEmpty
                    ? Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.getBackgroundTertiary(brightness),
                            child: Center(
                              child: Icon(
                                Icons.restaurant,
                                size: 48,
                                color: AppColors.getTextTertiary(brightness),
                              ),
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: AppColors.getBackgroundTertiary(brightness),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: AppColors.getBackgroundTertiary(brightness),
                        child: Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 48,
                            color: AppColors.getTextTertiary(brightness),
                          ),
                        ),
                      ),
              ),
            ),
            // Right section - Content (70%)
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Recipe title
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.getTextPrimary(brightness),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Ingredient count
                    Text(
                      '${ingredients.length} total ingredients',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Recipe details row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Difficulty badge
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Center(
                              child: Text(
                                'A',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Separator
                          Container(
                            width: 1,
                            height: 14,
                            color: AppColors.getBorderSecondary(brightness),
                          ),
                          const SizedBox(width: 6),
                          // Time icon
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppColors.getTextPrimary(brightness),
                          ),
                          const SizedBox(width: 3),
                          // Time text
                          Text(
                            '${totalMinutes}분',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Separator
                          Container(
                            width: 1,
                            height: 14,
                            color: AppColors.getBorderSecondary(brightness),
                          ),
                          const SizedBox(width: 6),
                          // Calories icon
                          Icon(
                            Icons.local_fire_department_outlined,
                            size: 14,
                            color: AppColors.getTextPrimary(brightness),
                          ),
                          const SizedBox(width: 3),
                          // Calories text
                          Text(
                            '${calories.toInt()}KCal',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Creator information
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Creator profile picture with laurel wreath
                        Stack(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFFFD700), // Gold color
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child:
                                    chefImageUrl != null &&
                                        chefImageUrl.isNotEmpty
                                    ? Image.network(
                                        chefImageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color:
                                                AppColors.getBackgroundTertiary(
                                                  brightness,
                                                ),
                                            child: Icon(
                                              Icons.person,
                                              size: 18,
                                              color: AppColors.getTextTertiary(
                                                brightness,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: AppColors.getBackgroundTertiary(
                                          brightness,
                                        ),
                                        child: Icon(
                                          Icons.person,
                                          size: 18,
                                          color: AppColors.getTextTertiary(
                                            brightness,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        // Creator username
                        Expanded(
                          child: Text(
                            creatorUsername,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
}
