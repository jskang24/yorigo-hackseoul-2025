import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/recipe_service.dart';
import '../models/recipe_models.dart' as models;

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({super.key});

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final RecipeService _recipeService = RecipeService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _isLoading = false;
  bool _isParsing = false; // Track if we're in the middle of parsing
  String _currentStage = '';
  double _currentProgress = 0.0;

  @override
  void dispose() {
    print(
      '[Frontend] AddRecipeScreen disposing (isParsing=$_isParsing, isLoading=$_isLoading)',
    );
    if (_isParsing) {
      print('[Frontend] WARNING: Disposing while parsing is in progress!');
    }
    _urlController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    print('[Frontend] AddRecipeScreen initialized');
  }

  Future<void> _handleSubmit() async {
    final l10n = AppLocalizations.of(context);
    if (_urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.enterYouTubeUrl ?? '유튜브 URL을 입력해주세요')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isParsing = true;
    });

    // Collapse the sheet when loading starts
    Future.microtask(() {
      if (mounted) {
        try {
          _sheetController.animateTo(
            0.5, // minChildSize
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } catch (e) {
          // Controller might not be attached yet, ignore
          print('Error collapsing sheet: $e');
        }
      }
    });

    final recipeUrl = _urlController.text.trim();
    models.ParseResponse? parseResponse;
    String? recipeId;

    try {
      // First, check if the user already has this recipe saved
      final existingUserRecipeId = await _recipeService
          .getUserRecipeIdBySourceUrl(recipeUrl);
      if (existingUserRecipeId != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미 저장된 레시피입니다'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          // Navigate to the existing recipe
          final existingRecipe = await _recipeService.getRecipeById(
            existingUserRecipeId,
          );
          if (existingRecipe != null && mounted) {
            Navigator.pushNamed(
              context,
              '/recipe-detail',
              arguments: {
                'parseResponse': existingRecipe,
                'recipeId': existingUserRecipeId,
              },
            );
          }
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Check if this recipe already exists in Firebase (any user)
      final existingRecipeData = await _recipeService.getRecipeBySourceUrl(
        recipeUrl,
      );
      if (existingRecipeData != null) {
        // Recipe exists, use existing data instead of parsing
        parseResponse = await _recipeService.getParseResponseFromRecipeData(
          existingRecipeData,
        );
        recipeId = existingRecipeData['id'] as String?;

        if (parseResponse != null) {
          // Save the recipe for the current user (if not already saved)
          try {
            recipeId = await _recipeService.saveRecipe(
              parseResponse: parseResponse,
              sourceUrl: recipeUrl,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('레시피가 저장되었습니다'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            // If it's a duplicate error, that's fine - user already has it
            if (!e.toString().contains('이미 저장된 레시피입니다')) {
              print('Error saving recipe to Firebase: $e');
            }
            // Use the existing recipe ID if save failed
            recipeId = existingRecipeData['id'] as String?;
          }

          // Navigate to recipe detail screen
          if (mounted) {
            Navigator.pushNamed(
              context,
              '/recipe-detail',
              arguments: recipeId != null
                  ? {'parseResponse': parseResponse, 'recipeId': recipeId}
                  : parseResponse,
            );
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // Recipe doesn't exist, proceed with parsing
      // Update state to show inline progress
      setState(() {
        _currentStage = '영상 분석중';
        _currentProgress = 0.0;
      });

      // Always parse recipes in Korean since the app primarily targets Koreans
      // Language settings only control the UI language, not recipe parsing
      const preferLang = 'ko';

      print('[Frontend] Starting recipe parsing stream...');
      // Stream the parsing progress
      final stream = ApiService.parseRecipeStream(
        url: recipeUrl,
        preferLang: preferLang,
      );

      await for (var event in stream) {
        // Check mounted status periodically
        if (!mounted) {
          print('[Frontend] WARNING: Widget unmounted during stream, stopping');
          return;
        }

        final stage = event['stage'] as String?;
        final progress = (event['progress'] as num?)?.toDouble() ?? 0.0;

        print(
          '[Frontend] Received event: stage=$stage, progress=$progress, mounted=$mounted',
        );

        if (stage == 'result') {
          // Final result received
          print('[Frontend] Received final result, parsing...');
          final data = event['data'] as Map<String, dynamic>;
          parseResponse = models.ParseResponse.fromJson(data);
          print('[Frontend] ParseResponse created successfully');
          break;
        } else if (stage == 'error') {
          // Error occurred
          print('[Frontend] Error received: ${event['error']}');
          throw Exception(event['error'] ?? 'Unknown error');
        } else if (stage != null) {
          // Update progress (including 'complete' stage)
          print(
            '[Frontend] Updating progress: $stage - ${progress.toStringAsFixed(0)}%',
          );

          // Update the UI via setState
          if (mounted) {
            setState(() {
              _currentStage = stage;
              _currentProgress = progress;
            });
          }
        }
      }

      print('[Frontend] Stream completed, processing results...');
      print('[Frontend] Checking mounted state: $mounted');
      print('[Frontend] Checking _isParsing state: $_isParsing');

      // Check mounted state first
      if (!mounted) {
        print('[Frontend] ERROR: Widget not mounted after stream completion!');
        return;
      }

      print('[Frontend] Widget is mounted, processing...');

      if (parseResponse == null) {
        print('[Frontend] ERROR: parseResponse is null');
        throw Exception('No response data received');
      }

      print('[Frontend] ParseResponse received: ${parseResponse.recipe.name}');
      print('[Frontend] Saving recipe to Firebase...');

      // Save recipe to Firebase
      try {
        recipeId = await _recipeService.saveRecipe(
          parseResponse: parseResponse,
          sourceUrl: recipeUrl,
        );
        print('[Frontend] Recipe saved successfully with ID: $recipeId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('레시피가 저장되었습니다'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // Log error but don't block navigation
        print('[Frontend] Error saving recipe to Firebase: $e');
        // Show a warning but still navigate
        if (mounted) {
          final errorMessage = e.toString().contains('logged in')
              ? '레시피를 저장하려면 로그인이 필요합니다'
              : e.toString().contains('이미 저장된 레시피입니다')
              ? '이미 저장된 레시피입니다'
              : '레시피를 저장하는 중 오류가 발생했습니다: $e';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // Navigate to recipe detail screen with the parsed recipe data
      print('[Frontend] Navigating to recipe detail screen...');
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/recipe-detail',
          arguments: recipeId != null
              ? {'parseResponse': parseResponse, 'recipeId': recipeId}
              : parseResponse,
        );
        print('[Frontend] Navigation initiated');
      }
    } catch (e, stackTrace) {
      print('[Frontend] ERROR: $e');
      print('[Frontend] Stack trace: $stackTrace');

      if (!mounted) {
        print('[Frontend] Widget not mounted during error handling');
        return;
      }

      // Try to close dialog if it's still open
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {
        // Dialog might already be closed
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        print('[Frontend] Cleaning up, setting _isLoading = false');
        setState(() {
          _isLoading = false;
          _isParsing = false;
        });
        print('[Frontend] Cleanup complete');
      } else {
        print('[Frontend] WARNING: Cannot cleanup - widget not mounted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WillPopScope(
      onWillPop: () async {
        // Prevent back button dismissal during parsing
        if (_isParsing) {
          print('[Frontend] Back button pressed during parsing - blocked');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('레시피 분석 중에는 뒤로 갈 수 없습니다'),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        return true;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final brightness = Theme.of(context).brightness;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.getBackground(brightness),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Show inline progress when parsing
                      if (_isParsing) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Yorigo icon
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Image.asset(
                                  'assets/Yorigo_icon_light.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 32),
                              // Progress indicator
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 120,
                                    height: 120,
                                    child: CircularProgressIndicator(
                                      value: _currentProgress / 100,
                                      strokeWidth: 8,
                                      backgroundColor:
                                          AppColors.getBackgroundTertiary(
                                            brightness,
                                          ),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            AppColors.primary,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '${_currentProgress.toInt()}%',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.getTextPrimary(
                                        brightness,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Current stage
                              Text(
                                _currentStage,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.getTextPrimary(brightness),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '잠시만 기다려주세요...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.getTextSecondary(brightness),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Show input form when not parsing
                      return SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 40,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Main Icon and Title
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Image.asset(
                                  'assets/Yorigo_icon_light.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                l10n?.appName ?? '요리고',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors
                                      .primary, // Primary color is same for both themes
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n?.homeSubtitle ??
                                    '유튜브 쇼츠 요리 영상을 공유하고\n재료·조리법을 자동으로 분석하세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.getTextSecondary(brightness),
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 40),

                              // Input Section
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.getBackgroundTertiary(
                                    brightness,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.link_outlined,
                                      size: 20,
                                      color: AppColors.getTextTertiary(
                                        brightness,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _urlController,
                                        decoration: InputDecoration(
                                          hintText:
                                              l10n?.youtubeUrlPlaceholder ??
                                              '유튜브 또는 인스타그램 영상 링크',
                                          hintStyle: TextStyle(
                                            color: AppColors.getTextTertiary(
                                              brightness,
                                            ),
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 12,
                                              ),
                                        ),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.getTextPrimary(
                                            brightness,
                                          ),
                                        ),
                                        keyboardType: TextInputType.url,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => _handleSubmit(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  disabledBackgroundColor: const Color(
                                    0xFFFFB380,
                                  ),
                                  minimumSize: const Size(double.infinity, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _isLoading
                                      ? (l10n?.analyzing ?? '분석 중...')
                                      : (l10n?.analyze ?? '레시피 분석하기'),
                                  style: TextStyle(
                                    color: AppColors.getBackground(brightness),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
