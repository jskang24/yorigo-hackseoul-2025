import 'dart:convert';
import 'package:http/http.dart' as http;

class FeedbackService {
  // Railway backend URL
  static const String baseUrl = 'https://yorigo-production-e15a.up.railway.app';

  /// Record user feedback on a recommendation
  Future<bool> recordFeedback({
    required String userId,
    required String recommendationId,
    required String feedback, // "positive" or "negative"
    String? recipeId,
    Map<String, dynamic>? context,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/recommendation_feedback');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'recommendation_id': recommendationId,
          'feedback': feedback,
          'recipe_id': recipeId,
          'context': context,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Feedback recorded: ${data['message']}');
        return data['success'] ?? false;
      } else {
        print('Error recording feedback: ${response.statusCode}');
        print('Response body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Exception in recordFeedback: $e');
      return false;
    }
  }

  /// Get user's personalized weights
  Future<Map<String, dynamic>?> getUserWeights(String userId) async {
    try {
      final uri = Uri.parse('$baseUrl/user_weights/$userId');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data as Map<String, dynamic>;
      } else {
        print('Error fetching user weights: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception in getUserWeights: $e');
      return null;
    }
  }
}
