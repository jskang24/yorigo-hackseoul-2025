import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe_models.dart' as models;
import 'meal_plan_service.dart';

class RecipeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Check if a recipe with the given sourceUrl already exists in Firebase (any user)
  Future<Map<String, dynamic>?> getRecipeBySourceUrl(String sourceUrl) async {
    try {
      final querySnapshot = await _firestore
          .collection('recipes')
          .where('sourceUrl', isEqualTo: sourceUrl)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();
      final convertedData = Map<String, dynamic>.from(data);
      return {'id': doc.id, ...convertedData};
    } catch (e) {
      print('Error getting recipe by sourceUrl: $e');
      return null;
    }
  }

  // Check if the current user already has a recipe with the given sourceUrl
  Future<String?> getUserRecipeIdBySourceUrl(String sourceUrl) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final querySnapshot = await _firestore
          .collection('recipes')
          .where('userId', isEqualTo: user.uid)
          .where('sourceUrl', isEqualTo: sourceUrl)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return querySnapshot.docs.first.id;
    } catch (e) {
      print('Error checking user recipe by sourceUrl: $e');
      return null;
    }
  }

  // Get ParseResponse from existing recipe data
  Future<models.ParseResponse?> getParseResponseFromRecipeData(
    Map<String, dynamic> recipeData,
  ) async {
    try {
      // Convert Firestore maps to Map<String, dynamic> recursively
      final source = _toMapStringDynamic(recipeData['source']);
      final recipe = _toMapStringDynamic(recipeData['recipe']);
      final nutrition = _toMapStringDynamic(recipeData['nutrition']);

      // Create and return the ParseResponse
      final parseResponse = models.ParseResponse.fromJson({
        'source': source,
        'recipe': recipe,
        'nutrition': nutrition,
        'debug': {},
      });

      return parseResponse;
    } catch (e, stackTrace) {
      print('Error converting recipe data to ParseResponse: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Save a recipe to Firestore
  Future<String> saveRecipe({
    required models.ParseResponse parseResponse,
    String? sourceUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to save recipes');
    }

    // Check if user already has this recipe saved
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      final existingRecipeId = await getUserRecipeIdBySourceUrl(sourceUrl);
      if (existingRecipeId != null) {
        throw Exception('이미 저장된 레시피입니다');
      }
    }

    final recipe = parseResponse.recipe;
    final nutrition = parseResponse.nutrition;

    // Create recipe document
    final recipeData = {
      'userId': user.uid,
      'title': recipe.name ?? parseResponse.source['title'] ?? '레시피',
      'sourceUrl': sourceUrl,
      'thumbnailUrl': parseResponse.source['thumbnail'] ?? '',
      'source': parseResponse
          .source, // This includes uploader, channel, uploader_id, categories, tags, nutrition_rating
      'categories':
          parseResponse.source['categories'] ??
          {}, // Save categories for filtering
      'tags': parseResponse.source['tags'] ?? [], // Save tags for display
      'nutrition_rating':
          parseResponse.source['nutrition_rating'] ??
          'A', // Save nutrition rating
      'recipe': {
        'name': recipe.name,
        'servings': recipe.servings,
        'ingredients': recipe.ingredients
            .map(
              (ing) => {
                'qty': ing.qty,
                'unit': ing.unit,
                'item': ing.item,
                'notes': ing.notes,
                'category': ing.category,
              },
            )
            .toList(),
        'steps': recipe.steps
            .map(
              (step) => {
                'order': step.order,
                'instruction': step.instruction,
                'est_minutes': step.estMinutes,
                'tools': step.tools,
              },
            )
            .toList(),
        'equipment': recipe.equipment,
        'notes': recipe.notes,
      },
      'nutrition': {
        'per_serving': nutrition.perServing,
        'assumptions': nutrition.assumptions,
        'llm_estimate': nutrition.llmEstimate != null
            ? {
                'calories_per_serving':
                    nutrition.llmEstimate!.caloriesPerServing,
                'protein_g': nutrition.llmEstimate!.proteinG,
                'fat_g': nutrition.llmEstimate!.fatG,
                'carbs_g': nutrition.llmEstimate!.carbsG,
                'sodium_mg': nutrition.llmEstimate!.sodiumMg,
              }
            : null,
      },
      'calories': nutrition.llmEstimate?.caloriesPerServing ?? 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Initialize save tracking fields
    recipeData['saveCount'] = 0;
    recipeData['weeklySaves'] = 0;
    recipeData['monthlySaves'] = 0;
    recipeData['lastSavedAt'] = null;

    // Add recipe to recipes collection
    final docRef = await _firestore.collection('recipes').add(recipeData);

    // Add recipe ID to user's saved recipes and track save
    await _firestore.collection('users').doc(user.uid).update({
      'savedRecipes': FieldValue.arrayUnion([docRef.id]),
    });

    // Track the save
    await _trackRecipeSave(docRef.id);

    return docRef.id;
  }

  // Track when a user saves a recipe
  Future<void> _trackRecipeSave(String recipeId) async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final recipeRef = _firestore.collection('recipes').doc(recipeId);
    final recipeDoc = await recipeRef.get();

    if (!recipeDoc.exists) return;

    final data = recipeDoc.data() ?? {};
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? now;

    // Increment total save count
    await recipeRef.update({
      'saveCount': FieldValue.increment(1),
      'lastSavedAt': FieldValue.serverTimestamp(),
    });

    // Check if recipe was created within the last week/month
    if (createdAt.isAfter(weekAgo)) {
      await recipeRef.update({'weeklySaves': FieldValue.increment(1)});
    }

    if (createdAt.isAfter(monthAgo)) {
      await recipeRef.update({'monthlySaves': FieldValue.increment(1)});
    }
  }

  // Get all recipes from all users
  Stream<List<Map<String, dynamic>>> getAllRecipes() {
    return _firestore
        .collection('recipes')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final convertedData = Map<String, dynamic>.from(data);
            return {'id': doc.id, ...convertedData};
          }).toList();
        });
  }

  // Get all-time popular recipes (top 10 by save count)
  Future<List<Map<String, dynamic>>> getAllTimePopularRecipes({
    int limit = 10,
  }) async {
    try {
      // Get all recipes and sort in memory to handle missing fields
      final snapshot = await _firestore.collection('recipes').get();

      final recipes = snapshot.docs.map((doc) {
        final data = doc.data();
        final convertedData = Map<String, dynamic>.from(data);
        return {'id': doc.id, ...convertedData};
      }).toList();

      // Sort by saveCount (default to 0 if missing)
      recipes.sort((a, b) {
        final saveCountA = (a['saveCount'] as num?)?.toInt() ?? 0;
        final saveCountB = (b['saveCount'] as num?)?.toInt() ?? 0;
        return saveCountB.compareTo(saveCountA);
      });

      return recipes.take(limit).toList();
    } catch (e) {
      print('Error getting all-time popular recipes: $e');
      return [];
    }
  }

  // Get weekly popular recipes (top 10 by weekly saves)
  Future<List<Map<String, dynamic>>> getWeeklyPopularRecipes({
    int limit = 10,
  }) async {
    try {
      // Get all recipes and sort in memory to handle missing fields
      final snapshot = await _firestore.collection('recipes').get();

      final recipes = snapshot.docs.map((doc) {
        final data = doc.data();
        final convertedData = Map<String, dynamic>.from(data);
        return {'id': doc.id, ...convertedData};
      }).toList();

      // Sort by weeklySaves (default to 0 if missing)
      recipes.sort((a, b) {
        final weeklySavesA = (a['weeklySaves'] as num?)?.toInt() ?? 0;
        final weeklySavesB = (b['weeklySaves'] as num?)?.toInt() ?? 0;
        return weeklySavesB.compareTo(weeklySavesA);
      });

      return recipes.take(limit).toList();
    } catch (e) {
      print('Error getting weekly popular recipes: $e');
      return [];
    }
  }

  // Get monthly popular recipes (top 10 by monthly saves)
  Future<List<Map<String, dynamic>>> getMonthlyPopularRecipes({
    int limit = 10,
  }) async {
    try {
      // Get all recipes and sort in memory to handle missing fields
      final snapshot = await _firestore.collection('recipes').get();

      final recipes = snapshot.docs.map((doc) {
        final data = doc.data();
        final convertedData = Map<String, dynamic>.from(data);
        return {'id': doc.id, ...convertedData};
      }).toList();

      // Sort by monthlySaves (default to 0 if missing)
      recipes.sort((a, b) {
        final monthlySavesA = (a['monthlySaves'] as num?)?.toInt() ?? 0;
        final monthlySavesB = (b['monthlySaves'] as num?)?.toInt() ?? 0;
        return monthlySavesB.compareTo(monthlySavesA);
      });

      return recipes.take(limit).toList();
    } catch (e) {
      print('Error getting monthly popular recipes: $e');
      return [];
    }
  }

  // Get most recently added recipes (top 10 by creation date)
  Future<List<Map<String, dynamic>>> getRecentlyAddedRecipes({
    int limit = 10,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('recipes')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        final convertedData = Map<String, dynamic>.from(data);
        return {'id': doc.id, ...convertedData};
      }).toList();
    } catch (e) {
      print('Error getting recently added recipes: $e');
      return [];
    }
  }

  // Get all recipes for the current user
  Stream<List<Map<String, dynamic>>> getUserRecipes() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('recipes')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            // Convert Firestore map to Map<String, dynamic>
            final convertedData = Map<String, dynamic>.from(data);
            return {'id': doc.id, ...convertedData};
          }).toList();
        });
  }

  // Helper to recursively convert Firestore maps to Map<String, dynamic>
  dynamic _convertFirestoreData(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      final Map<String, dynamic> result = {};
      data.forEach((key, value) {
        result[key.toString()] = _convertFirestoreData(value);
      });
      return result;
    } else if (data is List) {
      return data.map((item) => _convertFirestoreData(item)).toList();
    }
    return data;
  }

  // Helper to safely convert to Map<String, dynamic>
  Map<String, dynamic> _toMapStringDynamic(dynamic data) {
    if (data == null) return {};
    final converted = _convertFirestoreData(data);
    if (converted is Map<String, dynamic>) {
      return converted;
    }
    return {};
  }

  // Get a single recipe by ID
  Future<models.ParseResponse?> getRecipeById(String recipeId) async {
    try {
      final doc = await _firestore.collection('recipes').doc(recipeId).get();
      if (!doc.exists) {
        print('Recipe not found: $recipeId');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        print('Recipe data is null');
        return null;
      }

      // Convert Firestore maps to Map<String, dynamic> recursively
      final source = _toMapStringDynamic(data['source']);
      final recipe = _toMapStringDynamic(data['recipe']);
      final nutrition = _toMapStringDynamic(data['nutrition']);

      // Create and return the ParseResponse
      final parseResponse = models.ParseResponse.fromJson({
        'source': source,
        'recipe': recipe,
        'nutrition': nutrition,
        'debug': {},
      });

      return parseResponse;
    } catch (e, stackTrace) {
      print('Error getting recipe: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Delete a recipe
  Future<void> deleteRecipe(String recipeId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to delete recipes');
    }

    // Remove recipe from all meal plans first
    final mealPlanService = MealPlanService();
    await mealPlanService.removeRecipeFromAllMealPlans(recipeId);

    // Remove from recipes collection
    await _firestore.collection('recipes').doc(recipeId).delete();

    // Remove from user's saved recipes
    await _firestore.collection('users').doc(user.uid).update({
      'savedRecipes': FieldValue.arrayRemove([recipeId]),
    });
  }

  // Update recipe categories
  Future<void> updateRecipeCategories(
    String recipeId,
    Map<String, List<String>> categories,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to update recipes');
    }

    // Update categories in recipe document
    await _firestore.collection('recipes').doc(recipeId).update({
      'categories': categories,
      'source.categories': categories, // Also update in source
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Migrate existing recipes to add save tracking fields
  // This should be called once to update all existing recipes
  // Note: We can't count existing saves due to security rules, so we initialize to 0
  // Save counts will be tracked going forward as users save recipes
  Future<void> migrateExistingRecipes() async {
    try {
      print('Starting recipe migration...');

      // Get all recipes (this is allowed by security rules - anyone can read recipes)
      final recipesSnapshot = await _firestore.collection('recipes').get();
      print('Found ${recipesSnapshot.docs.length} recipes to migrate');

      // Update each recipe
      int updatedCount = 0;
      int skippedCount = 0;
      int errorCount = 0;

      for (var recipeDoc in recipesSnapshot.docs) {
        final recipeId = recipeDoc.id;
        final data = recipeDoc.data();

        // Check if recipe already has save tracking fields
        final hasSaveCount = data.containsKey('saveCount');
        final hasWeeklySaves = data.containsKey('weeklySaves');
        final hasMonthlySaves = data.containsKey('monthlySaves');
        final hasLastSavedAt = data.containsKey('lastSavedAt');

        // Skip if all fields already exist
        if (hasSaveCount &&
            hasWeeklySaves &&
            hasMonthlySaves &&
            hasLastSavedAt) {
          skippedCount++;
          continue;
        }

        // Check if current user owns this recipe (required for update)
        final user = _auth.currentUser;
        final recipeUserId = data['userId'] as String?;

        // Only update recipes owned by current user (due to security rules)
        // For other recipes, we can't update them without admin permissions
        if (user == null || recipeUserId != user.uid) {
          // Skip recipes not owned by current user
          // These will need to be updated by their owners or via admin
          continue;
        }

        // Prepare update data - initialize to 0
        // Save counts will be tracked going forward as users save recipes
        final updateData = <String, dynamic>{};

        if (!hasSaveCount) {
          updateData['saveCount'] = 0;
        }
        if (!hasWeeklySaves) {
          updateData['weeklySaves'] = 0;
        }
        if (!hasMonthlySaves) {
          updateData['monthlySaves'] = 0;
        }
        if (!hasLastSavedAt) {
          updateData['lastSavedAt'] = null;
        }

        // Update recipe (only if user owns it)
        if (updateData.isNotEmpty) {
          try {
            await recipeDoc.reference.update(updateData);
            updatedCount++;
          } catch (e) {
            print('Error updating recipe $recipeId: $e');
            errorCount++;
          }
        }
      }

      print('Migration complete!');
      print('Updated: $updatedCount recipes (owned by current user)');
      print('Skipped: $skippedCount recipes (already had fields)');
      if (errorCount > 0) {
        print('Errors: $errorCount recipes');
      }
      print(
        'Note: Recipes owned by other users will be updated when their owners use the app',
      );
    } catch (e, stackTrace) {
      print('Error migrating recipes: $e');
      print('Stack trace: $stackTrace');
      // Don't rethrow - just log the error and continue
      // This allows the app to continue working even if migration fails
    }
  }
}
