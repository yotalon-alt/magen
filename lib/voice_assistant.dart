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
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      debugPrint('🎤 Initializing Voice Assistant...');
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
        debugPrint('✅ Voice Assistant initialized successfully');
      } else {
        debugPrint('⚠️ Voice Assistant initialization returned false');
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ Voice Assistant Initialization Failed: $e');
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('העוזרת הקולית אינה זמינה. נסה לרענן את הדף.'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ),
      );
      return;
    }

    debugPrint('🎤 Starting to listen...');
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
      debugPrint('✅ Listening started');
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
            : (_isInitialized ? 'לחץ לדיבור (עברית)' : 'העוזרת לא זמינה'),
        onPressed: _isInitialized
            ? (_isListening ? _stopListening : _startListening)
            : null,
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
  ) {
    final lowerCommand = command.toLowerCase().trim();
    debugPrint(
      '🎯 Handling command: "$lowerCommand" on page $currentPageIndex',
    );

    // Page 0: Home - no voice commands
    if (currentPageIndex == 0) {
      debugPrint('📍 Page 0 (Home) - no commands available');
      _showMessage(context, 'אין פקודות קוליות זמינות בדף הבית');
      return;
    }

    // Page 1: Exercises
    if (currentPageIndex == 1) {
      _handleExercisesCommands(context, lowerCommand, onExerciseAction);
      return;
    }

    // Page 2: Feedbacks
    if (currentPageIndex == 2) {
      _handleFeedbacksCommands(context, lowerCommand, onFeedbackFilter);
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
  ) {
    debugPrint('📝 Processing feedbacks command: "$command"');
    // Feedback filtering commands
    if (command.contains('סנן') ||
        command.contains('הצג') ||
        command.contains('פתח')) {
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
      debugPrint('⚠️ No action verb found');
      _showMessage(context, 'הפקודה לא זמינה בדף זה. נסה: "סנן" או "הצג"');
    }
  }

  static void _handleStatisticsCommands(
    BuildContext context,
    String command,
    Function(String) onFilter,
  ) {
    debugPrint('📊 Processing statistics command: "$command"');
    // Statistics filtering commands
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
        // User needs to say the settlement name
        _showMessage(context, 'אנא ציין שם יישוב');
      } else if (command.contains('תפקיד')) {
        onFilter('filter_by_role');
        _showMessage(context, 'סינון לפי תפקיד');
      } else {
        _showMessage(context, 'לא זוהתה פקודת סינון');
      }
    } else {
      _showMessage(context, 'הפקודה לא זמינה בדף זה');
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
