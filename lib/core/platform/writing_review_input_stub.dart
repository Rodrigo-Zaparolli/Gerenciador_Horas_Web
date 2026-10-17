import 'package:flutter/material.dart';

Widget writingReviewInput(
        {required String text,
        required ValueChanged<String> onChanged,
        required Color foreground,
        required Color background}) =>
    TextFormField(
      initialValue: text,
      onChanged: onChanged,
      maxLines: null,
      expands: true,
      autocorrect: true,
      enableSuggestions: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
    );
