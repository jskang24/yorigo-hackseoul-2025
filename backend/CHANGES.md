# Backend Improvements Summary

## Changes Made

### 1. **Precise Ingredient Quantities (No More Nulls)**
- Updated LLM prompt to **require** qty and unit for every ingredient
- LLM now estimates reasonable amounts when not explicitly stated
- Uses context from servings, standard recipe proportions, and visual cues

### 2. **LLM-Based Nutrition Calculation**
- LLM now calculates nutrition based on ALL ingredients and their quantities
- Added `NutritionLLM` model with fields:
  - `calories_per_serving`
  - `protein_g`
  - `fat_g`
  - `carbs_g`
  - `sodium_mg`
- Nutrition response now includes both:
  - `per_serving`: Lookup table fallback (existing)
  - `llm_estimate`: LLM's comprehensive calculation (new)

### 3. **Video Description Extraction**
- Added `writedescription: True` to yt-dlp options
- Video description now passed to LLM alongside transcript and OCR text
- Helps LLM find ingredient lists often posted in video descriptions
- Debug info includes `has_description` flag

### 4. **Enhanced LLM Prompt**
- More detailed instructions for precision
- Explicitly forbids null values for qty/unit
- Requests nutrition calculation in the same call
- Increased context window from 12k to 16k characters

## API Response Changes

### Before:
```json
{
  "recipe": {
    "ingredients": [
      {"qty": null, "unit": null, "item": "멸치 액전"}
    ]
  },
  "nutrition": {
    "per_serving": {"kcal": 0.0, ...},
    "assumptions": ["Partial nutrition..."]
  }
}
```

### After:
```json
{
  "recipe": {
    "ingredients": [
      {"qty": 2, "unit": "tbsp", "item": "멸치 액전"}
    ]
  },
  "nutrition": {
    "per_serving": {"kcal": 0.0, ...},
    "assumptions": ["Nutrition calculated by LLM..."],
    "llm_estimate": {
      "calories_per_serving": 450,
      "protein_g": 35,
      "fat_g": 25,
      "carbs_g": 15,
      "sodium_mg": 1200
    }
  },
  "debug": {
    "has_description": true
  }
}
```

## Testing

Restart your server and test with the same video:

```bash
cd /Users/joonseokkang/Documents/yorigo
python -m uvicorn backend.backend:app --reload

# In another terminal:
curl -X POST "http://localhost:8000/parse_recipe" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://www.youtube.com/shorts/iZyofxQlJ2k","prefer_lang":"ko"}'
```

You should now see:
- ✅ All ingredients have qty and unit (no nulls)
- ✅ Nutrition info in `llm_estimate` field
- ✅ Video description used for better context

