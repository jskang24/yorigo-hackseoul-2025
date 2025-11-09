# 요리고 (Yorigo)

**AI-Powered Recipe Management & Smart Shopping for Korean Home Cooking**

Yorigo transforms YouTube cooking videos into actionable recipes and helps you shop smarter by optimizing ingredient purchases and minimizing food waste.

---

## Key Features

### AI Recipe Extraction
- **Parse any YouTube cooking video** into structured recipes
- Combines **speech recognition (Whisper ASR)** + **optical character recognition (EasyOCR)** + **GPT-4**
- Automatically extracts ingredients, quantities, steps, and nutritional information

### Smart Shopping Cart
- **Intelligent ingredient aggregation** across multiple recipes
- **Optimal product search** via Coupang API to minimize food waste and cost
- Categorized shopping lists (protein, vegetables, grains, seasonings)
- Real-time price comparison and per-serving cost calculation

### Personalized Recommendations
- **Q-Learning based recommendation system** that learns your preferences
- Suggests recipes that **reuse leftover ingredients** to reduce waste
- Calculates potential savings from adding recommended recipes
- Adapts to your cooking habits and taste profile over time

### Meal Planning
- Visual calendar for planning weekly meals
- Track servings and cooking days
- Sync shopping lists with planned meals
- One-tap deletion of meals and associated ingredients

---

## Tech Stack

### Frontend
- **Flutter (Dart)** - Cross-platform mobile & web app
- **Firebase Auth** - User authentication
- **Firebase Firestore** - Real-time database
- **Device Frame** - Mobile viewport simulation for web demo

### Backend
- **FastAPI (Python)** - High-performance REST API
- **yt-dlp** - Video content extraction
- **Whisper (faster-whisper)** - Speech-to-text transcription
- **EasyOCR** - On-screen text extraction
- **OpenAI GPT-4** - Recipe structuring and categorization
- **FFmpeg** - Video frame extraction for OCR

### AI & Machine Learning
- **Q-Learning** - Reinforcement learning for recipe recommendations
- **Multi-modal pipeline** - Audio (ASR) + Visual (OCR) + Language (LLM)
- **Epsilon-greedy exploration** - Balances personalization with discovery

### Infrastructure
- **Railway** - Backend hosting with Docker
- **Firebase Hosting** - Frontend web deployment
- **Coupang Partners API** - E-commerce product search

---

## Value Propositions

1. **Save Time** - No more manual recipe transcription from videos
2. **Save Money** - Optimize purchases to reduce food waste and cost
3. **Reduce Waste** - Smart recommendations for leftover ingredients
4. **Personalized** - Learns your preferences to suggest recipes you'll love
5. **Convenient** - From video → recipe → shopping → cooking, all in one app

---

## Platform Support

- **iOS** (iPhone, iPad)
- **Android** (Phone, Tablet)
- **Web** (Desktop, Mobile browsers)

---

## How It Works

### Recipe Parsing Pipeline
```
YouTube Video → Audio + Video Extraction
              ↓
         ASR (Whisper) → Transcript
              ↓
         OCR (EasyOCR) → On-screen Text
              ↓
         LLM (GPT-4) → Structured Recipe
              ↓
         Nutrition Estimation
```

### Recommendation System
```
User Cart + Preferences → State Representation
              ↓
         Q-Learning Agent
              ↓
         Recipe Selection (ε-greedy)
              ↓
         User Feedback → Q-Table Update
```

---

## Demo

**Web App**: [yorigo-f7408.web.app](https://yorigo-f7408.web.app)

**Backend API**: [yorigo-production.up.railway.app](https://yorigo-production.up.railway.app)

**Website**: [yorigo.kr](https://yorigo.kr/)

© 2025 Yorigo. All rights reserved.
