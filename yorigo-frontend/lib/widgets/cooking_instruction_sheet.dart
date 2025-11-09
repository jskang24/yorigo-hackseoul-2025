import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/recipe_models.dart' as models;

class CookingInstructionSheet extends StatefulWidget {
  final models.Recipe recipe;

  const CookingInstructionSheet({super.key, required this.recipe});

  @override
  State<CookingInstructionSheet> createState() =>
      _CookingInstructionSheetState();
}

class _CookingInstructionSheetState extends State<CookingInstructionSheet> {
  int _currentStepIndex = 0;
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _totalSteps => widget.recipe.steps.length;
  double get _progress =>
      _totalSteps > 0 ? (_currentStepIndex + 1) / _totalSteps : 0.0;
  int get _progressPercentage => (_progress * 100).round();

  models.Step? get _currentStep => _currentStepIndex < _totalSteps
      ? widget.recipe.steps[_currentStepIndex]
      : null;
  models.Step? get _nextStep => _currentStepIndex + 1 < _totalSteps
      ? widget.recipe.steps[_currentStepIndex + 1]
      : null;

  void _goToNextStep() {
    if (_currentStepIndex < _totalSteps - 1) {
      setState(() {
        _currentStepIndex++;
      });
      // Scroll to top when moving to next step
      Future.microtask(() {
        _controller.animateTo(
          0.9, // maxChildSize
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    } else {
      // Last step - close the sheet
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep == null) {
      return const SizedBox.shrink();
    }

    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final brightness = Theme.of(context).brightness;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.getBackground(brightness),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.getBorderSecondary(brightness),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Recipe title
                      Text(
                        widget.recipe.name ?? '레시피',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.getTextPrimary(brightness),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Progress bar
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: AppColors.getBorderSecondary(
                                  brightness,
                                ),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$_progressPercentage% 완성',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.getTextSecondary(brightness),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // Step number badge
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F1E8), // Light beige
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${_currentStep!.order}.',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppColors.getTextPrimary(brightness),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Instruction text (very large font)
                      Text(
                        _currentStep!.instruction,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.6,
                          color: AppColors.getTextPrimary(brightness),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Step-specific ingredients section
                      if (_currentStep!.stepIngredients != null &&
                          _currentStep!.stepIngredients!.isNotEmpty) ...[
                        Text(
                          '이 단계에 필요한 재료',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.getTextPrimary(brightness),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Match ingredient names to full ingredient objects
                        ..._currentStep!.stepIngredients!.map((ingredientName) {
                          // Find matching ingredient from recipe
                          final matchingIngredient = widget.recipe.ingredients
                              .firstWhere(
                                (ing) => ing.item == ingredientName,
                                orElse: () =>
                                    models.Ingredient(item: ingredientName),
                              );

                          // Build display text
                          String displayText = matchingIngredient.item;
                          if (matchingIngredient.qty != null &&
                              matchingIngredient.unit != null) {
                            final qty = matchingIngredient.qty!;
                            final unit = matchingIngredient.unit!;
                            // Format quantity nicely
                            String qtyText;
                            if (qty % 1 == 0) {
                              qtyText = qty.toInt().toString();
                            } else if (qty < 10) {
                              qtyText = qty.toStringAsFixed(1);
                            } else {
                              qtyText = qty.toInt().toString();
                            }
                            displayText = '$displayText $qtyText$unit';
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F1E8), // Light beige
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.getBorder(brightness),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  displayText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.getTextPrimary(brightness),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 32),
                      ],
                      // Tip section (if available)
                      if (_currentStep!.tip != null &&
                          _currentStep!.tip!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F1E8), // Light beige
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '요리 팁',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.getTextPrimary(
                                        brightness,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _currentStep!.tip!,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: AppColors.getTextPrimary(brightness),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      const SizedBox(height: 8),
                      // Next step preview and navigation button (at bottom)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Next step preview
                          if (_nextStep != null) ...[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '다음:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.getTextPrimary(
                                        brightness,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _nextStep!.instruction,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.5,
                                      color: AppColors.getTextPrimary(
                                        brightness,
                                      ),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          // Navigation button (circular orange button)
                          GestureDetector(
                            onTap: _goToNextStep,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _currentStepIndex < _totalSteps - 1
                                    ? Icons.arrow_forward
                                    : Icons.check,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
