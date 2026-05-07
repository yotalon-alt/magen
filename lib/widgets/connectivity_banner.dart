import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// פס אזהרה אדום שמוצג כשאין חיבור לאינטרנט.
/// עוטף את ה-child ולא משפיע על הפריסה שלו.
///
/// שימוש:
/// ```dart
/// ConnectivityBanner(child: Scaffold(...))
/// ```
class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  Future<void> _checkInitial() async {
    final results = await Connectivity().checkConnectivity();
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (mounted && offline != _isOffline) {
      setState(() => _isOffline = offline);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isOffline)
          Material(
            color: Colors.red.shade700,
            child: const SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'אין חיבור לאינטרנט — הנתונים נשמרים מקומית',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
