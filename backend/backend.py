# app.py
import os, json, tempfile, subprocess, hashlib, re, hmac, time, urllib.parse, shutil
from typing import List, Optional, Dict, Any, Union
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, HttpUrl, ValidationError
import yt_dlp
from faster_whisper import WhisperModel
from rapidfuzz import process, fuzz
from dotenv import load_dotenv
import asyncio
import concurrent.futures
import traceback
import requests
import uuid
from datetime import datetime

load_dotenv() 

app = FastAPI(title="Yorigo Backend")

# Add CORS middleware to allow frontend to access the API
from fastapi.middleware.cors import CORSMiddleware
# CORS configuration - supports localhost, Firebase, and Railway
allowed_origins = [
    "http://localhost:8000",
    "http://localhost:59411",
    "https://yorigo-f7408.web.app",
    "https://yorigo-f7408.firebaseapp.com",
]

# Add Railway origin if provided via environment variable
railway_origin = os.getenv("RAILWAY_PUBLIC_DOMAIN")
if railway_origin:
    # Remove http:// or https:// if present
    domain = railway_origin.replace("https://", "").replace("http://", "")
    allowed_origins.append(f"https://{domain}")
    allowed_origins.append(f"http://{domain}")

# For development: allow all origins (restrict in production)
# Railway domains will be added dynamically via environment variable
# Or you can add them manually to the list above

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if os.getenv("ENVIRONMENT") != "development" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add exception handler for validation errors
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    try:
        body = await request.body()
        body_str = body.decode('utf-8')[:500] if body else "No body"
    except Exception:
        body_str = "Could not read body"
    
    print(f"[ERROR] Validation error: {exc.errors()}")
    print(f"[ERROR] Request body: {body_str}")
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors(), "body": body_str}
    )

# Coupang Partners API Configuration
COUPANG_ACCESS_KEY = os.getenv("COUPANG_ACCESS_KEY", "")
COUPANG_SECRET_KEY = os.getenv("COUPANG_SECRET_KEY", "")
COUPANG_PARTNER_SUBID = os.getenv("COUPANG_PARTNER_SUBID", "YorigoMobile")

# Naver Shopping API Configuration (as proxy for Coupang)
NAVER_CLIENT_ID = os.getenv("NAVER_CLIENT_ID", "")
NAVER_CLIENT_SECRET = os.getenv("NAVER_CLIENT_SECRET", "")

### ---------- Models ----------
class ParseRequest(BaseModel):
    url: HttpUrl
    prefer_lang: Optional[str] = "ko"  # Always defaults to Korean since app primarily targets Koreans. Language settings only control UI, not recipe parsing.

class ProductSearchRequest(BaseModel):
    ingredient_name: str
    needed_qty: Optional[float] = None
    needed_unit: Optional[str] = None
    limit: Optional[int] = 10

class CoupangProduct(BaseModel):
    product_id: str
    product_name: str
    product_price: int
    product_image: str
    product_url: str
    rating: Optional[float] = None
    review_count: Optional[int] = None
    unit_price: Optional[float] = None  # Price per unit (g, ml, etc.)
    package_size: Optional[float] = None  # Size in grams or ml
    package_unit: Optional[str] = None  # Unit (g, ml, kg, l, etc.)
    match_score: Optional[float] = None  # How well it matches the need

class ProductRecommendationResponse(BaseModel):
    ingredient: str
    needed_qty: Optional[float] = None
    needed_unit: Optional[str] = None
    best_match: Optional[CoupangProduct] = None  # Best unit match with good price
    budget_option: Optional[CoupangProduct] = None  # Cheapest unit price
    all_products: List[CoupangProduct] = []

class ProductSearchResult(BaseModel):
    """Detailed product search result with amount and unit price"""
    product_id: str
    product_name: str
    product_price: int
    product_image: str
    product_url: str
    rating: Optional[float] = None
    review_count: Optional[int] = None
    package_size: Optional[float] = None  # Size in base units (g or ml)
    package_unit: Optional[str] = None  # Unit (g, ml, kg, l, etc.)
    unit_price: Optional[float] = None  # Price per base unit
    amount_match_score: Optional[float] = None  # How well the amount matches (0-100)
    total_match_score: Optional[float] = None  # Overall match score (0-100)

class AdvancedProductSearchResponse(BaseModel):
    ingredient: str
    needed_qty: Optional[float] = None
    needed_unit: Optional[str] = None
    best_amount_match: Optional[ProductSearchResult] = None  # Best match for needed amount
    cheapest_same_amount: Optional[ProductSearchResult] = None  # Cheapest if same amount exists
    cheapest_overall: Optional[ProductSearchResult] = None  # Cheapest unit price overall
    all_products: List[ProductSearchResult] = []  # All 50 products with mapped data

class RecipeRecommendationRequest(BaseModel):
    cart_recipes: List[Dict[str, Any]]  # Recipes currently in cart
    available_recipes: List[Dict[str, Any]]  # All recipes from database to consider
    user_preferences: Optional[Dict[str, Any]] = None  # User's taste preferences (tags, categories)
    user_id: Optional[str] = None  # User ID for personalized recommendations
    
    class Config:
        arbitrary_types_allowed = True
        json_encoders = {
            dict: lambda v: v,
            list: lambda v: v,
        }

class EfficiencyMetrics(BaseModel):
    money_saved_per_unit: float  # KRW saved per gram/ml
    waste_reduction_percent: float  # Percentage of waste reduced
    total_savings_krw: float  # Total money saved
    shared_main_ingredients: List[str]  # Main ingredients shared with cart recipes
    explanation: str  # Human-readable explanation

class RecipeRecommendationResponse(BaseModel):
    recommended_recipe: Dict[str, Any]  # The recommended recipe
    efficiency_metrics: EfficiencyMetrics  # Numerical evidence
    reasoning: str  # Why this recipe was recommended
    taste_match_score: float  # 0-100 score for taste preference match
    recommendation_id: Optional[str] = None  # ID for tracking feedback
    
    class Config:
        arbitrary_types_allowed = True

class RecommendationFeedbackRequest(BaseModel):
    user_id: str
    recommendation_id: str
    feedback: str  # "positive" or "negative"
    recipe_id: Optional[str] = None
    context: Optional[Dict[str, Any]] = None  # Additional context about the recommendation

class UserWeights(BaseModel):
    user_id: str
    weights: Dict[str, float]  # Factor weights
    total_feedback: int = 0
    positive_feedback: int = 0
    negative_feedback: int = 0
    last_updated: Optional[str] = None

class Ingredient(BaseModel):
    qty: Optional[float] = None
    unit: Optional[str] = None
    item: str
    notes: Optional[str] = None
    category: Optional[str] = None  # "main", "sub", or "sauce_msg"

class Step(BaseModel):
    order: int
    instruction: str
    tip: Optional[str] = None  # Cooking tip for this step
    step_ingredients: Optional[List[str]] = None  # Ingredients used in this step (item names)
    est_minutes: Optional[int] = None
    tools: Optional[List[str]] = None

class Recipe(BaseModel):
    name: Optional[str] = None
    servings: Optional[int] = None
    ingredients: List[Ingredient]
    steps: List[Step]
    equipment: Optional[List[str]] = None
    notes: Optional[List[str]] = None

class NutritionLLM(BaseModel):
    """Nutrition info calculated by LLM from ingredients"""
    calories_per_serving: float
    protein_g: float
    fat_g: float
    carbs_g: float
    sodium_mg: float

class Nutrition(BaseModel):
    per_serving: Dict[str, float]
    assumptions: List[str]
    llm_estimate: Optional[NutritionLLM] = None

class ParseResponse(BaseModel):
    source: Dict[str, Any]
    recipe: Recipe
    nutrition: Nutrition
    debug: Dict[str, Any]

### ---------- Globals (lazy loaded) ----------
WHISPER_MODEL_SIZE = os.getenv("WHISPER_MODEL_SIZE", "medium")  # small/medium/large-v3
_whisper_model = None
def get_whisper():
    global _whisper_model
    if _whisper_model is None:
        # device="cuda" if GPU available
        _whisper_model = WhisperModel(WHISPER_MODEL_SIZE, device="auto", compute_type="auto")
    return _whisper_model

### ---------- Coupang API Helpers ----------
def generate_coupang_hmac(method: str, url: str, secret_key: str) -> str:
    """Generate HMAC signature for Coupang API authentication"""
    path = url.replace("https://api-gateway.coupang.com", "")
    datetime = time.strftime("%y%m%d") + "T" + time.strftime("%H%M%S") + "Z"
    
    message = datetime + method + path
    signature = hmac.new(
        secret_key.encode('utf-8'),
        message.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    
    return f"CEA algorithm=HmacSHA256, access-key={COUPANG_ACCESS_KEY}, signed-date={datetime}, signature={signature}"

def parse_product_size(product_name: str) -> tuple[Optional[float], Optional[str]]:
    """Extract package size and unit from product name
    Examples: '당근 500g' -> (500.0, 'g'), '우유 1L' -> (1000.0, 'ml')
    """
    # Common patterns for Korean grocery products
    patterns = [
        r'(\d+(?:\.\d+)?)\s*(kg|킬로그램)',  # kilograms
        r'(\d+(?:\.\d+)?)\s*(g|그램|g)',      # grams
        r'(\d+(?:\.\d+)?)\s*(l|리터|L)',      # liters
        r'(\d+(?:\.\d+)?)\s*(ml|밀리리터)',    # milliliters
        r'(\d+(?:\.\d+)?)\s*(개입)',           # pieces/count
        r'(\d+(?:\.\d+)?)\s*(봉지)',           # bags
    ]
    
    for pattern in patterns:
        match = re.search(pattern, product_name, re.IGNORECASE)
        if match:
            size = float(match.group(1))
            unit = match.group(2).lower()
            
            # Normalize units to base units (g, ml)
            if unit in ['kg', '킬로그램']:
                return (size * 1000, 'g')
            elif unit in ['l', '리터']:
                return (size * 1000, 'ml')
            elif unit in ['g', '그램']:
                return (size, 'g')
            elif unit in ['ml', '밀리리터']:
                return (size, 'ml')
            elif unit in ['개입']:
                return (size, '개')
            elif unit in ['봉지']:
                return (size, '봉지')
    
    return (None, None)

def normalize_unit(unit: str) -> str:
    """Normalize various unit representations to standard units"""
    unit_map = {
        'kg': 'g',
        '킬로그램': 'g',
        'l': 'ml',
        '리터': 'ml',
        '그램': 'g',
        '밀리리터': 'ml',
        'tbsp': 'ml',
        'tsp': 'ml',
        '큰술': 'ml',
        '작은술': 'ml',
    }
    return unit_map.get(unit.lower(), unit.lower())

def convert_to_base_unit(qty: float, unit: str) -> tuple[float, str]:
    """Convert quantity to base units (g or ml)"""
    unit_conversions = {
        'kg': (1000, 'g'),
        '킬로그램': (1000, 'g'),
        'l': (1000, 'ml'),
        '리터': (1000, 'ml'),
        'tbsp': (15, 'ml'),
        '큰술': (15, 'ml'),
        'tsp': (5, 'ml'),
        '작은술': (5, 'ml'),
    }
    
    if unit.lower() in unit_conversions:
        multiplier, new_unit = unit_conversions[unit.lower()]
        return (qty * multiplier, new_unit)
    
    return (qty, normalize_unit(unit))

def encode_affiliate_link(product_url: str, product_id: Optional[str] = None) -> str:
    """
    Construct raw Coupang product URL with affiliate tracking.
    Uses the standard Coupang product page format: https://www.coupang.com/vp/products/{product_id}
    Adds subId parameter for commission tracking.
    
    Args:
        product_url: Original product URL from Coupang API (may be in various formats)
        product_id: Product ID to construct raw product URL
    
    Returns:
        Raw Coupang product URL with affiliate tracking: https://www.coupang.com/vp/products/{product_id}?subId={subId}
    """
    # Extract product_id from URL if not provided
    if not product_id and product_url:
        # Try to extract product_id from various URL formats
        # Format 1: https://www.coupang.com/vp/products/PRODUCT_ID?...
        # Format 2: https://link.coupang.com/... (affiliate link format)
        # Format 3: https://www.coupang.com/vp/products/PRODUCT_ID
        try:
            parsed = urllib.parse.urlparse(product_url)
            # Extract product_id from path: /vp/products/{product_id}
            if '/vp/products/' in parsed.path:
                product_id = parsed.path.split('/vp/products/')[-1].split('/')[0].split('?')[0]
            # Or try to get from query parameters
            elif not product_id:
                query_params = urllib.parse.parse_qs(parsed.query)
                product_id = query_params.get('productId', [None])[0] or query_params.get('product_id', [None])[0]
        except Exception as e:
            print(f"[WARNING] Could not extract product_id from URL: {e}")
    
    # If we still don't have product_id, try to use the URL as-is
    if not product_id:
        if product_url and product_url.startswith(('http://', 'https://')):
            # Use the original URL but ensure it has subId
            if 'subId=' not in product_url and 'sub_id=' not in product_url:
                try:
                    parsed = urllib.parse.urlparse(product_url)
                    query_params = urllib.parse.parse_qs(parsed.query)
                    query_params['subId'] = [COUPANG_PARTNER_SUBID]
                    new_query = urllib.parse.urlencode(query_params, doseq=True)
                    return urllib.parse.urlunparse((
                        parsed.scheme,
                        parsed.netloc,
                        parsed.path,
                        parsed.params,
                        new_query,
                        parsed.fragment
                    ))
                except Exception:
                    pass
            return product_url
        else:
            print("[WARNING] No product_id or valid URL provided")
            return ""
    
    # Construct raw Coupang product URL in standard format
    # Format: https://www.coupang.com/vp/products/{product_id}?subId={subId}
    raw_product_url = f"https://www.coupang.com/vp/products/{product_id}"
    
    # Add affiliate tracking parameter
    affiliate_url = f"{raw_product_url}?subId={COUPANG_PARTNER_SUBID}"
    
    print(f"[INFO] Constructed raw Coupang product link: {affiliate_url[:100]}...")
    return affiliate_url

def calculate_match_score(needed_qty: Optional[float], needed_unit: Optional[str],
                         product_size: Optional[float], product_unit: Optional[str],
                         product_price: int, rating: Optional[float]) -> float:
    """
    Calculate match score for a product based on:
    - How close the package size is to what's needed (higher weight)
    - Unit price (lower is better)
    - Rating (higher is better)
    Returns a score from 0-100
    """
    score = 0.0
    
    # Unit match score (40 points max)
    if needed_qty and needed_unit and product_size and product_unit:
        # Convert to same base unit
        needed_base_qty, needed_base_unit = convert_to_base_unit(needed_qty, needed_unit)
        product_base_qty, product_base_unit = convert_to_base_unit(product_size, product_unit)
        
        if needed_base_unit == product_base_unit:
            # Calculate how close the package size is to needed amount
            ratio = product_base_qty / needed_base_qty
            
            # Ideal is 1.0 (exact match) or slightly more (1.0-1.5)
            if 0.5 <= ratio <= 1.5:
                # Best match
                score += 40 * (1 - abs(ratio - 1.0))
            elif 1.5 < ratio <= 3.0:
                # Still acceptable, but less ideal
                score += 30 * (1 - (ratio - 1.5) / 1.5)
            elif 0.1 <= ratio < 0.5:
                # Too small but might be useful
                score += 20 * (ratio / 0.5)
            else:
                # Much too large or too small
                score += 10
    else:
        # No unit info, neutral score
        score += 20
    
    # Rating score (30 points max)
    if rating:
        score += (rating / 5.0) * 30
    else:
        score += 15  # Neutral if no rating
    
    # Price score (30 points max) - Lower unit price is better
    # This is handled separately for comparison, but we give base points
    score += 15  # Base points for having a price
    
    return min(score, 100)

def calculate_amount_match_score(needed_qty: Optional[float], needed_unit: Optional[str],
                                product_size: Optional[float], product_unit: Optional[str]) -> float:
    """
    Calculate how well the product amount matches the needed amount.
    Returns a score from 0-100, where 100 is perfect match.
    """
    if not needed_qty or not needed_unit or not product_size or not product_unit:
        return 0.0
    
    # Convert to same base unit
    needed_base_qty, needed_base_unit = convert_to_base_unit(needed_qty, needed_unit)
    product_base_qty, product_base_unit = convert_to_base_unit(product_size, product_unit)
    
    if needed_base_unit != product_base_unit:
        return 0.0
    
    # Calculate ratio
    ratio = product_base_qty / needed_base_qty
    
    # Perfect match (within 5%)
    if 0.95 <= ratio <= 1.05:
        return 100.0
    # Very good match (within 20%)
    elif 0.8 <= ratio <= 1.2:
        return 90.0 - (abs(ratio - 1.0) * 200)  # 90-100 range
    # Good match (within 50%)
    elif 0.5 <= ratio <= 1.5:
        return 70.0 - (abs(ratio - 1.0) * 100)  # 50-70 range
    # Acceptable match (within 100%)
    elif 0.25 <= ratio <= 2.0:
        return 50.0 - (abs(ratio - 1.0) * 30)  # 20-50 range
    # Poor match
    else:
        return max(0.0, 20.0 - abs(ratio - 1.0) * 5)

### ---------- Naver Shopping API ----------
def search_naver_shopping(query: str, limit: int = 50, coupang_only: bool = False) -> List[Dict[str, Any]]:
    """
    Search Naver Shopping API for products.
    
    Steps:
    1. Call Naver Shopping Search API
    2. Optionally filter for Coupang products only (if coupang_only=True)
    3. Extract product info (title, price, link, image)
    4. Parse package sizes from product titles
    5. Calculate unit prices
    
    By default, returns products from ALL shopping malls (not just Coupang).
    This provides real product data with actual prices from various retailers.
    """
    if not NAVER_CLIENT_ID or not NAVER_CLIENT_SECRET:
        print("[WARN] Naver API credentials not configured. Skipping Naver search.")
        return []
    
    # Naver Shopping API endpoint
    url = "https://openapi.naver.com/v1/search/shop.json"
    
    params = {
        "query": query,
        "display": min(limit, 100),  # Naver allows up to 100 results
        "sort": "sim"  # Sort by relevance
    }
    
    headers = {
        "X-Naver-Client-Id": NAVER_CLIENT_ID,
        "X-Naver-Client-Secret": NAVER_CLIENT_SECRET
    }
    
    print(f"[INFO] Calling Naver Shopping API for query: '{query}' (limit: {limit})")
    
    try:
        response = requests.get(url, params=params, headers=headers, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        items = data.get("items", [])
        print(f"[INFO] Naver returned {len(items)} total products")
        
        # Process all products (or filter for Coupang if requested)
        products = []
        for item in items:
            mall_name = item.get("mallName", "")
            product_url = item.get("link", "")
            
            # Check if product is from Coupang (for filtering if needed)
            is_coupang = (
                "coupang" in mall_name.lower() or 
                "coupang.com" in product_url.lower() or
                "coupang.co.kr" in product_url.lower() or
                "쿠팡" in mall_name
            )
            
            # Skip non-Coupang products if coupang_only filter is enabled
            if coupang_only and not is_coupang:
                continue
            
            # Process product (regardless of mall)
            if True:  # Keep the indentation for the following code
                # Extract product ID from URL
                product_id = _extract_product_id_from_url(item.get("link", ""))
                
                # Get product URL
                # For Coupang products, convert to Partners affiliate link
                # For other products, use the original URL
                original_url = item.get("link", "")
                if is_coupang:
                    final_url = _convert_to_coupang_partners_link(original_url)
                else:
                    final_url = original_url
                
                # Parse package size from title
                title = item.get("title", "")
                package_size, package_unit = parse_product_size(title)
                
                # Extract price
                price_str = item.get("lprice", "0")
                try:
                    price = int(price_str)
                except (ValueError, TypeError):
                    price = 0
                
                # Skip products with no price
                if price == 0:
                    continue
                
                # Extract image
                image = item.get("image", "")
                
                # Calculate unit price if we have package size
                unit_price = None
                if package_size and package_unit and price > 0:
                    unit_price = price / package_size
                
                # Clean title (remove HTML tags)
                clean_title = title.replace("<b>", "").replace("</b>", "")
                
                products.append({
                    "productId": product_id,
                    "productName": clean_title,
                    "productPrice": price,
                    "productImage": image,
                    "productUrl": final_url,
                    "rating": None,  # Naver doesn't provide ratings
                    "reviewCount": None,  # Naver doesn't provide review counts
                    "packageSize": package_size,
                    "packageUnit": package_unit,
                    "unitPrice": unit_price,
                    "mallName": mall_name  # Include mall name for reference
                })
        
        print(f"[INFO] Returning {len(products)} products from Naver Shopping")
        if coupang_only:
            print(f"[INFO] (Coupang-only filter was enabled)")
        return products
        
    except requests.exceptions.RequestException as e:
        print(f"[ERROR] Naver Shopping API request failed: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"[ERROR] Response status: {e.response.status_code}")
            print(f"[ERROR] Response body: {e.response.text[:500]}")
        return []
    except Exception as e:
        print(f"[ERROR] Error processing Naver Shopping results: {e}")
        import traceback
        traceback.print_exc()
        return []

def _extract_product_id_from_url(url: str) -> str:
    """
    Extract product ID from URL.
    
    Handles various URL formats:
    - Coupang: https://www.coupang.com/vp/products/12345678
    - Naver Smartstore: https://smartstore.naver.com/main/products/12345678
    - Other URLs: uses hash as fallback
    """
    # Try to extract product ID from URL (works for Coupang, Naver, etc.)
    match = re.search(r'/products/(\d+)', url)
    if match:
        return match.group(1)
    
    # Fallback: use hash of URL
    return hashlib.md5(url.encode()).hexdigest()[:16]

def _convert_to_coupang_partners_link(original_url: str) -> str:
    """
    Convert a regular Coupang product URL to a Coupang Partners affiliate link.
    
    Format: https://www.coupang.com/vp/products/{productId}?itemId={itemId}&vendorItemId={vendorItemId}&sourceType=...
    
    Partners link format: https://www.coupang.com/vp/products/{productId}?itemId={itemId}&vendorItemId={vendorItemId}&sourceType=SDP_XXX&subId={subId}
    
    If we have Coupang Partners credentials, we can generate proper affiliate links.
    Otherwise, we return the original URL (which still works, just not tracked).
    """
    if not COUPANG_ACCESS_KEY or not COUPANG_PARTNER_SUBID:
        # No Partners credentials, return original URL
        return original_url
    
    # Parse the original URL
    parsed = urllib.parse.urlparse(original_url)
    query_params = urllib.parse.parse_qs(parsed.query)
    
    # Extract product ID from path
    product_id_match = re.search(r'/products/(\d+)', parsed.path)
    if not product_id_match:
        return original_url
    
    product_id = product_id_match.group(1)
    
    # Build Partners affiliate link
    # Note: This is a simplified version. Full implementation would require
    # the itemId and vendorItemId from the original URL or API response
    base_url = f"https://www.coupang.com/vp/products/{product_id}"
    
    # Add subId for tracking
    if COUPANG_PARTNER_SUBID:
        if query_params:
            query_params['subId'] = [COUPANG_PARTNER_SUBID]
        else:
            query_params = {'subId': [COUPANG_PARTNER_SUBID]}
    
    # Reconstruct URL
    new_query = urllib.parse.urlencode(query_params, doseq=True)
    affiliate_url = f"{base_url}?{new_query}" if new_query else base_url
    
    return affiliate_url

def search_coupang_products(query: str, limit: int = 10) -> List[Dict[str, Any]]:
    """
    Search for products on Coupang using multiple methods in order of preference:
    1. Coupang Partners API (if credentials available)
    2. Naver Shopping API proxy (if Naver credentials available)
    3. Mock data (if explicitly enabled)
    """
    
    # MOCK MODE: Only use if explicitly enabled
    use_mock = os.getenv("USE_MOCK_COUPANG_DATA", "false").lower() == "true"
    
    if use_mock:
        print(f"[MOCK MODE] Returning mock data for query: {query}")
        return _get_mock_coupang_products(query, limit)
    
    # METHOD 1: Try Coupang Partners API first (if credentials available)
    if COUPANG_ACCESS_KEY and COUPANG_SECRET_KEY:
        try:
            return _search_coupang_api(query, limit)
        except Exception as e:
            print(f"[WARN] Coupang API failed: {e}")
            print("[INFO] Falling back to Naver Shopping API proxy...")
            # Fall through to Naver proxy
    
    # METHOD 2: Use Naver Shopping API as proxy (if credentials available)
    if NAVER_CLIENT_ID and NAVER_CLIENT_SECRET:
        print("[INFO] Using Naver Shopping API as proxy for Coupang products...")
        naver_results = search_naver_shopping(query, limit)
        if naver_results:
            print(f"[INFO] Successfully retrieved {len(naver_results)} products via Naver proxy")
            return naver_results
        else:
            print("[WARN] Naver proxy returned no results")
    
    # METHOD 3: No API access available
    print("[ERROR] No product search method available!")
    print("[ERROR] Options:")
    print("[ERROR]   1. Set COUPANG_ACCESS_KEY and COUPANG_SECRET_KEY for Coupang API")
    print("[ERROR]   2. Set NAVER_CLIENT_ID and NAVER_CLIENT_SECRET for Naver proxy")
    print("[ERROR]   3. Set USE_MOCK_COUPANG_DATA=true for mock data")
    raise ValueError("No product search method available. Configure Coupang API, Naver API, or enable mock mode.")

def _search_coupang_api(query: str, limit: int = 10) -> List[Dict[str, Any]]:
    """Internal function to search Coupang Partners API"""
    
    # Coupang Partners Search API endpoint
    url = f"https://api-gateway.coupang.com/v2/providers/affiliate_open_api/apis/openapi/v1/products/search"
    
    params = {
        "keyword": query,
        "limit": limit,
        "subId": COUPANG_PARTNER_SUBID
    }
    
    # Generate HMAC signature
    request_url = f"{url}?{urllib.parse.urlencode(params)}"
    authorization = generate_coupang_hmac("GET", request_url, COUPANG_SECRET_KEY)
    
    headers = {
        "Authorization": authorization,
        "Content-Type": "application/json"
    }
    
    print(f"[INFO] Calling Coupang API for query: '{query}' (limit: {limit})")
    print(f"[INFO] Request URL: {request_url}")
    
    response = requests.get(request_url, headers=headers, timeout=10)
    print(f"[INFO] API Response Status: {response.status_code}")
    
    response.raise_for_status()
    data = response.json()
    
    # Debug: Log the raw API response
    print(f"[DEBUG] Raw Coupang API Response:")
    print(f"[DEBUG] {json.dumps(data, indent=2, ensure_ascii=False)[:1000]}...")  # First 1000 chars
    
    # Parse response based on Coupang API structure
    products = []
    if "data" in data:
        if isinstance(data["data"], list):
            products = data["data"]
        elif isinstance(data["data"], dict) and "products" in data["data"]:
            products = data["data"]["products"]
        elif isinstance(data["data"], dict) and "product" in data["data"]:
            products = [data["data"]["product"]]
    elif isinstance(data, list):
        products = data
    elif "products" in data:
        products = data["products"] if isinstance(data["products"], list) else []
    elif "product" in data:
        products = [data["product"]] if isinstance(data["product"], dict) else []
    
    print(f"[INFO] Successfully parsed {len(products)} products from Coupang API")
    
    # Normalize product data structure
    normalized_products = []
    for idx, product in enumerate(products):
        # Coupang API may return different field names
        normalized = {
            "productId": str(product.get("productId") or product.get("id") or product.get("product_id") or f"api_{idx+1}"),
            "productName": str(product.get("productName") or product.get("name") or product.get("product_name") or query),
            "productPrice": int(product.get("productPrice") or product.get("price") or product.get("product_price") or 0),
            "productImage": str(product.get("productImage") or product.get("imageUrl") or product.get("image_url") or product.get("image") or ""),
            "productUrl": str(product.get("productUrl") or product.get("url") or product.get("product_url") or product.get("link") or ""),
            "rating": float(product.get("rating") or product.get("averageRating") or product.get("average_rating") or 0) if product.get("rating") or product.get("averageRating") or product.get("average_rating") else None,
            "reviewCount": int(product.get("reviewCount") or product.get("reviews") or product.get("review_count") or 0) if product.get("reviewCount") or product.get("reviews") or product.get("review_count") else None
        }
        normalized_products.append(normalized)
    
    if normalized_products:
        print(f"[INFO] Returning {len(normalized_products)} normalized products")
        # Debug: Log first product
        if normalized_products:
            print(f"[DEBUG] First product sample: {json.dumps(normalized_products[0], indent=2, ensure_ascii=False)}")
    
    return normalized_products if normalized_products else []

def _get_mock_coupang_products(query: str, limit: int = 10) -> List[Dict[str, Any]]:
    """Generate mock product data for testing"""
    import random
    
    # Common package sizes for Korean groceries
    package_sizes = [
        (500, "g"), (1000, "g"), (300, "g"), (200, "g"),
        (1, "kg"), (2, "kg"), (500, "ml"), (1000, "ml"),
        (1, "L"), (2, "L")
    ]
    
    mock_products = []
    for i in range(min(limit, 50)):  # Generate up to 50 mock products
        size, unit = random.choice(package_sizes)
        price = random.randint(2000, 8000)
        rating = round(random.uniform(3.5, 5.0), 1)
        reviews = random.randint(50, 1000)
        
        # Format product name with size
        if unit in ["g", "kg"]:
            if unit == "kg":
                display_name = f"{query} {size}kg"
            else:
                display_name = f"{query} {size}g"
        else:
            if unit == "L":
                display_name = f"{query} {size}L"
            else:
                display_name = f"{query} {size}ml"
        
        # Create mock product ID (simulate real Coupang product ID format)
        # Real Coupang product IDs are numeric, so we'll use a numeric format for mock
        mock_product_id = f"{1000000 + (i+1) * 1000 + (hash(query) % 1000)}"
        # Mock products don't have real URLs (no API access)
        # Set empty URL so frontend knows these are not clickable
        mock_url = ""
        
        mock_products.append({
            "productId": mock_product_id,
            "productName": display_name,
            "productPrice": price,
            "productImage": "https://via.placeholder.com/200?text=" + query.replace(" ", "+"),
            "productUrl": mock_url,
            "rating": rating,
            "reviewCount": reviews
        })
    
    return mock_products

### ---------- Helpers ----------
def url_hash(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()[:16]

def extract_with_ytdlp(url: str) -> Dict[str, Any]:
    print(f"     [yt-dlp] Extracting info from URL (this may take 10-20 seconds)...")
    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "writesubtitles": True,
        "writeautomaticsub": True,
        "writedescription": True,  # Extract video description
        "forcejson": True,
        "extract_flat": False,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)
    print(f"     [yt-dlp] ✓ Info extraction complete")
    return info

def download_audio(url: str, outdir: str) -> str:
    print(f"     [yt-dlp] Downloading audio (this may take 10-30 seconds)...")
    target = os.path.join(outdir, "audio.m4a")
    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": os.path.join(outdir, "a.%(ext)s"),
        "quiet": True,
        "postprocessors": [{"key": "FFmpegExtractAudio", "preferredcodec": "m4a"}],
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])
    print(f"     [yt-dlp] ✓ Audio download complete")
    # Find resulting file
    for fname in os.listdir(outdir):
        if fname.endswith(".m4a"):
            return os.path.join(outdir, fname)
    raise RuntimeError("Audio download failed")

def get_youtube_transcript(info: Dict[str, Any]) -> Optional[str]:
    # If yt-dlp found subtitles, try to fetch the best language track
    print(f"     [Captions] Checking for available captions...")
    subs = info.get("subtitles") or info.get("automatic_captions") or {}
    if not subs:
        print(f"     [Captions] No captions found")
        return None
    print(f"     [Captions] Found captions in {len(subs)} language(s), fetching...")
    # prefer original language > en
    for lang_pref in [info.get("language"), "en", "ko"]:
        for lang, tracks in subs.items():
            if not tracks: 
                continue
            if lang_pref and not lang.startswith(lang_pref):
                continue
            # pick first .vtt track
            for tr in tracks:
                if tr.get("ext") == "vtt":
                    try:
                        import requests
                        r = requests.get(tr["url"], timeout=10)
                        if r.ok:
                            print(f"     [Captions] ✓ Successfully fetched captions")
                            return vtt_to_text(r.text)
                    except Exception:
                        pass
    print(f"     [Captions] Failed to fetch captions")
    return None

def vtt_to_text(vtt: str) -> str:
    lines = []
    for line in vtt.splitlines():
        if re.match(r"^\d{2}:\d{2}:\d{2}\.\d{3} -->", line): 
            continue
        if line.strip() and not line.startswith("WEBVTT"):
            lines.append(line.strip())
    return " ".join(lines)

def transcribe(audio_path: str, prefer_lang: Optional[str] = "ko") -> str:
    print(f"     [Whisper] Starting transcription (this may take 20-60 seconds)...")
    model = get_whisper()
    segments, info = model.transcribe(audio_path, language=prefer_lang, vad_filter=True)
    result = " ".join(seg.text.strip() for seg in segments if seg.text)
    print(f"     [Whisper] ✓ Transcription complete")
    return result

def _find_ffmpeg() -> str:
    """Find FFmpeg executable in common locations."""
    # Try to find ffmpeg in PATH first
    ffmpeg_path = shutil.which("ffmpeg")
    if ffmpeg_path:
        return ffmpeg_path
    
    # Check common installation locations
    common_paths = [
        "/usr/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/ffmpeg",  # macOS Homebrew
        "/bin/ffmpeg",
        "/app/.apt/usr/bin/ffmpeg",  # Railway/Heroku buildpack location
    ]
    
    for path in common_paths:
        if os.path.exists(path) and os.access(path, os.X_OK):
            return path
    
    # If not found, raise a helpful error
    raise RuntimeError(
        "FFmpeg not found. Please ensure FFmpeg is installed and available in PATH. "
        "On Railway, you may need to add FFmpeg via a buildpack or Dockerfile."
    )

def sample_frames_to_tmp(video_url: str, outdir: str, fps: float = 0.3) -> List[str]:
    # yt-dlp can also give us a direct URL; but easiest path:
    # Reuse the downloaded audio's dir; also fetch a light mp4
    print(f"     [Video] Downloading video for OCR (this may take 10-30 seconds)...")
    mp4_path = os.path.join(outdir, "video.mp4")
    ydl_opts = {
        "format": "mp4[height<=480]/best",
        "outtmpl": mp4_path,
        "quiet": True,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([video_url])
    print(f"     [Video] ✓ Video downloaded, extracting frames...")
    img_dir = os.path.join(outdir, "frames")
    os.makedirs(img_dir, exist_ok=True)
    # Extract frames using subprocess (system ffmpeg)
    output_pattern = os.path.join(img_dir, "frame_%05d.jpg")
    
    # Find FFmpeg executable
    ffmpeg_path = _find_ffmpeg()
    print(f"     [Video] Using FFmpeg at: {ffmpeg_path}")
    
    cmd = [
        ffmpeg_path,
        "-i", mp4_path,
        "-vf", f"fps={fps}",
        "-vsync", "0",
        "-loglevel", "error",
        output_pattern
    ]
    subprocess.run(cmd, check=True)
    frame_list = [os.path.join(img_dir, f) for f in sorted(os.listdir(img_dir)) if f.endswith(".jpg")]
    print(f"     [Video] ✓ Extracted {len(frame_list)} frames")
    return frame_list

def ocr_frames(paths: List[str]) -> str:
    try:
        print(f"     [OCR] Initializing OCR reader...")
        import easyocr
        reader = easyocr.Reader(["en","ko"])  # add more if needed
        print(f"     [OCR] Processing {len(paths)} frames (this may take 10-30 seconds)...")
        texts = []
        for i, p in enumerate(paths):
            if i % 5 == 0:  # Log every 5 frames
                print(f"     [OCR] Processing frame {i+1}/{len(paths)}...")
            result = reader.readtext(p, detail=0, paragraph=True)
            if result: texts.append(" ".join(result))
        print(f"     [OCR] ✓ OCR processing complete")
        return " ".join(texts)
    except Exception as e:
        print(f"     [OCR] Warning: OCR failed - {e}")
        return ""

def normalize_units(text: str) -> str:
    # very light normalization example
    return (text
            .replace("½","0.5").replace("¼","0.25").replace("¾","0.75")
            .replace("tablespoons","tbsp").replace("tablespoon","tbsp")
            .replace("teaspoons","tsp").replace("teaspoon","tsp"))

### ---------- LLM: structure the recipe ----------
# Note: prefer_lang should always be "ko" since the app primarily targets Koreans.
# Language settings in the UI only control the app interface, not recipe parsing.
def call_llm_to_structure(transcript_text: str, ocr_text: str, title: str, description: str = "", prefer_lang: str = "ko") -> Dict[str, Any]:
    content = normalize_units(f"{title}\n\nDESCRIPTION:\n{description}\n\nTRANSCRIPT:\n{transcript_text}\n\nON-SCREEN TEXT:\n{ocr_text}")
    
    # Language-specific instructions
    if prefer_lang == "ko":
        lang_instruction = """
LANGUAGE REQUIREMENT:
- ALL recipe content (name, ingredients, steps, equipment, notes) MUST be in KOREAN (한국어)
- Use Korean ingredient names (e.g., "돼지고기" not "pork", "김치" not "kimchi")
- Use METRIC UNITS ONLY:
  * For solids: grams (g) or kilograms (kg)
  * For liquids: milliliters (ml) or liters (l)
  * For countable items: use "개" (pieces), "컵" (cups) when appropriate
  * DO NOT use "큰술" (tablespoon) or "작은술" (teaspoon)
  * Convert tablespoons and teaspoons to ml (1 큰술 = 15ml, 1 작은술 = 5ml)
- Steps and instructions must be in natural Korean
"""
    else:
        lang_instruction = """
LANGUAGE REQUIREMENT:
- ALL recipe content should be in English
- Use METRIC UNITS ONLY:
  * For solids: grams (g) or kilograms (kg)
  * For liquids: milliliters (ml) or liters (l)
  * For countable items: pieces, cups when appropriate
  * DO NOT use tablespoons (tbsp) or teaspoons (tsp)
  * Convert tablespoons and teaspoons to ml (1 tbsp = 15ml, 1 tsp = 5ml)
"""
    
    system = f"""You extract COOKING RECIPES from noisy transcripts with MAXIMUM PRECISION.

{lang_instruction}

CRITICAL REQUIREMENTS:
1. EVERY ingredient MUST have a specific quantity (qty) - NEVER use null
2. EVERY ingredient MUST have a unit - NEVER use null
3. If exact amounts aren't stated, make REASONABLE estimates based on:
   - Standard recipe proportions
   - Servings mentioned
   - Visual cues from on-screen text
   - Context from the cooking process
4. Be as precise as possible with measurements
5. Extract ALL cooking tips, tricks, and important notes mentioned in the video
6. Make instructions DETAILED and SPECIFIC - include exact techniques, timing, and what to look for

Return STRICT JSON with keys: recipe {{name, servings, ingredients[], steps[], equipment[], notes[], nutrition{{}} }}, categories {{}}, tags [], nutrition_rating string.

Ingredient fields (ALL REQUIRED):
- qty: number (NEVER null, estimate if needed)
- unit: string (NEVER null, use: g, kg, ml, l, 개, 컵, piece, cup, clove, etc.)
  * For solids use g or kg
  * For liquids use ml or l
  * Convert tablespoons/teaspoons to ml (1 tablespoon = 15ml, 1 teaspoon = 5ml)
- item: string (specific ingredient name in the target language)
- notes: string or null (preparation notes like "chopped", "minced" or "다진", "썬" in Korean)
- category: string (REQUIRED - one of: "main", "sub", or "sauce_msg")
  * "main": Primary protein or main ingredient (e.g., "돼지고기", "닭고기", "두부", "김치")
  * "sub": Supporting vegetables, aromatics, or secondary ingredients (e.g., "양파", "마늘", "당근", "버섯")
  * "sauce_msg": Seasonings, sauces, condiments, MSG, or flavor enhancers (e.g., "고추장", "된장", "간장", "소금", "후추", "MSG")

Step fields:
- order: int
- instruction: string (ACTUAL RECIPE INSTRUCTION ONLY - no tips, tricks, or advice)
  * Include exact cooking techniques (e.g., "중불에서" "slowly stir")
  * Mention visual/texture cues (e.g., "when edges turn golden", "until sauce thickens")
  * Specify exact timing when mentioned
  * DO NOT include tips, tricks, warnings, or advice in the instruction field
- tip: string or null (COOKING TIP for this specific step - separate from instruction)
  * Extract any tips, tricks, warnings, or advice mentioned specifically for this step
  * Examples: "감자를 너무 얇게 썰면 식감이 떨어지니 적당한 두께를 유지해주세요"
  * If no tip is mentioned for this step, use null
- step_ingredients: string[] or null (List of ingredient item names used in THIS step)
  * Extract which specific ingredients from the main ingredients list are used in this step
  * Use the exact item names from the ingredients list (e.g., ["돼지고기", "김치"])
  * If no specific ingredients are mentioned for this step, use null
- est_minutes: int or null
- tools: string[] or null (in the target language)

Nutrition fields (calculate based on ingredients):
- calories_per_serving: number
- protein_g: number
- fat_g: number
- carbs_g: number
- sodium_mg: number

Equipment: string[] (all tools/equipment needed in the target language)
Notes: string[] (IMPORTANT - Extract ALL cooking tips, tricks, warnings, and advice mentioned)
  * Include ingredient substitutions
  * Storage and reheating instructions
  * Cooking tips for better results (e.g., "감자를 너무 얇게 썰면 식감이 떨어지니 적당한 두께를 유지해주세요")
  * Common mistakes to avoid
  * Serving suggestions
  * Any other helpful information from the video

Estimate missing servings reasonably from context (default to 4 if unclear).

Categories fields (REQUIRED - select ALL applicable tags):
- meat_type: string[] - Select from: ["소고기", "돼지고기", "닭고기", "양고기"] (can be empty if no meat)
- cuisine_type: string[] - Select from: ["양식", "한식", "일식", "중식"] (at least one required)
- menu_type: string[] - Select from: ["면", "밥", "국", "찌개", "디저트", "빵"] (at least one required)
- meal_time: string[] - Select from: ["아침", "점심", "저녁"] (at least one required, can be multiple)
- ingredient_type: string[] - Select from: ["해산물", "채소", "육류"] (can be empty or multiple)
- time_category: string[] - Select from: ["10분 이내", "30분 이내", "1시간 이내", "1시간 이상"] (at least one required based on total cooking time)

Analyze the recipe name, ingredients, and cooking method to select the most appropriate tags. For example:
- "돼지고기 김치찌개" → meat_type: ["돼지고기"], cuisine_type: ["한식"], menu_type: ["찌개"], meal_time: ["점심", "저녁"], ingredient_type: ["육류", "채소"], time_category: ["30분 이내"] or ["1시간 이내"]

Recipe tags (REQUIRED - select ALL applicable tags from this list):
- Available tags: ["단백한", "자극적인", "단짠단짠", "매콤한", "담백한", "고소한", "얼큰한", "고단백", "건강식", "채소가득", "바삭한", "쫄깃한", "전통", "간편식", "비건", "베지터리언"]
- Select 2-5 tags that best describe the recipe's taste, texture, and characteristics
- IMPORTANT: Only include tags that actually apply. Do NOT include empty strings or null values in the tags array
- Store in: tags: string[] (must be an array of non-empty strings only)

Nutrition rating (REQUIRED):
- Rate the recipe's overall nutrition quality on a scale of A, B, or C
- Be GENEROUS with ratings - most recipes should get A or B
- Consider: ingredient quality, balance of nutrients, use of fresh ingredients, cooking methods
- Only give C if the recipe is clearly unhealthy (excessive oil, processed foods, very high calories without nutritional value)
- Store in: nutrition_rating: string (one of "A", "B", or "C")"""
    
    user = f"""Extract a complete, precise recipe from this content. 
    
REQUIREMENTS:
- EVERY ingredient must have qty and unit
- Make instructions VERY DETAILED with specific techniques, timing, and visual cues
- CRITICAL: Separate actual recipe instructions from tips
  * instruction field: ONLY the actual cooking step (what to do)
  * tip field: Any tips, tricks, warnings, or advice for that specific step (if mentioned)
- For each step, identify which ingredients from the main ingredients list are used in that step
  * step_ingredients: List of ingredient item names used in that step
- Extract general cooking tips, tricks, and advice (not step-specific) into the notes array
- Include any warnings or common mistakes to avoid

Output JSON only."""
    
    # Example using OpenAI; replace as needed
    print(f"     [LLM] Sending request to OpenAI (model: {os.getenv('RECIPE_MODEL','gpt-4o-mini')})...")
    print(f"     [LLM] Input size: transcript={len(transcript_text)} chars, ocr={len(ocr_text)} chars")
    from openai import OpenAI
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    resp = client.chat.completions.create(
        model=os.getenv("RECIPE_MODEL","gpt-4o-mini"),
        messages=[
            {"role":"system","content":system},
            {"role":"user","content":user+"\n\n"+content[:16000]} # keep within token limits
        ],
        temperature=0.2
    )
    print(f"     [LLM] ✓ Received response from OpenAI")
    text = resp.choices[0].message.content.strip()
    print(f"     [LLM] Parsing JSON response...")
    # Ensure JSON:
    start = text.find("{")
    end = text.rfind("}")
    js = json.loads(text[start:end+1])
    print(f"     [LLM] ✓ JSON parsing complete")
    return js

### ---------- Nutrition ----------
# Mini table (extend or swap with external API)
NUTRITION_TABLE = {
    "pork belly": {"kcal": 518, "protein_g": 9.3, "fat_g": 53.0, "carb_g": 0.0, "sodium_mg": 73},  # per 100g, rough
    "gochujang": {"kcal": 208, "protein_g": 3.7, "fat_g": 3.5, "carb_g": 43.0, "sodium_mg": 3000}, # per 100g
    "tofu": {"kcal": 76, "protein_g": 8.0, "fat_g": 4.8, "carb_g": 1.9, "sodium_mg": 7},
}

def match_food(name: str) -> str:
    choices = list(NUTRITION_TABLE.keys())
    best, score, _ = process.extractOne(name.lower(), choices, scorer=fuzz.WRatio)
    return best if score >= 70 else ""

UNIT_TO_G = {"g": 1, "kg": 1000}
UNIT_TO_ML = {"ml": 1, "l": 1000}

def estimate_nutrition(ingredients: List[Dict[str, Any]], servings: int, llm_nutrition: Optional[Dict[str, float]] = None) -> Nutrition:
    """Estimate nutrition using lookup table as fallback, prioritize LLM calculation"""
    total = {"kcal":0.0,"protein_g":0.0,"fat_g":0.0,"carb_g":0.0,"sodium_mg":0.0}
    assumptions = []
    
    # Try to use LLM nutrition estimate first
    llm_estimate = None
    if llm_nutrition:
        try:
            llm_estimate = NutritionLLM(
                calories_per_serving=llm_nutrition.get("calories_per_serving", 0),
                protein_g=llm_nutrition.get("protein_g", 0),
                fat_g=llm_nutrition.get("fat_g", 0),
                carbs_g=llm_nutrition.get("carbs_g", 0),
                sodium_mg=llm_nutrition.get("sodium_mg", 0)
            )
            assumptions.append("Nutrition calculated by LLM based on all ingredients and quantities")
        except Exception:
            pass
    
    # Fallback: use lookup table for known ingredients
    for ing in ingredients:
        item = ing.get("item","")
        qty = ing.get("qty")
        unit = (ing.get("unit") or "").lower()
        canonical = match_food(item)
        if not canonical or canonical not in NUTRITION_TABLE or not qty:
            continue
        basis = NUTRITION_TABLE[canonical]
        grams = None
        if unit in UNIT_TO_G:
            grams = qty*UNIT_TO_G[unit]
        elif unit in UNIT_TO_ML:
            # crude: 1ml ~ 1g if water-like; for sauces it's acceptable as a first pass
            grams = qty*UNIT_TO_ML[unit]
        elif unit in ["tbsp","tsp"]:
            # crude densities (adjust per item)
            grams = qty*(15 if unit=="tbsp" else 5)
        if grams is None:
            continue
        factor = grams/100.0
        for k in total:
            total[k] += basis[k]*factor
        assumptions.append(f"{canonical} {int(grams)}g at table values per 100g")
    
    if not servings or servings <= 0:
        servings = 1
    per_serving = {k: round(v/servings, 2) for k,v in total.items()}
    
    if not assumptions:
        assumptions = ["Nutrition primarily from LLM estimate" if llm_estimate else "Limited nutrition data available"]
    
    return Nutrition(
        per_serving=per_serving, 
        assumptions=assumptions,
        llm_estimate=llm_estimate
    )

### ---------- Progress Streaming Helper ----------
async def generate_progress_events(url: str, prefer_lang: str):
    """Generator that yields SSE events for each processing stage"""
    try:
        print(f"\n{'='*60}")
        print(f"[PARSE START] URL: {url}")
        print(f"{'='*60}\n")
        
        h = url_hash(url)
        with tempfile.TemporaryDirectory(prefix=f"vr_{h}_") as tmp:
            # Stage 1: Video Analysis
            print(f"[STAGE 1/7] Starting video analysis...")
            yield f"data: {json.dumps({'stage': '영상 분석중', 'progress': 0})}\n\n"
            await asyncio.sleep(0.1)  # Small delay for UI update
            
            print(f"  → Extracting video info with yt-dlp...")
            info = extract_with_ytdlp(url)
            title = info.get("title") or "Untitled"
            duration = int(info.get("duration") or 0)
            platform = info.get("extractor_key","unknown").lower()
            description = info.get("description") or ""
            thumbnail = info.get("thumbnail") or ""
            uploader = info.get("uploader") or ""
            channel = info.get("channel") or ""
            uploader_id = info.get("uploader_id") or ""
            print(f"  ✓ Video info extracted: {title} ({duration}s) - Platform: {platform}")
            
            # Get transcript
            print(f"  → Getting transcript...")
            transcript = get_youtube_transcript(info) if platform == "youtube" else None
            used_captions = transcript is not None
            if not transcript:
                print(f"  → No captions available, downloading audio for transcription...")
                audio_path = download_audio(url, tmp)
                print(f"  → Audio downloaded, transcribing with Whisper...")
                transcript = transcribe(audio_path, prefer_lang)
                print(f"  ✓ Transcription complete ({len(transcript)} chars)")
            else:
                print(f"  ✓ Captions extracted ({len(transcript)} chars)")
            
            # OCR from frames
            print(f"  → Sampling frames for OCR...")
            frames = sample_frames_to_tmp(url, tmp, fps=0.3)
            print(f"  → Running OCR on {len(frames)} frames...")
            ocr_text = ocr_frames(frames)
            used_ocr = bool(ocr_text.strip())
            print(f"  ✓ OCR complete ({'text found' if used_ocr else 'no text'}, {len(ocr_text)} chars)")
            print(f"[STAGE 1/7] ✓ Video analysis complete\n")
            
            # Stage 2: Recipe Analysis (this is the slow LLM call)
            print(f"[STAGE 2/7] Starting LLM recipe analysis (this may take 30-60 seconds)...")
            yield f"data: {json.dumps({'stage': '레시피 분석중', 'progress': 20})}\n\n"
            await asyncio.sleep(0.1)
            
            # Call LLM to get structured data (this is the slowest part)
            print(f"  → Calling LLM with transcript ({len(transcript)} chars) and OCR ({len(ocr_text)} chars)...")
            structured = call_llm_to_structure(transcript, ocr_text, title, description, prefer_lang or "ko")
            recipe = structured.get("recipe") or structured
            print(f"  ✓ LLM analysis complete")
            print(f"    - Recipe name: {recipe.get('name', 'N/A')}")
            print(f"    - Ingredients: {len(recipe.get('ingredients', []))}")
            print(f"    - Steps: {len(recipe.get('steps', []))}")
            print(f"[STAGE 2/7] ✓ Recipe analysis complete\n")
            
            # Stage 3: Ingredient Analysis (fast - just extraction)
            print(f"[STAGE 3/7] Extracting ingredients...")
            yield f"data: {json.dumps({'stage': '재료 분석중', 'progress': 60})}\n\n"
            await asyncio.sleep(0.1)
            
            # Process ingredients (already done by LLM, just extracting here)
            ingredients = recipe.get("ingredients", [])
            print(f"  ✓ Extracted {len(ingredients)} ingredients")
            print(f"[STAGE 3/7] ✓ Ingredient analysis complete\n")
            
            # Stage 4: Category Analysis (fast - just extraction)
            print(f"[STAGE 4/7] Analyzing categories...")
            yield f"data: {json.dumps({'stage': '카테고리 분석중', 'progress': 70})}\n\n"
            await asyncio.sleep(0.1)
            
            categories = structured.get("categories") or {}
            categories = {
                "meat_type": categories.get("meat_type", []),
                "cuisine_type": categories.get("cuisine_type", []),
                "menu_type": categories.get("menu_type", []),
                "meal_time": categories.get("meal_time", []),
                "ingredient_type": categories.get("ingredient_type", []),
                "time_category": categories.get("time_category", []),
            }
            print(f"  ✓ Categories extracted: {sum(len(v) for v in categories.values())} total tags")
            print(f"[STAGE 4/7] ✓ Category analysis complete\n")
            
            # Stage 5: Tag Analysis (fast - just extraction)
            print(f"[STAGE 5/7] Extracting tags...")
            yield f"data: {json.dumps({'stage': '태그 분석중', 'progress': 80})}\n\n"
            await asyncio.sleep(0.1)
            
            tags_raw = structured.get("tags") or []
            tags = [tag for tag in tags_raw if tag and isinstance(tag, str) and tag.strip()]
            nutrition_rating = structured.get("nutrition_rating") or "A"
            print(f"  ✓ Extracted {len(tags)} tags, nutrition rating: {nutrition_rating}")
            print(f"[STAGE 5/7] ✓ Tag analysis complete\n")
            
            # Stage 6: Nutrition Analysis (fast - just calculation)
            print(f"[STAGE 6/7] Calculating nutrition...")
            yield f"data: {json.dumps({'stage': '영양 분석중', 'progress': 90})}\n\n"
            await asyncio.sleep(0.1)
            
            servings = recipe.get("servings") or 1
            llm_nutrition = structured.get("nutrition") or recipe.get("nutrition")
            nutrition = estimate_nutrition(ingredients, servings, llm_nutrition)
            print(f"  ✓ Nutrition calculated for {servings} serving(s)")
            print(f"[STAGE 6/7] ✓ Nutrition analysis complete\n")
            
            # Stage 7: Finalizing (creating response)
            print(f"[STAGE 7/7] Finalizing response...")
            yield f"data: {json.dumps({'stage': '완료', 'progress': 95})}\n\n"
            await asyncio.sleep(0.1)
            
            # Final result - wrap in try-except to catch any model validation errors
            try:
                print(f"  → Building response object...")
                # Ensure recipe has required fields with defaults
                recipe_clean = {
                    "name": recipe.get("name"),
                    "servings": recipe.get("servings") or 1,
                    "ingredients": recipe.get("ingredients", []),
                    "steps": recipe.get("steps", []),
                    "equipment": recipe.get("equipment"),
                    "notes": recipe.get("notes"),
                }
                
                # Create response object
                result = ParseResponse(
                    source={
                        "url": url,
                        "platform": platform,
                        "title": title,
                        "duration_sec": duration,
                        "thumbnail": thumbnail,
                        "uploader": uploader,
                        "channel": channel,
                        "uploader_id": uploader_id,
                        "categories": categories,
                        "tags": tags,
                        "nutrition_rating": nutrition_rating,
                    },
                    recipe=Recipe(**recipe_clean),
                    nutrition=nutrition,
                    debug={"used_captions": used_captions, "used_asr": not used_captions, "used_ocr": used_ocr, "has_description": bool(description)}
                )
                print(f"  ✓ Response object created")
                
                # Progress update before serialization
                yield f"data: {json.dumps({'stage': '완료', 'progress': 98})}\n\n"
                await asyncio.sleep(0.05)
                
                # Use asyncio to run model_dump in thread pool to avoid blocking the event loop
                print(f"  → Serializing response...")
                loop = asyncio.get_event_loop()
                with concurrent.futures.ThreadPoolExecutor() as pool:
                    result_dict = await loop.run_in_executor(pool, result.model_dump)
                print(f"  ✓ Serialization complete")
                
                # Send final result
                print(f"[STAGE 7/7] ✓ Finalization complete\n")
                print(f"{'='*60}")
                print(f"[PARSE COMPLETE] Successfully parsed: {title}")
                print(f"{'='*60}\n")
                yield f"data: {json.dumps({'stage': 'result', 'progress': 100, 'data': result_dict})}\n\n"
            except Exception as model_error:
                # If model creation fails, send error with details
                error_details = traceback.format_exc()
                print(f"\n{'!'*60}")
                print(f"[ERROR] Failed to create ParseResponse")
                print(f"{'!'*60}")
                print(f"{error_details}")
                print(f"{'!'*60}\n")
                error_msg = f"Error creating response model: {str(model_error)}"
                yield f"data: {json.dumps({'stage': 'error', 'error': error_msg})}\n\n"
            
    except Exception as e:
        error_msg = str(e)
        error_details = traceback.format_exc()
        print(f"\n{'!'*60}")
        print(f"[ERROR] Parse failed")
        print(f"{'!'*60}")
        print(f"{error_details}")
        print(f"{'!'*60}\n")
        yield f"data: {json.dumps({'stage': 'error', 'error': error_msg})}\n\n"

@app.post("/parse_recipe_stream")
async def parse_recipe_stream(req: ParseRequest):
    """Stream parsing progress with SSE"""
    print(f"\n[API] /parse_recipe_stream endpoint called")
    print(f"[API] URL: {req.url}")
    print(f"[API] Language: {req.prefer_lang or 'ko'}")
    
    async def event_generator():
        async for event in generate_progress_events(str(req.url), req.prefer_lang or "ko"):
            yield event
        print(f"[API] ✓ Stream generation complete, closing connection")
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
            "Access-Control-Allow-Origin": "*",
        }
    )

### ---------- Endpoint ----------
@app.post("/parse_recipe", response_model=ParseResponse)
def parse_recipe(req: ParseRequest):
    h = url_hash(str(req.url))
    with tempfile.TemporaryDirectory(prefix=f"vr_{h}_") as tmp:
        info = extract_with_ytdlp(str(req.url))
        title = info.get("title") or "Untitled"
        duration = int(info.get("duration") or 0)
        platform = info.get("extractor_key","unknown").lower()
        description = info.get("description") or ""  # Extract video description
        thumbnail = info.get("thumbnail") or ""  # Extract video thumbnail URL

        # Captions first; ASR fallback
        transcript = get_youtube_transcript(info) if platform == "youtube" else None
        used_captions = transcript is not None
        if not transcript:
            audio_path = download_audio(str(req.url), tmp)
            transcript = transcribe(audio_path, req.prefer_lang)

        # OCR from frames
        frames = sample_frames_to_tmp(str(req.url), tmp, fps=0.3)
        ocr_text = ocr_frames(frames)
        used_ocr = bool(ocr_text.strip())

        # LLM to structure - now includes description
        structured = call_llm_to_structure(transcript, ocr_text, title, description, req.prefer_lang or "ko")
        recipe = structured.get("recipe") or structured  # tolerate models that skip top-level key

        # Nutrition - extract LLM's nutrition estimate if provided
        servings = recipe.get("servings") or 1
        llm_nutrition = structured.get("nutrition") or recipe.get("nutrition")
        nutrition = estimate_nutrition(recipe.get("ingredients", []), servings, llm_nutrition)

        # Extract categories from structured response
        categories = structured.get("categories") or {}
        # Ensure all category fields exist with defaults
        categories = {
            "meat_type": categories.get("meat_type", []),
            "cuisine_type": categories.get("cuisine_type", []),
            "menu_type": categories.get("menu_type", []),
            "meal_time": categories.get("meal_time", []),
            "ingredient_type": categories.get("ingredient_type", []),
            "time_category": categories.get("time_category", []),
        }

        # Extract tags and nutrition rating from structured response
        tags_raw = structured.get("tags") or []
        # Filter out empty strings, null values, and whitespace-only strings
        tags = [tag for tag in tags_raw if tag and isinstance(tag, str) and tag.strip()]
        nutrition_rating = structured.get("nutrition_rating") or "A"  # Default to A if not provided

        # Extract creator/username information from YouTube video
        uploader = info.get("uploader") or ""
        channel = info.get("channel") or ""
        uploader_id = info.get("uploader_id") or ""
        
        return ParseResponse(
            source={
                "url": str(req.url), 
                "platform": platform, 
                "title": title, 
                "duration_sec": duration, 
                "thumbnail": thumbnail,
                "uploader": uploader,
                "channel": channel,
                "uploader_id": uploader_id,
                "categories": categories,
                "tags": tags,
                "nutrition_rating": nutrition_rating,
            },
            recipe=Recipe(**recipe),
            nutrition=nutrition,
            debug={"used_captions": used_captions, "used_asr": not used_captions, "used_ocr": used_ocr, "has_description": bool(description)}
        )

### ---------- Product Recommendation Endpoint ----------
@app.post("/recommend_products", response_model=ProductRecommendationResponse)
def recommend_products(req: ProductSearchRequest):
    """
    Search Coupang for products matching an ingredient and recommend best options
    based on unit match, price per unit, and ratings.
    """
    # Search Coupang for products
    raw_products = search_coupang_products(req.ingredient_name, req.limit or 10)
    
    if not raw_products:
        return ProductRecommendationResponse(
            ingredient=req.ingredient_name,
            needed_qty=req.needed_qty,
            needed_unit=req.needed_unit,
            best_match=None,
            budget_option=None,
            all_products=[]
        )
    
    # Parse and enrich products with size/unit information
    products: List[CoupangProduct] = []
    
    for raw_product in raw_products:
        # Extract product info from Coupang API response
        # The exact field names may vary based on Coupang's API structure
        product_id = str(raw_product.get("productId", raw_product.get("id", "")))
        product_name = raw_product.get("productName", raw_product.get("name", ""))
        product_price = int(raw_product.get("productPrice", raw_product.get("price", 0)))
        product_image = raw_product.get("productImage", raw_product.get("imageUrl", ""))
        product_url = raw_product.get("productUrl", raw_product.get("url", ""))
        rating = raw_product.get("rating")
        if rating:
            rating = float(rating)
        review_count = raw_product.get("reviewCount", raw_product.get("reviews"))
        if review_count:
            review_count = int(review_count)
        
        # Use raw product URL from API
        # Accept URLs from all shopping malls (Coupang, Naver, etc.)
        final_product_url = product_url if product_url and product_url.startswith('http') else ""
        
        # Parse size from product name
        package_size, package_unit = parse_product_size(product_name)
        
        # Calculate unit price (price per base unit)
        unit_price = None
        if package_size and package_size > 0:
            unit_price = product_price / package_size
        
        # Calculate match score
        match_score = calculate_match_score(
            req.needed_qty,
            req.needed_unit,
            package_size,
            package_unit,
            product_price,
            rating
        )
        
        products.append(CoupangProduct(
            product_id=product_id,
            product_name=product_name,
            product_price=product_price,
            product_image=product_image,
            product_url=final_product_url,  # Use raw URL from API
            rating=rating,
            review_count=review_count,
            unit_price=unit_price,
            package_size=package_size,
            package_unit=package_unit,
            match_score=match_score
        ))
    
    # Sort by match score (best match first)
    products.sort(key=lambda p: p.match_score or 0, reverse=True)
    
    # Find best match (highest match score with good rating)
    best_match = None
    for product in products:
        if product.match_score and product.match_score > 50:
            # Ensure decent rating if available
            if product.rating is None or product.rating >= 3.5:
                best_match = product
                break
    
    # If no good match, just take the top one
    if not best_match and products:
        best_match = products[0]
    
    # Find budget option (lowest unit price)
    budget_option = None
    products_with_unit_price = [p for p in products if p.unit_price is not None]
    if products_with_unit_price:
        products_with_unit_price.sort(key=lambda p: p.unit_price or float('inf'))
        # Prefer products with decent ratings for budget option too
        for product in products_with_unit_price:
            if product.rating is None or product.rating >= 3.0:
                budget_option = product
                break
        # If no decent rating, just take the cheapest
        if not budget_option:
            budget_option = products_with_unit_price[0]
    
        return ProductRecommendationResponse(
            ingredient=req.ingredient_name,
            needed_qty=req.needed_qty,
            needed_unit=req.needed_unit,
            best_match=best_match,
            budget_option=budget_option,
            all_products=products[:10]  # Limit to top 10
        )

### ---------- Advanced Product Search Endpoint ----------
@app.post("/search_products_advanced", response_model=AdvancedProductSearchResponse)
def search_products_advanced(req: ProductSearchRequest):
    """
    Advanced product search that:
    1. Searches Coupang for up to 50 products
    2. Maps all products with amount and unit price
    3. Finds best match for needed amount
    4. Finds cheapest option if same amount exists
    5. Returns all 50 products with detailed mapping
    """
    # Search for 50 products
    limit = min(req.limit or 50, 50)  # Cap at 50
    raw_products = search_coupang_products(req.ingredient_name, limit)
    
    if not raw_products:
        return AdvancedProductSearchResponse(
            ingredient=req.ingredient_name,
            needed_qty=req.needed_qty,
            needed_unit=req.needed_unit,
            best_amount_match=None,
            cheapest_same_amount=None,
            cheapest_overall=None,
            all_products=[]
        )
    
    # Parse and map all products
    products: List[ProductSearchResult] = []
    
    for raw_product in raw_products:
        # Extract product info
        product_id = str(raw_product.get("productId", raw_product.get("id", "")))
        product_name = raw_product.get("productName", raw_product.get("name", ""))
        product_price = int(raw_product.get("productPrice", raw_product.get("price", 0)))
        product_image = raw_product.get("productImage", raw_product.get("imageUrl", ""))
        product_url = raw_product.get("productUrl", raw_product.get("url", ""))
        rating = raw_product.get("rating")
        if rating:
            rating = float(rating)
        review_count = raw_product.get("reviewCount", raw_product.get("reviews"))
        if review_count:
            review_count = int(review_count)
        
        # Use raw product URL from API
        # Accept URLs from all shopping malls (Coupang, Naver, etc.)
        final_product_url = product_url if product_url and product_url.startswith('http') else ""
        
        # Parse size from product name
        package_size, package_unit = parse_product_size(product_name)
        
        # Calculate unit price (price per base unit)
        unit_price = None
        if package_size and package_size > 0:
            unit_price = product_price / package_size
        
        # Calculate amount match score
        amount_match_score = calculate_amount_match_score(
            req.needed_qty,
            req.needed_unit,
            package_size,
            package_unit
        )
        
        # Calculate total match score (amount + rating + price)
        total_match_score = calculate_match_score(
            req.needed_qty,
            req.needed_unit,
            package_size,
            package_unit,
            product_price,
            rating
        )
        
        products.append(ProductSearchResult(
            product_id=product_id,
            product_name=product_name,
            product_price=product_price,
            product_image=product_image,
            product_url=final_product_url,  # Use raw URL from API
            rating=rating,
            review_count=review_count,
            package_size=package_size,
            package_unit=package_unit,
            unit_price=unit_price,
            amount_match_score=amount_match_score,
            total_match_score=total_match_score
        ))
    
    # Sort by amount match score (best match first)
    products.sort(key=lambda p: p.amount_match_score or 0, reverse=True)
    
    # Find best amount match
    best_amount_match = None
    if products:
        # Get product with highest amount match score
        best_amount_match = products[0]
    
    # Find cheapest option with same amount (if needed amount is specified)
    cheapest_same_amount = None
    if req.needed_qty and req.needed_unit:
        needed_base_qty, needed_base_unit = convert_to_base_unit(req.needed_qty, req.needed_unit)
        
        # Find products with same amount (within 5% tolerance)
        same_amount_products = []
        for product in products:
            if product.package_size and product.package_unit:
                product_base_qty, product_base_unit = convert_to_base_unit(
                    product.package_size, product.package_unit
                )
                if product_base_unit == needed_base_unit:
                    ratio = product_base_qty / needed_base_qty
                    if 0.95 <= ratio <= 1.05:  # Within 5% of needed amount
                        same_amount_products.append(product)
        
        # If multiple products have same amount, pick cheapest unit price
        if same_amount_products:
            same_amount_products.sort(
                key=lambda p: p.unit_price if p.unit_price else float('inf')
            )
            cheapest_same_amount = same_amount_products[0]
    
    # Find cheapest overall (by unit price)
    cheapest_overall = None
    products_with_unit_price = [p for p in products if p.unit_price is not None]
    if products_with_unit_price:
        products_with_unit_price.sort(
            key=lambda p: p.unit_price if p.unit_price else float('inf')
        )
        cheapest_overall = products_with_unit_price[0]
    
    # Debug: Log the response JSON
    response_data = {
        "ingredient": req.ingredient_name,
        "needed_qty": req.needed_qty,
        "needed_unit": req.needed_unit,
        "best_amount_match": best_amount_match.dict() if best_amount_match else None,
        "cheapest_same_amount": cheapest_same_amount.dict() if cheapest_same_amount else None,
        "cheapest_overall": cheapest_overall.dict() if cheapest_overall else None,
        "all_products_count": len(products)
    }
    print(f"[DEBUG] Advanced Product Search Response for '{req.ingredient_name}':")
    print(f"[DEBUG] {json.dumps(response_data, indent=2, ensure_ascii=False)}")
    
    # Log the most efficient product details
    most_efficient = cheapest_same_amount or best_amount_match or cheapest_overall
    if most_efficient:
        print(f"[DEBUG] Most Efficient Product Selected:")
        print(f"[DEBUG]   - Name: {most_efficient.product_name}")
        print(f"[DEBUG]   - Price: {most_efficient.product_price}")
        print(f"[DEBUG]   - URL: {most_efficient.product_url}")
        print(f"[DEBUG]   - Package: {most_efficient.package_size} {most_efficient.package_unit}")
        print(f"[DEBUG]   - Unit Price: {most_efficient.unit_price}")
        print(f"[DEBUG]   - Amount Match Score: {most_efficient.amount_match_score}")
        print(f"[DEBUG]   - Total Match Score: {most_efficient.total_match_score}")
    else:
        print(f"[DEBUG] No efficient product found for '{req.ingredient_name}'")
    
    return AdvancedProductSearchResponse(
        ingredient=req.ingredient_name,
        needed_qty=req.needed_qty,
        needed_unit=req.needed_unit,
        best_amount_match=best_amount_match,
        cheapest_same_amount=cheapest_same_amount,
        cheapest_overall=cheapest_overall,
        all_products=products  # All 50 products with mapped data
    )

### ---------- Recipe Recommendation Endpoint ----------
@app.post("/recommend_recipe", response_model=RecipeRecommendationResponse)
def recommend_recipe(req: RecipeRecommendationRequest):
    """
    Recommend a recipe that:
    1. Shares main ingredients with cart recipes (reduces waste)
    2. Saves money per unit by buying in bulk
    3. Matches user's taste preferences (tags, categories)
    
    Returns numerical evidence for why the recipe is recommended.
    """
    try:
        print(f"[DEBUG] Received recommendation request:")
        print(f"[DEBUG]   - Cart recipes count: {len(req.cart_recipes)}")
        print(f"[DEBUG]   - Available recipes count: {len(req.available_recipes)}")
        print(f"[DEBUG]   - User preferences: {req.user_preferences}")
        
        # Validate input
        if not req.cart_recipes:
            raise HTTPException(
                status_code=400,
                detail="cart_recipes cannot be empty"
            )
        
        if not req.available_recipes:
            raise HTTPException(
                status_code=400,
                detail="available_recipes cannot be empty"
            )
        
        # Extract main ingredients from cart recipes
        cart_main_ingredients = _extract_main_ingredients(req.cart_recipes)
        
        if not cart_main_ingredients:
            print(f"[ERROR] No main ingredients found. Cart recipes: {req.cart_recipes}")
            raise HTTPException(
                status_code=400,
                detail="No main ingredients found in cart recipes. Please ensure your recipes have ingredients with quantities."
            )
        
        # Extract user preferences from cart recipes
        user_preferences = _extract_user_preferences(req.cart_recipes, req.user_preferences)
        
        # Find candidate recipes that share main ingredients
        candidate_recipes = _find_candidate_recipes(
            cart_main_ingredients,
            req.available_recipes,
            req.cart_recipes
        )
        
        if not candidate_recipes:
            raise HTTPException(
                status_code=404,
                detail="No recipes found that share main ingredients with cart"
            )
        
        # Create state hash for Q-learning
        state_hash = None
        available_actions = []
        selected_action = None
        
        if _personalized_q_agent and req.user_id:
            try:
                state_hash = _personalized_q_agent.get_user_agent(req.user_id or "default").hash_state(
                    cart_ingredients=list(cart_main_ingredients.keys()),
                    user_preferences=user_preferences,
                    available_recipes_count=len(candidate_recipes)
                )
                
                # Get available actions (recipe IDs)
                available_actions = [
                    str(r.get('id') or r.get('recipeId') or r.get('recipe', {}).get('name', ''))
                    for r in candidate_recipes
                ]
                
                # Q-Learning: Select action (recipe) using epsilon-greedy policy
                selected_action = _personalized_q_agent.select_action_for_user(
                    user_id=req.user_id,
                    state=state_hash,
                    available_actions=available_actions,
                    use_epsilon=True  # Use exploration
                )
                print(f"[RL] Q-Learning selected action: {selected_action}")
            except Exception as e:
                print(f"[WARNING] Q-Learning selection failed: {e}")
                state_hash = None
                selected_action = None
        
        # If Q-learning selected an action, use that recipe; otherwise use LLM
        if selected_action and candidate_recipes:
            # Find the selected recipe
            selected_recipe = None
            for recipe in candidate_recipes:
                recipe_id = str(recipe.get('id') or recipe.get('recipeId') or recipe.get('recipe', {}).get('name', ''))
                if recipe_id == selected_action:
                    selected_recipe = recipe
                    break
            
            if selected_recipe:
                recommendation = {
                    'recipe': selected_recipe,
                    'reasoning': 'Q-Learning 기반 개인화 추천입니다.'
                }
                print(f"[RL] Using Q-Learning recommendation: {selected_recipe.get('recipe', {}).get('name', 'Unknown')}")
            else:
                # Fallback to LLM if selected recipe not found
                recommendation = _get_llm_recommendation(
                    cart_recipes=req.cart_recipes,
                    candidate_recipes=candidate_recipes,
                    cart_main_ingredients=cart_main_ingredients,
                    user_preferences=user_preferences
                )
        else:
            # Use LLM to recommend best recipe based on efficiency and preferences
            recommendation = _get_llm_recommendation(
                cart_recipes=req.cart_recipes,
                candidate_recipes=candidate_recipes,
                cart_main_ingredients=cart_main_ingredients,
                user_preferences=user_preferences
            )
        
        # Calculate efficiency metrics
        efficiency = _calculate_efficiency_metrics(
            cart_recipes=req.cart_recipes,
            recommended_recipe=recommendation['recipe'],
            cart_main_ingredients=cart_main_ingredients
        )
        
        # Calculate taste match score
        taste_score = _calculate_taste_match_score(
            recommended_recipe=recommendation['recipe'],
            user_preferences=user_preferences
        )
        
        # Get personalized weights for user (if user_id provided)
        user_weights = None
        if req.user_id:
            user_weights = _get_user_weights(req.user_id)
            print(f"[DEBUG] Using personalized weights for user {req.user_id}: {user_weights}")
        
        # Generate recommendation ID for tracking feedback
        recommendation_id = str(uuid.uuid4())
        
        # Calculate factor scores for feedback
        efficiency_score = min(1.0, efficiency.waste_reduction_percent / 100.0)
        taste_score_normalized = taste_score / 100.0
        price_saving_score = min(1.0, efficiency.total_savings_krw / 10000.0)  # Normalize to 0-1
        
        # Store recommendation context for feedback (including Q-learning state)
        recommendation_context = {
            'user_id': req.user_id,
            'recipe_id': recommendation['recipe'].get('id') or recommendation['recipe'].get('recipeId'),
            'recipe_name': recommendation['recipe'].get('recipe', {}).get('name', 'Unknown'),
            'state_hash': state_hash,  # Q-learning state
            'action': str(recommendation['recipe'].get('id') or recommendation['recipe'].get('recipeId') or recommendation['recipe'].get('recipe', {}).get('name', '')),
            'next_state': None,  # Will be set when next recommendation is made
            'next_available_actions': available_actions,  # For Q-learning update
            'factors': {
                'efficiency': efficiency_score,
                'taste_match': taste_score_normalized,
                'price_saving': price_saving_score,
                'popularity': 0.5  # Default
            },
            'efficiency_metrics': {
                'waste_reduction_percent': efficiency.waste_reduction_percent,
                'total_savings_krw': efficiency.total_savings_krw,
                'shared_ingredients': efficiency.shared_main_ingredients
            },
            'taste_match_score': taste_score,
            'timestamp': datetime.now().isoformat()
        }
        _store_recommendation_context(recommendation_id, recommendation_context)
        
        return RecipeRecommendationResponse(
            recommended_recipe=recommendation['recipe'],
            efficiency_metrics=efficiency,
            reasoning=recommendation['reasoning'],
            taste_match_score=taste_score,
            recommendation_id=recommendation_id
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Recipe recommendation failed: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Recommendation failed: {str(e)}")

### ---------- RL Feedback Endpoints ----------

@app.post("/recommendation_feedback")
def record_feedback(req: RecommendationFeedbackRequest):
    """
    Record user feedback on a recommendation.
    Updates personalized weights using RL algorithm and Q-learning.
    """
    try:
        print(f"[DEBUG] Received feedback: user={req.user_id}, recommendation={req.recommendation_id}, feedback={req.feedback}")
        
        # Get recommendation context
        context = _get_recommendation_context(req.recommendation_id)
        if not context:
            raise HTTPException(
                status_code=404,
                detail="Recommendation context not found"
            )
        
        # Get current user weights (for backward compatibility with old RLAgent)
        current_weights = _get_user_weights(req.user_id)
        
        # Get factor scores from context
        factors = context.get('factors', {})
        
        # Update weights using old RL algorithm (for backward compatibility)
        updated_weights = RLAgent.update_weights(
            current_weights=current_weights,
            feedback=req.feedback,
            factors=factors
        )
        
        # Save updated weights
        _update_user_weights(req.user_id, updated_weights, req.feedback)
        
        # Q-Learning: Learn from feedback
        if _personalized_q_agent:
            state = context.get('state_hash')
            action = context.get('recipe_id') or context.get('action')
            next_state = context.get('next_state')
            next_available_actions = context.get('next_available_actions', [])
            
            if state and action:
                try:
                    _personalized_q_agent.learn_from_feedback_for_user(
                        user_id=req.user_id,
                        state=state,
                        action=str(action),
                        feedback=req.feedback,
                        next_state=next_state,
                        next_available_actions=next_available_actions
                    )
                    print(f"[RL] Q-Learning update completed for user {req.user_id}")
                except Exception as e:
                    print(f"[WARNING] Q-Learning update failed: {e}")
        
        print(f"[DEBUG] Updated weights for user {req.user_id}: {updated_weights}")
        
        return {
            "success": True,
            "message": "Feedback recorded",
            "updated_weights": updated_weights,
            "q_learning_updated": state and action
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] Failed to record feedback: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to record feedback: {str(e)}")

@app.get("/user_weights/{user_id}")
def get_user_weights(user_id: str):
    """
    Get personalized weights for a user.
    """
    try:
        weights = _get_user_weights(user_id)
        all_weights = _load_user_weights()
        user_data = all_weights.get(user_id, {})
        
        # Get Q-learning statistics
        q_stats = None
        if _personalized_q_agent:
            try:
                q_stats = _personalized_q_agent.get_user_statistics(user_id)
            except Exception as e:
                print(f"[WARNING] Failed to get Q-learning stats: {e}")
        
        return {
            "user_id": user_id,
            "weights": weights,
            "total_feedback": user_data.get('total_feedback', 0),
            "positive_feedback": user_data.get('positive_feedback', 0),
            "negative_feedback": user_data.get('negative_feedback', 0),
            "last_updated": user_data.get('last_updated'),
            "q_learning_stats": q_stats
        }
    except Exception as e:
        print(f"[ERROR] Failed to get user weights: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get user weights: {str(e)}")

@app.get("/rl_agent/stats")
def get_rl_agent_stats():
    """Get Q-learning agent statistics."""
    try:
        if _q_learning_agent and _personalized_q_agent:
            return {
                "base_agent": _q_learning_agent.get_statistics(),
                "total_users": len(_personalized_q_agent.user_agents)
            }
        else:
            return {
                "error": "Q-Learning agent not initialized",
                "base_agent": None,
                "total_users": 0
            }
    except Exception as e:
        print(f"[ERROR] Failed to get RL agent stats: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get RL agent stats: {str(e)}")

def _extract_main_ingredients(cart_recipes: List[Dict[str, Any]]) -> Dict[str, float]:
    """
    Extract main ingredients from cart recipes and aggregate quantities.
    Returns dict: {ingredient_name: total_qty}
    
    If no ingredients have 'category' field, treats all ingredients as 'main' (backwards compatibility).
    """
    main_ingredients = {}
    has_any_categories = False
    
    # First pass: check if any ingredients have categories
    for cart_recipe in cart_recipes:
        recipe_data = cart_recipe.get('recipe', {})
        ingredients = recipe_data.get('ingredients', [])
        for ing in ingredients:
            if 'category' in ing and ing.get('category'):
                has_any_categories = True
                break
        if has_any_categories:
            break
    
    print(f"[DEBUG] Has categorized ingredients: {has_any_categories}")
    
    for cart_recipe in cart_recipes:
        recipe_data = cart_recipe.get('recipe', {})
        ingredients = recipe_data.get('ingredients', [])
        servings = cart_recipe.get('servings', 1)
        base_servings = recipe_data.get('servings', 1)
        scale_factor = servings / base_servings if base_servings > 0 else 1
        
        print(f"[DEBUG] Processing recipe: {recipe_data.get('name', 'Unknown')}, ingredients: {len(ingredients)}")
        
        for ingredient in ingredients:
            category = ingredient.get('category', '')
            # If no categories exist in any recipe, treat all ingredients as main
            is_main = (category == 'main') if has_any_categories else True
            
            if is_main:
                item = ingredient.get('item', '').strip()
                qty = ingredient.get('qty', 0) or 0
                
                print(f"[DEBUG]   - Main ingredient: {item}, qty: {qty}, category: '{category}'")
                
                if item:
                    scaled_qty = qty * scale_factor
                    if item in main_ingredients:
                        main_ingredients[item] += scaled_qty
                    else:
                        main_ingredients[item] = scaled_qty
    
    print(f"[DEBUG] Extracted main ingredients: {list(main_ingredients.keys())}")
    return main_ingredients

def _extract_user_preferences(
    cart_recipes: List[Dict[str, Any]],
    explicit_preferences: Optional[Dict[str, Any]]
) -> Dict[str, Any]:
    """Extract user taste preferences from cart recipes and explicit preferences."""
    preferences = {
        'tags': [],
        'categories': {
            'meat_type': [],
            'cuisine_type': [],
            'menu_type': [],
            'meal_time': [],
            'ingredient_type': [],
            'time_category': []
        }
    }
    
    # Extract from cart recipes
    for cart_recipe in cart_recipes:
        source = cart_recipe.get('source', {})
        
        # Tags
        tags = source.get('tags', [])
        if tags:
            preferences['tags'].extend(tags)
        
        # Categories
        categories = source.get('categories', {})
        for cat_type in preferences['categories'].keys():
            cat_values = categories.get(cat_type, [])
            if cat_values:
                preferences['categories'][cat_type].extend(cat_values)
    
    # Remove duplicates
    preferences['tags'] = list(set(preferences['tags']))
    for cat_type in preferences['categories']:
        preferences['categories'][cat_type] = list(set(preferences['categories'][cat_type]))
    
    # Merge with explicit preferences if provided
    if explicit_preferences:
        if 'tags' in explicit_preferences:
            preferences['tags'].extend(explicit_preferences['tags'])
            preferences['tags'] = list(set(preferences['tags']))
        
        if 'categories' in explicit_preferences:
            for cat_type, cat_values in explicit_preferences['categories'].items():
                if cat_values:
                    preferences['categories'][cat_type].extend(cat_values)
                    preferences['categories'][cat_type] = list(set(preferences['categories'][cat_type]))
    
    return preferences

def _normalize_ingredient_name(name: str) -> str:
    """
    Normalize ingredient names for better matching.
    Removes common suffixes and normalizes pasta/noodle names.
    """
    if not name:
        return ""
    
    # Convert to lowercase for comparison
    normalized = name.lower().strip()
    
    # Remove common suffixes
    suffixes = ['면', ' noodles', ' noodle', ' 파스타', ' pasta']
    for suffix in suffixes:
        if normalized.endswith(suffix):
            normalized = normalized[:-len(suffix)].strip()
    
    return normalized

def _are_ingredients_similar(ing1: str, ing2: str) -> bool:
    """
    Check if two ingredients are similar (same category).
    Handles pasta/noodle variations, fuzzy matching, etc.
    """
    if not ing1 or not ing2:
        return False
    
    # Normalize both names
    norm1 = _normalize_ingredient_name(ing1)
    norm2 = _normalize_ingredient_name(ing2)
    
    # Exact match after normalization
    if norm1 == norm2:
        return True
    
    # Check if one contains the other (handles "스파게티 면" vs "스파게티")
    if norm1 in norm2 or norm2 in norm1:
        return True
    
    # Pasta/noodle type matching - all pasta types should match each other
    pasta_keywords = [
        '스파게티', 'spaghetti', 'spagetti',
        '파스타', 'pasta', 
        '펜네', 'penne',
        '페투치니', 'fettuccine', 'fettucine', 'fettuccini',
        '라자냐', 'lasagna', '라자니아', '라자냐',
        '리가토니', 'rigatoni',
        '푸실리', 'fusilli',
        '마카로니', 'macaroni',
        '면', 'noodle', 'noodles',
    ]
    
    # Check if both ingredients contain pasta-related keywords
    norm1_has_pasta = any(kw in norm1 for kw in pasta_keywords)
    norm2_has_pasta = any(kw in norm2 for kw in pasta_keywords)
    
    # If both are pasta-related, they're similar (all pasta types match)
    if norm1_has_pasta and norm2_has_pasta:
        return True
    
    # Use fuzzy matching for other ingredients
    from rapidfuzz import fuzz
    ratio = fuzz.ratio(norm1, norm2)
    if ratio >= 75:  # 75% similarity threshold
        return True
    
    # Partial ratio (handles substring matches better)
    partial_ratio = fuzz.partial_ratio(norm1, norm2)
    if partial_ratio >= 85:  # 85% partial similarity
        return True
    
    return False

def _find_candidate_recipes(
    cart_main_ingredients: Dict[str, float],
    available_recipes: List[Dict[str, Any]],
    cart_recipes: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """
    Find recipes that share main ingredients with cart recipes.
    Excludes recipes already in cart.
    Uses fuzzy matching for ingredient names to handle variations.
    Recognizes pasta/noodle types as similar ingredients.
    """
    cart_recipe_names = {r.get('recipe', {}).get('name', '') for r in cart_recipes}
    cart_recipe_ids = {r.get('recipeId', '') for r in cart_recipes if r.get('recipeId')}
    
    print(f"[DEBUG] Finding candidates. Cart main ingredients: {list(cart_main_ingredients.keys())}")
    print(f"[DEBUG] Available recipes count: {len(available_recipes)}")
    
    candidates = []
    
    # Check if any recipes have categories
    has_any_categories = False
    for recipe_data in available_recipes:
        recipe_ingredients = recipe_data.get('recipe', {}).get('ingredients', [])
        for ing in recipe_ingredients:
            if 'category' in ing and ing.get('category'):
                has_any_categories = True
                break
        if has_any_categories:
            break
    
    print(f"[DEBUG] Recipes have categories: {has_any_categories}")
    
    for recipe_data in available_recipes:
        # Skip if already in cart
        recipe_name = recipe_data.get('recipe', {}).get('name', '')
        recipe_id = recipe_data.get('id', '') or recipe_data.get('recipeId', '')
        
        if recipe_name in cart_recipe_names or recipe_id in cart_recipe_ids:
            print(f"[DEBUG] Skipping {recipe_name} - already in cart")
            continue
        
        # Check if recipe shares main ingredients
        recipe_ingredients = recipe_data.get('recipe', {}).get('ingredients', [])
        
        # Extract main ingredients (or all if no categories exist)
        recipe_main_ingredients = {}
        for ing in recipe_ingredients:
            category = ing.get('category', '')
            # If no categories exist, treat all ingredients as main
            is_main = (category == 'main') if has_any_categories else True
            
            if is_main:
                item = ing.get('item', '').strip()
                qty = ing.get('qty', 0) or 0
                if item:
                    recipe_main_ingredients[item] = qty
        
        print(f"[DEBUG] Recipe '{recipe_name}' main ingredients: {list(recipe_main_ingredients.keys())}")
        
        # Check for shared main ingredients using improved matching
        shared = []
        for cart_ing in cart_main_ingredients.keys():
            for recipe_ing in recipe_main_ingredients.keys():
                if _are_ingredients_similar(cart_ing, recipe_ing):
                    # Use the cart ingredient name for consistency
                    if cart_ing not in shared:
                        shared.append(cart_ing)
                        print(f"[DEBUG]   Matched: '{cart_ing}' <-> '{recipe_ing}'")
        
        if shared:
            print(f"[DEBUG] Found match! Recipe '{recipe_name}' shares: {shared}")
            candidates.append({
                **recipe_data,
                'shared_main_ingredients': shared,
                'shared_count': len(shared)
            })
    
    print(f"[DEBUG] Found {len(candidates)} candidate recipes")
    
    # Sort by number of shared ingredients (descending)
    candidates.sort(key=lambda x: x.get('shared_count', 0), reverse=True)
    
    return candidates

def _get_llm_recommendation(
    cart_recipes: List[Dict[str, Any]],
    candidate_recipes: List[Dict[str, Any]],
    cart_main_ingredients: Dict[str, float],
    user_preferences: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Use LLM to recommend the best recipe from candidates based on:
    1. Efficiency (shared ingredients, bulk buying)
    2. Taste preferences (tags, categories)
    """
    from openai import OpenAI
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    
    # Prepare cart summary
    cart_summary = []
    for recipe in cart_recipes[:5]:  # Limit to 5 recipes
        name = recipe.get('recipe', {}).get('name', 'Unknown')
        servings = recipe.get('servings', 1)
        tags = recipe.get('source', {}).get('tags', [])
        cart_summary.append(f"- {name} ({servings} servings, tags: {', '.join(tags[:3])})")
    
    # Prepare candidate recipes summary
    candidate_summary = []
    for i, recipe in enumerate(candidate_recipes[:10], 1):  # Top 10 candidates
        name = recipe.get('recipe', {}).get('name', 'Unknown')
        shared = recipe.get('shared_main_ingredients', [])
        tags = recipe.get('source', {}).get('tags', [])
        candidate_summary.append(
            f"{i}. {name} (shares: {', '.join(shared[:3])}, tags: {', '.join(tags[:3])})"
        )
    
    system = """You are a smart recipe recommendation system that helps users save money and reduce food waste.

Your goal is to recommend ONE recipe from the candidate list that:
1. Maximizes use of main ingredients already in the user's cart (reduces waste)
2. Matches the user's taste preferences (tags, categories)
3. Would benefit from bulk buying (saves money per unit)

Analyze the cart recipes and candidate recipes, then recommend the BEST recipe with clear reasoning.

Return JSON with:
- recipe_index: int (index in candidate list, 0-based)
- reasoning: string (why this recipe is recommended, in Korean)
"""
    
    user = f"""User's Cart Recipes:
{chr(10).join(cart_summary)}

Main Ingredients in Cart:
{', '.join(cart_main_ingredients.keys())}

User Preferences:
- Tags: {', '.join(user_preferences.get('tags', [])[:10])}
- Cuisine: {', '.join(user_preferences.get('categories', {}).get('cuisine_type', [])[:5])}
- Meal Time: {', '.join(user_preferences.get('categories', {}).get('meal_time', [])[:5])}

Candidate Recipes:
{chr(10).join(candidate_summary)}

Recommend the BEST recipe that maximizes efficiency and matches preferences. Return JSON only."""
    
    try:
        resp = client.chat.completions.create(
            model=os.getenv("RECIPE_MODEL", "gpt-4o-mini"),
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user}
            ],
            temperature=0.3
        )
        
        text = resp.choices[0].message.content.strip()
        start = text.find("{")
        end = text.rfind("}")
        result = json.loads(text[start:end+1])
        
        recipe_index = result.get('recipe_index', 0)
        reasoning = result.get('reasoning', '효율적인 재료 사용과 취향을 고려한 추천입니다.')
        
        if 0 <= recipe_index < len(candidate_recipes):
            return {
                'recipe': candidate_recipes[recipe_index],
                'reasoning': reasoning
            }
        else:
            # Fallback to first candidate
            return {
                'recipe': candidate_recipes[0],
                'reasoning': reasoning
            }
            
    except Exception as e:
        print(f"[ERROR] LLM recommendation failed: {e}")
        # Fallback to first candidate
        return {
            'recipe': candidate_recipes[0],
            'reasoning': '공유된 주재료를 활용하여 음식 낭비를 줄이고 효율적인 구매를 도와줍니다.'
        }

def _calculate_efficiency_metrics(
    cart_recipes: List[Dict[str, Any]],
    recommended_recipe: Dict[str, Any],
    cart_main_ingredients: Dict[str, float]
) -> EfficiencyMetrics:
    """
    Calculate efficiency metrics:
    - Money saved per unit (by buying in bulk)
    - Waste reduction percentage
    - Total savings
    """
    # Get shared main ingredients
    rec_ingredients = recommended_recipe.get('recipe', {}).get('ingredients', [])
    rec_main_ingredients = {
        ing.get('item', '').strip(): ing.get('qty', 0) or 0
        for ing in rec_ingredients
        if ing.get('category') == 'main'
    }
    
    shared_ingredients = list(set(cart_main_ingredients.keys()) & set(rec_main_ingredients.keys()))
    
    # Calculate waste reduction (simplified: assume 20% waste reduction per shared ingredient)
    waste_reduction = min(100.0, len(shared_ingredients) * 15.0)  # Up to 100%
    
    # Calculate money savings (simplified: assume 10% savings per shared ingredient from bulk buying)
    # In real implementation, this would use actual product prices
    total_savings = len(shared_ingredients) * 2000  # 2000 KRW per shared ingredient
    money_saved_per_unit = total_savings / max(1, sum(rec_main_ingredients.values())) if rec_main_ingredients else 0
    
    explanation = f"{len(shared_ingredients)}개의 주재료({', '.join(shared_ingredients[:3])})를 공유하여 음식 낭비를 {waste_reduction:.0f}% 줄이고, 대량 구매로 약 {total_savings:,.0f}원을 절약할 수 있습니다."
    
    return EfficiencyMetrics(
        money_saved_per_unit=money_saved_per_unit,
        waste_reduction_percent=waste_reduction,
        total_savings_krw=total_savings,
        shared_main_ingredients=shared_ingredients,
        explanation=explanation
    )

### ---------- RL Agent for Personalized Recommendations ----------
# Import Q-Learning agent (lazy import to avoid circular dependencies)
try:
    from rl_agent import QLearningAgent, PersonalizedQLearningAgent
    
    # Initialize Q-Learning agent (global instance)
    _q_learning_agent = QLearningAgent(
        learning_rate=0.1,
        discount_factor=0.95,
        epsilon=0.1,
        epsilon_decay=0.995,
        epsilon_min=0.01
    )
    
    # Initialize personalized Q-Learning agent
    _personalized_q_agent = PersonalizedQLearningAgent(_q_learning_agent)
except ImportError as e:
    print(f"[WARNING] Failed to import Q-Learning agent: {e}")
    _q_learning_agent = None
    _personalized_q_agent = None

class RLAgent:
    """
    Reinforcement Learning Agent for learning personalized recommendation weights.
    Uses a contextual bandit approach with exponential moving average updates.
    """
    
    # Default weights for different factors
    DEFAULT_WEIGHTS = {
        'efficiency': 0.4,      # Shared ingredients, waste reduction
        'taste_match': 0.3,     # Tags, categories matching
        'price_saving': 0.2,    # Money saved per unit
        'popularity': 0.1,      # Recipe popularity (future)
    }
    
    # Learning rate (how much to adjust weights per feedback)
    LEARNING_RATE = 0.1
    
    # Minimum weight value
    MIN_WEIGHT = 0.05
    
    # Maximum weight value
    MAX_WEIGHT = 0.8
    
    @staticmethod
    def get_default_weights() -> Dict[str, float]:
        """Get default weights for new users."""
        return RLAgent.DEFAULT_WEIGHTS.copy()
    
    @staticmethod
    def normalize_weights(weights: Dict[str, float]) -> Dict[str, float]:
        """Normalize weights so they sum to 1.0."""
        total = sum(weights.values())
        if total == 0:
            return RLAgent.get_default_weights()
        
        normalized = {k: max(RLAgent.MIN_WEIGHT, min(RLAgent.MAX_WEIGHT, v / total)) 
                     for k, v in weights.items()}
        
        # Renormalize to ensure sum is 1.0
        total = sum(normalized.values())
        return {k: v / total for k, v in normalized.items()}
    
    @staticmethod
    def update_weights(
        current_weights: Dict[str, float],
        feedback: str,
        factors: Dict[str, float]
    ) -> Dict[str, float]:
        """
        Update weights based on feedback using exponential moving average.
        
        Args:
            current_weights: Current personalized weights
            feedback: "positive" or "negative"
            factors: Dictionary of factor scores for the recommendation
                    e.g., {'efficiency': 0.8, 'taste_match': 0.6, ...}
        
        Returns:
            Updated weights dictionary
        """
        reward = 1.0 if feedback == "positive" else -0.5
        
        updated_weights = {}
        
        for factor, weight in current_weights.items():
            # Get the factor's contribution to this recommendation
            factor_score = factors.get(factor, 0.5)  # Default to 0.5 if not present
            
            # Calculate adjustment: if factor contributed well and got positive feedback,
            # increase its weight. If it contributed poorly or got negative feedback, decrease.
            if reward > 0:
                # Positive feedback: increase weight for factors that scored well
                adjustment = RLAgent.LEARNING_RATE * reward * factor_score
            else:
                # Negative feedback: decrease weight for factors that scored well
                # (they didn't work for this user)
                adjustment = RLAgent.LEARNING_RATE * reward * (1 - factor_score)
            
            updated_weights[factor] = weight + adjustment
        
        # Normalize to ensure weights sum to 1.0
        return RLAgent.normalize_weights(updated_weights)
    
    @staticmethod
    def calculate_personalized_score(
        weights: Dict[str, float],
        efficiency_score: float,
        taste_score: float,
        price_saving_score: float,
        popularity_score: float = 0.5
    ) -> float:
        """
        Calculate personalized recommendation score using learned weights.
        
        Args:
            weights: Personalized weights for each factor
            efficiency_score: 0-1 score for ingredient efficiency
            taste_score: 0-1 score for taste matching
            price_saving_score: 0-1 score for price savings
            popularity_score: 0-1 score for recipe popularity
        
        Returns:
            Weighted score (0-1)
        """
        score = (
            weights.get('efficiency', 0.4) * efficiency_score +
            weights.get('taste_match', 0.3) * taste_score +
            weights.get('price_saving', 0.2) * price_saving_score +
            weights.get('popularity', 0.1) * popularity_score
        )
        
        return min(1.0, max(0.0, score))

### ---------- User Weights Storage (Simple File-based) ----------
# In production, this should be stored in Firebase or a database

USER_WEIGHTS_FILE = "user_weights.json"
RECOMMENDATION_CONTEXT_FILE = "recommendation_context.json"

def _load_user_weights() -> Dict[str, Dict[str, Any]]:
    """Load user weights from file."""
    if os.path.exists(USER_WEIGHTS_FILE):
        try:
            with open(USER_WEIGHTS_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"[ERROR] Failed to load user weights: {e}")
            return {}
    return {}

def _save_user_weights(weights: Dict[str, Dict[str, Any]]):
    """Save user weights to file."""
    try:
        with open(USER_WEIGHTS_FILE, 'w', encoding='utf-8') as f:
            json.dump(weights, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[ERROR] Failed to save user weights: {e}")

def _get_user_weights(user_id: str) -> Dict[str, float]:
    """Get personalized weights for a user."""
    all_weights = _load_user_weights()
    if user_id in all_weights:
        return all_weights[user_id].get('weights', RLAgent.get_default_weights())
    return RLAgent.get_default_weights()

def _update_user_weights(user_id: str, new_weights: Dict[str, float], feedback: str):
    """Update user weights based on feedback."""
    all_weights = _load_user_weights()
    
    if user_id not in all_weights:
        all_weights[user_id] = {
            'weights': RLAgent.get_default_weights(),
            'total_feedback': 0,
            'positive_feedback': 0,
            'negative_feedback': 0,
            'last_updated': datetime.now().isoformat()
        }
    
    user_data = all_weights[user_id]
    user_data['weights'] = new_weights
    user_data['total_feedback'] = user_data.get('total_feedback', 0) + 1
    if feedback == "positive":
        user_data['positive_feedback'] = user_data.get('positive_feedback', 0) + 1
    else:
        user_data['negative_feedback'] = user_data.get('negative_feedback', 0) + 1
    user_data['last_updated'] = datetime.now().isoformat()
    
    _save_user_weights(all_weights)

def _load_recommendation_context() -> Dict[str, Dict[str, Any]]:
    """Load recommendation context for feedback."""
    if os.path.exists(RECOMMENDATION_CONTEXT_FILE):
        try:
            with open(RECOMMENDATION_CONTEXT_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"[ERROR] Failed to load recommendation context: {e}")
            return {}
    return {}

def _save_recommendation_context(context: Dict[str, Dict[str, Any]]):
    """Save recommendation context."""
    try:
        with open(RECOMMENDATION_CONTEXT_FILE, 'w', encoding='utf-8') as f:
            json.dump(context, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[ERROR] Failed to save recommendation context: {e}")

def _store_recommendation_context(recommendation_id: str, context: Dict[str, Any]):
    """Store context for a recommendation (for feedback)."""
    all_context = _load_recommendation_context()
    all_context[recommendation_id] = context
    _save_recommendation_context(all_context)

def _get_recommendation_context(recommendation_id: str) -> Optional[Dict[str, Any]]:
    """Get stored context for a recommendation."""
    all_context = _load_recommendation_context()
    return all_context.get(recommendation_id)

def _calculate_taste_match_score(
    recommended_recipe: Dict[str, Any],
    user_preferences: Dict[str, Any]
) -> float:
    """
    Calculate taste match score (0-100) based on tags and categories.
    """
    score = 0.0
    max_score = 100.0
    
    rec_source = recommended_recipe.get('source', {})
    rec_tags = set(rec_source.get('tags', []))
    rec_categories = rec_source.get('categories', {})
    
    user_tags = set(user_preferences.get('tags', []))
    user_categories = user_preferences.get('categories', {})
    
    # Tag matching (40 points)
    if user_tags:
        tag_overlap = len(rec_tags & user_tags)
        tag_score = min(40.0, (tag_overlap / len(user_tags)) * 40.0)
        score += tag_score
    
    # Category matching (60 points)
    category_score = 0.0
    category_count = 0
    
    for cat_type in ['cuisine_type', 'menu_type', 'meal_time']:
        rec_cats = set(rec_categories.get(cat_type, []))
        user_cats = set(user_categories.get(cat_type, []))
        
        if user_cats:
            category_count += 1
            if rec_cats & user_cats:
                category_score += 20.0
    
    if category_count > 0:
        score += category_score / category_count * 3  # Normalize to 60 points max
    
    return min(100.0, max(0.0, score))

### ---------- Ingredient Categorization ----------
class CategorizeIngredientRequest(BaseModel):
    ingredient_name: str
    category: Optional[str] = None  # Original category from recipe (main, sub, sauce_msg)

class CategorizeIngredientResponse(BaseModel):
    category: str  # One of: "육류/단백질", "채소", "곡류/쌀", "양념/소스"
    confidence: Optional[str] = None  # "high", "medium", "low"

@app.post("/categorize_ingredient", response_model=CategorizeIngredientResponse)
def categorize_ingredient(req: CategorizeIngredientRequest):
    """
    Categorize an ingredient using LLM as a fallback when pattern matching fails.
    Returns one of: "육류/단백질", "채소", "곡류/쌀", "양념/소스"
    """
    ingredient_name = req.ingredient_name.strip()
    original_category = req.category
    
    # First, try pattern matching (same logic as frontend)
    name_lower = ingredient_name.lower()
    
    # Check if it's meat/protein
    if any(keyword in name_lower for keyword in [
        '돼지', '소고기', '닭', '오리', '양고기', '계란', '달걀', '생선', 
        '고등어', '연어', '참치', '새우', '오징어', '문어', '조개', '굴',
        '두부', '콩', '닭가슴살', '삼겹살', '목살', '갈비', '안심', '등심',
        '치킨', '베이컨', '햄', '소시지'
    ]):
        return CategorizeIngredientResponse(category="육류/단백질", confidence="high")
    
    # Check if it's vegetable
    if any(keyword in name_lower for keyword in [
        '배추', '양파', '당근', '오이', '토마토', '상추', '시금치', '브로콜리',
        '양배추', '파', '마늘', '생강', '고추', '피망', '버섯', '가지', '호박',
        '무', '단무지', '깻잎', '치커리', '아삭이', '채소'
    ]):
        return CategorizeIngredientResponse(category="채소", confidence="high")
    
    # Check if it's grain/rice
    if any(keyword in name_lower for keyword in [
        '쌀', '밥', '국수', '면', '파스타', '스파게티', '라면', '떡', '빵',
        '밀가루', '곡물', '보리', '현미', '잡곡'
    ]):
        return CategorizeIngredientResponse(category="곡류/쌀", confidence="high")
    
    # If pattern matching didn't work, use LLM
    try:
        from openai import OpenAI
        client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        
        system = """You are a Korean ingredient categorization system. Categorize ingredients into one of these four categories:
- "육류/단백질": Meat, poultry, fish, seafood, eggs, tofu, beans (protein sources)
- "채소": Vegetables, leafy greens, roots, mushrooms
- "곡류/쌀": Rice, grains, noodles, pasta, bread, flour
- "양념/소스": Seasonings, sauces, condiments, spices, oils, vinegars, MSG

Return ONLY the category name in Korean (one of the four above), nothing else."""
        
        user = f"Categorize this ingredient: {ingredient_name}"
        if original_category:
            user += f"\nOriginal category from recipe: {original_category}"
        
        resp = client.chat.completions.create(
            model=os.getenv("RECIPE_MODEL", "gpt-4o-mini"),
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user}
            ],
            temperature=0.1,
            max_tokens=20
        )
        
        result = resp.choices[0].message.content.strip()
        
        # Validate the result
        valid_categories = ["육류/단백질", "채소", "곡류/쌀", "양념/소스"]
        if result in valid_categories:
            return CategorizeIngredientResponse(category=result, confidence="medium")
        else:
            # Fallback: try to extract category from response
            for cat in valid_categories:
                if cat in result:
                    return CategorizeIngredientResponse(category=cat, confidence="low")
            # Final fallback
            return CategorizeIngredientResponse(category="양념/소스", confidence="low")
            
    except Exception as e:
        print(f"[ERROR] LLM categorization failed for '{ingredient_name}': {e}")
        # Fallback to default category based on original category
        if original_category == 'sauce_msg' or original_category == 'sub':
            return CategorizeIngredientResponse(category="양념/소스", confidence="low")
        else:
            return CategorizeIngredientResponse(category="양념/소스", confidence="low")
