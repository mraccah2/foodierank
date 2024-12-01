import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models/restaurant.dart';
import '../services/proxy_service.dart';

class RestaurantPhotoViewer extends StatefulWidget {
  final Restaurant restaurant;
  final int initialIndex;

  const RestaurantPhotoViewer({
    super.key,
    required this.restaurant,
    this.initialIndex = 0,
  });

  @override
  State<RestaurantPhotoViewer> createState() => _RestaurantPhotoViewerState();
}

class _RestaurantPhotoViewerState extends State<RestaurantPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<String, String> _loadedPhotos = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _loadPhoto(String photoRef) async {
    if (_loadedPhotos.containsKey(photoRef)) {
      return _loadedPhotos[photoRef]!;
    }
    
    final photoUrl = await ProxyService.getPlacePhoto(
      photoRef,
      1200, // width
      800,  // height
    );
    
    if (photoUrl.isNotEmpty) {
      _loadedPhotos[photoRef] = photoUrl;
    }
    return photoUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1}/${widget.restaurant.photoRefs.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: widget.restaurant.photoRefs.length,
              builder: (context, index) {
                return PhotoViewGalleryPageOptions.customChild(
                  child: GestureDetector(
                    onTap: () {},
                    child: FutureBuilder<String>(
                      future: _loadPhoto(widget.restaurant.photoRefs[index]),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                          return PhotoView(
                            imageProvider: NetworkImage(snapshot.data!),
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 2,
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                );
              },
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
            ),
          ),
          if (_currentIndex > 0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '<',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          if (_currentIndex < widget.restaurant.photoRefs.length - 1)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '>',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
} 