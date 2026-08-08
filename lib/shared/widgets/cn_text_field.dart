import 'package:flutter/material.dart';

class CnTextField extends StatelessWidget {
  const CnTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.enabled = true,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final bool enabled;

  /// iOS/Android autofill hints — e.g. [AutofillHints.email],
  /// [AutofillHints.password], [AutofillHints.newPassword].
  final Iterable<String>? autofillHints;

  /// Keyboard action button (e.g. [TextInputAction.next], [TextInputAction.done]).
  final TextInputAction? textInputAction;

  /// Called when user taps the keyboard action button.
  final ValueChanged<String>? onSubmitted;

  final FocusNode? focusNode;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      focusNode: focusNode,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffix,
      ),
    );
  }
}
