import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user document
  Future<DocumentSnapshot> getUserDocument(String uid) async {
    return await _firestore.collection('users').doc(uid).get();
  }

  // Get user data stream
  Stream<DocumentSnapshot> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? photoUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    updates['updatedAt'] = FieldValue.serverTimestamp();

    await _firestore.collection('users').doc(uid).update(updates);
  }

  // Add recipe to saved recipes and track save
  Future<void> addSavedRecipe(String uid, String recipeId) async {
    // Check if recipe is already in saved recipes
    final doc = await getUserDocument(uid);
    final data = doc.data() as Map<String, dynamic>?;
    final savedRecipes = List<String>.from(data?['savedRecipes'] ?? []);

    // Only track save if recipe is not already saved
    if (!savedRecipes.contains(recipeId)) {
      // Track the save in the recipe document
      await _trackRecipeSave(recipeId);
    }

    // Use set with merge to create the field if it doesn't exist
    await _firestore.collection('users').doc(uid).set({
      'savedRecipes': FieldValue.arrayUnion([recipeId]),
    }, SetOptions(merge: true));
  }

  // Track when a recipe is saved by a user
  Future<void> _trackRecipeSave(String recipeId) async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final monthAgo = now.subtract(const Duration(days: 30));

    final recipeRef = _firestore.collection('recipes').doc(recipeId);
    final recipeDoc = await recipeRef.get();

    if (!recipeDoc.exists) return;

    final data = recipeDoc.data() ?? {};
    final lastSavedAt = (data['lastSavedAt'] as Timestamp?)?.toDate();

    // Increment total save count
    await recipeRef.update({
      'saveCount': FieldValue.increment(1),
      'lastSavedAt': FieldValue.serverTimestamp(),
    });

    // Track weekly saves (if saved within last week)
    if (lastSavedAt == null || lastSavedAt.isAfter(weekAgo)) {
      await recipeRef.update({'weeklySaves': FieldValue.increment(1)});
    }

    // Track monthly saves (if saved within last month)
    if (lastSavedAt == null || lastSavedAt.isAfter(monthAgo)) {
      await recipeRef.update({'monthlySaves': FieldValue.increment(1)});
    }
  }

  // Remove recipe from saved recipes
  Future<void> removeSavedRecipe(String uid, String recipeId) async {
    await _firestore.collection('users').doc(uid).set({
      'savedRecipes': FieldValue.arrayRemove([recipeId]),
    }, SetOptions(merge: true));
  }

  // Add item to cart
  Future<void> addToCart(String uid, Map<String, dynamic> cartItem) async {
    // Use set with merge to create the field if it doesn't exist
    await _firestore.collection('users').doc(uid).set({
      'cartItems': FieldValue.arrayUnion([cartItem]),
    }, SetOptions(merge: true));
  }

  // Remove item from cart
  Future<void> removeFromCart(String uid, Map<String, dynamic> cartItem) async {
    await _firestore.collection('users').doc(uid).set({
      'cartItems': FieldValue.arrayRemove([cartItem]),
    }, SetOptions(merge: true));
  }

  // Clear cart
  Future<void> clearCart(String uid) async {
    await _firestore.collection('users').doc(uid).set({
      'cartItems': [],
    }, SetOptions(merge: true));
  }

  // Get saved recipes
  Future<List<String>> getSavedRecipes(String uid) async {
    final doc = await getUserDocument(uid);
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      return List<String>.from(data?['savedRecipes'] ?? []);
    }
    return [];
  }

  // Get cart items
  Future<List<Map<String, dynamic>>> getCartItems(String uid) async {
    final doc = await getUserDocument(uid);
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      final items = data?['cartItems'] as List?;
      return items?.map((item) => item as Map<String, dynamic>).toList() ?? [];
    }
    return [];
  }

  // Remove all cart items with a specific recipeId
  Future<void> removeCartItemsByRecipeId(String uid, String recipeId) async {
    final doc = await getUserDocument(uid);
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>?;
    final cartItems = data?['cartItems'] as List? ?? [];

    // Filter out items with matching recipeId
    final remainingItems = cartItems.where((item) {
      final cartItem = item as Map<String, dynamic>;
      final itemRecipeId = cartItem['recipeId']?.toString();
      return itemRecipeId != recipeId;
    }).toList();

    // Update cart with remaining items
    await _firestore.collection('users').doc(uid).set({
      'cartItems': remainingItems,
    }, SetOptions(merge: true));
  }
}
