import { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter, useLocalSearchParams } from 'expo-router';

export default function RecipeDetailPage() {
  const router = useRouter();
  const { id } = useLocalSearchParams();
  
  const [portionCount, setPortionCount] = useState(2);

  // Mock recipe data - in real app this would come from API/state
  const recipe = {
    title: '김치찌개 (Kimchi Jjigae)',
    calories: 320,
    healthGrade: 'A',
    videoUrl: 'https://example.com/video',
    baseServings: 2, // Base recipe is for 2 servings
    ingredients: [
      { id: '1', name: '김치', baseAmount: 200.0, unit: 'g', hasInPantry: false },
      { id: '2', name: '돼지고기', baseAmount: 150.0, unit: 'g', hasInPantry: false },
      { id: '3', name: '두부', baseAmount: 1.0, unit: '모', hasInPantry: false },
      { id: '4', name: '대파', baseAmount: 1.0, unit: '대', hasInPantry: false },
      { id: '5', name: '고추가루', baseAmount: 1.0, unit: '큰술', hasInPantry: true },
      { id: '6', name: '간장', baseAmount: 1.0, unit: '큰술', hasInPantry: true },
      { id: '7', name: '다진 마늘', baseAmount: 1.0, unit: '큰술', hasInPantry: true },
    ],
    instructions: [
      '냄비에 김치 200g과 돼지고기 150g을 넣고 중불에서 볶습니다.',
      '물 2컵을 붓고 끓입니다.',
      '두부 1모를 넣고 5분간 더 끓입니다.',
      '대파, 고추가루, 간장, 다진 마늘을 넣고 간을 맞춥니다.',
      '2-3분 더 끓인 후 불을 끕니다.',
    ],
    nutrition: {
      calories: 320,
      protein: 25,
      carbs: 15,
      fat: 18,
    },
  };

  // Initialize with pantry items selected by default
  const [selectedIngredients, setSelectedIngredients] = useState<Set<string>>(
    () => new Set(recipe.ingredients.filter(ing => ing.hasInPantry).map(ing => ing.id))
  );

  const toggleIngredient = (id: string) => {
    const newSelected = new Set(selectedIngredients);
    if (newSelected.has(id)) {
      newSelected.delete(id);
    } else {
      newSelected.add(id);
    }
    setSelectedIngredients(newSelected);
  };

  // Calculate scaled amount based on portion count
  const getScaledAmount = (baseAmount: number) => {
    const scaleFactor = portionCount / recipe.baseServings;
    const scaledAmount = baseAmount * scaleFactor;
    
    // Format the number nicely
    if (scaledAmount % 1 === 0) {
      return scaledAmount.toFixed(0); // Whole number
    } else if (scaledAmount < 10) {
      return scaledAmount.toFixed(1); // One decimal for small numbers
    } else {
      return scaledAmount.toFixed(0); // No decimals for large numbers
    }
  };

  return (
    <View style={styles.wrapper}>
      <View style={styles.container}>
        {/* Top Header */}
        <View style={styles.topHeader}>
          <TouchableOpacity onPress={() => router.push('/recipes')} style={styles.backButton}>
            <Ionicons name="arrow-back" size={24} color="#333333" />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>레시피</Text>
          <View style={styles.placeholder} />
        </View>

        {/* Main Content */}
        <ScrollView 
          style={styles.content}
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          {/* Recipe Title and Info */}
          <View style={styles.titleSection}>
            <Text style={styles.recipeTitle}>{recipe.title}</Text>
            <View style={styles.infoRow}>
              <Text style={styles.caloriesText}>{recipe.calories} kcal</Text>
              <Text style={styles.separator}>•</Text>
              <Text style={styles.healthGrade}>Health Grade: {recipe.healthGrade}</Text>
            </View>
          </View>

          {/* Action Buttons */}
          <View style={styles.actionButtons}>
            <TouchableOpacity style={styles.shareButton}>
              <Ionicons name="share-social-outline" size={20} color="#ffffff" />
            </TouchableOpacity>
            <TouchableOpacity style={styles.deleteButton}>
              <Ionicons name="trash-outline" size={20} color="#FF6900" />
            </TouchableOpacity>
          </View>

          {/* Video Player */}
          <View style={styles.videoContainer}>
            <View style={styles.videoPlaceholder}>
              <View style={styles.playButton}>
                <Ionicons name="play" size={32} color="#ffffff" />
              </View>
              <Text style={styles.videoText}>영상과 함께 요리하기</Text>
            </View>
          </View>

          {/* Portion Control */}
          <View style={styles.portionControl}>
            <Text style={styles.portionLabel}>인분 조절</Text>
            <View style={styles.portionButtons}>
              <TouchableOpacity 
                style={styles.portionButton}
                onPress={() => setPortionCount(Math.max(1, portionCount - 1))}
              >
                <Ionicons name="remove" size={20} color="#333333" />
              </TouchableOpacity>
              <Text style={styles.portionNumber}>{portionCount}</Text>
              <TouchableOpacity 
                style={styles.portionButton}
                onPress={() => setPortionCount(portionCount + 1)}
              >
                <Ionicons name="add" size={20} color="#333333" />
              </TouchableOpacity>
            </View>
          </View>

          {/* Ingredients Section */}
          <View style={styles.ingredientsSection}>
            <Text style={styles.sectionTitle}>재료</Text>
            <Text style={styles.deselectText}>이미 보유한 재료는 선택 해제하세요</Text>
            
            {/* All Ingredients with consistent styling */}
            {recipe.ingredients.map((ingredient) => {
              const isSelected = selectedIngredients.has(ingredient.id);
              const scaledAmount = getScaledAmount(ingredient.baseAmount);
              return (
                <TouchableOpacity
                  key={ingredient.id}
                  style={[
                    styles.ingredientItem,
                    isSelected && styles.ingredientItemSelected
                  ]}
                  onPress={() => toggleIngredient(ingredient.id)}
                >
                  <View style={styles.ingredientLeft}>
                    <View style={[
                      styles.checkbox,
                      isSelected && styles.checkboxChecked
                    ]}>
                      {isSelected && (
                        <Ionicons name="checkmark" size={16} color="#FF6900" />
                      )}
                    </View>
                    <Text style={styles.ingredientName}>{ingredient.name}</Text>
                  </View>
                  <View style={styles.ingredientRight}>
                    <Text style={styles.ingredientAmount}>
                      {scaledAmount} {ingredient.unit}
                    </Text>
                    {ingredient.hasInPantry && isSelected && (
                      <Ionicons name="cart-outline" size={16} color="#FF6900" style={styles.cartIcon} />
                    )}
                  </View>
                </TouchableOpacity>
              );
            })}
          </View>

          {/* Add to Cart Button */}
          <TouchableOpacity style={styles.addToCartButton}>
            <Ionicons name="cart-outline" size={20} color="#ffffff" />
            <Text style={styles.addToCartText}>장바구니에 추가</Text>
          </TouchableOpacity>

          {/* Instructions Section */}
          <View style={styles.instructionsSection}>
            <Text style={styles.sectionTitle}>조리 방법</Text>
            {recipe.instructions.map((instruction, index) => (
              <View key={index} style={styles.instructionItem}>
                <View style={styles.instructionNumber}>
                  <Text style={styles.instructionNumberText}>{index + 1}</Text>
                </View>
                <Text style={styles.instructionText}>{instruction}</Text>
              </View>
            ))}
          </View>

          {/* Nutrition Info */}
          <View style={styles.nutritionSection}>
            <Text style={styles.sectionTitle}>영양 정보 (1인분)</Text>
            <View style={styles.nutritionGrid}>
              <View style={styles.nutritionItem}>
                <Text style={styles.nutritionValue}>{recipe.nutrition.calories}</Text>
                <Text style={styles.nutritionLabel}>칼로리 (kcal)</Text>
              </View>
              <View style={styles.nutritionItem}>
                <Text style={styles.nutritionValue}>{recipe.nutrition.protein}g</Text>
                <Text style={styles.nutritionLabel}>단백질</Text>
              </View>
              <View style={styles.nutritionItem}>
                <Text style={styles.nutritionValue}>{recipe.nutrition.carbs}g</Text>
                <Text style={styles.nutritionLabel}>탄수화물</Text>
              </View>
              <View style={styles.nutritionItem}>
                <Text style={styles.nutritionValue}>{recipe.nutrition.fat}g</Text>
                <Text style={styles.nutritionLabel}>지방</Text>
              </View>
            </View>
          </View>
        </ScrollView>
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
    backgroundColor: '#ffffff',
  },
  topHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  backButton: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333333',
  },
  placeholder: {
    width: 32,
  },
  content: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 40,
  },
  titleSection: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 16,
  },
  recipeTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  caloriesText: {
    fontSize: 15,
    color: '#666666',
  },
  separator: {
    fontSize: 15,
    color: '#cccccc',
    marginHorizontal: 8,
  },
  healthGrade: {
    fontSize: 15,
    color: '#FF6900',
    fontWeight: '600',
  },
  actionButtons: {
    flexDirection: 'row',
    paddingHorizontal: 20,
    gap: 12,
    marginBottom: 20,
  },
  shareButton: {
    backgroundColor: '#FF6900',
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
  },
  deleteButton: {
    backgroundColor: '#ffffff',
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: '#FF6900',
  },
  videoContainer: {
    paddingHorizontal: 20,
    marginBottom: 24,
  },
  videoPlaceholder: {
    backgroundColor: '#1a1a1a',
    borderRadius: 16,
    height: 200,
    justifyContent: 'center',
    alignItems: 'center',
  },
  playButton: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: '#FF6900',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  videoText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '500',
  },
  portionControl: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    backgroundColor: '#f8f8f8',
    marginHorizontal: 20,
    borderRadius: 12,
    marginBottom: 24,
  },
  portionLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333333',
  },
  portionButtons: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  portionButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#ffffff',
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#e0e0e0',
  },
  portionNumber: {
    fontSize: 20,
    fontWeight: '600',
    color: '#333333',
    minWidth: 30,
    textAlign: 'center',
  },
  ingredientsSection: {
    paddingHorizontal: 20,
    marginBottom: 20,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 12,
  },
  deselectText: {
    fontSize: 14,
    color: '#999999',
    marginBottom: 16,
  },
  ingredientItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 14,
    paddingHorizontal: 12,
    borderRadius: 8,
    marginBottom: 8,
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#f0f0f0',
  },
  ingredientItemSelected: {
    backgroundColor: '#FFF5ED',
    borderColor: '#FF6900',
  },
  ingredientLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  ingredientRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: '#cccccc',
    marginRight: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  checkboxChecked: {
    backgroundColor: '#FFF5ED',
    borderColor: '#FF6900',
  },
  ingredientName: {
    fontSize: 15,
    color: '#333333',
  },
  ingredientAmount: {
    fontSize: 14,
    color: '#999999',
  },
  cartIcon: {
    marginLeft: 4,
  },
  addToCartButton: {
    flexDirection: 'row',
    backgroundColor: '#FF6900',
    marginHorizontal: 20,
    paddingVertical: 16,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
    marginBottom: 32,
  },
  addToCartText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  instructionsSection: {
    paddingHorizontal: 20,
    marginBottom: 32,
  },
  instructionItem: {
    flexDirection: 'row',
    marginBottom: 20,
  },
  instructionNumber: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#FF6900',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 16,
  },
  instructionNumberText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  instructionText: {
    flex: 1,
    fontSize: 15,
    color: '#333333',
    lineHeight: 22,
    paddingTop: 6,
  },
  nutritionSection: {
    paddingHorizontal: 20,
    marginBottom: 32,
  },
  nutritionGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 16,
    marginTop: 16,
  },
  nutritionItem: {
    width: '47%',
    backgroundColor: '#f8f8f8',
    padding: 20,
    borderRadius: 12,
    alignItems: 'center',
  },
  nutritionValue: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  nutritionLabel: {
    fontSize: 13,
    color: '#666666',
  },
});

