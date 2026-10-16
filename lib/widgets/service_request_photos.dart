import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'local_link_image.dart';

class ServiceRequestPhotoStrip extends StatelessWidget {
  const ServiceRequestPhotoStrip({
    super.key,
    required this.imageUrls,
    this.compact = false,
    this.title = 'Photos',
  });

  final List<String> imageUrls;
  final bool compact;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    final height = compact ? 74.0 : 108.0;
    final width = compact ? 98.0 : 144.0;

    return Column(
      key: const ValueKey('service-request-photo-strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final url = imageUrls[index];
              return InkWell(
                key: ValueKey('service-request-photo-$index'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => showServiceRequestPhotoViewer(
                  context,
                  imageUrls,
                  initialIndex: index,
                ),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: LocalLinkImage(
                    imageUrl: url,
                    aspectRatio: width / height,
                    fallbackIcon: Icons.image_not_supported_outlined,
                    accentColor: AppColors.serviceGreen,
                    semanticLabel: 'Service request photo',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ServiceRequestPhotoPreview extends StatelessWidget {
  const ServiceRequestPhotoPreview({super.key, required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return InkWell(
      key: const ValueKey('service-request-photo-preview'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showServiceRequestPhotoViewer(context, imageUrls),
      child: SizedBox(
        width: 82,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LocalLinkImage(
              imageUrl: imageUrls.first,
              aspectRatio: 82 / 72,
              fallbackIcon: Icons.image_not_supported_outlined,
              accentColor: AppColors.serviceGreen,
              semanticLabel: 'Service request photo preview',
            ),
            if (imageUrls.length > 1)
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.charcoal.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      '+${imageUrls.length - 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void showServiceRequestPhotoViewer(
  BuildContext context,
  List<String> imageUrls, {
  int initialIndex = 0,
}) {
  if (imageUrls.isEmpty) return;

  showDialog<void>(
    context: context,
    builder: (context) {
      final controller = PageController(initialPage: initialIndex);
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return Center(
                  child: InteractiveViewer(
                    child: LocalLinkImage(
                      imageUrl: imageUrls[index],
                      aspectRatio: 1,
                      fallbackIcon: Icons.image_not_supported_outlined,
                      accentColor: AppColors.serviceGreen,
                      semanticLabel: 'Service request photo',
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      );
    },
  );
}
