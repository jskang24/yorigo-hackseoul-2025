import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/recipe_service.dart';
import '../services/meal_plan_service.dart';
import '../widgets/meal_plan_editor_dialog.dart';
import 'add_recipe_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RecipeService _recipeService = RecipeService();
  final MealPlanService _mealPlanService = MealPlanService();
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;
  DateTime? _lastKnownToday;

  // Filter states
  String _selectedPrimaryCategory = '전체';
  String? _selectedSecondaryCategory;

  // Search state
  String _searchQuery = '';

  // Meal plans data
  Map<String, Map<String, dynamic>> _mealPlans = {};

  @override
  void initState() {
    super.initState();
    // Initialize selected date to today
    final today = _getToday();
    _selectedDate = today;
    _lastKnownToday = today;
    _loadMealPlans();

    // Add listener to search controller
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  // Load meal plans for the current week
  void _loadMealPlans() {
    final weekDates = _getWeekDates();
    final startDate = weekDates.first;
    final endDate = weekDates.last;

    _mealPlanService.getMealPlansForDateRange(startDate, endDate).listen((
      mealPlans,
    ) {
      if (mounted) {
        setState(() {
          _mealPlans = mealPlans;
        });
      }
    });
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Get today's date (normalized to start of day)
  DateTime _getToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Get the week dates with today in the second column
  List<DateTime> _getWeekDates() {
    final today = _getToday();
    final List<DateTime> weekDates = [];

    // Today should be in the second column (index 1)
    // So we need: 1 day before, today, 5 days after
    for (int i = -1; i <= 5; i++) {
      weekDates.add(today.add(Duration(days: i)));
    }

    return weekDates;
  }

  // Get Korean day of week abbreviation
  String _getKoreanDayOfWeek(DateTime date) {
    final weekday = date.weekday;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[weekday - 1];
  }

  // Get Korean month name (e.g., "11월")
  String _getKoreanMonthName(DateTime date) {
    return '${date.month}월';
  }

  // Get meal indicators for a date
  List<String> _getMealIndicators(DateTime date, int index) {
    final dateKey = _getDateKey(date);
    final mealPlan = _mealPlans[dateKey];
    if (mealPlan == null) return [];

    final meals = mealPlan['meals'] as Map<String, dynamic>? ?? {};
    final List<String> indicators = [];

    if (meals['breakfast'] != null && (meals['breakfast'] as List).isNotEmpty) {
      indicators.add('breakfast');
    }
    if (meals['lunch'] != null && (meals['lunch'] as List).isNotEmpty) {
      indicators.add('lunch');
    }
    if (meals['dinner'] != null && (meals['dinner'] as List).isNotEmpty) {
      indicators.add('dinner');
    }

    return indicators;
  }

  // Get meal items for a specific date and meal type
  // Returns a list of maps with 'recipeId' and 'title'
  List<Map<String, String>> _getMealItems(DateTime date, String mealType) {
    final dateKey = _getDateKey(date);
    final mealPlan = _mealPlans[dateKey];
    if (mealPlan == null) return [];

    final meals = mealPlan['meals'] as Map<String, dynamic>? ?? {};
    final recipeTitles =
        mealPlan['recipeTitles'] as Map<String, dynamic>? ?? {};

    final mealTimeMeals = meals[mealType] as List? ?? [];
    return mealTimeMeals.map((recipeId) {
      final recipeIdStr = recipeId.toString();
      return {
        'recipeId': recipeIdStr,
        'title': recipeTitles[recipeIdStr]?.toString() ?? '레시피',
      };
    }).toList();
  }

  Color _getMealColor(String meal) {
    switch (meal) {
      case 'breakfast':
        return AppColors.breakfast;
      case 'lunch':
        return AppColors.lunch;
      case 'dinner':
        return AppColors.dinner;
      default:
        final brightness = Theme.of(context).brightness;
        return AppColors.getTextTertiary(brightness);
    }
  }

  // Build orange line widgets for selected date
  List<Widget> _buildOrangeLines(
    double containerWidth,
    double monthNameHeight,
  ) {
    // With Expanded widgets, each date column gets equal width
    final columnWidth = containerWidth / 7;
    final bottomPosition = -16.0;

    return _getWeekDates().asMap().entries.map((entry) {
      final index = entry.key;
      final date = entry.value;
      final isSelected =
          _selectedDate != null &&
          date.year == _selectedDate!.year &&
          date.month == _selectedDate!.month &&
          date.day == _selectedDate!.day;

      if (!isSelected) return const SizedBox.shrink();

      return Positioned(
        left: index * columnWidth,
        width: columnWidth,
        bottom: bottomPosition,
        child: Container(height: 2, color: AppColors.primary),
      );
    }).toList();
  }

  // Build meal menu section for selected date
  Widget _buildMealMenuSection(DateTime date, Brightness brightness) {
    final mealTypes = ['breakfast', 'lunch', 'dinner'];
    final mealRows = <Widget>[];

    for (int i = 0; i < mealTypes.length; i++) {
      final mealType = mealTypes[i];
      final items = _getMealItems(date, mealType);
      mealRows.add(_buildMealRow(mealType, items, brightness));
      // Add consistent spacing between rows (measured from bar to bar)
      if (i < mealTypes.length - 1) {
        mealRows.add(const SizedBox(height: 12));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.getBorder(Theme.of(context).brightness),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mealRows,
      ),
    );
  }

  // Build a single meal row
  Widget _buildMealRow(
    String mealType,
    List<Map<String, String>> items,
    Brightness brightness,
  ) {
    Color barColor;
    switch (mealType) {
      case 'breakfast':
        barColor = AppColors.breakfast;
        break;
      case 'lunch':
        barColor = AppColors.lunch;
        break;
      case 'dinner':
        barColor = AppColors.dinner;
        break;
      default:
        final brightness = Theme.of(context).brightness;
        barColor = AppColors.getTextTertiary(brightness);
    }

    return SizedBox(
      height:
          32, // Fixed height: tag height (6px top + ~20px text + 6px bottom)
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Colored vertical bar - centered vertically
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Meal items as tags
          Expanded(
            child: items.isEmpty
                ? const SizedBox.shrink() // Empty when no items
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: items.map((item) {
                      final recipeId = item['recipeId'] ?? '';
                      final title = item['title'] ?? '레시피';
                      return GestureDetector(
                        onTap: () async {
                          // Fetch full recipe data and navigate to detail screen
                          final parseResponse = await _recipeService
                              .getRecipeById(recipeId);
                          if (parseResponse != null && mounted) {
                            Navigator.pushNamed(
                              context,
                              '/recipe-detail',
                              arguments: {
                                'parseResponse': parseResponse,
                                'recipeId': recipeId,
                              },
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: AppColors.getBorder(brightness),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  // Get secondary filter options based on primary category
  List<Map<String, dynamic>> _getSecondaryFilters(String primaryCategory) {
    switch (primaryCategory) {
      case '고기재료':
        return [
          {'label': '소고기', 'icon': Icons.restaurant},
          {'label': '돼지고기', 'icon': Icons.restaurant_menu},
          {'label': '닭고기', 'icon': Icons.set_meal},
          {'label': '양고기', 'icon': Icons.dinner_dining},
        ];
      case '나라별':
        return [
          {'label': '양식', 'icon': Icons.restaurant},
          {'label': '한식', 'icon': Icons.restaurant_menu},
          {'label': '일식', 'icon': Icons.set_meal},
          {'label': '중식', 'icon': Icons.dinner_dining},
        ];
      case '메뉴별':
        return [
          {'label': '면', 'icon': Icons.ramen_dining},
          {'label': '밥', 'icon': Icons.rice_bowl},
          {'label': '국', 'icon': Icons.soup_kitchen},
          {'label': '찌개', 'icon': Icons.soup_kitchen},
          {'label': '디저트', 'icon': Icons.cake},
          {'label': '빵', 'icon': Icons.bakery_dining},
        ];
      case '끼니별':
        return [
          {'label': '아침', 'icon': Icons.wb_sunny},
          {'label': '점심', 'icon': Icons.lunch_dining},
          {'label': '저녁', 'icon': Icons.dinner_dining},
        ];
      case '재료별':
        return [
          {'label': '해산물', 'icon': Icons.set_meal},
          {'label': '채소', 'icon': Icons.eco},
          {'label': '육류', 'icon': Icons.restaurant},
        ];
      case '시간':
        return [
          {'label': '10분 이내', 'icon': Icons.timer},
          {'label': '30분 이내', 'icon': Icons.timer_outlined},
          {'label': '1시간 이내', 'icon': Icons.access_time},
          {'label': '1시간 이상', 'icon': Icons.schedule},
        ];
      default:
        return [];
    }
  }

  // Build primary filter layer (pills)
  Widget _buildPrimaryFilterLayer(Brightness brightness) {
    final categories = ['전체', '고기재료', '나라별', '메뉴별', '끼니별', '재료별', '시간'];

    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      decoration: const BoxDecoration(color: Colors.white),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: categories.map((category) {
            final isSelected = _selectedPrimaryCategory == category;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPrimaryCategory = category;
                  // Auto-select first sub-category if available (except for '전체')
                  if (category == '전체') {
                    _selectedSecondaryCategory = null;
                  } else {
                    final secondaryFilters = _getSecondaryFilters(category);
                    if (secondaryFilters.isNotEmpty) {
                      _selectedSecondaryCategory =
                          secondaryFilters.first['label'] as String;
                    } else {
                      _selectedSecondaryCategory = null;
                    }
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F0), // Light beige background
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.getBorder(brightness),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected
                            ? AppColors.getTextPrimary(brightness)
                            : AppColors.getTextSecondary(brightness),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Build secondary filter layer (icon circles)
  Widget _buildSecondaryFilterLayer(Brightness brightness) {
    final secondaryFilters = _getSecondaryFilters(_selectedPrimaryCategory);

    if (secondaryFilters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      decoration: const BoxDecoration(color: Colors.white),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: secondaryFilters.map((filter) {
            final label = filter['label'] as String;
            final icon = filter['icon'] as IconData;
            final isSelected = _selectedSecondaryCategory == label;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSecondaryCategory = isSelected ? null : label;
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.getBorder(brightness),
                          width: isSelected ? 2 : 1,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.getTextSecondary(brightness),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.getTextSecondary(brightness),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
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

  // Build recipe listing
  Widget _buildRecipeListing(Brightness brightness) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _recipeService.getUserRecipes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.getTextTertiary(brightness),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '오류가 발생했습니다: ${snapshot.error}',
                    style: TextStyle(
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final recipes = snapshot.data ?? [];

        // Filter and score recipes based on search query and selected categories
        final recipesWithPriority = recipes
            .map((recipe) {
              // Check search match priority
              final searchPriority = _searchQuery.isNotEmpty
                  ? _getSearchMatchPriority(recipe, _searchQuery)
                  : 0;

              // If search query exists and no match found, exclude this recipe
              if (_searchQuery.isNotEmpty && searchPriority == -1) {
                return {'recipe': recipe, 'priority': -1};
              }

              // Check category filter
              bool categoryMatch = true;
              if (_selectedPrimaryCategory != '전체') {
                final recipeCategories =
                    recipe['categories'] as Map<String, dynamic>? ?? {};

                // Map primary category to category field name
                String categoryField = '';
                switch (_selectedPrimaryCategory) {
                  case '고기재료':
                    categoryField = 'meat_type';
                    break;
                  case '나라별':
                    categoryField = 'cuisine_type';
                    break;
                  case '메뉴별':
                    categoryField = 'menu_type';
                    break;
                  case '끼니별':
                    categoryField = 'meal_time';
                    break;
                  case '재료별':
                    categoryField = 'ingredient_type';
                    break;
                  case '시간':
                    categoryField = 'time_category';
                    break;
                  default:
                    categoryMatch = true;
                    break;
                }

                if (categoryField.isNotEmpty) {
                  final recipeCategoryList =
                      recipeCategories[categoryField] as List? ?? [];

                  if (_selectedSecondaryCategory == null) {
                    categoryMatch = recipeCategoryList.isNotEmpty;
                  } else {
                    categoryMatch = recipeCategoryList.contains(
                      _selectedSecondaryCategory,
                    );
                  }
                }
              }

              // If category doesn't match, exclude this recipe
              if (!categoryMatch) {
                return {'recipe': recipe, 'priority': -1};
              }

              return {'recipe': recipe, 'priority': searchPriority};
            })
            .where((item) => item['priority'] != -1)
            .toList();

        // Sort by priority (higher priority first), then by title
        recipesWithPriority.sort((a, b) {
          final priorityA = a['priority'] as int;
          final priorityB = b['priority'] as int;

          // First sort by priority (descending)
          if (priorityA != priorityB) {
            return priorityB.compareTo(priorityA);
          }

          // If same priority, sort by title alphabetically
          final titleA =
              (a['recipe'] as Map<String, dynamic>)['title'] as String? ?? '';
          final titleB =
              (b['recipe'] as Map<String, dynamic>)['title'] as String? ?? '';
          return titleA.compareTo(titleB);
        });

        // Extract recipes from sorted list
        final filteredRecipes = recipesWithPriority
            .map((item) => item['recipe'] as Map<String, dynamic>)
            .toList();

        if (filteredRecipes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.restaurant_outlined,
                    size: 64,
                    color: AppColors.getTextTertiary(brightness),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '레시피가 없습니다',
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

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...filteredRecipes.map(
                (recipe) => _buildRecipeCard(recipe, brightness),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Always ensure today is in the second column and update if date changed
    final today = _getToday();

    // Check if the date has changed
    if (_lastKnownToday == null ||
        _lastKnownToday!.year != today.year ||
        _lastKnownToday!.month != today.month ||
        _lastKnownToday!.day != today.day) {
      // Date has changed - update to new today
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedDate = today;
            _lastKnownToday = today;
          });
        }
      });
    }

    // Ensure selected date is initialized
    if (_selectedDate == null) {
      _selectedDate = today;
    }

    final brightness = Theme.of(context).brightness;
    return Scaffold(
      backgroundColor: AppColors.getBackground(brightness),
      body: SafeArea(
        child: Column(
          children: [
            // Custom header with logo and search bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.getBackground(brightness),
              ),
              child: Row(
                children: [
                  // Logo and brand name
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
                  const SizedBox(width: 24),
                  // Search bar - takes up remaining space
                  Expanded(
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
                                hintText: '오늘 뭘 요리 할까?',
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
                ],
              ),
            ),
            // Scrollable content - everything below header including calendar
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Week calendar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.getBorder(brightness),
                            width: 1,
                          ),
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final today = _getToday();
                          final monthName = _getKoreanMonthName(today);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Month name and edit button
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        monthName,
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.getTextPrimary(
                                            brightness,
                                          ),
                                        ),
                                      ),
                                      // Edit button
                                      GestureDetector(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) =>
                                                MealPlanEditorDialog(
                                                  onMealDeleted: () {
                                                    // Reload meal plans after deletion
                                                    _loadMealPlans();
                                                  },
                                                ),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color:
                                                AppColors.getBackgroundTertiary(
                                                  brightness,
                                                ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                            color: AppColors.getTextPrimary(
                                              brightness,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Calendar dates
                                  Row(
                                    children: _getWeekDates().asMap().entries.map((
                                      entry,
                                    ) {
                                      final index = entry.key;
                                      final date = entry.value;
                                      final isSelected =
                                          _selectedDate != null &&
                                          date.year == _selectedDate!.year &&
                                          date.month == _selectedDate!.month &&
                                          date.day == _selectedDate!.day;
                                      final mealIndicators = _getMealIndicators(
                                        date,
                                        index,
                                      );

                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedDate = date;
                                            });
                                          },
                                          child: Column(
                                            children: [
                                              Text(
                                                _getKoreanDayOfWeek(date),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isSelected
                                                      ? AppColors.primary
                                                      : AppColors.textSecondary,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? AppColors.primary
                                                      : Colors.transparent,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${date.day}',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : AppColors
                                                                .textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: mealIndicators
                                                    .take(3)
                                                    .map((meal) {
                                                      return Container(
                                                        width: 6,
                                                        height: 6,
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 2,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color:
                                                                  _getMealColor(
                                                                    meal,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                      );
                                                    })
                                                    .toList(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                              // Orange line for selected date that overlaps the border
                              // Month name is approximately 28px tall (fontSize 20 + line height)
                              ..._buildOrangeLines(constraints.maxWidth, 28),
                            ],
                          );
                        },
                      ),
                    ),
                    // Meal menu display section
                    if (_selectedDate != null)
                      _buildMealMenuSection(_selectedDate!, brightness),
                    // Filter layers
                    _buildPrimaryFilterLayer(brightness),
                    _buildSecondaryFilterLayer(brightness),
                    // Recipe listing
                    _buildRecipeListing(brightness),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            isDismissible: false, // Prevent dismissing by tapping outside
            enableDrag: false, // Prevent dismissing by dragging
            builder: (context) => const AddRecipeScreen(),
          );
        },
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildRecipeCard(Map<String, dynamic> recipe, Brightness brightness) {
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
                    // Creator information and action icons aligned in same row
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
