import 'package:flutter/material.dart';

/// Widget מרכזי לשדה שם חניך - מחליט אוטומטית אם להציג autocomplete
///
/// משתמש ב-autocomplete רק עבור:
/// - מטווחים 474
/// - תרגילי הפתעה 474
/// - סיכום אימון 474
///
/// עבור כל השאר - TextField רגיל
class TraineeNameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final List<String> autocompleteOptions;
  final bool enableAutocomplete;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;

  const TraineeNameField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autocompleteOptions = const [],
    this.enableAutocomplete = false,
    this.textAlign = TextAlign.center,
    this.style,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDecoration =
        decoration ??
        const InputDecoration(
          hintText: 'שם',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        );

    final effectiveStyle = style ?? const TextStyle(fontSize: 12);

    // אם autocomplete מופעל ויש אופציות - השתמש ב-Autocomplete
    if (enableAutocomplete && autocompleteOptions.isNotEmpty) {
      return Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return autocompleteOptions;
          }
          return autocompleteOptions.where((name) {
            return name.contains(textEditingValue.text);
          });
        },
        onSelected: (String selection) {
          controller.text = selection;
          if (onChanged != null) {
            onChanged!(selection);
          }
        },
        fieldViewBuilder:
            (context, fieldController, fieldFocusNode, onFieldSubmitted) {
              // Sync controllers
              if (fieldController.text.isEmpty && controller.text.isNotEmpty) {
                fieldController.text = controller.text;
              }
              fieldController.addListener(() {
                controller.text = fieldController.text;
              });

              return TextField(
                controller: fieldController,
                focusNode: fieldFocusNode,
                decoration: effectiveDecoration,
                textAlign: textAlign,
                style: effectiveStyle,
                maxLines: 1,
                onChanged: onChanged,
                onSubmitted: (v) {
                  onFieldSubmitted();
                  if (onSubmitted != null) {
                    onSubmitted!(v);
                  }
                },
              );
            },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topRight,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 250,
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(
                        option,
                        style: const TextStyle(fontSize: 13),
                        textAlign: TextAlign.right,
                      ),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

    // אם לא - TextField רגיל
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: effectiveDecoration,
      textAlign: textAlign,
      style: effectiveStyle,
      maxLines: 1,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
