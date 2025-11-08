import { View, Text, StyleSheet, ScrollView, Image, TouchableOpacity, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Link } from 'expo-router';

export default function RecipesPage() {
  const recipes = [
    {
      id: 1,
      title: '김치찌개 (Kimchi Jjigae)',
      image: 'https://images.unsplash.com/photo-1582734404997-c645a89e5d63?w=800&q=80',
      ingredients: 7,
      servings: 1,
      calories: 320,
    },
    {
      id: 2,
      title: '불고기 (Bulgogi)',
      image: 'https://images.unsplash.com/photo-1603360946369-dc9bb6258143?w=800&q=80',
      ingredients: 10,
      servings: 2,
      calories: 450,
    },
    {
      id: 3,
      title: '비빔밥 (Bibimbap)',
      image: 'https://images.unsplash.com/photo-1553163147-622ab57be1c7?w=800&q=80',
      ingredients: 12,
      servings: 1,
      calories: 520,
    },
  ];

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
      <ScrollView 
        style={styles.content}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.headerSection}>
          <Text style={styles.pageTitle}>저장된 레시피</Text>
          <Text style={styles.recipeCount}>레시피 {recipes.length}개</Text>
        </View>

        <View style={styles.recipesContainer}>
          {recipes.map((recipe) => (
            <Link href={`/recipe/${recipe.id}`} asChild key={recipe.id}>
              <TouchableOpacity style={styles.recipeCard}>
              <Image 
                source={{ uri: recipe.image }} 
                style={styles.recipeImage}
                resizeMode="cover"
              />
              <View style={styles.recipeInfo}>
                <Text style={styles.recipeTitle}>{recipe.title}</Text>
                <Text style={styles.recipeDetails}>
                  재료 {recipe.ingredients}가지 • {recipe.servings}인분
                </Text>
                <View style={styles.calorieContainer}>
                  <View style={styles.calorieGrade}>
                    <Text style={styles.calorieGradeText}>A</Text>
                  </View>
                  <Text style={styles.calorieText}>{recipe.calories} kcal</Text>
                </View>
              </View>
            </TouchableOpacity>
            </Link>
          ))}
        </View>
      </ScrollView>

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
            <Ionicons name="restaurant-outline" size={24} color="#FF6900" />
            <Text style={styles.navLabelActive}>레시피</Text>
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
            <Ionicons name="cart-outline" size={24} color="#999999" />
            <Text style={styles.navLabel}>장바구니</Text>
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
  content: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 20,
    paddingTop: 24,
    paddingBottom: 40,
  },
  headerSection: {
    marginBottom: 24,
  },
  pageTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  recipeCount: {
    fontSize: 16,
    color: '#999999',
  },
  recipesContainer: {
    gap: 20,
  },
  recipeCard: {
    backgroundColor: '#ffffff',
    borderRadius: 16,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 3,
    marginBottom: 20,
  },
  recipeImage: {
    width: '100%',
    height: 240,
  },
  recipeInfo: {
    padding: 20,
  },
  recipeTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  recipeDetails: {
    fontSize: 14,
    color: '#999999',
    marginBottom: 12,
  },
  calorieContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  calorieGrade: {
    width: 28,
    height: 28,
    borderRadius: 6,
    backgroundColor: '#FFF5ED',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 8,
  },
  calorieGradeText: {
    fontSize: 14,
    fontWeight: 'bold',
    color: '#FF6900',
  },
  calorieText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333333',
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
});

