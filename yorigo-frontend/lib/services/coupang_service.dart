import 'dart:convert';
import 'package:http/http.dart' as http;

class CoupangProduct {
  final String productId;
  final String productName;
  final int productPrice;
  final String productImage;
  final String productUrl;
  final double? rating;
  final int? reviewCount;
  final double? unitPrice; // Price per unit (g, ml, etc.)
  final double? packageSize; // Size in grams or ml
  final String? packageUnit; // Unit (g, ml, kg, l, etc.)
  final double? matchScore; // How well it matches the need (0-100)

  CoupangProduct({
    required this.productId,
    required this.productName,
    required this.productPrice,
    required this.productImage,
    required this.productUrl,
    this.rating,
    this.reviewCount,
    this.unitPrice,
    this.packageSize,
    this.packageUnit,
    this.matchScore,
  });

  factory CoupangProduct.fromJson(Map<String, dynamic> json) {
    return CoupangProduct(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productPrice: json['product_price'] ?? 0,
      productImage: json['product_image']?.toString() ?? '',
      productUrl: json['product_url']?.toString() ?? '',
      rating: json['rating']?.toDouble(),
      reviewCount: json['review_count'],
      unitPrice: json['unit_price']?.toDouble(),
      packageSize: json['package_size']?.toDouble(),
      packageUnit: json['package_unit']?.toString(),
      matchScore: json['match_score']?.toDouble(),
    );
  }

  String get formattedPrice {
    return '₩${productPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String get packageInfo {
    if (packageSize != null && packageUnit != null) {
      return '${packageSize!.toStringAsFixed(0)}$packageUnit';
    }
    return '';
  }
}

class ProductRecommendation {
  final String ingredient;
  final double? neededQty;
  final String? neededUnit;
  final CoupangProduct? bestMatch;
  final CoupangProduct? budgetOption;
  final List<CoupangProduct> allProducts;

  ProductRecommendation({
    required this.ingredient,
    this.neededQty,
    this.neededUnit,
    this.bestMatch,
    this.budgetOption,
    this.allProducts = const [],
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      ingredient: json['ingredient']?.toString() ?? '',
      neededQty: json['needed_qty']?.toDouble(),
      neededUnit: json['needed_unit']?.toString(),
      bestMatch: json['best_match'] != null
          ? CoupangProduct.fromJson(json['best_match'])
          : null,
      budgetOption: json['budget_option'] != null
          ? CoupangProduct.fromJson(json['budget_option'])
          : null,
      allProducts:
          (json['all_products'] as List<dynamic>?)
              ?.map((e) => CoupangProduct.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ProductSearchResult {
  final String productId;
  final String productName;
  final int productPrice;
  final String productImage;
  final String productUrl;
  final double? rating;
  final int? reviewCount;
  final double? packageSize;
  final String? packageUnit;
  final double? unitPrice;
  final double? amountMatchScore;
  final double? totalMatchScore;

  ProductSearchResult({
    required this.productId,
    required this.productName,
    required this.productPrice,
    required this.productImage,
    required this.productUrl,
    this.rating,
    this.reviewCount,
    this.packageSize,
    this.packageUnit,
    this.unitPrice,
    this.amountMatchScore,
    this.totalMatchScore,
  });

  factory ProductSearchResult.fromJson(Map<String, dynamic> json) {
    return ProductSearchResult(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productPrice: json['product_price'] ?? 0,
      productImage: json['product_image']?.toString() ?? '',
      productUrl: json['product_url']?.toString() ?? '',
      rating: json['rating']?.toDouble(),
      reviewCount: json['review_count'],
      packageSize: json['package_size']?.toDouble(),
      packageUnit: json['package_unit']?.toString(),
      unitPrice: json['unit_price']?.toDouble(),
      amountMatchScore: json['amount_match_score']?.toDouble(),
      totalMatchScore: json['total_match_score']?.toDouble(),
    );
  }

  String get formattedPrice {
    return '₩${productPrice.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String get packageInfo {
    if (packageSize != null && packageUnit != null) {
      return '${packageSize!.toStringAsFixed(0)}$packageUnit';
    }
    return '';
  }
}

class AdvancedProductSearchResponse {
  final String ingredient;
  final double? neededQty;
  final String? neededUnit;
  final ProductSearchResult? bestAmountMatch;
  final ProductSearchResult? cheapestSameAmount;
  final ProductSearchResult? cheapestOverall;
  final List<ProductSearchResult> allProducts;

  AdvancedProductSearchResponse({
    required this.ingredient,
    this.neededQty,
    this.neededUnit,
    this.bestAmountMatch,
    this.cheapestSameAmount,
    this.cheapestOverall,
    this.allProducts = const [],
  });

  factory AdvancedProductSearchResponse.fromJson(Map<String, dynamic> json) {
    return AdvancedProductSearchResponse(
      ingredient: json['ingredient']?.toString() ?? '',
      neededQty: json['needed_qty']?.toDouble(),
      neededUnit: json['needed_unit']?.toString(),
      bestAmountMatch: json['best_amount_match'] != null
          ? ProductSearchResult.fromJson(json['best_amount_match'])
          : null,
      cheapestSameAmount: json['cheapest_same_amount'] != null
          ? ProductSearchResult.fromJson(json['cheapest_same_amount'])
          : null,
      cheapestOverall: json['cheapest_overall'] != null
          ? ProductSearchResult.fromJson(json['cheapest_overall'])
          : null,
      allProducts:
          (json['all_products'] as List<dynamic>?)
              ?.map((e) => ProductSearchResult.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class CoupangService {
  // Railway backend URL
  static const String baseUrl = 'https://yorigo-production-e15a.up.railway.app';

  /// Advanced product search with 50 results and detailed mapping
  Future<AdvancedProductSearchResponse?> searchProductsAdvanced({
    required String ingredientName,
    double? neededQty,
    String? neededUnit,
    int limit = 50,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/search_products_advanced');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ingredient_name': ingredientName,
          'needed_qty': neededQty,
          'needed_unit': neededUnit,
          'limit': limit,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Debug: Log the raw JSON response
        print('[DEBUG] Raw API Response JSON:');
        print('[DEBUG] ${jsonEncode(data)}');

        return AdvancedProductSearchResponse.fromJson(data);
      } else {
        print('Error fetching advanced product search: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception in searchProductsAdvanced: $e');
      return null;
    }
  }

  /// Search for products and get recommendations based on ingredient needs
  Future<ProductRecommendation?> getProductRecommendations({
    required String ingredientName,
    double? neededQty,
    String? neededUnit,
    int limit = 10,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/recommend_products');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ingredient_name': ingredientName,
          'needed_qty': neededQty,
          'needed_unit': neededUnit,
          'limit': limit,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ProductRecommendation.fromJson(data);
      } else {
        print('Error fetching product recommendations: ${response.statusCode}');
        print('Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception in getProductRecommendations: $e');
      return null;
    }
  }

  /// Batch get recommendations for multiple ingredients
  Future<Map<String, ProductRecommendation>> getMultipleRecommendations({
    required List<Map<String, dynamic>> ingredients,
  }) async {
    final Map<String, ProductRecommendation> results = {};

    // Process sequentially to respect API rate limits
    for (final ingredient in ingredients) {
      final name =
          ingredient['name']?.toString() ??
          ingredient['item']?.toString() ??
          '';
      if (name.isEmpty) continue;

      final qty = ingredient['qty']?.toDouble();
      final unit = ingredient['unit']?.toString();

      final recommendation = await getProductRecommendations(
        ingredientName: name,
        neededQty: qty,
        neededUnit: unit,
      );

      if (recommendation != null) {
        results[name] = recommendation;
      }

      // Small delay to avoid rate limiting (Coupang API allows 10 calls per hour)
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return results;
  }
}
