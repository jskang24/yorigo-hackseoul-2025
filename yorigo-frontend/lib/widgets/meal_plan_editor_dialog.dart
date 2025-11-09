import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/meal_plan_service.dart';

class MealPlanEditorDialog extends StatefulWidget {
  final Function() onMealDeleted;

  const MealPlanEditorDialog({super.key, required this.onMealDeleted});

  @override
  State<MealPlanEditorDialog> createState() => _MealPlanEditorDialogState();
}

class _MealPlanEditorDialogState extends State<MealPlanEditorDialog> {
  final MealPlanService _mealPlanService = MealPlanService();
  bool _isDeleting = false;

  Stream<Map<String, Map<String, dynamic>>> _getMealPlansStream() {
    final weekDates = _getWeekDates();
    final startDate = weekDates.first;
    final endDate = weekDates.last;
    return _mealPlanService.getMealPlansForDateRange(startDate, endDate);
  }

  String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getKoreanDayOfWeek(DateTime date) {
    final weekday = date.weekday;
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[weekday - 1];
  }

  String _getKoreanDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  String _getMealTimeLabel(String mealTime) {
    switch (mealTime) {
      case 'breakfast':
        return '아침';
      case 'lunch':
        return '점심';
      case 'dinner':
        return '저녁';
      default:
        return mealTime;
    }
  }

  Color _getMealTimeColor(String mealTime) {
    switch (mealTime) {
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

  Future<void> _deleteMeal(
    DateTime date,
    String mealTime,
    String recipeId,
  ) async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await _mealPlanService.removeMealFromDate(
        date: date,
        mealTime: mealTime,
        recipeId: recipeId,
      );
      widget.onMealDeleted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('식사 계획이 삭제되었습니다'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  List<DateTime> _getWeekDates() {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final List<DateTime> weekDates = [];

    // Today should be in the second column (index 1)
    // So we need: 1 day before, today, 5 days after
    for (int i = -1; i <= 5; i++) {
      weekDates.add(normalizedToday.add(Duration(days: i)));
    }

    return weekDates;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Dialog(
      backgroundColor: AppColors.getBackground(brightness),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '식사 계획 편집',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.getTextPrimary(brightness),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppColors.getTextSecondary(brightness),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Scrollable list of meals with StreamBuilder for real-time updates
            Expanded(
              child: StreamBuilder<Map<String, Map<String, dynamic>>>(
                stream: _getMealPlansStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '오류가 발생했습니다: ${snapshot.error}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.getTextSecondary(brightness),
                        ),
                      ),
                    );
                  }

                  final mealPlans = snapshot.data ?? {};
                  final weekDates = _getWeekDates();
                  final mealTimes = ['breakfast', 'lunch', 'dinner'];

                  // Build list of all meals with their dates
                  final List<Map<String, dynamic>> allMeals = [];

                  for (var date in weekDates) {
                    final dateKey = _getDateKey(date);
                    final mealPlan = mealPlans[dateKey];
                    if (mealPlan == null) continue;

                    final meals =
                        mealPlan['meals'] as Map<String, dynamic>? ?? {};
                    final recipeTitles =
                        mealPlan['recipeTitles'] as Map<String, dynamic>? ?? {};

                    for (var mealTime in mealTimes) {
                      final mealTimeMeals = meals[mealTime] as List? ?? [];
                      for (var recipeId in mealTimeMeals) {
                        final recipeIdStr = recipeId.toString();
                        allMeals.add({
                          'date': date,
                          'dateKey': dateKey,
                          'mealTime': mealTime,
                          'recipeId': recipeIdStr,
                          'title':
                              recipeTitles[recipeIdStr]?.toString() ?? '레시피',
                        });
                      }
                    }
                  }

                  if (allMeals.isEmpty) {
                    return Center(
                      child: Text(
                        '계획된 식사가 없습니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.getTextSecondary(brightness),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: allMeals.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: AppColors.getBorderSecondary(brightness),
                    ),
                    itemBuilder: (context, index) {
                      final meal = allMeals[index];
                      final date = meal['date'] as DateTime;
                      final mealTime = meal['mealTime'] as String;
                      final recipeId = meal['recipeId'] as String;
                      final title = meal['title'] as String;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            // Date and meal time info
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _getKoreanDayOfWeek(date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.getTextSecondary(
                                          brightness,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getKoreanDate(date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.getTextSecondary(
                                          brightness,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: _getMealTimeColor(mealTime),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _getMealTimeLabel(mealTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.getTextSecondary(
                                          brightness,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Recipe title
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.getTextPrimary(brightness),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Delete button
                            GestureDetector(
                              onTap: _isDeleting
                                  ? null
                                  : () => _deleteMeal(date, mealTime, recipeId),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _isDeleting
                                      ? AppColors.borderSecondary
                                      : AppColors.backgroundTertiary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: _isDeleting
                                      ? AppColors.textTertiary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
