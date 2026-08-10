import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The one search control, in both of the forms the app needs.
///
/// The library shows a *read-only* one that opens the Search tab, and Search
/// shows the real one. Two widgets would guarantee they drifted apart in shape,
/// hint and radius, and the whole point of the library's version is that it
/// looks like the field you are about to land on.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    required this.hintText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.hasText = false,
    super.key,
  });

  /// A read-only field that only reports taps.
  ///
  /// Rendered as a field rather than as a button because that is what it
  /// becomes: tapping it lands on Search with the same pill in the same place.
  const AppSearchField.button({
    required this.hintText,
    required VoidCallback this.onTap,
    super.key,
  }) : controller = null,
       focusNode = null,
       onChanged = null,
       onSubmitted = null,
       onClear = null,
       readOnly = true,
       autofocus = false,
       hasText = false;

  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;

  /// Drives the clear button. Passed in rather than read off the controller so
  /// the field does not have to listen to it — the screens that own a query
  /// already rebuild when it changes.
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      // The library's pill is a button wearing a field's clothes. Left
      // focusable it takes a caret on tap and holds focus after the Search tab
      // has opened, which leaves a blinking cursor on a screen the user is no
      // longer looking at.
      canRequestFocus: !readOnly,
      autofocus: autofocus,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        // The library's pill must not read as an active input waiting for a
        // keyboard that is not coming.
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        suffixIcon: !hasText
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        // Fully rounded, unlike every other field in the app. A search box is
        // the one input people look for by silhouette rather than by reading
        // its label.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}
