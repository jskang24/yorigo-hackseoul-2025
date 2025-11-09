class Ingredient {
  final double? qty;
  final String? unit;
  final String item;
  final String? notes;
  final String? category; // "main", "sub", or "sauce_msg"

  Ingredient({
    this.qty,
    this.unit,
    required this.item,
    this.notes,
    this.category,
  });

  factory Ingredient.fromJson(dynamic json) {
    // Handle Firestore _Map<dynamic, dynamic> types
    if (json is! Map) return Ingredient(item: '');

    return Ingredient(
      qty: json['qty']?.toDouble(),
      unit: json['unit']?.toString(),
      item: json['item']?.toString() ?? '',
      notes: json['notes']?.toString(),
      category: json['category']?.toString(),
    );
  }
}

class Step {
  final int order;
  final String instruction;
  final String? tip; // Cooking tip for this step
  final List<String>?
  stepIngredients; // Ingredients used in this step (item names)
  final int? estMinutes;
  final List<String>? tools;

  Step({
    required this.order,
    required this.instruction,
    this.tip,
    this.stepIngredients,
    this.estMinutes,
    this.tools,
  });

  factory Step.fromJson(dynamic json) {
    // Handle Firestore _Map<dynamic, dynamic> types
    if (json is! Map) return Step(order: 0, instruction: '');

    return Step(
      order: json['order'] ?? 0,
      instruction: json['instruction']?.toString() ?? '',
      tip: json['tip']?.toString(),
      stepIngredients: json['step_ingredients'] != null
          ? List<String>.from(json['step_ingredients'])
          : null,
      estMinutes: json['est_minutes'],
      tools: json['tools'] != null ? List<String>.from(json['tools']) : null,
    );
  }
}

class Recipe {
  final String? name;
  final int? servings;
  final List<Ingredient> ingredients;
  final List<Step> steps;
  final List<String>? equipment;
  final List<String>? notes;

  Recipe({
    this.name,
    this.servings,
    required this.ingredients,
    required this.steps,
    this.equipment,
    this.notes,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      name: json['name']?.toString(),
      servings: json['servings'],
      ingredients:
          (json['ingredients'] as List<dynamic>?)
              ?.map((e) => Ingredient.fromJson(e))
              .toList() ??
          [],
      steps:
          (json['steps'] as List<dynamic>?)
              ?.map((e) => Step.fromJson(e))
              .toList() ??
          [],
      equipment: json['equipment'] != null
          ? List<String>.from(json['equipment'])
          : null,
      notes: json['notes'] != null ? List<String>.from(json['notes']) : null,
    );
  }
}

class NutritionLLM {
  final double caloriesPerServing;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double sodiumMg;

  NutritionLLM({
    required this.caloriesPerServing,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.sodiumMg,
  });

  factory NutritionLLM.fromJson(Map<String, dynamic> json) {
    return NutritionLLM(
      caloriesPerServing: (json['calories_per_serving'] ?? 0).toDouble(),
      proteinG: (json['protein_g'] ?? 0).toDouble(),
      fatG: (json['fat_g'] ?? 0).toDouble(),
      carbsG: (json['carbs_g'] ?? 0).toDouble(),
      sodiumMg: (json['sodium_mg'] ?? 0).toDouble(),
    );
  }
}

class Nutrition {
  final Map<String, double> perServing;
  final List<String> assumptions;
  final NutritionLLM? llmEstimate;

  Nutrition({
    required this.perServing,
    required this.assumptions,
    this.llmEstimate,
  });

  factory Nutrition.fromJson(Map<String, dynamic> json) {
    // Handle Firestore _Map<dynamic, dynamic> types
    Map<String, double> parsePerServing(dynamic data) {
      if (data == null) return {};
      if (data is Map) {
        final Map<String, double> result = {};
        data.forEach((key, value) {
          if (value != null) {
            result[key.toString()] = (value as num).toDouble();
          }
        });
        return result;
      }
      return {};
    }

    Map<String, dynamic> convertMap(dynamic data) {
      if (data == null) return {};
      if (data is Map) {
        final Map<String, dynamic> result = {};
        data.forEach((key, value) {
          result[key.toString()] = value;
        });
        return result;
      }
      return {};
    }

    return Nutrition(
      perServing: parsePerServing(json['per_serving']),
      assumptions: json['assumptions'] != null
          ? List<String>.from(json['assumptions'])
          : [],
      llmEstimate: json['llm_estimate'] != null
          ? NutritionLLM.fromJson(convertMap(json['llm_estimate']))
          : null,
    );
  }
}

class ParseResponse {
  final Map<String, dynamic> source;
  final Recipe recipe;
  final Nutrition nutrition;
  final Map<String, dynamic> debug;

  ParseResponse({
    required this.source,
    required this.recipe,
    required this.nutrition,
    required this.debug,
  });

  factory ParseResponse.fromJson(Map<String, dynamic> json) {
    // Helper to safely convert to Map<String, dynamic>
    Map<String, dynamic> convertMap(dynamic data) {
      if (data == null) return {};
      if (data is Map<String, dynamic>) return data;
      if (data is Map) {
        final Map<String, dynamic> result = {};
        data.forEach((key, value) {
          result[key.toString()] = value;
        });
        return result;
      }
      return {};
    }

    return ParseResponse(
      source: convertMap(json['source']),
      recipe: Recipe.fromJson(convertMap(json['recipe'])),
      nutrition: Nutrition.fromJson(convertMap(json['nutrition'])),
      debug: convertMap(json['debug']),
    );
  }
}
