import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class MealPlanService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();

  // Save a meal plan for a specific date and meal time
  Future<void> addMealToDate({
    required DateTime date,
    required String mealTime, // 'breakfast', 'lunch', 'dinner'
    required String recipeId,
    required String recipeTitle,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to add meals');
    }

    // Format date as YYYY-MM-DD for consistent storage
    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // Get or create meal plan document for this date
    final mealPlanRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mealPlans')
        .doc(dateKey);

    final mealPlanDoc = await mealPlanRef.get();

    if (mealPlanDoc.exists) {
      // Update existing meal plan
      final data = mealPlanDoc.data() ?? {};
      final meals = Map<String, dynamic>.from(data['meals'] ?? {});

      // Get existing meals for this meal time
      final mealTimeMeals = List<String>.from(meals[mealTime] ?? []);

      // Add recipe if not already present
      if (!mealTimeMeals.contains(recipeId)) {
        mealTimeMeals.add(recipeId);
      }

      meals[mealTime] = mealTimeMeals;

      await mealPlanRef.update({
        'meals': meals,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create new meal plan
      await mealPlanRef.set({
        'date': Timestamp.fromDate(date),
        'dateKey': dateKey,
        'meals': {
          mealTime: [recipeId],
        },
        'recipeTitles': {recipeId: recipeTitle},
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Also update recipe titles map
    await mealPlanRef.update({'recipeTitles.$recipeId': recipeTitle});
  }

  // Get meal plan for a specific date
  Future<Map<String, dynamic>?> getMealPlanForDate(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final mealPlanDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mealPlans')
        .doc(dateKey)
        .get();

    if (!mealPlanDoc.exists) {
      return null;
    }

    return mealPlanDoc.data();
  }

  // Get all meal plans for a date range
  Stream<Map<String, Map<String, dynamic>>> getMealPlansForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value({});
    }

    // Generate date keys for the range
    final startDateKey =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final endDateKey =
        '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';

    // Query all meal plans and filter by dateKey range in memory
    // (Firestore doesn't support multiple where clauses on the same field)
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mealPlans')
        .snapshots()
        .map((snapshot) {
          final Map<String, Map<String, dynamic>> mealPlans = {};

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final dateKey = data['dateKey'] as String? ?? doc.id;

            // Filter by dateKey range
            if (dateKey.compareTo(startDateKey) >= 0 &&
                dateKey.compareTo(endDateKey) <= 0) {
              mealPlans[dateKey] = data;
            }
          }

          return mealPlans;
        });
  }

  // Remove a meal from a date
  Future<void> removeMealFromDate({
    required DateTime date,
    required String mealTime,
    required String recipeId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to remove meals');
    }

    final dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final mealPlanRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mealPlans')
        .doc(dateKey);

    final mealPlanDoc = await mealPlanRef.get();

    if (mealPlanDoc.exists) {
      final data = mealPlanDoc.data() ?? {};
      final meals = Map<String, dynamic>.from(data['meals'] ?? {});

      // Get existing meals for this meal time
      final mealTimeMeals = List<String>.from(meals[mealTime] ?? []);

      // Remove recipe if present
      mealTimeMeals.remove(recipeId);

      meals[mealTime] = mealTimeMeals;

      // If all meals are empty, delete the document
      final hasAnyMeals = meals.values.any(
        (mealList) => mealList is List && mealList.isNotEmpty,
      );

      if (hasAnyMeals) {
        await mealPlanRef.update({
          'meals': meals,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await mealPlanRef.delete();
      }
    }

    // Also remove all cart items related to this recipe
    await _userService.removeCartItemsByRecipeId(user.uid, recipeId);
  }

  // Remove a recipe from all meal plans (used when recipe is deleted)
  Future<void> removeRecipeFromAllMealPlans(String recipeId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception(
        'User must be logged in to remove recipes from meal plans',
      );
    }

    // Get all meal plans for this user
    final mealPlansSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('mealPlans')
        .get();

    // Process each meal plan
    final batch = _firestore.batch();
    final List<String> emptyMealPlanIds = [];
    bool hasBatchOperations = false;

    for (var doc in mealPlansSnapshot.docs) {
      final data = doc.data();
      final meals = Map<String, dynamic>.from(data['meals'] ?? {});
      bool recipeFound = false;

      // Remove recipe from all meal times
      for (var mealTime in ['breakfast', 'lunch', 'dinner']) {
        final mealTimeMeals = List<String>.from(meals[mealTime] ?? []);
        if (mealTimeMeals.contains(recipeId)) {
          mealTimeMeals.remove(recipeId);
          meals[mealTime] = mealTimeMeals;
          recipeFound = true;
        }
      }

      // If recipe was found in this meal plan, update or delete it
      if (recipeFound) {
        // Check if all meals are now empty
        final hasAnyMeals = meals.values.any(
          (mealList) => mealList is List && mealList.isNotEmpty,
        );

        if (hasAnyMeals) {
          // Update meal plan: remove recipe from meals and recipeTitles
          final updateData = <String, dynamic>{
            'meals': meals,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          // Remove recipe from recipeTitles if it exists
          final recipeTitles = Map<String, dynamic>.from(
            data['recipeTitles'] ?? {},
          );
          if (recipeTitles.containsKey(recipeId)) {
            recipeTitles.remove(recipeId);
            updateData['recipeTitles'] = recipeTitles;
          }

          batch.update(doc.reference, updateData);
          hasBatchOperations = true;
        } else {
          // All meals are empty, mark for deletion
          emptyMealPlanIds.add(doc.id);
        }
      }
    }

    // Commit batch updates if there are any
    if (hasBatchOperations) {
      await batch.commit();
    }

    // Delete empty meal plans
    for (var mealPlanId in emptyMealPlanIds) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('mealPlans')
          .doc(mealPlanId)
          .delete();
    }

    // Also remove all cart items related to this recipe
    await _userService.removeCartItemsByRecipeId(user.uid, recipeId);
  }
}
