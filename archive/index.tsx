import { useState } from 'react';
import { 
  View, 
  Text, 
  TextInput, 
  TouchableOpacity, 
  Image, 
  ScrollView, 
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
  SafeAreaView,
  StatusBar
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Link } from 'expo-router';

export default function Index() {
  const [youtubeUrl, setYoutubeUrl] = useState('');
  const [thumbnailUrl, setThumbnailUrl] = useState('');
  const [videoTitle, setVideoTitle] = useState('');
  const [videoDescription, setVideoDescription] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const extractVideoId = (url: string) => {
    const regex = /(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})/;
    const match = url.match(regex);
    return match ? match[1] : null;
  };

  const getYouTubeThumbnail = (videoId: string) => {
    return `https://img.youtube.com/vi/${videoId}/maxresdefault.jpg`;
  };

  const fetchVideoDetails = async (youtubeUrl: string) => {
    try {
      // Call our backend API instead of YouTube directly
      const response = await fetch('http://localhost:8000/api/fetch-video', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          youtubeUrl: youtubeUrl,
        }),
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.detail || 'Failed to fetch video details');
      }

      const data = await response.json();
      
      return {
        videoId: data.videoId,
        title: data.title,
        description: data.description,
        channelTitle: data.channelTitle,
        publishedAt: data.publishedAt,
        thumbnailUrl: data.thumbnailUrl
      };
      
    } catch (error) {
      console.error('Backend API Error:', error);
      
      // Fallback to mock data if backend fails
      console.log('Falling back to mock data...');
      const videoId = extractVideoId(youtubeUrl) || 'unknown';
      
      return {
        videoId: videoId,
        title: `Recipe Video ${videoId.substring(0, 8)}`,
        description: `This is a fallback description for video ${videoId}. 

To get real video descriptions, you need to:
1. Set up your YouTube API key in the backend server
2. Create a .env file in the server directory
3. Add: YOUTUBE_API_KEY=your_actual_api_key
4. Restart your backend server

Ingredients:
- 2 cups of flour
- 1 cup of sugar
- 3 eggs
- 1/2 cup of butter
- 1 tsp vanilla extract

Instructions:
1. Preheat oven to 350°F
2. Mix dry ingredients in a bowl
3. Beat eggs and add to mixture
4. Bake for 25-30 minutes
5. Let cool before serving

Enjoy this wonderful recipe!`,
        channelTitle: 'Demo Channel',
        publishedAt: new Date().toISOString(),
        thumbnailUrl: getYouTubeThumbnail(videoId)
      };
    }
  };

  const sendToBackend = async (videoData: any) => {
    try {
      const response = await fetch('http://localhost:8000/api/recipes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          videoId: videoData.videoId,
          title: videoData.title,
          description: videoData.description,
          thumbnailUrl: videoData.thumbnailUrl,
          youtubeUrl: youtubeUrl,
          channelTitle: videoData.channelTitle,
          publishedAt: videoData.publishedAt,
        }),
      });

      if (!response.ok) {
        throw new Error('Failed to save recipe to backend');
      }

      const result = await response.json();
      console.log('Backend response:', result);
      return result;
    } catch (error) {
      console.error('Backend error:', error);
      throw error;
    }
  };

  const handleSubmit = async () => {
    if (!youtubeUrl.trim()) {
      Alert.alert('Error', 'Please enter a YouTube URL');
      return;
    }

    const videoId = extractVideoId(youtubeUrl);
    if (!videoId) {
      Alert.alert('Error', 'Please enter a valid YouTube URL');
      return;
    }

    setIsLoading(true);
    
    try {
      // Fetch video details from our backend API
      const videoDetails = await fetchVideoDetails(youtubeUrl);
      
      // Update UI state
      setThumbnailUrl(videoDetails.thumbnailUrl);
      setVideoTitle(videoDetails.title);
      setVideoDescription(videoDetails.description);
      
      // Send to backend
      await sendToBackend({
        videoId: videoDetails.videoId,
        title: videoDetails.title,
        description: videoDetails.description,
        thumbnailUrl: videoDetails.thumbnailUrl,
        channelTitle: videoDetails.channelTitle,
        publishedAt: videoDetails.publishedAt,
      });
      
      Alert.alert('Success', 'Recipe saved successfully!');
    } catch (error) {
      Alert.alert('Error', 'Failed to process the video');
      console.error('Error:', error);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={styles.wrapper}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
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

      <KeyboardAvoidingView 
        style={styles.content} 
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <ScrollView 
          contentContainerStyle={styles.scrollContent}
          showsVerticalScrollIndicator={false}
        >
          {/* Main Content */}
          <View style={styles.mainContent}>
            {/* Center Icon and Title */}
            <View style={styles.centerContent}>
              <View style={styles.mainIcon}>
                <Image 
                  source={require('../assets/images/Yorigo_icon_light.png')} 
                  style={styles.mainIconImage}
                  resizeMode="contain"
                />
              </View>
              <Text style={styles.mainTitle}>요리고</Text>
              <Text style={styles.mainDescription}>
                유튜브 쇼츠 요리 영상을 공유하고 재료·조리법을{'\n'}자동으로 분석하세요
              </Text>
            </View>

            {/* Input Section */}
            <View style={styles.inputSection}>
              <View style={styles.inputWrapper}>
                <Ionicons name="link-outline" size={20} color="#999999" style={styles.inputIcon} />
                <TextInput
                  style={styles.input}
                  placeholder="유튜브 또는 인스타그램 영상 링크"
                  placeholderTextColor="#999999"
                  value={youtubeUrl}
                  onChangeText={setYoutubeUrl}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="url"
                />
              </View>
              
              <TouchableOpacity 
                style={[styles.analyzeButton, isLoading && styles.analyzeButtonDisabled]}
                onPress={handleSubmit}
                disabled={isLoading}
              >
                <Text style={styles.analyzeButtonText}>
                  {isLoading ? '분석 중...' : '레시피 분석하기'}
                </Text>
              </TouchableOpacity>
            </View>

            {/* Results Display */}
            {thumbnailUrl && (
              <View style={styles.resultsContainer}>
                <Text style={styles.resultsTitle}>저장된 레시피:</Text>
                <Image 
                  source={{ uri: thumbnailUrl }} 
                  style={styles.thumbnail}
                  resizeMode="cover"
                />
                <Text style={styles.videoTitleText}>{videoTitle}</Text>
                
                {videoDescription && (
                  <View style={styles.descriptionContainer}>
                    <Text style={styles.descriptionTitle}>레시피 설명:</Text>
                    <Text style={styles.descriptionText}>{videoDescription}</Text>
                  </View>
                )}
              </View>
            )}
          </View>
        </ScrollView>
      </KeyboardAvoidingView>

      {/* Bottom Navigation */}
      <View style={styles.bottomNav}>
        <Link href="/" asChild>
          <TouchableOpacity style={styles.navItem}>
            <Ionicons name="home-outline" size={24} color="#FF6900" />
            <Text style={styles.navLabelActive}>홈</Text>
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
    backgroundColor: '#ffffff',
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
    flexGrow: 1,
    justifyContent: 'center',
    paddingBottom: 40,
  },
  mainContent: {
    paddingHorizontal: 24,
    paddingVertical: 20,
  },
  centerContent: {
    alignItems: 'center',
    marginBottom: 40,
  },
  mainIcon: {
    width: 100,
    height: 100,
    borderRadius: 25,
    backgroundColor: '#FFF5ED',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 20,
    overflow: 'hidden',
  },
  mainIconImage: {
    width: 80,
    height: 80,
  },
  mainTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#FF6900',
    marginBottom: 16,
  },
  mainDescription: {
    fontSize: 14,
    color: '#666666',
    textAlign: 'center',
    lineHeight: 22,
  },
  inputSection: {
    marginBottom: 24,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#f8f8f8',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 4,
    marginBottom: 16,
  },
  inputIcon: {
    marginRight: 8,
  },
  input: {
    flex: 1,
    fontSize: 14,
    color: '#333333',
    paddingVertical: 12,
  },
  analyzeButton: {
    backgroundColor: '#FF6900',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  analyzeButtonDisabled: {
    backgroundColor: '#FFB380',
  },
  analyzeButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  resultsContainer: {
    marginTop: 32,
    alignItems: 'center',
  },
  resultsTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 16,
  },
  thumbnail: {
    width: '100%',
    height: 200,
    borderRadius: 12,
    marginBottom: 12,
  },
  videoTitleText: {
    fontSize: 16,
    color: '#333333',
    textAlign: 'center',
    marginBottom: 16,
  },
  descriptionContainer: {
    width: '100%',
    padding: 16,
    backgroundColor: '#f8f8f8',
    borderRadius: 12,
  },
  descriptionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#333333',
    marginBottom: 8,
  },
  descriptionText: {
    fontSize: 14,
    color: '#666666',
    lineHeight: 20,
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
