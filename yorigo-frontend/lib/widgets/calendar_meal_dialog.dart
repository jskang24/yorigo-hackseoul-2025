import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/meal_plan_service.dart';
import '../services/user_service.dart';

class CalendarMealDialog extends StatefulWidget {
  final String recipeId;
  final String recipeTitle;
  final Set<String>? selectedIngredients;
  final int? portionCount;
  final dynamic parseResponse; // ParseResponse from recipe_detail_screen
  final VoidCallback?
  onBackToStep1; // Callback to go back to ingredient selection

  const CalendarMealDialog({
    super.key,
    required this.recipeId,
    required this.recipeTitle,
    this.selectedIngredients,
    this.portionCount,
    this.parseResponse,
    this.onBackToStep1,
  });

  @override
  State<CalendarMealDialog> createState() => _CalendarMealDialogState();
}

class _CalendarMealDialogState extends State<CalendarMealDialog> {
  final MealPlanService _mealPlanService = MealPlanService();
  final UserService _userService = UserService();
  DateTime? _selectedDate;
  Map<String, Map<String, dynamic>> _mealPlans = {};
  String? _selectedMealTime; // Only one meal can be selected

  @override
  void initState() {
    super.initState();
    _selectedDate = _getToday();
    _loadMealPlans();
  }

  DateTime _getToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<DateTime> _getWeekDates() {
    final today = _getToday();
    final List<DateTime> weekDates = [];
    for (int i = -1; i <= 5; i++) {
      weekDates.add(today.add(Duration(days: i)));
    }
    return weekDates;
  }

  String _getKoreanDayOfWeek(DateTime date) {
    final weekday = date.weekday;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[weekday - 1];
  }

  String _getKoreanMonthName(DateTime date) {
    return '${date.month}월';
  }

  List<String> _getMealIndicators(DateTime date) {
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

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
        return AppColors.textTertiary;
    }
  }

  Future<void> _loadMealPlans() async {
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

  List<Map<String, dynamic>> _getMealItems(DateTime date) {
    final dateKey = _getDateKey(date);
    final mealPlan = _mealPlans[dateKey];
    if (mealPlan == null) return [];

    final meals = mealPlan['meals'] as Map<String, dynamic>? ?? {};
    final recipeTitles =
        mealPlan['recipeTitles'] as Map<String, dynamic>? ?? {};
    final List<Map<String, dynamic>> mealItems = [];

    // Breakfast meals
    if (meals['breakfast'] != null) {
      final breakfastRecipes = meals['breakfast'] as List? ?? [];
      for (var recipeId in breakfastRecipes) {
        mealItems.add({
          'mealTime': 'breakfast',
          'recipeId': recipeId.toString(),
          'recipeTitle': recipeTitles[recipeId]?.toString() ?? '레시피',
        });
      }
    }

    // Lunch meals
    if (meals['lunch'] != null) {
      final lunchRecipes = meals['lunch'] as List? ?? [];
      for (var recipeId in lunchRecipes) {
        mealItems.add({
          'mealTime': 'lunch',
          'recipeId': recipeId.toString(),
          'recipeTitle': recipeTitles[recipeId]?.toString() ?? '레시피',
        });
      }
    }

    // Dinner meals
    if (meals['dinner'] != null) {
      final dinnerRecipes = meals['dinner'] as List? ?? [];
      for (var recipeId in dinnerRecipes) {
        mealItems.add({
          'mealTime': 'dinner',
          'recipeId': recipeId.toString(),
          'recipeTitle': recipeTitles[recipeId]?.toString() ?? '레시피',
        });
      }
    }

    return mealItems;
  }

  Widget _buildMealRow(
    String mealType,
    String label,
    List<Map<String, dynamic>> items,
    BuildContext context,
    bool isSelectable,
  ) {
    final brightness = Theme.of(context).brightness;
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
        barColor = AppColors.getTextTertiary(brightness);
    }

    return SizedBox(
      height: 32,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Colored vertical bar
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // Meal label
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.getTextPrimary(brightness),
            ),
          ),
          const SizedBox(width: 8),
          // Meal items as tags
          Expanded(
            child: items.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: items.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.getBackground(brightness),
                          border: Border.all(
                            color: AppColors.getBorder(brightness),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          item['recipeTitle'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.getTextPrimary(brightness),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(width: 8),
          // Add/Select button (circular + or check)
          isSelectable
              ? GestureDetector(
                  onTap: () {
                    setState(() {
                      // Only allow one meal selection
                      if (_selectedMealTime == mealType) {
                        _selectedMealTime =
                            null; // Deselect if already selected
                      } else {
                        _selectedMealTime = mealType; // Select this meal
                      }
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _selectedMealTime == mealType
                          ? Colors.transparent
                          : const Color(0xFFF5F1E8), // Light beige
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedMealTime == mealType
                            ? Colors.transparent
                            : AppColors.getBorder(brightness),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _selectedMealTime == mealType ? Icons.check : Icons.add,
                      size: 20,
                      color: _selectedMealTime == mealType
                          ? AppColors
                                .primary // Orange checkmark
                          : AppColors.getTextPrimary(brightness),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: () async {
                    if (_selectedDate != null) {
                      try {
                        await _mealPlanService.addMealToDate(
                          date: _selectedDate!,
                          mealTime: mealType,
                          recipeId: widget.recipeId,
                          recipeTitle: widget.recipeTitle,
                        );
                        // Reload meal plans to update the UI
                        _loadMealPlans();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('메뉴가 추가되었습니다'),
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
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F1E8), // Light beige
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _getToday();
    final monthName = _getKoreanMonthName(today);
    final weekDates = _getWeekDates();

    // Get meal items for selected date
    final mealItems = _selectedDate != null
        ? _getMealItems(_selectedDate!)
        : [];
    final breakfastItems = mealItems
        .where((item) => item['mealTime'] == 'breakfast')
        .cast<Map<String, dynamic>>()
        .toList();
    final lunchItems = mealItems
        .where((item) => item['mealTime'] == 'lunch')
        .cast<Map<String, dynamic>>()
        .toList();
    final dinnerItems = mealItems
        .where((item) => item['mealTime'] == 'dinner')
        .cast<Map<String, dynamic>>()
        .toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator (only show if this is Step 2)
            if (widget.selectedIngredients != null) ...[
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
                      'Step 2/2',
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
            ],
            // Title
            Text(
              widget.selectedIngredients != null ? '날짜와 식사 선택' : '날짜 선택',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.getTextPrimary(Theme.of(context).brightness),
              ),
            ),
            const SizedBox(height: 20),
            // Calendar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month name
                  Text(
                    monthName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.getTextPrimary(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Calendar dates
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Row(
                            children: weekDates.map((date) {
                              final isSelected =
                                  _selectedDate != null &&
                                  date.year == _selectedDate!.year &&
                                  date.month == _selectedDate!.month &&
                                  date.day == _selectedDate!.day;
                              final mealIndicators = _getMealIndicators(date);

                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedDate = date;
                                      // Reset meal selection when date changes
                                      if (widget.selectedIngredients != null) {
                                        _selectedMealTime = null;
                                      }
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
                                              : AppColors.getTextSecondary(
                                                  Theme.of(context).brightness,
                                                ),
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
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white
                                                  : AppColors.getTextPrimary(
                                                      Theme.of(
                                                        context,
                                                      ).brightness,
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: mealIndicators.take(3).map((
                                          meal,
                                        ) {
                                          return Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _getMealColor(meal),
                                              shape: BoxShape.circle,
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          // Orange line for selected date
                          if (_selectedDate != null)
                            Positioned(
                              left:
                                  weekDates.asMap().entries.firstWhere((entry) {
                                    final date = entry.value;
                                    return date.year == _selectedDate!.year &&
                                        date.month == _selectedDate!.month &&
                                        date.day == _selectedDate!.day;
                                  }).key *
                                  (constraints.maxWidth / 7),
                              width: constraints.maxWidth / 7,
                              bottom: -16,
                              child: Container(
                                height: 2,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Meal rows section
            if (_selectedDate != null) ...[
              // Display all three meal rows directly with labels and add buttons
              _buildMealRow(
                'breakfast',
                '아침',
                breakfastItems,
                context,
                widget.selectedIngredients != null,
              ),
              const SizedBox(height: 12),
              _buildMealRow(
                'lunch',
                '점심',
                lunchItems,
                context,
                widget.selectedIngredients != null,
              ),
              const SizedBox(height: 12),
              _buildMealRow(
                'dinner',
                '저녁',
                dinnerItems,
                context,
                widget.selectedIngredients != null,
              ),
              const SizedBox(height: 20),
            ],
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back button (only show in Step 2)
                if (widget.selectedIngredients != null &&
                    widget.onBackToStep1 != null)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onBackToStep1!();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          size: 18,
                          color: AppColors.getTextPrimary(
                            Theme.of(context).brightness,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '이전',
                          style: TextStyle(
                            color: AppColors.getTextPrimary(
                              Theme.of(context).brightness,
                            ),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                // Right side buttons
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
                    if (widget.selectedIngredients != null &&
                        _selectedDate != null &&
                        _selectedMealTime != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          await _handleCompleteStep2(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          '완료',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCompleteStep2(BuildContext context) async {
    if (_selectedDate == null || _selectedMealTime == null) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인이 필요합니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Step 1: Add to meal plan
      await _mealPlanService.addMealToDate(
        date: _selectedDate!,
        mealTime: _selectedMealTime!,
        recipeId: widget.recipeId,
        recipeTitle: widget.recipeTitle,
      );

      // Step 2: Add selected ingredients to cart
      if (widget.selectedIngredients != null &&
          widget.parseResponse != null &&
          widget.portionCount != null) {
        // Access recipe from parseResponse (dynamic type)
        final parseResponse = widget.parseResponse as dynamic;
        final recipe = parseResponse.recipe;
        final baseServings = recipe.servings ?? 2;
        final scaleFactor = widget.portionCount! / baseServings;

        // Get selected ingredients with scaled quantities
        final selectedIngredients = recipe.ingredients
            .asMap()
            .entries
            .where(
              (entry) =>
                  widget.selectedIngredients!.contains(entry.key.toString()),
            )
            .map((entry) {
              final ingredient = entry.value;
              final scaledQty = ingredient.qty != null
                  ? ingredient.qty! * scaleFactor
                  : null;

              return {
                'item': ingredient.item,
                'qty': scaledQty,
                'unit': ingredient.unit,
                'notes': ingredient.notes,
              };
            })
            .toList();

        // Create cart item
        final cartItem = {
          'recipeId': widget.recipeId,
          'recipeName': recipe.name ?? '레시피',
          'servings': widget.portionCount,
          'ingredients': selectedIngredients,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
        };

        // Add to cart
        await _userService.addToCart(user.uid, cartItem);
      }

      // Close dialog
      Navigator.of(context).pop();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('장바구니에 추가되고 식사 계획에 추가되었습니다'),
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
