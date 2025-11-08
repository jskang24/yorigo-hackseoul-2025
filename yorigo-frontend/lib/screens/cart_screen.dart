import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_header.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  List<Map<String, dynamic>> cartRecipes = [
    {
      'id': '1',
      'name': '비빔밥 (Bibimbap)',
      'servings': 4,
      'isExpanded': false,
      'ingredients': [
        {
          'name': '당근',
          'amount': '100 g',
          'recommendations': [
            {
              'id': 'p1',
              'type': 'best',
              'name': 'Premium 당근',
              'price': '₩2,890',
              'weight': '500g',
              'rating': 4.7,
              'reviews': 523,
              'image':
                  'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=200&q=80',
            },
            {
              'id': 'p2',
              'type': 'budget',
              'name': 'Value 당근',
              'price': '₩1,950',
              'weight': '500g',
              'rating': 4.2,
              'reviews': 187,
              'image':
                  'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=200&q=80',
            },
          ],
        },
        {
          'name': '시금치',
          'amount': '150 g',
          'recommendations': [
            {
              'id': 'p3',
              'type': 'best',
              'name': 'Premium 시금치',
              'price': '₩3,200',
              'weight': '300g',
              'rating': 4.6,
              'reviews': 412,
              'image':
                  'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=200&q=80',
            },
          ],
        },
      ],
    },
    {
      'id': '2',
      'name': '김치찌개 (Kimchi Jjigae)',
      'servings': 2,
      'isExpanded': false,
      'ingredients': [
        {'name': '다진 마늘', 'amount': '1 큰술', 'recommendations': []},
      ],
    },
  ];

  void _toggleRecipe(String recipeId) {
    setState(() {
      cartRecipes = cartRecipes.map((recipe) {
        if (recipe['id'] == recipeId) {
          return {...recipe, 'isExpanded': !recipe['isExpanded']};
        }
        return recipe;
      }).toList();
    });
  }

  void _removeRecipe(String recipeId) {
    setState(() {
      cartRecipes.removeWhere((recipe) => recipe['id'] == recipeId);
    });
  }

  void _clearAll() {
    setState(() {
      cartRecipes.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = cartRecipes.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundSecondary,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              onLoginPressed: () {
                Navigator.pushNamed(context, '/login');
              },
            ),
            Expanded(child: isEmpty ? _buildEmptyState() : _buildCartContent()),
            // Bottom nav is handled by MainNavigator
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
                color: AppColors.backgroundTertiary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 80,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '장바구니가 비어있습니다',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '레시피를 추가하여 시작하세요!',
              style: TextStyle(fontSize: 15, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                // TODO: Navigate to recipes
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
              child: const Text(
                '레시피 둘러보기',
                style: TextStyle(
                  color: AppColors.background,
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

  Widget _buildCartContent() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: const BoxDecoration(color: AppColors.backgroundSecondary),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '장바구니',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: _clearAll,
                child: const Text(
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${cartRecipes.length}개 레시피 • 쿠팡에서 비교하고 구매하세요',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cartRecipes.length,
            itemBuilder: (context, index) {
              return _buildRecipeCard(cartRecipes[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecipeCard(Map<String, dynamic> recipe) {
    final isExpanded = recipe['isExpanded'] as bool;
    final ingredients = recipe['ingredients'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Recipe Header
          InkWell(
            onTap: () => _toggleRecipe(recipe['id'] as String),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe['name'] as String,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${recipe['servings']} 인분',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () => _removeRecipe(recipe['id'] as String),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 24,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: ingredients.map((ingredient) {
                  return _buildIngredientSection(ingredient);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIngredientSection(Map<String, dynamic> ingredient) {
    final recommendations = ingredient['recommendations'] as List;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ingredient['name'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${ingredient['amount']} needed',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recommendations.map((product) => _buildProductCard(product)),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final type = product['type'] as String;
    final isBest = type == 'best';
    final isBudget = type == 'budget';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(
          color: isBest
              ? AppColors.primary
              : isBudget
              ? AppColors.success
              : AppColors.borderSecondary,
          width: isBest ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          if (isBest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.local_fire_department,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'BEST MATCH (95%)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            )
          else if (isBudget)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '\$ Budget Friendly',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ),
          if (isBest || isBudget) const SizedBox(height: 12),

          // Product Info
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  product['image'] as String,
                  width: 70,
                  height: 70,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 70,
                      height: 70,
                      color: AppColors.backgroundTertiary,
                      child: const Icon(Icons.error_outline),
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
                      product['name'] as String,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: product['price'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          TextSpan(
                            text: ' (${product['weight']})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.normal,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star,
                          size: 14,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${product['rating']} • ${product['reviews']} reviews',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Coupang Button
          ElevatedButton(
            onPressed: () {
              // TODO: Open Coupang link
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  '쿠팡에서 보기',
                  style: TextStyle(
                    color: AppColors.background,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.background,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
