import 'package:flutter/material.dart';

class FullScreenPhoto extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenPhoto({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Black background for photo viewer
      backgroundColor: Colors.black,
      // Add close button at the top
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // Make the body interactive for zooming/panning
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Hero(
            tag: heroTag,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child:
                      Icon(Icons.error_outline, size: 40, color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
