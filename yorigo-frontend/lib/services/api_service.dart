import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Railway backend URL
  static const String baseUrl = 'https://yorigo-production-e15a.up.railway.app';

  static Future<Map<String, dynamic>> parseRecipe({
    required String url,
    String? preferLang,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/parse_recipe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': url,
          if (preferLang != null) 'prefer_lang': preferLang,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to parse recipe: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error calling API: $e');
    }
  }

  static Stream<Map<String, dynamic>> parseRecipeStream({
    required String url,
    String? preferLang,
  }) async* {
    try {
      print(
        '[ApiService] Creating SSE request to $baseUrl/parse_recipe_stream',
      );
      final request = http.Request(
        'POST',
        Uri.parse('$baseUrl/parse_recipe_stream'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'url': url,
        if (preferLang != null) 'prefer_lang': preferLang,
      });

      final client = http.Client();
      print('[ApiService] Sending request...');
      final response = await client.send(request);

      if (response.statusCode != 200) {
        print('[ApiService] Request failed with status ${response.statusCode}');
        throw Exception('Failed to parse recipe: ${response.statusCode}');
      }

      print('[ApiService] Connected, listening for SSE events...');
      String buffer = '';
      int eventCount = 0;

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        // Parse complete SSE messages (lines ending with \n\n)
        final parts = buffer.split('\n\n');
        // Keep the last incomplete part in buffer
        buffer = parts.last;

        for (var part in parts) {
          if (part.isEmpty) continue;
          final lines = part.split('\n');
          for (var line in lines) {
            if (line.startsWith('data: ')) {
              final data = line.substring(6);
              if (data.trim().isNotEmpty) {
                try {
                  final parsed = jsonDecode(data) as Map<String, dynamic>;
                  eventCount++;
                  print('[ApiService] Event #$eventCount: ${parsed['stage']}');
                  yield parsed;
                } catch (e) {
                  print('[ApiService] Error parsing SSE data: $e');
                  print('[ApiService] Raw data: $data');
                }
              }
            }
          }
        }
      }

      // Process any remaining data in buffer
      if (buffer.isNotEmpty) {
        final lines = buffer.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data.trim().isNotEmpty) {
              try {
                final parsed = jsonDecode(data) as Map<String, dynamic>;
                eventCount++;
                print(
                  '[ApiService] Event #$eventCount (final): ${parsed['stage']}',
                );
                yield parsed;
              } catch (e) {
                print('[ApiService] Error parsing final SSE data: $e');
              }
            }
          }
        }
      }

      print('[ApiService] Stream completed, received $eventCount events');
      client.close();
    } catch (e) {
      print('[ApiService] Stream error: $e');
      throw Exception('Error calling API: $e');
    }
  }

  static Future<String> categorizeIngredient({
    required String ingredientName,
    String? category,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/categorize_ingredient'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ingredient_name': ingredientName,
          if (category != null) 'category': category,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['category'] as String;
      } else {
        throw Exception(
          'Failed to categorize ingredient: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('[ApiService] Error categorizing ingredient: $e');
      // Fallback to default category
      return '양념/소스';
    }
  }
}
