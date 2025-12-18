import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Global Voice Assistant Widget - Fixed microphone button in AppBar
class VoiceAssistantButton extends StatefulWidget {
  final Function(String command) onVoiceCommand;

  const VoiceAssistantButton({super.key, required this.onVoiceCommand});

  @override
  State<VoiceAssistantButton> createState() => _VoiceAssistantButtonState();
}

class _VoiceAssistantButtonState extends State<VoiceAssistantButton> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isInitialized = false;
  bool _permissionRequested = false;
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // אין אתחול אוטומטי - רק בעת לחיצה על הכפתור
  }

  Future<void> _requestMicrophonePermission() async {
    debugPrint('mic button clicked');

    if (_isInitialized) {
      // כבר יש הרשאה - התחל האזנה ישירות
      await _startListening();
      return;
    }

    if (_permissionRequested) {
      // נסיון חוזר אחרי דחייה
      debugPrint('⚠️ Permission previously denied - retrying initialization');
    }

    try {
      debugPrint('microphone permission requested');
      _permissionRequested = true;

      // speech_to_text מבקש הרשאה אוטומטית ב-initialize
      _isInitialized = await _speech.initialize(
        onError: (error) {
          debugPrint('❌ Voice Assistant Error: ${error.errorMsg}');
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('שגיאה בזיהוי דיבור: ${error.errorMsg}'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              ),
            );
          }
        },
        onStatus: (status) {
          debugPrint('🔊 Voice Assistant Status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
            }
          }
        },
      );

      if (_isInitialized) {
        debugPrint('microphone permission granted');
        if (mounted) setState(() {});
        // התחל האזנה מיד לאחר הענקת ההרשאה
        await _startListening();
      } else {
        debugPrint('⚠️ Microphone permission denied or not available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('נא לאשר גישה למיקרופון בהגדרות הדפדפן'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Microphone Permission Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('העוזרת הקולית לא זמינה בדפדפן זה'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      debugPrint('⚠️ Cannot start listening - not initialized');
      // נסה לבקש הרשאה שוב
      await _requestMicrophonePermission();
      return;
    }

    debugPrint('speech recognition started');
    setState(() {
      _isListening = true;
      _currentText = '';
    });

    try {
      await _speech.listen(
        onResult: (result) {
          debugPrint(
            '📝 Recognized: "${result.recognizedWords}" (final: ${result.finalResult})',
          );
          setState(() {
            _currentText = result.recognizedWords;
          });

          // If final result, process command
          if (result.finalResult) {
            _processCommand(_currentText);
            _stopListening();
          }
        },
        localeId: 'he-IL', // Hebrew locale
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: true,
          partialResults: true,
        ),
      );
      debugPrint('✅ Listening active');
    } catch (e) {
      debugPrint('❌ Error starting listening: $e');
      setState(() => _isListening = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בהאזנה: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  void _processCommand(String command) {
    if (command.trim().isEmpty) {
      debugPrint('⚠️ Empty command received');
      return;
    }

    debugPrint('✨ Processing Voice Command: "$command"');
    widget.onVoiceCommand(command.trim());

    // Show visual feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('זיהיתי: "$command"'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: IconButton(
        icon: Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: _isListening
              ? Colors.red
              : (_isInitialized ? Colors.white : Colors.grey),
          size: 28,
        ),
        tooltip: _isListening
            ? 'לחץ להפסקה'
            : (_isInitialized
                  ? 'לחץ לדיבור (עברית)'
                  : 'לחץ לאישור גישה למיקרופון'),
        onPressed: _isListening ? _stopListening : _requestMicrophonePermission,
      ),
    );
  }
}

/// Voice Command Handler - Maps voice commands to actions per page
class VoiceCommandHandler {
  static void handleCommand(
    BuildContext context,
    String command,
    int currentPageIndex,
    Function(String) onFeedbackFilter,
    Function(String) onStatisticsFilter,
    Function(String) onExerciseAction,
    Function(String) onMaterialsAction,
    Function() onNavigateBack,
    Function(int) onNavigateToPage,
  ) {
    final lowerCommand = command.toLowerCase().trim();
    debugPrint(
      '🎯 Handling command: "$lowerCommand" on page $currentPageIndex',
    );

    // ========================
    // פקודות גלובליות (עובדות מכל דף)
    // ========================

    // חזור אחורה
    if (_matchIntent(lowerCommand, ['חזור', 'אחורה', 'חזרה'])) {
      debugPrint('🔙 Global: Navigate back');
      onNavigateBack();
      _showMessage(context, 'חוזר אחורה');
      return;
    }

    // לך לדף הבית
    if (_matchIntent(lowerCommand, ['דף הבית', 'בית', 'דף בית', 'לבית'])) {
      debugPrint('🏠 Global: Navigate to Home');
      onNavigateToPage(0);
      _showMessage(context, 'עובר לדף הבית');
      return;
    }

    // תראה לי את כל המשובים
    if (_matchIntent(lowerCommand, ['משובים', 'תראה משובים', 'כל המשובים'])) {
      debugPrint('📋 Global: Navigate to Feedbacks');
      onNavigateToPage(2);
      _showMessage(context, 'עובר לדף המשובים');
      return;
    }

    // פתח סטטיסטיקה / לך לסטטיסטיקות
    if (_matchIntent(lowerCommand, ['סטטיסטיקה', 'סטטיסטיקות', 'נתונים'])) {
      debugPrint('📊 Global: Navigate to Statistics');
      onNavigateToPage(3);
      _showMessage(context, 'עובר לסטטיסטיקות');
      return;
    }

    // חפש (גלובלי)
    if (_matchIntent(lowerCommand, ['חפש', 'חיפוש'])) {
      debugPrint('🔍 Global: Search command');
      _showMessage(context, 'חיפוש זמין בדף המשובים');
      return;
    }

    // ========================
    // פקודות ספציפיות לדף
    // ========================

    // Page 0: Home - no specific commands
    if (currentPageIndex == 0) {
      debugPrint('📍 Page 0 (Home) - using global commands only');
      _showMessage(context, 'נסה: "לך למשובים", "פתח סטטיסטיקה"');
      return;
    }

    // Page 1: Exercises
    if (currentPageIndex == 1) {
      _handleExercisesCommands(context, lowerCommand, onExerciseAction);
      return;
    }

    // Page 2: Feedbacks
    if (currentPageIndex == 2) {
      _handleFeedbacksCommands(
        context,
        lowerCommand,
        onFeedbackFilter,
        onNavigateBack,
      );
      return;
    }

    // Page 3: Statistics
    if (currentPageIndex == 3) {
      _handleStatisticsCommands(context, lowerCommand, onStatisticsFilter);
      return;
    }

    // Page 4: Materials
    if (currentPageIndex == 4) {
      _handleMaterialsCommands(context, lowerCommand, onMaterialsAction);
      return;
    }

    _showMessage(context, 'לא זוהתה פקודה');
  }

  /// Helper: Intent matching based on keywords
  static bool _matchIntent(String command, List<String> keywords) {
    return keywords.any((keyword) => command.contains(keyword));
  }

  /// Helper: Extract name/text after keyword
  static String? _extractParameter(String command, List<String> prefixes) {
    for (final prefix in prefixes) {
      final index = command.indexOf(prefix);
      if (index != -1) {
        final afterPrefix = command.substring(index + prefix.length).trim();
        if (afterPrefix.isNotEmpty) {
          return afterPrefix;
        }
      }
    }
    return null;
  }

  static void _handleExercisesCommands(
    BuildContext context,
    String command,
    Function(String) onAction,
  ) {
    debugPrint('📋 Processing exercises command: "$command"');
    // Exercise navigation commands
    if (command.contains('מעגל פתוח') || command.contains('פתח מעגל')) {
      debugPrint('✅ Opening מעגל פתוח');
      onAction('open_maagal_patuach');
      _showMessage(context, 'פותח תרגיל מעגל פתוח');
    } else if (command.contains('מעגל פרוץ') || command.contains('פרוץ')) {
      debugPrint('✅ Opening מעגל פרוץ');
      onAction('open_maagal_poruz');
      _showMessage(context, 'פותח תרגיל מעגל פרוץ');
    } else if (command.contains('סריקות') || command.contains('סריקת')) {
      debugPrint('✅ Opening סריקות רחוב');
      onAction('open_sarikot');
      _showMessage(context, 'פותח תרגיל סריקות רחוב');
    } else if (command.contains('מיונים') || command.contains('מדריכים')) {
      debugPrint('✅ Opening מיונים לקורס מדריכים');
      onAction('open_instructor_selection');
      _showMessage(context, 'פותח מיונים לקורס מדריכים');
    } else {
      debugPrint('⚠️ No matching exercise command');
      _showMessage(
        context,
        'הפקודה לא זמינה בדף זה. נסה: "מעגל פתוח", "מעגל פרוץ", "סריקות"',
      );
    }
  }

  static void _handleFeedbacksCommands(
    BuildContext context,
    String command,
    Function(String) onFilter,
    Function() onNavigateBack,
  ) {
    debugPrint('📝 Processing feedbacks command: "$command"');

    // ========================
    // דף משובים – ניווט וחיפוש
    // ========================

    // כנס למשוב / פתח משוב
    if (_matchIntent(command, ['כנס למשוב', 'פתח משוב', 'כנס לפידבק'])) {
      debugPrint('✅ Intent: Open feedback');
      onFilter('action_open_feedback');
      _showMessage(context, 'פותח משוב');
      return;
    }

    // חפש משוב של {שם} / תראה לי משוב של {שם}
    if (_matchIntent(command, ['חפש משוב', 'תראה משוב', 'משוב של'])) {
      final name = _extractParameter(command, ['של ', 'משוב ']);
      if (name != null) {
        debugPrint('✅ Intent: Search feedback for: $name');
        onFilter('search_feedback_$name');
        _showMessage(context, 'מחפש משוב של $name');
      } else {
        debugPrint('⚠️ No name provided for feedback search');
        _showMessage(context, 'אנא ציין שם לחיפוש, למשל: "חפש משוב של יוסי"');
      }
      return;
    }

    // כנס למשוב האחרון
    if (_matchIntent(command, ['משוב אחרון', 'אחרון', 'למשוב האחרון'])) {
      debugPrint('✅ Intent: Open last feedback');
      onFilter('action_open_last_feedback');
      _showMessage(context, 'פותח משוב אחרון');
      return;
    }

    // כנס למשוב הראשון
    if (_matchIntent(command, ['משוב ראשון', 'ראשון', 'למשוב הראשון'])) {
      debugPrint('✅ Intent: Open first feedback');
      onFilter('action_open_first_feedback');
      _showMessage(context, 'פותח משוב ראשון');
      return;
    }

    // סגור משוב
    if (_matchIntent(command, ['סגור משוב', 'סגור', 'חזור מהמשוב'])) {
      debugPrint('✅ Intent: Close feedback');
      onNavigateBack();
      _showMessage(context, 'סוגר משוב');
      return;
    }

    // Existing filtering commands
    if (command.contains('סנן') ||
        command.contains('הצג') ||
        command.contains('פתח תרגיל')) {
      if (command.contains('מעגל פתוח')) {
        debugPrint('✅ Filtering by מעגל פתוח');
        onFilter('filter_maagal_patuach');
        _showMessage(context, 'מסנן משובי מעגל פתוח');
      } else if (command.contains('מעגל פרוץ') || command.contains('פרוץ')) {
        debugPrint('✅ Filtering by מעגל פרוץ');
        onFilter('filter_maagal_poruz');
        _showMessage(context, 'מסנן משובי מעגל פרוץ');
      } else if (command.contains('סריקות')) {
        debugPrint('✅ Filtering by סריקות רחוב');
        onFilter('filter_sarikot');
        _showMessage(context, 'מסנן משובי סריקות רחוב');
      } else if (command.contains('מיונים') || command.contains('מדריכים')) {
        debugPrint('✅ Filtering by מיונים');
        onFilter('filter_instructor_course');
        _showMessage(context, 'מסנן מיונים לקורס מדריכים');
      } else if (command.contains('כללי')) {
        debugPrint('✅ Filtering by כללי');
        onFilter('filter_general');
        _showMessage(context, 'מסנן משובים כלליים');
      } else {
        debugPrint('⚠️ No matching filter keyword');
        _showMessage(context, 'לא זוהתה פקודת סינון. נסה: "סנן מעגל פתוח"');
      }
    } else {
      debugPrint('⚠️ No recognized command');
      _showMessage(
        context,
        'נסה: "כנס למשוב", "חפש משוב של שם", "סנן מעגל פתוח"',
      );
    }
  }

  static void _handleStatisticsCommands(
    BuildContext context,
    String command,
    Function(String) onFilter,
  ) {
    debugPrint('📊 Processing statistics command: "$command"');

    // ========================
    // סטטיסטיקות – חישובים
    // ========================

    // כמה משובים יש (סך הכל)
    if (_matchIntent(command, [
      'כמה משובים',
      'סך משובים',
      'סך כל',
      'כמות משובים',
    ])) {
      debugPrint('✅ Intent: Count all feedbacks');
      onFilter('action_count_feedbacks');
      _showMessage(context, 'מחשב סך משובים');
      return;
    }

    // כמה משובים יש לקורס מדריכים
    if (_matchIntent(command, ['כמה משובים']) &&
        _matchIntent(command, ['מדריכים', 'קורס'])) {
      debugPrint('✅ Intent: Count instructor course feedbacks');
      onFilter('action_count_instructor_feedbacks');
      _showMessage(context, 'מחשב משובי קורס מדריכים');
      return;
    }

    // כמה משובים יש בתרגיל הזה
    if (_matchIntent(command, ['כמה משובים']) &&
        _matchIntent(command, ['תרגיל', 'תקריאה'])) {
      debugPrint('✅ Intent: Count exercise feedbacks');
      onFilter('action_count_exercise_feedbacks');
      _showMessage(context, 'מחשב משובים לתרגיל הנוכחי');
      return;
    }

    // ========================
    // סטטיסטיקות – סינונים
    // ========================

    // אפס סינונים / תראה לי את כל הנתונים
    if (_matchIntent(command, ['אפס', 'נקה סינון', 'כל הנתונים', 'הכל'])) {
      debugPrint('✅ Intent: Clear all filters');
      onFilter('action_clear_filters');
      _showMessage(context, 'מאפס סינונים');
      return;
    }

    // סנן לפי קורס / קורס מדריכים
    if (_matchIntent(command, [
      'סנן לפי קורס',
      'קורס מדריכים',
      'מיונים מדריכים',
    ])) {
      debugPrint('✅ Intent: Filter by instructor course');
      onFilter('folder_mioonim_madrichim');
      _showMessage(context, 'מסנן לפי קורס מדריכים');
      return;
    }

    // סנן לפי תרגיל / תקריאה
    if (_matchIntent(command, ['סנן לפי תרגיל', 'סנן לפי תקריאה', 'תרגיל'])) {
      debugPrint('✅ Intent: Filter by exercise (need specific exercise name)');
      _showMessage(context, 'אנא ציין תרגיל: מעגל פתוח, מעגל פרוץ, או סריקות');
      return;
    }

    // סנן לפי תאריך
    if (_matchIntent(command, ['סנן לפי תאריך', 'תאריך', 'תקופה'])) {
      debugPrint('✅ Intent: Filter by date');
      onFilter('action_filter_by_date');
      _showMessage(context, 'פתח סינון תאריך');
      return;
    }

    // Existing detailed filtering commands
    if (command.contains('סנן') ||
        command.contains('הצג') ||
        command.contains('סטטיסטיקה')) {
      if (command.contains('תיקיית') || command.contains('תיקייה')) {
        if (command.contains('מטווחים') || command.contains('ירי')) {
          onFilter('folder_matawhim');
          _showMessage(context, 'מסנן לפי מטווחי ירי');
        } else if (command.contains('חטיבה') || command.contains('הגנה')) {
          onFilter('folder_hativah');
          _showMessage(context, 'מסנן לפי מחלקות ההגנה');
        } else if (command.contains('במבנה') || command.contains('בניין')) {
          onFilter('folder_binyan');
          _showMessage(context, 'מסנן לפי עבודה במבנה');
        } else if (command.contains('מיונים') && command.contains('מדריכים')) {
          onFilter('folder_mioonim_madrichim');
          _showMessage(context, 'מסנן לפי מיונים לקורס מדריכים');
        } else if (command.contains('מיונים')) {
          onFilter('folder_mioonim');
          _showMessage(context, 'מסנן לפי מיונים כללי');
        } else if (command.contains('משובים') || command.contains('כללי')) {
          onFilter('folder_general');
          _showMessage(context, 'מסנן לפי משובים כלליים');
        } else {
          _showMessage(context, 'ציין שם תיקייה מדויק');
        }
      } else if (command.contains('תרגיל')) {
        if (command.contains('מעגל פתוח') || command.contains('פתוח')) {
          onFilter('exercise_maagal_patuach');
          _showMessage(context, 'מסנן לפי מעגל פתוח');
        } else if (command.contains('מעגל פרוץ') || command.contains('פרוץ')) {
          onFilter('exercise_maagal_poruz');
          _showMessage(context, 'מסנן לפי מעגל פרוץ');
        } else if (command.contains('סריקות')) {
          onFilter('exercise_sarikot');
          _showMessage(context, 'מסנן לפי סריקות רחוב');
        } else {
          _showMessage(context, 'ציין שם תרגיל');
        }
      } else if (command.contains('יישוב')) {
        final settlement = _extractParameter(command, ['יישוב ', 'ב', 'של ']);
        if (settlement != null) {
          onFilter('settlement_$settlement');
          _showMessage(context, 'מסנן לפי יישוב: $settlement');
        } else {
          _showMessage(context, 'אנא ציין שם יישוב');
        }
      } else if (command.contains('תפקיד')) {
        onFilter('filter_by_role');
        _showMessage(context, 'סינון לפי תפקיד');
      } else {
        _showMessage(context, 'לא זוהתה פקודת סינון');
      }
    } else {
      _showMessage(
        context,
        'נסה: "כמה משובים יש", "סנן לפי קורס", "אפס סינונים"',
      );
    }
  }

  static void _handleMaterialsCommands(
    BuildContext context,
    String command,
    Function(String) onAction,
  ) {
    // Materials navigation commands
    if (command.contains('פתח') || command.contains('הצג')) {
      if (command.contains('מעגל פתוח')) {
        onAction('open_maagal_patuach');
        _showMessage(context, 'פותח חומר עיוני - מעגל פתוח');
      } else if (command.contains('פרוץ')) {
        onAction('open_maagal_poruz');
        _showMessage(context, 'פותח חומר עיוני - מעגל פרוץ');
      } else if (command.contains('סריקות')) {
        onAction('open_sarikot');
        _showMessage(context, 'פותח חומר עיוני - סריקות רחוב');
      } else if (command.contains('עקרונות') || command.contains('לחימה')) {
        onAction('open_sheva');
        _showMessage(context, 'פותח שבע עקרונות לחימה');
      } else if (command.contains('סעבל') || command.contains('עדיפויות')) {
        onAction('open_saabal');
        _showMessage(context, 'פותח סעב"ל');
      } else {
        _showMessage(context, 'לא זוהה חומר עיוני');
      }
    } else {
      _showMessage(context, 'הפקודה לא זמינה בדף זה');
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }
}
