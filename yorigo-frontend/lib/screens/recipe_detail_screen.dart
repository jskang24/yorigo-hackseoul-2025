import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../models/recipe_models.dart' as models;
import '../services/recipe_service.dart';
import '../widgets/calendar_meal_dialog.dart';
import '../widgets/cooking_instruction_sheet.dart';

class RecipeDetailScreen extends StatefulWidget {
  final models.ParseResponse parseResponse;
  final String? recipeId; // Optional recipe ID for delete functionality

  const RecipeDetailScreen({
    super.key,
    required this.parseResponse,
    this.recipeId,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  int _portionCount = 2;
  final Set<String> _selectedIngredients = {};
  final RecipeService _recipeService = RecipeService();
  Map<String, List<String>> _categories = {};
  int _selectedTabIndex = 0; // 0: 재료, 1: 요리법, 2: 영양정보

  @override
  void initState() {
    super.initState();
    final recipe = widget.parseResponse.recipe;
    final baseServings = recipe.servings ?? 2;
    _portionCount = baseServings;

    // Initialize with all ingredients selected (we'll need to check pantry status later)
    for (int i = 0; i < recipe.ingredients.length; i++) {
      _selectedIngredients.add(i.toString());
    }

    // Initialize categories from source
    final source = widget.parseResponse.source;
    final categoriesRaw = source['categories'] as Map<String, dynamic>? ?? {};
    _categories = {
      'meat_type':
          (categoriesRaw['meat_type'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      'cuisine_type':
          (categoriesRaw['cuisine_type'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      'menu_type':
          (categoriesRaw['menu_type'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      'meal_time':
          (categoriesRaw['meal_time'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      'ingredient_type':
          (categoriesRaw['ingredient_type'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      'time_category':
          (categoriesRaw['time_category'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    };
  }

  String _getScaledAmount(double baseAmount) {
    final recipe = widget.parseResponse.recipe;
    final baseServings = recipe.servings ?? 2;
    final scaleFactor = _portionCount / baseServings;
    final scaledAmount = baseAmount * scaleFactor;

    // Format the number nicely
    if (scaledAmount % 1 == 0) {
      return scaledAmount.toInt().toString();
    } else if (scaledAmount < 10) {
      return scaledAmount.toStringAsFixed(1);
    } else {
      return scaledAmount.toInt().toString();
    }
  }

  Future<void> _handleDelete() async {
    if (widget.recipeId == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('레시피 삭제'),
        content: const Text('이 레시피를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _recipeService.deleteRecipe(widget.recipeId!);
        if (mounted) {
          Navigator.pop(context); // Go back to recipes screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('레시피가 삭제되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('레시피 삭제 중 오류가 발생했습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.parseResponse.recipe;
    final nutrition = widget.parseResponse.nutrition;
    final source = widget.parseResponse.source;
    final baseServings = recipe.servings ?? 2;
    final calories = nutrition.llmEstimate?.caloriesPerServing ?? 0;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppColors.getBackground(brightness),
      body: SafeArea(
        child: Column(
          children: [
            // Top Thumbnail with Overlays
            _buildThumbnailHeader(source, brightness),

            // Main Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Recipe Title and Info
                    _buildTitleSection(recipe, calories, brightness),

                    // Tabbed Content Section
                    _buildTabbedContent(
                      recipe,
                      nutrition,
                      baseServings,
                      brightness,
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailHeader(
    Map<String, dynamic> source,
    Brightness brightness,
  ) {
    final thumbnailUrl = source['thumbnail'] as String? ?? '';
    final uploader = source['uploader'] as String? ?? '';
    final channel = source['channel'] as String? ?? '';
    final platform = source['platform'] as String? ?? '';

    // Get creator username
    String creatorUsername = '@ChefAntoine';
    if (uploader.isNotEmpty) {
      creatorUsername = uploader.startsWith('@') ? uploader : '@$uploader';
    } else if (channel.isNotEmpty) {
      creatorUsername = channel.startsWith('@') ? channel : '@$channel';
    }

    // Get platform display name
    String platformName = 'Youtube.com';
    if (platform.toLowerCase() == 'youtube') {
      platformName = 'Youtube.com';
    } else if (platform.isNotEmpty) {
      platformName = '$platform.com';
    }

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail image
          thumbnailUrl.isNotEmpty
              ? Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.getBackgroundTertiary(brightness),
                      child: Center(
                        child: Icon(
                          Icons.restaurant,
                          size: 64,
                          color: AppColors.getTextTertiary(brightness),
                        ),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: AppColors.getBackgroundTertiary(brightness),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                )
              : Container(
                  color: AppColors.getBackgroundTertiary(brightness),
                  child: Center(
                    child: Icon(
                      Icons.restaurant,
                      size: 64,
                      color: AppColors.getTextTertiary(brightness),
                    ),
                  ),
                ),
          // Back button overlay (top left)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 24,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          // Share and Delete buttons overlay (top right)
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Share button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.share_outlined,
                      size: 20,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      // TODO: Implement share functionality
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 12),
                // Delete button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.white,
                    ),
                    onPressed: widget.recipeId != null ? _handleDelete : null,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          // Creator info overlay (bottom right)
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Creator handle overlay
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Creator profile picture with golden border
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFD700), // Gold color
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Container(
                            color: AppColors.getBackgroundTertiary(brightness),
                            child: Icon(
                              Icons.person,
                              size: 14,
                              color: AppColors.getTextTertiary(brightness),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        creatorUsername,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Platform overlay
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // YouTube logo icon (red circle)
                      if (platform.toLowerCase() == 'youtube')
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF0000), // YouTube red
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 12,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.video_library,
                          size: 20,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        platformName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection(
    models.Recipe recipe,
    double calories,
    Brightness brightness,
  ) {
    final source = widget.parseResponse.source;
    final tagsRaw = source['tags'] as List? ?? [];
    // Filter out empty strings, null values, and whitespace-only strings
    final tags = tagsRaw
        .where((tag) {
          if (tag == null) return false;
          final tagStr = tag.toString().trim();
          return tagStr.isNotEmpty;
        })
        .map((tag) => tag.toString().trim())
        .where((tag) => tag.isNotEmpty) // Double-check after mapping
        .toList();
    final nutritionRating = source['nutrition_rating'] as String? ?? 'A';

    // Calculate cooking time from steps
    int totalMinutes = 0;
    for (var step in recipe.steps) {
      if (step.estMinutes != null) {
        totalMinutes += step.estMinutes!;
      }
    }
    if (totalMinutes == 0) totalMinutes = 15; // Default

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: Recipe name, tags, time/calories
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recipe name with action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        recipe.name ?? '레시피',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Tags
                if (tags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags
                        .where((tag) => tag.toString().trim().isNotEmpty)
                        .map((tag) {
                          final tagText = tag.toString().trim();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getTagColor(tagText),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _getTagBorderColor(tagText),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              tagText,
                              style: TextStyle(
                                fontSize: 13,
                                color: _getTagTextColor(tagText),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),
                if (tags.isNotEmpty) const SizedBox(height: 16),
                // Time and calories row
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 18,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${totalMinutes}분',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 1,
                      height: 16,
                      color: AppColors.getBorderSecondary(brightness),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.local_fire_department_outlined,
                      size: 18,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${calories.toInt()}KCal',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Category section
                _buildCategorySection(brightness),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Right side: Nutrition rating
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F0), // Light beige background
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rating circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      nutritionRating,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '요리고 영양평가',
                  style: TextStyle(
                    fontSize: 8,
                    color: AppColors.getTextSecondary(brightness),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build category section
  Widget _buildCategorySection(Brightness brightness) {
    // Get all selected categories as a flat list
    final allCategories = <String>[];
    _categories.forEach((key, value) {
      allCategories.addAll(value);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category heading
        Text(
          '카테고리',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.getTextPrimary(brightness),
          ),
        ),
        const SizedBox(height: 12),
        // Category pills with add button
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...allCategories.map((category) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8), // Light beige background
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.getBorder(brightness),
                    width: 1,
                  ),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.getTextPrimary(brightness),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }),
            // Add category button
            GestureDetector(
              onTap: () => _showCategoryDialog(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8), // Light beige background
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.getBorder(brightness),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: AppColors.getTextPrimary(brightness),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Show category selection dialog
  Future<void> _showCategoryDialog() async {
    // Get all available categories
    final allCategories = _getAllAvailableCategories();

    // Create a copy of current categories for editing
    final selectedCategories = <String, Set<String>>{};
    _categories.forEach((key, value) {
      selectedCategories[key] = Set<String>.from(value);
    });

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 600),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      '카테고리 선택',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.getTextPrimary(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Scrollable list of categories
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: allCategories.entries.map((entry) {
                            final categoryType = entry.key;
                            final categoryName = _getCategoryTypeName(
                              categoryType,
                            );
                            final options = entry.value;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category type heading
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 8,
                                    top: 8,
                                  ),
                                  child: Text(
                                    categoryName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.getTextPrimary(
                                        Theme.of(context).brightness,
                                      ),
                                    ),
                                  ),
                                ),
                                // Category options with checkboxes
                                ...options.map((option) {
                                  final isSelected =
                                      selectedCategories[categoryType]
                                          ?.contains(option) ??
                                      false;

                                  return CheckboxListTile(
                                    title: Text(
                                      option,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.getTextPrimary(
                                          Theme.of(context).brightness,
                                        ),
                                      ),
                                    ),
                                    value: isSelected,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        if (value == true) {
                                          selectedCategories[categoryType] ??=
                                              <String>{};
                                          selectedCategories[categoryType]!.add(
                                            option,
                                          );
                                        } else {
                                          selectedCategories[categoryType]
                                              ?.remove(option);
                                        }
                                      });
                                    },
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: AppColors.getTextSecondary(
                                Theme.of(context).brightness,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            // Close dialog first
                            Navigator.of(context).pop();

                            // Update categories in parent widget
                            if (mounted) {
                              setState(() {
                                _categories = selectedCategories.map(
                                  (key, value) => MapEntry(key, value.toList()),
                                );
                              });

                              // Update in Firestore if recipeId exists
                              if (widget.recipeId != null) {
                                await _updateCategoriesInFirestore();
                              }

                              // Update in parseResponse source
                              final source = widget.parseResponse.source;
                              source['categories'] = _categories;
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '저장',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Get all available categories organized by type
  Map<String, List<String>> _getAllAvailableCategories() {
    return {
      'meat_type': ['소고기', '돼지고기', '닭고기', '양고기'],
      'cuisine_type': ['양식', '한식', '일식', '중식'],
      'menu_type': ['면', '밥', '국', '찌개', '디저트', '빵'],
      'meal_time': ['아침', '점심', '저녁'],
      'ingredient_type': ['해산물', '채소', '육류'],
      'time_category': ['10분 이내', '30분 이내', '1시간 이내', '1시간 이상'],
    };
  }

  // Get category type name in Korean
  String _getCategoryTypeName(String categoryType) {
    switch (categoryType) {
      case 'meat_type':
        return '고기재료';
      case 'cuisine_type':
        return '나라별';
      case 'menu_type':
        return '메뉴별';
      case 'meal_time':
        return '끼니별';
      case 'ingredient_type':
        return '재료별';
      case 'time_category':
        return '시간';
      default:
        return categoryType;
    }
  }

  // Build tabbed content section
  Widget _buildTabbedContent(
    models.Recipe recipe,
    models.Nutrition nutrition,
    int baseServings,
    Brightness brightness,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab headers
          _buildTabHeaders(brightness),
          const SizedBox(height: 20),
          // Tab content
          _buildTabContent(recipe, nutrition, baseServings, brightness),
        ],
      ),
    );
  }

  // Build tab headers
  Widget _buildTabHeaders(Brightness brightness) {
    final tabs = ['재료', '요리법', '영양정보'];

    return Row(
      children: tabs.asMap().entries.map((entry) {
        final index = entry.key;
        final tabName = entry.value;
        final isSelected = _selectedTabIndex == index;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedTabIndex = index;
              });
            },
            child: Column(
              children: [
                Text(
                  tabName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? AppColors.getTextPrimary(brightness)
                        : AppColors.getTextSecondary(brightness),
                  ),
                ),
                const SizedBox(height: 8),
                // Orange underline for selected tab
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Build tab content based on selected tab
  Widget _buildTabContent(
    models.Recipe recipe,
    models.Nutrition nutrition,
    int baseServings,
    Brightness brightness,
  ) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildIngredientsTab(recipe, baseServings, brightness);
      case 1:
        return _buildRecipeTab(recipe, brightness);
      case 2:
        return _buildNutritionTab(nutrition, brightness);
      default:
        return const SizedBox.shrink();
    }
  }

  // Build ingredients tab (재료)
  Widget _buildIngredientsTab(
    models.Recipe recipe,
    int baseServings,
    Brightness brightness,
  ) {
    // Group ingredients by category
    final mainIngredients = <models.Ingredient>[];
    final subIngredients = <models.Ingredient>[];
    final sauceIngredients = <models.Ingredient>[];

    for (final ingredient in recipe.ingredients) {
      final category =
          ingredient.category ?? 'sub'; // Default to sub if not categorized
      if (category == 'main') {
        mainIngredients.add(ingredient);
      } else if (category == 'sauce_msg') {
        sauceIngredients.add(ingredient);
      } else {
        subIngredients.add(ingredient);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Serving size selector and Add to Cart button
        Row(
          children: [
            // Serving size selector
            Expanded(child: _buildServingSizeSelector(brightness)),
            const SizedBox(width: 12),
            // Add to Cart button
            Expanded(flex: 2, child: _buildAddToCartButtonPill(brightness)),
          ],
        ),
        const SizedBox(height: 24),
        // Main ingredients section
        if (mainIngredients.isNotEmpty) ...[
          _buildIngredientSection('주재료', mainIngredients, brightness),
          const SizedBox(height: 16),
        ],
        // Sub ingredients section
        if (subIngredients.isNotEmpty) ...[
          _buildIngredientSection('부재료', subIngredients, brightness),
          const SizedBox(height: 16),
        ],
        // Sauce/MSG ingredients section
        if (sauceIngredients.isNotEmpty) ...[
          _buildIngredientSection('양념/조미료', sauceIngredients, brightness),
        ],
      ],
    );
  }

  Widget _buildIngredientSection(
    String title,
    List<models.Ingredient> ingredients,
    Brightness brightness,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.getTextPrimary(brightness),
          ),
        ),
        const SizedBox(height: 8),
        ...ingredients.map((ingredient) {
          final scaledAmount = ingredient.qty != null
              ? _getScaledAmount(ingredient.qty!)
              : '';
          final unit = ingredient.unit ?? '';

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.getBorderSecondary(brightness),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    ingredient.item,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.getTextPrimary(brightness),
                    ),
                  ),
                ),
                if (scaledAmount.isNotEmpty && unit.isNotEmpty)
                  Text(
                    '$scaledAmount$unit',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.getTextPrimary(brightness),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Build serving size selector
  Widget _buildServingSizeSelector(Brightness brightness) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8), // Light beige
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              if (_portionCount > 1) {
                setState(() {
                  _portionCount--;
                });
              }
            },
            child: Icon(
              Icons.remove,
              size: 16,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$_portionCount인분',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.getTextPrimary(brightness),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _portionCount++;
              });
            },
            child: Icon(
              Icons.add,
              size: 16,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  // Build Add to Cart button (pill shape)
  Widget _buildAddToCartButtonPill(Brightness brightness) {
    return ElevatedButton(
      onPressed: () => _showAddToCartDialog(),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.shopping_cart_outlined, size: 18, color: Colors.white),
          SizedBox(width: 8),
          Text(
            '장바구니 넣기',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Show add to cart dialog with ingredient selection
  Future<void> _showAddToCartDialog() async {
    final recipe = widget.parseResponse.recipe;
    // Create a copy of selected ingredients for the dialog
    final selectedForCart = Set<String>.from(_selectedIngredients);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 600),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step indicator
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Step 1/2',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      '장바구니에 추가할 재료 선택',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.getTextPrimary(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '이미 보유한 재료는 선택 해제하세요',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextTertiary(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Scrollable ingredients list with checkboxes
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: recipe.ingredients.asMap().entries.map((
                            entry,
                          ) {
                            final index = entry.key;
                            final ingredient = entry.value;
                            final id = index.toString();
                            final isSelected = selectedForCart.contains(id);
                            final scaledAmount = ingredient.qty != null
                                ? _getScaledAmount(ingredient.qty!)
                                : '';
                            final unit = ingredient.unit ?? '';

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    selectedForCart.remove(id);
                                  } else {
                                    selectedForCart.add(id);
                                  }
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryLight
                                      : AppColors.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.getBorder(
                                            Theme.of(context).brightness,
                                          ),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Checkbox
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primaryLight
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppColors.primary
                                              : const Color(0xFFCCCCCC),
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              size: 16,
                                              color: AppColors.primary,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    // Ingredient name
                                    Expanded(
                                      child: Text(
                                        ingredient.item,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: AppColors.getTextPrimary(
                                            Theme.of(context).brightness,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Amount
                                    if (scaledAmount.isNotEmpty &&
                                        unit.isNotEmpty)
                                      Text(
                                        '$scaledAmount $unit',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.getTextTertiary(
                                            Theme.of(context).brightness,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: AppColors.getTextSecondary(
                                Theme.of(context).brightness,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: selectedForCart.isEmpty
                              ? null
                              : () async {
                                  // Save parent context before closing dialog
                                  final parentContext = context;
                                  final navigator = Navigator.of(context);

                                  // Update selected ingredients
                                  setState(() {
                                    _selectedIngredients.clear();
                                    _selectedIngredients.addAll(
                                      selectedForCart,
                                    );
                                  });

                                  // Close ingredient selection dialog
                                  navigator.pop();

                                  // Check if user is logged in
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  if (user == null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        parentContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('로그인이 필요합니다'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  // Show Step 2: Calendar meal selection
                                  final recipeId = widget.recipeId;
                                  if (recipeId != null) {
                                    await showDialog(
                                      context: parentContext,
                                      builder: (context) => CalendarMealDialog(
                                        recipeId: recipeId,
                                        recipeTitle:
                                            widget.parseResponse.recipe.name ??
                                            '레시피',
                                        selectedIngredients: selectedForCart,
                                        portionCount: _portionCount,
                                        parseResponse: widget.parseResponse,
                                        onBackToStep1: () {
                                          // Reopen ingredient selection dialog
                                          _showAddToCartDialog();
                                        },
                                      ),
                                    );
                                  } else {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        parentContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('레시피를 먼저 저장해주세요'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            '다음',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Build recipe tab (요리법)
  Widget _buildRecipeTab(models.Recipe recipe, Brightness brightness) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Start Cooking button
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => CookingInstructionSheet(recipe: recipe),
              );
            },
            icon: const Icon(Icons.play_arrow, size: 20, color: Colors.white),
            label: const Text(
              '요리 시작하기',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Recipe steps
        ...recipe.steps.map((step) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step number badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1E8), // Light beige
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${step.order}',
                      style: TextStyle(
                        color: AppColors.getTextPrimary(brightness),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Step instruction
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      step.instruction,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.getTextPrimary(brightness),
                        height: 1.47,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Build nutrition tab (영양정보)
  Widget _buildNutritionTab(models.Nutrition nutrition, Brightness brightness) {
    final source = widget.parseResponse.source;
    final nutritionRating = source['nutrition_rating'] as String? ?? 'A';
    final llmEstimate = nutrition.llmEstimate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nutrition rating card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Rating circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F1E8), // Light beige
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    nutritionRating,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Rating text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A HEARTY MEAL',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getNutritionRatingDescription(nutritionRating),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'From AI calculated nutrition and analysis',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Nutrition details
        if (llmEstimate != null) ...[
          _buildNutritionDetailRow(
            'calories',
            '${llmEstimate.caloriesPerServing.toInt()}',
            brightness,
          ),
          _buildNutritionDetailRow(
            'sodium',
            '${llmEstimate.sodiumMg.toInt()}mg',
            brightness,
          ),
          _buildNutritionDetailRow(
            'protein',
            '${llmEstimate.proteinG.toStringAsFixed(1)}g',
            brightness,
          ),
          _buildNutritionDetailRow(
            'carbs',
            '${llmEstimate.carbsG.toStringAsFixed(1)}g',
            brightness,
          ),
          _buildNutritionDetailRow(
            'fat',
            '${llmEstimate.fatG.toStringAsFixed(1)}g',
            brightness,
          ),
        ],
      ],
    );
  }

  // Build nutrition detail row
  Widget _buildNutritionDetailRow(
    String label,
    String value,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.getBorderSecondary(brightness),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
        ],
      ),
    );
  }

  // Get nutrition rating description
  String _getNutritionRatingDescription(String rating) {
    switch (rating) {
      case 'A':
        return 'This meal provides excellent nutritional balance with high-quality ingredients and a good mix of nutrients.';
      case 'B':
        return 'This meal offers good nutritional value with balanced ingredients and reasonable nutrient content.';
      case 'C':
        return 'This meal provides basic nutrition but may benefit from additional nutrient-dense ingredients.';
      default:
        return 'Nutrition information available.';
    }
  }

  // Update categories in Firestore
  Future<void> _updateCategoriesInFirestore() async {
    if (widget.recipeId == null) return;

    try {
      await _recipeService.updateRecipeCategories(
        widget.recipeId!,
        _categories,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카테고리 업데이트 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper methods for tag colors
  Color _getTagColor(String tag) {
    // Return colorful background colors for tags
    switch (tag) {
      case '단백한':
        return const Color(0xFFFFE5E5);
      case '자극적인':
        return const Color(0xFFFFF0E5);
      case '단짠단짠':
        return const Color(0xFFFFF5E5);
      case '매콤한':
        return const Color(0xFFFFE5E5);
      case '담백한':
        return const Color(0xFFE5F5FF);
      case '고소한':
        return const Color(0xFFFFF5E5);
      case '얼큰한':
        return const Color(0xFFFFE5E5);
      case '고단백':
        return const Color(0xFFE5FFE5);
      case '건강식':
        return const Color(0xFFE5FFE5);
      case '채소가득':
        return const Color(0xFFE5FFE5);
      case '바삭한':
        return const Color(0xFFFFF5E5);
      case '쫄깃한':
        return const Color(0xFFFFE5F5);
      case '전통':
        return const Color(0xFFE5E5FF);
      case '간편식':
        return const Color(0xFFE5F5FF);
      case '비건':
        return const Color(0xFFE5FFE5);
      case '베지터리언':
        return const Color(0xFFE5FFE5);
      default:
        return const Color(0xFFF5F5F0);
    }
  }

  Color _getTagBorderColor(String tag) {
    // Return matching border colors
    switch (tag) {
      case '단백한':
        return const Color(0xFFFF9999);
      case '자극적인':
        return const Color(0xFFFFB366);
      case '단짠단짠':
        return const Color(0xFFFFCC99);
      case '매콤한':
        return const Color(0xFFFF6666);
      case '담백한':
        return const Color(0xFF99CCFF);
      case '고소한':
        return const Color(0xFFFFCC99);
      case '얼큰한':
        return const Color(0xFFFF6666);
      case '고단백':
        return const Color(0xFF99FF99);
      case '건강식':
        return const Color(0xFF99FF99);
      case '채소가득':
        return const Color(0xFF99FF99);
      case '바삭한':
        return const Color(0xFFFFCC99);
      case '쫄깃한':
        return const Color(0xFFFF99CC);
      case '전통':
        return const Color(0xFF9999FF);
      case '간편식':
        return const Color(0xFF99CCFF);
      case '비건':
        return const Color(0xFF99FF99);
      case '베지터리언':
        return const Color(0xFF99FF99);
      default:
        final brightness = Theme.of(context).brightness;
        return AppColors.getBorder(brightness);
    }
  }

  Color _getTagTextColor(String tag) {
    // Return text colors that contrast with backgrounds
    switch (tag) {
      case '단백한':
      case '자극적인':
      case '단짠단짠':
      case '매콤한':
      case '고소한':
      case '얼큰한':
      case '바삭한':
      case '쫄깃한':
        return const Color(0xFF8B4513);
      case '담백한':
      case '간편식':
        return const Color(0xFF0066);
      case '고단백':
      case '건강식':
      case '채소가득':
      case '비건':
      case '베지터리언':
        return const Color(0xFF006600);
      case '전통':
        return const Color(0xFF4B0082);
      default:
        final brightness = Theme.of(context).brightness;
        return AppColors.getTextPrimary(brightness);
    }
  }
}
