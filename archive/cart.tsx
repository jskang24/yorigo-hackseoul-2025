import { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Platform, Image } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Link } from 'expo-router';

export default function CartPage() {
  // Mock cart data - in real app this would come from global state
  const [cartRecipes, setCartRecipes] = useState([
    {
      id: '1',
      name: '비빔밥 (Bibimbap)',
      servings: 4,
      isExpanded: false,
      ingredients: [
        {
          name: '당근',
          amount: '100 g',
          recommendations: [
            {
              id: 'p1',
              type: 'best',
              name: 'Premium 당근',
              price: '₩2,890',
              weight: '500g',
              rating: 4.7,
              reviews: 523,
              image: 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=200&q=80',
            },
            {
              id: 'p2',
              type: 'budget',
              name: 'Value 당근',
              price: '₩1,950',
              weight: '500g',
              rating: 4.2,
              reviews: 187,
              image: 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=200&q=80',
            },
          ],
        },
        {
          name: '시금치',
          amount: '150 g',
          recommendations: [
            {
              id: 'p3',
              type: 'best',
              name: 'Premium 시금치',
              price: '₩3,200',
              weight: '300g',
              rating: 4.6,
              reviews: 412,
              image: 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=200&q=80',
            },
            {
              id: 'p4',
              type: 'budget',
              name: 'Value 시금치',
              price: '₩2,100',
              weight: '300g',
              rating: 4.1,
              reviews: 156,
              image: 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=200&q=80',
            },
          ],
        },
      ],
    },
    {
      id: '2',
      name: '김치찌개 (Kimchi Jjigae)',
      servings: 2,
      isExpanded: false,
      ingredients: [
        {
          name: '다진 마늘',
          amount: '1 큰술',
          recommendations: [],
        },
      ],
    },
  ]);

  const toggleRecipe = (recipeId: string) => {
    setCartRecipes(prevRecipes =>
      prevRecipes.map(recipe =>
        recipe.id === recipeId
          ? { ...recipe, isExpanded: !recipe.isExpanded }
          : recipe
      )
    );
  };

  const removeRecipe = (recipeId: string) => {
    setCartRecipes(prevRecipes => prevRecipes.filter(recipe => recipe.id !== recipeId));
  };

  const clearAll = () => {
    setCartRecipes([]);
  };

  const isEmpty = cartRecipes.length === 0;

  return (
    <View style={styles.wrapper}>
      <View style={styles.container}>
        {/* Top Header */}
        <View style={styles.topHeader}>
          <View style={styles.logoContainer}>
            <View style={styles.logoIcon}>
              <Image 
                source={require('../assets/images/Yorigo_icon_dark.png')} 
                style={styles.logoIconImage}
                resizeMode="contain"
              />
            </View>
            <Text style={styles.logoText}>요리고</Text>
          </View>
          <Link href="/login" asChild>
            <TouchableOpacity style={styles.loginButton}>
              <Text style={styles.loginButtonText}>로그인</Text>
            </TouchableOpacity>
          </Link>
        </View>

        {/* Main Content */}
        {isEmpty ? (
          // Empty State
          <View style={styles.emptyContainer}>
            <View style={styles.emptyIconContainer}>
              <Ionicons name="cart-outline" size={80} color="#cccccc" />
            </View>
            <Text style={styles.emptyTitle}>장바구니가 비어있습니다</Text>
            <Text style={styles.emptySubtitle}>레시피를 추가하여 시작하세요!</Text>
            <TouchableOpacity style={styles.browseButton}>
              <Text style={styles.browseButtonText}>레시피 둘러보기</Text>
            </TouchableOpacity>
          </View>
        ) : (
          // Cart with Items
          <ScrollView 
            style={styles.content}
            contentContainerStyle={styles.scrollContent}
            showsVerticalScrollIndicator={false}
          >
            <View style={styles.headerSection}>
              <Text style={styles.pageTitle}>장바구니</Text>
              <TouchableOpacity onPress={clearAll}>
                <Text style={styles.clearAllButton}>전체 삭제</Text>
              </TouchableOpacity>
            </View>

            <Text style={styles.recipeCount}>
              {cartRecipes.length}개 레시피 • 쿠팡에서 비교하고 구매하세요
            </Text>

            {/* Recipe Cards */}
            {cartRecipes.map((recipe) => (
              <View key={recipe.id} style={styles.recipeCard}>
                <TouchableOpacity
                  style={styles.recipeHeader}
                  onPress={() => toggleRecipe(recipe.id)}
                >
                  <View style={styles.recipeHeaderLeft}>
                    <Text style={styles.recipeName}>{recipe.name}</Text>
                    <Text style={styles.recipeServings}>{recipe.servings} 인분</Text>
                  </View>
                  <View style={styles.recipeHeaderRight}>
                    <TouchableOpacity
                      onPress={() => removeRecipe(recipe.id)}
                      style={styles.deleteButton}
                    >
                      <Ionicons name="trash-outline" size={20} color="#999999" />
                    </TouchableOpacity>
                    <Ionicons
                      name={recipe.isExpanded ? 'chevron-up' : 'chevron-down'}
                      size={24}
                      color="#666666"
                    />
                  </View>
                </TouchableOpacity>

                {/* Expanded Content */}
                {recipe.isExpanded && (
                  <View style={styles.recipeContent}>
                    {recipe.ingredients.map((ingredient, index) => (
                      <View key={index} style={styles.ingredientSection}>
                        <View style={styles.ingredientHeader}>
                          <Text style={styles.ingredientName}>{ingredient.name}</Text>
                          <Text style={styles.ingredientAmount}>
                            {ingredient.amount} needed
                          </Text>
                        </View>

                        {ingredient.recommendations.map((product) => (
                          <View
                            key={product.id}
                            style={[
                              styles.productCard,
                              product.type === 'best' && styles.productCardBest,
                              product.type === 'budget' && styles.productCardBudget,
                            ]}
                          >
                            {product.type === 'best' && (
                              <View style={styles.bestMatchBadge}>
                                <Ionicons name="flame" size={14} color="#FF6900" />
                                <Text style={styles.bestMatchText}>BEST MATCH (95%)</Text>
                              </View>
                            )}
                            {product.type === 'budget' && (
                              <View style={styles.budgetBadge}>
                                <Text style={styles.budgetText}>$ Budget Friendly</Text>
                              </View>
                            )}

                            <View style={styles.productInfo}>
                              <Image
                                source={{ uri: product.image }}
                                style={styles.productImage}
                                resizeMode="cover"
                              />
                              <View style={styles.productDetails}>
                                <Text style={styles.productName}>{product.name}</Text>
                                <Text style={styles.productPrice}>
                                  {product.price}{' '}
                                  <Text style={styles.productWeight}>({product.weight})</Text>
                                </Text>
                                <View style={styles.productRating}>
                                  <Ionicons name="star" size={14} color="#FFB800" />
                                  <Text style={styles.ratingText}>
                                    {product.rating} • {product.reviews} reviews
                                  </Text>
                                </View>
                              </View>
                            </View>

                            <TouchableOpacity style={styles.coupangButton}>
                              <Text style={styles.coupangButtonText}>쿠팡에서 보기</Text>
                              <Ionicons name="arrow-forward" size={16} color="#ffffff" />
                            </TouchableOpacity>
                          </View>
                        ))}
                      </View>
                    ))}
                  </View>
                )}
              </View>
            ))}
          </ScrollView>
        )}

        {/* Bottom Navigation */}
        <View style={styles.bottomNav}>
          <Link href="/" asChild>
            <TouchableOpacity style={styles.navItem}>
              <Ionicons name="home-outline" size={24} color="#999999" />
              <Text style={styles.navLabel}>홈</Text>
            </TouchableOpacity>
          </Link>
          
          <Link href="/recipes" asChild>
            <TouchableOpacity style={styles.navItem}>
              <Ionicons name="restaurant-outline" size={24} color="#999999" />
              <Text style={styles.navLabel}>레시피</Text>
            </TouchableOpacity>
          </Link>
          
          <Link href="/feed" asChild>
            <TouchableOpacity style={styles.navItem}>
              <Ionicons name="people-outline" size={24} color="#999999" />
              <Text style={styles.navLabel}>피드</Text>
            </TouchableOpacity>
          </Link>
          
          <Link href="/cart" asChild>
            <TouchableOpacity style={styles.navItem}>
              <Ionicons name="cart" size={24} color="#FF6900" />
              <Text style={styles.navLabelActive}>장바구니</Text>
              {!isEmpty && (
                <View style={styles.cartBadge}>
                  <Text style={styles.cartBadgeText}>{cartRecipes.length}</Text>
                </View>
              )}
            </TouchableOpacity>
          </Link>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    flex: 1,
    backgroundColor: '#ffffff',
    paddingTop: Platform.OS === 'ios' ? 50 : 0,
  },
  container: {
    flex: 1,
    backgroundColor: '#F5F5F5',
  },
  topHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 12,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  logoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  logoIcon: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: '#FF6900',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
    overflow: 'hidden',
  },
  logoIconImage: {
    width: 32,
    height: 32,
  },
  logoText: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333333',
  },
  loginButton: {
    backgroundColor: '#FF6900',
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 20,
  },
  loginButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 40,
  },
  emptyIconContainer: {
    width: 140,
    height: 140,
    borderRadius: 70,
    backgroundColor: '#f5f5f5',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  emptySubtitle: {
    fontSize: 15,
    color: '#999999',
    marginBottom: 32,
  },
  browseButton: {
    backgroundColor: '#FF6900',
    paddingHorizontal: 40,
    paddingVertical: 16,
    borderRadius: 12,
  },
  browseButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  content: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 40,
  },
  headerSection: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 8,
    backgroundColor: '#F5F5F5',
  },
  pageTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333333',
  },
  clearAllButton: {
    fontSize: 15,
    color: '#FF6900',
    fontWeight: '600',
  },
  recipeCount: {
    fontSize: 14,
    color: '#666666',
    paddingHorizontal: 20,
    paddingBottom: 16,
  },
  recipeCard: {
    backgroundColor: '#ffffff',
    marginBottom: 12,
    marginHorizontal: 16,
    borderRadius: 12,
    overflow: 'hidden',
  },
  recipeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
  },
  recipeHeaderLeft: {
    flex: 1,
  },
  recipeName: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 4,
  },
  recipeServings: {
    fontSize: 14,
    color: '#999999',
  },
  recipeHeaderRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  deleteButton: {
    padding: 4,
  },
  recipeContent: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  ingredientSection: {
    marginBottom: 20,
  },
  ingredientHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  ingredientName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333333',
  },
  ingredientAmount: {
    fontSize: 14,
    color: '#999999',
  },
  productCard: {
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 12,
    padding: 12,
    marginBottom: 12,
  },
  productCardBest: {
    borderColor: '#FF6900',
    borderWidth: 2,
  },
  productCardBudget: {
    borderColor: '#4CAF50',
    borderWidth: 1,
  },
  bestMatchBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFF5ED',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 6,
    alignSelf: 'flex-start',
    marginBottom: 12,
    gap: 4,
  },
  bestMatchText: {
    fontSize: 11,
    fontWeight: 'bold',
    color: '#FF6900',
  },
  budgetBadge: {
    backgroundColor: '#E8F5E9',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 6,
    alignSelf: 'flex-start',
    marginBottom: 12,
  },
  budgetText: {
    fontSize: 11,
    fontWeight: 'bold',
    color: '#4CAF50',
  },
  productInfo: {
    flexDirection: 'row',
    marginBottom: 12,
  },
  productImage: {
    width: 70,
    height: 70,
    borderRadius: 8,
    backgroundColor: '#f0f0f0',
    marginRight: 12,
  },
  productDetails: {
    flex: 1,
    justifyContent: 'center',
  },
  productName: {
    fontSize: 15,
    fontWeight: '600',
    color: '#333333',
    marginBottom: 4,
  },
  productPrice: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 4,
  },
  productWeight: {
    fontSize: 13,
    fontWeight: 'normal',
    color: '#999999',
  },
  productRating: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  ratingText: {
    fontSize: 13,
    color: '#666666',
  },
  coupangButton: {
    backgroundColor: '#FF6900',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 8,
    gap: 6,
  },
  coupangButtonText: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: 'bold',
  },
  bottomNav: {
    flexDirection: 'row',
    backgroundColor: '#ffffff',
    borderTopWidth: 1,
    borderTopColor: '#f0f0f0',
    paddingTop: 8,
    paddingBottom: Platform.OS === 'ios' ? 20 : 8,
  },
  navItem: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 4,
    position: 'relative',
  },
  navLabel: {
    fontSize: 11,
    color: '#999999',
    marginTop: 4,
  },
  navLabelActive: {
    fontSize: 11,
    color: '#FF6900',
    fontWeight: '600',
    marginTop: 4,
  },
  cartBadge: {
    position: 'absolute',
    top: -4,
    right: '30%',
    backgroundColor: '#FF6900',
    borderRadius: 10,
    minWidth: 20,
    height: 20,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 6,
  },
  cartBadgeText: {
    color: '#ffffff',
    fontSize: 11,
    fontWeight: 'bold',
  },
});

