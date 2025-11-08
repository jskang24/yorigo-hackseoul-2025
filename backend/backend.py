# app.py
import os, json, tempfile, subprocess, hashlib, re
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, HttpUrl
import yt_dlp
import ffmpeg
from faster_whisper import WhisperModel
from rapidfuzz import process, fuzz
from dotenv import load_dotenv

load_dotenv() 

app = FastAPI(title="Yorigo Backend")

### ---------- Models ----------
class ParseRequest(BaseModel):
    url: HttpUrl
    prefer_lang: Optional[str] = None  # e.g., "ko" or "en"

class Ingredient(BaseModel):
    qty: Optional[float] = None
    unit: Optional[str] = None
    item: str
    notes: Optional[str] = None

class Step(BaseModel):
    order: int
    instruction: str
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

### ---------- Helpers ----------
def url_hash(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()[:16]

def extract_with_ytdlp(url: str) -> Dict[str, Any]:
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
    return info

def download_audio(url: str, outdir: str) -> str:
    target = os.path.join(outdir, "audio.m4a")
    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": os.path.join(outdir, "a.%(ext)s"),
        "quiet": True,
        "postprocessors": [{"key": "FFmpegExtractAudio", "preferredcodec": "m4a"}],
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([url])
    # Find resulting file
    for fname in os.listdir(outdir):
        if fname.endswith(".m4a"):
            return os.path.join(outdir, fname)
    raise RuntimeError("Audio download failed")

def get_youtube_transcript(info: Dict[str, Any]) -> Optional[str]:
    # If yt-dlp found subtitles, try to fetch the best language track
    subs = info.get("subtitles") or info.get("automatic_captions") or {}
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
                            return vtt_to_text(r.text)
                    except Exception:
                        pass
    return None

def vtt_to_text(vtt: str) -> str:
    lines = []
    for line in vtt.splitlines():
        if re.match(r"^\d{2}:\d{2}:\d{2}\.\d{3} -->", line): 
            continue
        if line.strip() and not line.startswith("WEBVTT"):
            lines.append(line.strip())
    return " ".join(lines)

def transcribe(audio_path: str, prefer_lang: Optional[str]) -> str:
    model = get_whisper()
    segments, info = model.transcribe(audio_path, language=prefer_lang, vad_filter=True)
    return " ".join(seg.text.strip() for seg in segments if seg.text)

def sample_frames_to_tmp(video_url: str, outdir: str, fps: float = 0.3) -> List[str]:
    # yt-dlp can also give us a direct URL; but easiest path:
    # Reuse the downloaded audio’s dir; also fetch a light mp4
    mp4_path = os.path.join(outdir, "video.mp4")
    ydl_opts = {
        "format": "mp4[height<=480]/best",
        "outtmpl": mp4_path,
        "quiet": True,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([video_url])
    img_dir = os.path.join(outdir, "frames")
    os.makedirs(img_dir, exist_ok=True)
    # Extract frames
    (
        ffmpeg
        .input(mp4_path)
        .filter("fps", fps=fps)   # ~1 frame every ~3.3s if fps=0.3
        .output(os.path.join(img_dir, "frame_%05d.jpg"), vsync=0, loglevel="error")
        .run()
    )
    return [os.path.join(img_dir, f) for f in sorted(os.listdir(img_dir)) if f.endswith(".jpg")]

def ocr_frames(paths: List[str]) -> str:
    try:
        import easyocr
        reader = easyocr.Reader(["en","ko"])  # add more if needed
        texts = []
        for p in paths:
            result = reader.readtext(p, detail=0, paragraph=True)
            if result: texts.append(" ".join(result))
        return " ".join(texts)
    except Exception:
        return ""

def normalize_units(text: str) -> str:
    # very light normalization example
    return (text
            .replace("½","0.5").replace("¼","0.25").replace("¾","0.75")
            .replace("tablespoons","tbsp").replace("tablespoon","tbsp")
            .replace("teaspoons","tsp").replace("teaspoon","tsp"))

### ---------- LLM: structure the recipe ----------
def call_llm_to_structure(transcript_text: str, ocr_text: str, title: str, description: str = "") -> Dict[str, Any]:
    content = normalize_units(f"{title}\n\nDESCRIPTION:\n{description}\n\nTRANSCRIPT:\n{transcript_text}\n\nON-SCREEN TEXT:\n{ocr_text}")
    system = """You extract COOKING RECIPES from noisy transcripts with MAXIMUM PRECISION.

CRITICAL REQUIREMENTS:
1. EVERY ingredient MUST have a specific quantity (qty) - NEVER use null
2. EVERY ingredient MUST have a unit - NEVER use null
3. If exact amounts aren't stated, make REASONABLE estimates based on:
   - Standard recipe proportions
   - Servings mentioned
   - Visual cues from on-screen text
   - Context from the cooking process
4. Be as precise as possible with measurements

Return STRICT JSON with keys: recipe {name, servings, ingredients[], steps[], equipment[], notes[], nutrition{} }.

Ingredient fields (ALL REQUIRED):
- qty: number (NEVER null, estimate if needed)
- unit: string (NEVER null, use: g, kg, ml, l, tsp, tbsp, cup, piece, clove, etc.)
- item: string (specific ingredient name)
- notes: string or null (preparation notes like "chopped", "minced")

Step fields:
- order: int
- instruction: string (detailed, clear)
- est_minutes: int or null
- tools: string[] or null

Nutrition fields (calculate based on ingredients):
- calories_per_serving: number
- protein_g: number
- fat_g: number
- carbs_g: number
- sodium_mg: number

Equipment: string[] (all tools/equipment needed)
Notes: string[] (cooking tips, substitutions, storage)

Estimate missing servings reasonably from context (default to 4 if unclear)."""
    
    user = f"Extract a complete, precise recipe from this content. EVERY ingredient must have qty and unit. Output JSON only."
    
    # Example using OpenAI; replace as needed
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
    text = resp.choices[0].message.content.strip()
    # Ensure JSON:
    start = text.find("{")
    end = text.rfind("}")
    js = json.loads(text[start:end+1])
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
        structured = call_llm_to_structure(transcript, ocr_text, title, description)
        recipe = structured.get("recipe") or structured  # tolerate models that skip top-level key

        # Nutrition - extract LLM's nutrition estimate if provided
        servings = recipe.get("servings") or 1
        llm_nutrition = structured.get("nutrition") or recipe.get("nutrition")
        nutrition = estimate_nutrition(recipe.get("ingredients", []), servings, llm_nutrition)

        return ParseResponse(
            source={"url": str(req.url), "platform": platform, "title": title, "duration_sec": duration},
            recipe=Recipe(**recipe),
            nutrition=nutrition,
            debug={"used_captions": used_captions, "used_asr": not used_captions, "used_ocr": used_ocr, "has_description": bool(description)}
        )
