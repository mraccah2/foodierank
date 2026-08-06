import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../models/restaurant.dart';
import '../services/proxy_service.dart';
import '../theme/app_spacing.dart';
import 'package:flutter/services.dart';

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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<String> _loadPhoto(String photoRef) async {
    if (_loadedPhotos.containsKey(photoRef)) {
      return _loadedPhotos[photoRef]!;
    }

    final photoUrl = await ProxyService.getPlacePhoto(
      photoRef,
      1200, // width
      800, // height
    );

    if (photoUrl.isNotEmpty) {
      _loadedPhotos[photoRef] = photoUrl;
    }
    return photoUrl;
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: orientation == Orientation.portrait
              ? AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                  // The gallery is always on black, so this bar is the one
                  // place white is the right answer in both schemes.
                  title: Text(
                    '${_currentIndex + 1} / ${widget.restaurant.photoRefs.length}',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: Colors.white),
                  ),
                )
              : null,
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
                          future:
                              _loadPhoto(widget.restaurant.photoRefs[index]),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return PhotoView(
                                // Cached on disk, so reopening the gallery — or
                                // swiping back to a photo — does not re-download
                                // a full-size image. A bare NetworkImage kept
                                // only the decoded frame, and only until the
                                // image cache evicted it.
                                imageProvider:
                                    CachedNetworkImageProvider(snapshot.data!),
                                minScale: PhotoViewComputedScale.contained,
                                maxScale: PhotoViewComputedScale.covered * 2,
                                scaleStateController:
                                    PhotoViewScaleStateController(),
                              );
                            }
                            return const Center(
                                child: CircularProgressIndicator());
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
              if (orientation == Orientation.portrait) ...[
                if (_currentIndex > 0)
                  Positioned(
                    left: AppSpacing.lg,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavArrow(
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Previous photo',
                        onTap: () => _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                      ),
                    ),
                  ),
                if (_currentIndex < widget.restaurant.photoRefs.length - 1)
                  Positioned(
                    right: AppSpacing.lg,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _NavArrow(
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Next photo',
                        onTap: () => _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A circular step-through control.
///
/// These were the literal text characters `<` and `>` set in the body font at
/// 24pt — which is why they sat slightly high in their circles and went
/// noticeably lopsided at large text scales.
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _NavArrow({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppSpacing.minTouch,
            height: AppSpacing.minTouch,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
