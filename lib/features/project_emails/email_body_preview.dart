import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'email_document.dart';

class EmailBodyPreview extends StatelessWidget {
  final String body;
  final Uint8List productsImage;
  const EmailBodyPreview({super.key, required this.body, required this.productsImage});

  @override
  Widget build(BuildContext context) {
    final parts = emailBodyWithProductsImage(body).split(productsImageMarker);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < parts.length; i++) ...[
        if (parts[i].isNotEmpty) SelectableText(parts[i]),
        if (i < parts.length - 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.memory(productsImage,
                key: i == 0 ? const ValueKey('email-products-image-preview') : null,
                height: 220, fit: BoxFit.contain),
          ),
      ],
    ]);
  }
}
