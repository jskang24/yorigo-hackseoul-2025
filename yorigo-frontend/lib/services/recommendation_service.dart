import 'dart:convert';
import 'package:http/http.dart' as http;

class RecommendationService {
  // Railway backend URL
  static const String baseUrl = 'https://yorigo-production-e15a.up.railway.app';

  /// Get recipe recommendation based on cart recipes
  Future<RecipeRecommendation?> getRecommendation({
    required List<Map<String, dynamic>> cartRecipes,
    required List<Map<String, dynamic>> availableRecipes,
    Map<String, dynamic>? userPreferences,
    String? userId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/recommend_recipe');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'cart_recipes': cartRecipes,
          'available_recipes': availableRecipes,
          'user_preferences': userPreferences,
          'user_id': userId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return RecipeRecommendation.fromJson(data);
      } else {
        print('Error fetching recommendation: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception in getRecommendation: $e');
      return null;
    }
  }
}

class EfficiencyMetrics {
  final double moneySavedPerUnit;
  final double wasteReductionPercent;
  final double totalSavingsKrw;
  final List<String> sharedMainIngredients;
  final String explanation;

  EfficiencyMetrics({
    required this.moneySavedPerUnit,
    required this.wasteReductionPercent,
    required this.totalSavingsKrw,
    required this.sharedMainIngredients,
    required this.explanation,
  });

  factory EfficiencyMetrics.fromJson(Map<String, dynamic> json) {
    return EfficiencyMetrics(
      moneySavedPerUnit: (json['money_saved_per_unit'] ?? 0).toDouble(),
      wasteReductionPercent: (json['waste_reduction_percent'] ?? 0).toDouble(),
      totalSavingsKrw: (json['total_savings_krw'] ?? 0).toDouble(),
      sharedMainIngredients:
          (json['shared_main_ingredients'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      explanation: json['explanation']?.toString() ?? '',
    );
  }
}

class RecipeRecommendation {
  final Map<String, dynamic> recommendedRecipe;
  final EfficiencyMetrics efficiencyMetrics;
  final String reasoning;
  final double tasteMatchScore;
  final String? recommendationId; // For tracking feedback

  RecipeRecommendation({
    required this.recommendedRecipe,
    required this.efficiencyMetrics,
    required this.reasoning,
    required this.tasteMatchScore,
    this.recommendationId,
  });

  factory RecipeRecommendation.fromJson(Map<String, dynamic> json) {
    return RecipeRecommendation(
      recommendedRecipe: json['recommended_recipe'] as Map<String, dynamic>,
      efficiencyMetrics: EfficiencyMetrics.fromJson(
        json['efficiency_metrics'] as Map<String, dynamic>,
      ),
      reasoning: json['reasoning']?.toString() ?? '',
      tasteMatchScore: (json['taste_match_score'] ?? 0).toDouble(),
      recommendationId: json['recommendation_id']?.toString(),
    );
  }

  String get recipeName {
    return recommendedRecipe['recipe']?['name']?.toString() ?? 'Unknown Recipe';
  }

  int get servings {
    return recommendedRecipe['recipe']?['servings'] ?? 1;
  }

  List<dynamic> get ingredients {
    return recommendedRecipe['recipe']?['ingredients'] ?? [];
  }
}
