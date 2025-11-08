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

  // Add recipe to saved recipes
  Future<void> addSavedRecipe(String uid, String recipeId) async {
    await _firestore.collection('users').doc(uid).update({
      'savedRecipes': FieldValue.arrayUnion([recipeId]),
    });
  }

  // Remove recipe from saved recipes
  Future<void> removeSavedRecipe(String uid, String recipeId) async {
    await _firestore.collection('users').doc(uid).update({
      'savedRecipes': FieldValue.arrayRemove([recipeId]),
    });
  }

  // Add item to cart
  Future<void> addToCart(String uid, Map<String, dynamic> cartItem) async {
    await _firestore.collection('users').doc(uid).update({
      'cartItems': FieldValue.arrayUnion([cartItem]),
    });
  }

  // Remove item from cart
  Future<void> removeFromCart(String uid, Map<String, dynamic> cartItem) async {
    await _firestore.collection('users').doc(uid).update({
      'cartItems': FieldValue.arrayRemove([cartItem]),
    });
  }

  // Clear cart
  Future<void> clearCart(String uid) async {
    await _firestore.collection('users').doc(uid).update({'cartItems': []});
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
}
