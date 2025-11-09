import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';
import '../services/user_service.dart';
import '../services/coupang_service.dart';
import '../services/recommendation_service.dart';
import '../services/recipe_service.dart';
import '../services/feedback_service.dart';
import '../services/meal_plan_service.dart';
import '../services/api_service.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CoupangService _coupangService = CoupangService();
  final RecommendationService _recommendationService = RecommendationService();
  final RecipeService _recipeService = RecipeService();
  final FeedbackService _feedbackService = FeedbackService();
  final MealPlanService _mealPlanService = MealPlanService();

  // Cache for product search results
  Map<String, AdvancedProductSearchResponse> _productCache = {};

  // Cache for ingredient categorization (LLM results)
  Map<String, String> _ingredientCategoryCache = {};

  // Cache for ingredient hash (to detect changes)
  String _lastIngredientHash = '';

  // Loading states
  bool _isSearchingProducts = false;
  bool _hasCompletedInitialSearch = false;
  Map<String, bool> _ingredientLoadingStates = {};
  bool _isLoadingRecommendation = false;

  // Expanded states
  Map<String, bool> _recipeExpandedStates = {};
  Map<String, bool> _categoryExpandedStates = {
    '육류/단백질': true,
    '채소': false,
    '곡류/쌀': false,
    '양념/소스': false,
  };
  bool _recommendationExpanded = false;

  // Store current cart items for async operations
  List<dynamic>? _currentCartItems;

  // Recommendation state
  RecipeRecommendation? _recommendation;
  String _lastRecommendationCartHash = '';

  // Meal plans map: recipeId -> date
  Map<String, DateTime> _recipeDates = {};
  bool _isLoadingMealPlans = false;
  String _lastRecipeIdsHash = '';

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
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
              child: Container(
                color: AppColors.getBackgroundSecondary(brightness),
                child: user == null
                    ? _buildLoginPrompt(brightness)
                    : StreamBuilder<DocumentSnapshot>(
                        stream: _userService.getUserStream(user.uid),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (!snapshot.hasData || !snapshot.data!.exists) {
                            return _buildEmptyState(brightness);
                          }

                          final userData =
                              snapshot.data!.data() as Map<String, dynamic>?;
                          final cartItems =
                              userData?['cartItems'] as List? ?? [];

                          if (cartItems.isEmpty) {
                            return _buildEmptyState(brightness);
                          }

                          return _buildCartContent(cartItems, brightness);
                        },
                      ),
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
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.getBackgroundTertiary(brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.login,
                size: 80,
                color: AppColors.getTextTertiary(brightness),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '로그인이 필요합니다',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.getTextPrimary(brightness),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '장바구니를 사용하려면 로그인해주세요',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.getTextTertiary(brightness),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '로그인',
                style: TextStyle(
                  color: AppColors.getBackground(brightness),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Brightness brightness) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.getBackgroundTertiary(brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 80,
                color: AppColors.getTextTertiary(brightness),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '장바구니가 비어있습니다',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.getTextPrimary(brightness),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '레시피를 추가하여 시작하세요!',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.getTextTertiary(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartContent(List<dynamic> cartItems, Brightness brightness) {
    // Store current cart items for async operations
    _currentCartItems = cartItems;

    // Group by recipe
    final Map<String, List<Map<String, dynamic>>> groupedByRecipe = {};
    for (final item in cartItems) {
      final cartItem = item as Map<String, dynamic>;
      final recipeId = cartItem['recipeId']?.toString() ?? 'unknown';
      if (!groupedByRecipe.containsKey(recipeId)) {
        groupedByRecipe[recipeId] = [];
      }
      groupedByRecipe[recipeId]!.add(cartItem);
    }

    // Load meal plans to get dates for recipes (only if not already loading and recipe list changed)
    final recipeIdsHash = groupedByRecipe.keys.join(',');
    if (recipeIdsHash != _lastRecipeIdsHash && !_isLoadingMealPlans) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoadingMealPlans) {
          _lastRecipeIdsHash = recipeIdsHash;
          _loadMealPlansForRecipes(groupedByRecipe.keys.toList());
        }
      });
    }

    // Aggregate ingredients across all recipes
    final aggregatedIngredients = _aggregateIngredients(cartItems);

    // Count total ingredients
    final totalIngredientCount = aggregatedIngredients.length;

    // Check if ingredients changed and trigger search if needed (after build)
    final currentHash = _generateIngredientHash(aggregatedIngredients);
    if (currentHash != _lastIngredientHash && !_isSearchingProducts) {
      // Use post-frame callback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _currentCartItems != null && !_isSearchingProducts) {
          // Verify hash is still the same (cart hasn't changed)
          final latestIngredients = _aggregateIngredients(_currentCartItems!);
          final latestHash = _generateIngredientHash(latestIngredients);
          if (latestHash == currentHash && latestHash != _lastIngredientHash) {
            _lastIngredientHash = currentHash;
            _searchProductsForIngredients(latestIngredients);
          }
        }
      });
    }

    // Calculate total price
    final totalPrice = _calculateTotalPrice(aggregatedIngredients);

    // Calculate average price per serving
    final totalServings = cartItems.fold<int>(
      0,
      (sum, item) =>
          sum + ((item as Map<String, dynamic>)['servings'] as int? ?? 1),
    );
    final avgPricePerServing = totalServings > 0
        ? totalPrice / totalServings
        : 0.0;

    return Column(
      children: [
        // Header with recipe and ingredient counts
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.getBackgroundSecondary(brightness),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '장바구니',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.getTextPrimary(brightness),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${groupedByRecipe.length}개 레시피 • $totalIngredientCount개 항목',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => _clearAll(),
                child: Text(
                  '전체 삭제',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Content with three sections
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section 1: 내 레시피
                _buildMyRecipesSection(groupedByRecipe, brightness),

                const SizedBox(height: 24),

                // Section 2: 쇼핑 리스트
                _buildShoppingListSection(
                  aggregatedIngredients,
                  avgPricePerServing,
                  brightness,
                ),

                const SizedBox(height: 24),

                // Section 3: 남은 재료 활용하기
                _buildLeftoverUtilizationSection(cartItems, brightness),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Total price and link popup button (above nav bar)
        _buildTotalPriceBar(totalPrice, aggregatedIngredients, brightness),
      ],
    );
  }

  // Load meal plans to get dates for recipes
  Future<void> _loadMealPlansForRecipes(List<String> recipeIds) async {
    if (_isLoadingMealPlans) return;

    final user = _auth.currentUser;
    if (user == null) return;

    _isLoadingMealPlans = true;

    // Get date range (today to 30 days from now)
    final now = DateTime.now();
    final endDate = now.add(const Duration(days: 30));

    try {
      final mealPlans = await _mealPlanService
          .getMealPlansForDateRange(now, endDate)
          .first;

      final Map<String, DateTime> recipeDates = {};

      for (final mealPlanEntry in mealPlans.entries) {
        final dateKey = mealPlanEntry.key;
        final mealPlan = mealPlanEntry.value;
        final meals = mealPlan['meals'] as Map<String, dynamic>? ?? {};

        // Parse date from dateKey
        final dateParts = dateKey.split('-');
        if (dateParts.length == 3) {
          final date = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );

          // Check all meal times for recipes
          for (final mealTime in ['breakfast', 'lunch', 'dinner']) {
            final mealTimeRecipes = List<String>.from(meals[mealTime] ?? []);
            for (final recipeId in mealTimeRecipes) {
              if (recipeIds.contains(recipeId)) {
                // Use the earliest date if recipe appears multiple times
                if (!recipeDates.containsKey(recipeId) ||
                    date.isBefore(recipeDates[recipeId]!)) {
                  recipeDates[recipeId] = date;
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _recipeDates = recipeDates;
          _isLoadingMealPlans = false;
        });
      }
    } catch (e) {
      print('Error loading meal plans: $e');
      if (mounted) {
        setState(() {
          _isLoadingMealPlans = false;
        });
      }
    }
  }

  // Get Korean day of week
  String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }

  // Format date for display
  String _formatDate(DateTime date) {
    return '${date.month}.${date.day.toString().padLeft(2, '0')} ${_getKoreanDayOfWeek(date)}';
  }

  // Categorize ingredient into one of the 4 categories
  String _categorizeIngredient(String ingredientName, String? category) {
    // Check cache first (for LLM results)
    if (_ingredientCategoryCache.containsKey(ingredientName)) {
      return _ingredientCategoryCache[ingredientName]!;
    }

    // Always check ingredient name first for accurate categorization
    final nameLower = ingredientName.toLowerCase();

    // Check if it's meat/protein
    if (nameLower.contains('돼지') ||
        nameLower.contains('소고기') ||
        nameLower.contains('닭') ||
        nameLower.contains('오리') ||
        nameLower.contains('양고기') ||
        nameLower.contains('계란') ||
        nameLower.contains('달걀') ||
        nameLower.contains('생선') ||
        nameLower.contains('고등어') ||
        nameLower.contains('연어') ||
        nameLower.contains('참치') ||
        nameLower.contains('새우') ||
        nameLower.contains('오징어') ||
        nameLower.contains('문어') ||
        nameLower.contains('조개') ||
        nameLower.contains('굴') ||
        nameLower.contains('두부') ||
        nameLower.contains('콩') ||
        nameLower.contains('닭가슴살') ||
        nameLower.contains('삼겹살') ||
        nameLower.contains('목살') ||
        nameLower.contains('갈비') ||
        nameLower.contains('안심') ||
        nameLower.contains('등심') ||
        nameLower.contains('치킨') ||
        nameLower.contains('베이컨') ||
        nameLower.contains('햄') ||
        nameLower.contains('소시지')) {
      return '육류/단백질';
    }

    // Check if it's vegetable
    if (nameLower.contains('배추') ||
        nameLower.contains('양파') ||
        nameLower.contains('당근') ||
        nameLower.contains('오이') ||
        nameLower.contains('토마토') ||
        nameLower.contains('상추') ||
        nameLower.contains('시금치') ||
        nameLower.contains('브로콜리') ||
        nameLower.contains('양배추') ||
        nameLower.contains('파') ||
        nameLower.contains('마늘') ||
        nameLower.contains('생강') ||
        nameLower.contains('고추') ||
        nameLower.contains('피망') ||
        nameLower.contains('버섯') ||
        nameLower.contains('가지') ||
        nameLower.contains('호박') ||
        nameLower.contains('무') ||
        nameLower.contains('단무지') ||
        nameLower.contains('깻잎') ||
        nameLower.contains('상추') ||
        nameLower.contains('치커리') ||
        nameLower.contains('아삭이') ||
        nameLower.contains('채소')) {
      return '채소';
    }

    // Check if it's grain/rice
    if (nameLower.contains('쌀') ||
        nameLower.contains('밥') ||
        nameLower.contains('국수') ||
        nameLower.contains('면') ||
        nameLower.contains('파스타') ||
        nameLower.contains('스파게티') ||
        nameLower.contains('라면') ||
        nameLower.contains('떡') ||
        nameLower.contains('빵') ||
        nameLower.contains('밀가루') ||
        nameLower.contains('곡물') ||
        nameLower.contains('보리') ||
        nameLower.contains('현미') ||
        nameLower.contains('잡곡')) {
      return '곡류/쌀';
    }

    // If pattern matching didn't work, trigger LLM categorization asynchronously
    // Use default category for now, LLM will update it later
    final defaultCategory = (category == 'sauce_msg' || category == 'sub')
        ? '양념/소스'
        : '양념/소스';

    // Trigger LLM categorization in background (don't await)
    _categorizeWithLLM(ingredientName, category);

    return defaultCategory;
  }

  // Asynchronously categorize ingredient using LLM
  Future<void> _categorizeWithLLM(
    String ingredientName,
    String? category,
  ) async {
    // Skip if already in cache or currently being processed
    if (_ingredientCategoryCache.containsKey(ingredientName)) {
      return;
    }

    try {
      final llmCategory = await ApiService.categorizeIngredient(
        ingredientName: ingredientName,
        category: category,
      );

      // Update cache and rebuild UI
      if (mounted) {
        setState(() {
          _ingredientCategoryCache[ingredientName] = llmCategory;
        });
      }
    } catch (e) {
      print('[CartScreen] Error categorizing ingredient with LLM: $e');
      // Don't update cache on error, will use default category
    }
  }

  // Calculate total price from aggregated ingredients
  double _calculateTotalPrice(
    Map<String, Map<String, dynamic>> aggregatedIngredients,
  ) {
    double total = 0.0;
    for (final entry in aggregatedIngredients.entries) {
      final ingredientName = entry.key;
      final productResult = _productCache[ingredientName];
      if (productResult != null) {
        final bestMatch =
            productResult.cheapestSameAmount ??
            productResult.bestAmountMatch ??
            productResult.cheapestOverall;
        if (bestMatch != null) {
          total += bestMatch.productPrice;
        }
      }
    }
    return total;
  }

  // Build "내 레시피" section
  Widget _buildMyRecipesSection(
    Map<String, List<Map<String, dynamic>>> groupedByRecipe,
    Brightness brightness,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.getBackground(brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '내 레시피 (${groupedByRecipe.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.getTextPrimary(brightness),
              ),
            ),
          ),
          const Divider(height: 1),
          ...groupedByRecipe.entries.map((entry) {
            final recipeId = entry.key;
            final recipeItems = entry.value;
            final firstItem = recipeItems.first;
            final recipeName = firstItem['recipeName']?.toString() ?? '레시피';
            final servings = firstItem['servings'] ?? 1;
            final date = _recipeDates[recipeId];

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recipeName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.getTextPrimary(brightness),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '$servings 인분',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.getTextSecondary(
                                      brightness,
                                    ),
                                  ),
                                ),
                                if (date != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDate(date),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.getTextSecondary(
                                        brightness,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry != groupedByRecipe.entries.last)
                  const Divider(height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }

  // Build "쇼핑 리스트" section with 4 collapsible subsections
  Widget _buildShoppingListSection(
    Map<String, Map<String, dynamic>> aggregatedIngredients,
    double avgPricePerServing,
    Brightness brightness,
  ) {
    // Group ingredients by category
    final Map<String, Map<String, Map<String, dynamic>>>
    categorizedIngredients = {'육류/단백질': {}, '채소': {}, '곡류/쌀': {}, '양념/소스': {}};

    for (final entry in aggregatedIngredients.entries) {
      final ingredientName = entry.key;
      final ingredientData = entry.value;
      final category = _categorizeIngredient(
        ingredientName,
        ingredientData['category']?.toString(),
      );
      categorizedIngredients[category]![ingredientName] = ingredientData;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.getBackground(brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '쇼핑 리스트',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.getTextPrimary(brightness),
                  ),
                ),
                if (_isSearchingProducts && !_hasCompletedInitialSearch)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    '평균 ₩${avgPricePerServing.toStringAsFixed(0)}/인분',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isSearchingProducts && !_hasCompletedInitialSearch)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('최적의 상품을 찾는 중...', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            ...categorizedIngredients.entries.map((categoryEntry) {
              final categoryName = categoryEntry.key;
              final ingredients = categoryEntry.value;
              final isExpanded = _categoryExpandedStates[categoryName] ?? false;
              final count = ingredients.length;

              if (count == 0) return const SizedBox.shrink();

              return Column(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _categoryExpandedStates[categoryName] = !isExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$categoryName ($count)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            color: AppColors.getTextSecondary(brightness),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isExpanded)
                    ...ingredients.entries.map((ingredientEntry) {
                      return _buildIngredientProductCard(
                        ingredientName: ingredientEntry.key,
                        ingredientData: ingredientEntry.value,
                        brightness: brightness,
                      );
                    }),
                  const Divider(height: 1),
                ],
              );
            }),
        ],
      ),
    );
  }

  // Build ingredient product card (matching the image design)
  Widget _buildIngredientProductCard({
    required String ingredientName,
    required Map<String, dynamic> ingredientData,
    required Brightness brightness,
  }) {
    final totalQty = ingredientData['totalQty'] as double?;
    final unit = ingredientData['unit']?.toString() ?? '';
    final isLoading = _ingredientLoadingStates[ingredientName] ?? false;
    final productResult = _productCache[ingredientName];

    // Use the most efficient product
    final bestMatch =
        productResult?.cheapestSameAmount ??
        productResult?.bestAmountMatch ??
        productResult?.cheapestOverall;

    String amountText = '';
    if (totalQty != null && unit.isNotEmpty) {
      if (totalQty % 1 == 0) {
        amountText = '${totalQty.toInt()} $unit';
      } else {
        amountText = '${totalQty.toStringAsFixed(1)} $unit';
      }
    } else if (unit.isNotEmpty) {
      amountText = unit;
    }

    // Get recipes that use this ingredient
    final recipesUsingIngredient = <String, double>{};
    if (_currentCartItems != null) {
      for (final item in _currentCartItems!) {
        final cartItem = item as Map<String, dynamic>;
        final ingredients = cartItem['ingredients'] as List? ?? [];
        for (final ing in ingredients) {
          final ingMap = ing as Map<String, dynamic>;
          if (ingMap['item']?.toString() == ingredientName) {
            final recipeName = cartItem['recipeName']?.toString() ?? '레시피';
            final qty = ingMap['qty']?.toDouble() ?? 0.0;
            recipesUsingIngredient[recipeName] = qty;
          }
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bestMatch != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    bestMatch.productImage,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 80,
                        height: 80,
                        color: AppColors.getBackgroundTertiary(brightness),
                        child: const Icon(Icons.image_not_supported, size: 24),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product name with tag
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ingredientName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.getTextPrimary(brightness),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '공유',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Price
                      Text(
                        '₩${bestMatch.productPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Rating
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${bestMatch.rating?.toStringAsFixed(1) ?? '0.0'} (${bestMatch.reviewCount ?? 0})',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.getTextSecondary(brightness),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Product specification
                      Text(
                        bestMatch.packageInfo.isNotEmpty
                            ? bestMatch.packageInfo
                            : '${bestMatch.packageSize}${bestMatch.packageUnit}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.getTextTertiary(brightness),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Required amount
                      Text(
                        '필요량: $amountText',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.getTextSecondary(brightness),
                        ),
                      ),
                      // Recipes using this ingredient
                      if (recipesUsingIngredient.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: recipesUsingIngredient.entries.map((entry) {
                            final recipeName = entry.key;
                            final qty = entry.value;
                            String qtyText = '';
                            if (qty % 1 == 0) {
                              qtyText = '${qty.toInt()}$unit';
                            } else {
                              qtyText = '${qty.toStringAsFixed(1)}$unit';
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.getBackgroundSecondary(
                                  brightness,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$recipeName ($qtyText)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.getTextSecondary(brightness),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Purchase button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: bestMatch.productUrl.isNotEmpty
                    ? () => _openCoupangLink(bestMatch.productUrl)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '구매하기',
                      style: TextStyle(
                        color: AppColors.getBackground(brightness),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: AppColors.getBackground(brightness),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (isLoading) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          ] else ...[
            Text(
              ingredientName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.getTextPrimary(brightness),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '필요량: $amountText',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.getTextSecondary(brightness),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '제품을 찾을 수 없습니다',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.getTextTertiary(brightness),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build "남은 재료 활용하기" section
  Widget _buildLeftoverUtilizationSection(
    List<dynamic> cartItems,
    Brightness brightness,
  ) {
    // Generate hash of current cart state
    final currentCartHash = cartItems
        .map((item) {
          final cartItem = item as Map<String, dynamic>;
          return '${cartItem['recipeId']}_${cartItem['servings']}';
        })
        .join('|');

    // Trigger recommendation fetch when cart changes (only after initial product search completes)
    if (cartItems.isNotEmpty &&
        _recommendation == null &&
        !_isLoadingRecommendation &&
        _hasCompletedInitialSearch &&
        currentCartHash != _lastRecommendationCartHash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoadingRecommendation) {
          _lastRecommendationCartHash = currentCartHash;
          _fetchRecommendation(cartItems);
        }
      });
    }

    // If cart changed, reset recommendation and send negative feedback if recommendation was ignored
    if (currentCartHash != _lastRecommendationCartHash &&
        _recommendation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          // Send negative feedback for ignored recommendation
          final user = _auth.currentUser;
          if (user != null && _recommendation!.recommendationId != null) {
            await _feedbackService.recordFeedback(
              userId: user.uid,
              recommendationId: _recommendation!.recommendationId!,
              feedback: 'negative',
            );
          }

          setState(() {
            _recommendation = null;
            _lastRecommendationCartHash = currentCartHash;
          });
        }
      });
    }

    final metrics = _recommendation?.efficiencyMetrics;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.getBackground(brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _recommendationExpanded = !_recommendationExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '남은 재료 활용하기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _recommendationExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          if (_recommendationExpanded) ...[
            if (metrics != null) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₩${metrics.totalSavingsKrw.toStringAsFixed(0)} 절약 • ${metrics.wasteReductionPercent.toInt()}% 음식물 쓰레기 감소',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.getTextSecondary(brightness),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_isLoadingRecommendation)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_recommendation != null)
              _buildRecommendationCard(_recommendation!, brightness)
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '추천 레시피를 찾는 중...',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.getTextTertiary(brightness),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // Build total price bar with link popup button
  Widget _buildTotalPriceBar(
    double totalPrice,
    Map<String, Map<String, dynamic>> aggregatedIngredients,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.getBackground(brightness),
        border: Border(
          top: BorderSide(color: AppColors.getBorder(brightness), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '총 예상 금액',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.getTextSecondary(brightness),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '₩${totalPrice.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.getTextPrimary(brightness),
                ),
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _showLinkPopup(aggregatedIngredients, brightness),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('링크 한눈에 보기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show link popup with all ingredient links
  void _showLinkPopup(
    Map<String, Map<String, dynamic>> aggregatedIngredients,
    Brightness brightness,
  ) {
    final links = <String, String>{};

    for (final entry in aggregatedIngredients.entries) {
      final ingredientName = entry.key;
      final productResult = _productCache[ingredientName];
      if (productResult != null) {
        final bestMatch =
            productResult.cheapestSameAmount ??
            productResult.bestAmountMatch ??
            productResult.cheapestOverall;
        if (bestMatch != null && bestMatch.productUrl.isNotEmpty) {
          links[ingredientName] = bestMatch.productUrl;
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('링크 한눈에 보기'),
        content: SizedBox(
          width: double.maxFinite,
          child: links.isEmpty
              ? const Text('링크가 없습니다')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: links.length,
                  itemBuilder: (context, index) {
                    final entry = links.entries.elementAt(index);
                    return ListTile(
                      title: Text(entry.key),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _openCoupangLink(entry.value),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeCard({
    required String recipeId,
    required String recipeName,
    required int servings,
    required List<Map<String, dynamic>> recipeItems,
    required bool isExpanded,
    required Brightness brightness,
    required VoidCallback onToggle,
  }) {
    // Collect all ingredients
    final allIngredients = <Map<String, dynamic>>[];
    for (final item in recipeItems) {
      final ingredients = item['ingredients'] as List? ?? [];
      allIngredients.addAll(
        ingredients.map((ing) => ing as Map<String, dynamic>),
      );
    }

    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$servings 인분',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.getTextTertiary(brightness),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: AppColors.getTextTertiary(brightness),
                      ),
                      onPressed: () => _editRecipe(recipeItems),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.getTextTertiary(brightness),
                      ),
                      onPressed: () => _removeRecipe(recipeItems),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 24,
                      color: AppColors.getTextSecondary(brightness),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: allIngredients.map((ingredient) {
                return _buildIngredientItem(
                  ingredient,
                  isEditable: true,
                  brightness: brightness,
                );
              }).toList(),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildIngredientItem(
    Map<String, dynamic> ingredient, {
    bool isEditable = false,
    required Brightness brightness,
  }) {
    final item = ingredient['item']?.toString() ?? '';
    final qty = ingredient['qty']?.toDouble();
    final unit = ingredient['unit']?.toString() ?? '';
    final notes = ingredient['notes']?.toString();

    String amountText = '';
    if (qty != null && unit.isNotEmpty) {
      if (qty % 1 == 0) {
        amountText = '${qty.toInt()} $unit';
      } else {
        amountText = '${qty.toStringAsFixed(1)} $unit';
      }
    } else if (unit.isNotEmpty) {
      amountText = unit;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.getBackgroundSecondary(brightness),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.getTextPrimary(brightness),
                  ),
                ),
                if (notes != null && notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      notes,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.getTextTertiary(brightness),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (amountText.isNotEmpty)
            Text(
              amountText,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.getTextSecondary(brightness),
              ),
            ),
          if (isEditable)
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.getTextTertiary(brightness),
              ),
              onPressed: () => _editIngredient(ingredient),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductSearchResult product, Brightness brightness) {
    // Debug: Print product URL to console
    print('Product URL for ${product.productName}: ${product.productUrl}');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.getBackgroundSecondary(brightness),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  product.productImage,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: AppColors.getBackgroundTertiary(brightness),
                      child: const Icon(Icons.image_not_supported, size: 24),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.getTextPrimary(brightness),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.formattedPrice,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.getTextPrimary(brightness),
                      ),
                    ),
                    if (product.packageInfo.isNotEmpty)
                      Text(
                        product.packageInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.getTextTertiary(brightness),
                        ),
                      ),
                    // Debug: Show URL (for testing)
                    if (product.productUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'URL: ${product.productUrl.length > 50 ? product.productUrl.substring(0, 50) + "..." : product.productUrl}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.getTextTertiary(brightness),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: product.productUrl.isNotEmpty
                ? () => _openCoupangLink(product.productUrl)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '쿠팡에서 구매하기',
                  style: TextStyle(
                    color: AppColors.getBackground(brightness),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.getBackground(brightness),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Map<String, dynamic>> _aggregateIngredients(
    List<dynamic> cartItems,
  ) {
    final Map<String, Map<String, dynamic>> aggregated = {};

    for (final item in cartItems) {
      final cartItem = item as Map<String, dynamic>;
      final ingredients = cartItem['ingredients'] as List? ?? [];

      for (final ingredient in ingredients) {
        final ing = ingredient as Map<String, dynamic>;
        final name = ing['item']?.toString() ?? '';
        if (name.isEmpty) continue;

        final qty = ing['qty']?.toDouble();
        final unit = ing['unit']?.toString() ?? '';

        if (aggregated.containsKey(name)) {
          // Add quantities if units match
          final existing = aggregated[name]!;
          final existingUnit = existing['unit']?.toString() ?? '';
          if (existingUnit == unit && qty != null) {
            final existingQty = existing['totalQty'] as double? ?? 0.0;
            aggregated[name]!['totalQty'] = existingQty + qty;
          }
        } else {
          aggregated[name] = {
            'totalQty': qty,
            'unit': unit,
            'notes': ing['notes'],
            'category': ing['category'],
          };
        }
      }
    }

    return aggregated;
  }

  String _generateIngredientHash(
    Map<String, Map<String, dynamic>> ingredients,
  ) {
    // Create a hash based on ingredient names and quantities
    final sortedEntries = ingredients.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final hashData = sortedEntries
        .map((e) {
          return '${e.key}:${e.value['totalQty']}:${e.value['unit']}';
        })
        .join('|');

    return hashData;
  }

  Future<void> _searchProductsForIngredients(
    Map<String, Map<String, dynamic>> ingredients,
  ) async {
    if (!mounted) return;

    setState(() {
      _isSearchingProducts = true;
    });

    // Collect all ingredients that need searching
    final ingredientsToSearch = <String, Map<String, dynamic>>{};

    for (final entry in ingredients.entries) {
      final ingredientName = entry.key;
      final ingredientData = entry.value;

      // Check if ingredient changed (quantity or unit)
      final cachedResult = _productCache[ingredientName];
      final totalQty = ingredientData['totalQty'] as double?;
      final unit = ingredientData['unit']?.toString();

      // Skip if already cached and quantities match
      if (cachedResult != null) {
        final cachedQty = cachedResult.neededQty;
        final cachedUnit = cachedResult.neededUnit;

        // Check if quantity or unit changed
        bool hasChanged = false;
        if (cachedQty != totalQty || cachedUnit != unit) {
          hasChanged = true;
        }

        if (!hasChanged) {
          continue; // No change, skip search
        }
      }

      ingredientsToSearch[ingredientName] = ingredientData;
      _ingredientLoadingStates[ingredientName] = true;
    }

    // If nothing to search, just mark as complete and return
    if (ingredientsToSearch.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearchingProducts = false;
          _hasCompletedInitialSearch = true;
        });
      }
      return;
    }

    // Search for all ingredients
    final results = <String, AdvancedProductSearchResponse?>{};
    for (final entry in ingredientsToSearch.entries) {
      final ingredientName = entry.key;
      final ingredientData = entry.value;
      final totalQty = ingredientData['totalQty'] as double?;
      final unit = ingredientData['unit']?.toString();

      try {
        final result = await _coupangService.searchProductsAdvanced(
          ingredientName: ingredientName,
          neededQty: totalQty,
          neededUnit: unit,
          limit: 50,
        );

        results[ingredientName] = result;

        // Small delay to respect rate limits
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        print('Error searching for $ingredientName: $e');
        results[ingredientName] = null;
      }
    }

    // Batch update all results at once to minimize rebuilds
    if (mounted) {
      setState(() {
        for (final entry in results.entries) {
          final ingredientName = entry.key;
          final result = entry.value;

          if (result != null) {
            _productCache[ingredientName] = result;
          }
          _ingredientLoadingStates[ingredientName] = false;
        }
        _isSearchingProducts = false;
        _hasCompletedInitialSearch = true;
      });
    }
  }

  Future<void> _openCoupangLink(String url) async {
    print('Attempting to open Coupang link: $url');

    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('유효하지 않은 링크입니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Ensure URL has proper scheme
      String finalUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        finalUrl = 'https://$url';
      }

      final uri = Uri.parse(finalUrl);
      print('Parsed URI: $uri');

      // Check if URL can be launched
      final canLaunch = await canLaunchUrl(uri);
      print('Can launch URL: $canLaunch');

      if (canLaunch) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('URL launched: $launched');

        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('링크를 열 수 없습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('링크를 열 수 없습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Error opening Coupang link: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('링크 열기 오류: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editRecipe(List<Map<String, dynamic>> recipeItems) async {
    // TODO: Implement recipe editing
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('레시피 편집 기능은 곧 추가될 예정입니다')));
  }

  Future<void> _editIngredient(Map<String, dynamic> ingredient) async {
    // TODO: Implement ingredient editing
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('재료 편집 기능은 곧 추가될 예정입니다')));
  }

  Future<void> _removeRecipe(List<Map<String, dynamic>> recipeItems) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('레시피 삭제'),
        content: const Text('이 레시피의 모든 재료를 장바구니에서 제거하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        for (final cartItem in recipeItems) {
          await _userService.removeFromCart(user.uid, cartItem);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('장바구니에서 제거되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류가 발생했습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _clearAll() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Get current cart items to extract recipe IDs
    final cartItems = await _userService.getCartItems(user.uid);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('장바구니의 모든 항목을 삭제하시겠습니까?\n해당 레시피의 식사 계획도 함께 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Extract unique recipe IDs from cart items
        final recipeIds = <String>{};
        for (final item in cartItems) {
          final recipeId = item['recipeId']?.toString();
          if (recipeId != null && recipeId.isNotEmpty) {
            recipeIds.add(recipeId);
          }
        }

        // Remove recipes from all meal plans
        for (final recipeId in recipeIds) {
          try {
            await _mealPlanService.removeRecipeFromAllMealPlans(recipeId);
          } catch (e) {
            print('Error removing recipe $recipeId from meal plans: $e');
            // Continue with other recipes even if one fails
          }
        }

        // Clear the cart
        await _userService.clearCart(user.uid);

        setState(() {
          _productCache.clear();
          _ingredientCategoryCache.clear();
          _lastIngredientHash = '';
          _hasCompletedInitialSearch = false;
          _recipeDates.clear();
          _lastRecipeIdsHash = '';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('장바구니와 식사 계획이 삭제되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('오류가 발생했습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildRecommendationCard(
    RecipeRecommendation recommendation,
    Brightness brightness,
  ) {
    final metrics = recommendation.efficiencyMetrics;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recipe name and taste match
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  recommendation.recipeName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.getTextPrimary(brightness),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '취향 일치 ${recommendation.tasteMatchScore.toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Efficiency metrics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.getBackgroundSecondary(brightness),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.savings,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '약 ${metrics.totalSavingsKrw.toStringAsFixed(0)}원 절약',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.recycling, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '음식 낭비 ${metrics.wasteReductionPercent.toInt()}% 감소',
                      style: const TextStyle(fontSize: 14, color: Colors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  metrics.explanation,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.getTextSecondary(brightness),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Reasoning
          Text(
            recommendation.reasoning,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.getTextSecondary(brightness),
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // TODO: Navigate to recipe detail
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('레시피 상세 페이지로 이동합니다')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    '레시피 보기',
                    style: TextStyle(
                      color: AppColors.getTextPrimary(brightness),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    // Add recipe to cart
                    final user = _auth.currentUser;
                    if (user != null &&
                        recommendation.recommendationId != null) {
                      // Get recipe data
                      final recipeData = recommendation.recommendedRecipe;
                      final recipeId =
                          recipeData['id'] ?? recipeData['recipeId'];

                      // Add to cart
                      await _userService.addToCart(user.uid, {
                        'recipeId': recipeId,
                        'recipe': recipeData['recipe'] ?? {},
                        'source': recipeData['source'] ?? {},
                        'servings': recipeData['recipe']?['servings'] ?? 1,
                      });

                      // Send positive feedback
                      await _feedbackService.recordFeedback(
                        userId: user.uid,
                        recommendationId: recommendation.recommendationId!,
                        feedback: 'positive',
                        recipeId: recipeId?.toString(),
                      );

                      // Reset recommendation to trigger new fetch
                      setState(() {
                        _recommendation = null;
                        _lastRecommendationCartHash = '';
                      });
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('레시피가 장바구니에 추가되었습니다'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '장바구니에 추가',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRecommendation(List<dynamic> cartItems) async {
    if (_isLoadingRecommendation) return;

    setState(() {
      _isLoadingRecommendation = true;
    });

    try {
      // Get all available recipes from Firestore (user's recipes for now)
      // TODO: In the future, get recipes from all users for better recommendations
      final availableRecipes = await _recipeService.getUserRecipes().first;

      // Fetch full recipe data for each cart item
      final cartRecipes = <Map<String, dynamic>>[];

      for (final item in cartItems) {
        final cartItem = item as Map<String, dynamic>;
        final recipeId = cartItem['recipeId']?.toString();

        if (recipeId == null || recipeId.isEmpty) continue;

        // Find the full recipe data from availableRecipes
        final fullRecipeData = availableRecipes.firstWhere(
          (recipe) => recipe['id'] == recipeId,
          orElse: () => <String, dynamic>{},
        );

        if (fullRecipeData.isNotEmpty) {
          cartRecipes.add({
            'recipe': fullRecipeData['recipe'] ?? {},
            'servings': cartItem['servings'] ?? 1,
            'source': fullRecipeData['source'] ?? {},
            'recipeId': recipeId,
          });
        }
      }

      if (cartRecipes.isEmpty) {
        print('No valid recipes found in cart');
        if (mounted) {
          setState(() {
            _isLoadingRecommendation = false;
          });
        }
        return;
      }

      // Convert available recipes to format expected by API
      final recipesForApi = availableRecipes.map((recipe) {
        return {
          'id': recipe['id'],
          'recipe': recipe['recipe'] ?? {},
          'source': recipe['source'] ?? {},
        };
      }).toList();

      // Get current user ID for personalized recommendations
      final userId = _auth.currentUser?.uid;

      final recommendation = await _recommendationService.getRecommendation(
        cartRecipes: cartRecipes,
        availableRecipes: recipesForApi,
        userId: userId,
      );

      if (mounted) {
        setState(() {
          _recommendation = recommendation;
          _isLoadingRecommendation = false;
        });
      }
    } catch (e) {
      print('Error fetching recommendation: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecommendation = false;
        });
      }
    }
  }
}
