import 'package:flutter/material.dart';
import 'range_training_page.dart';

/// תרגילי הפתעה - Surprise Drills Page (Using RangeTrainingPage in surprise mode)
/// 
/// This page provides IDENTICAL UI/UX to טווח קצר/טווח רחוק pages
/// The only differences are:
/// - Terminology: "עקרונות" instead of "מקצים"
/// - Data columns: 8 fixed principles instead of dynamic stations
/// - Scoring: 1-10 scale instead of hit/bullet tracking
/// - No shooting-specific fields (bullets, hits percentage)
class SurpriseDrillsPage extends StatelessWidget {
  const SurpriseDrillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect to RangeTrainingPage in surprise mode
    // This ensures IDENTICAL layout, fonts, spacing, and components
    return const RangeTrainingPage(
      rangeType: 'הפתעה',
      mode: 'surprise',
    );
  }
}
