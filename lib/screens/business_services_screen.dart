import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/helpers.dart';
import 'add_service_screen.dart';
import 'post_availability_screen.dart';

class BusinessServicesScreen extends StatelessWidget {
  final String businessId;

  const BusinessServicesScreen({super.key, required this.businessId});

  Future<void> _openEditor(
    BuildContext context, {
    String? serviceId,
    Map<String, dynamic>? service,
  }) async {
    final result = await Navigator.push<AddServiceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddServiceScreen(
          businessId: businessId,
          serviceId: serviceId,
          existingService: service,
        ),
      ),
    );

    if (!context.mounted) return;

    if (result?.nextStep == AddServiceNextStep.shareNow) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostAvailabilityScreen(
            businessId: result!.businessId,
            initialServiceId: result.serviceId,
          ),
        ),
      );
    }
  }

  Future<void> _toggleArchived(
    BuildContext context, {
    required String serviceId,
    required bool isActive,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final willArchive = isActive;

    try {
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .collection('services')
          .doc(serviceId)
          .update({'isActive': !isActive});

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            willArchive
                ? 'Service hidden. People will not see it when booking.'
                : 'Service is live again.',
          ),
        ),
      );
    } on FirebaseException catch (error) {
      final message = error.code == 'permission-denied'
          ? 'We could not update this service because your Page access needs refreshing. Please ask the owner to check your access.'
          : 'We could not update that service just now. Please try again.';

      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deleteService(
    BuildContext context, {
    required String serviceId,
    required String serviceName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete service?'),
          content: Text(
            'Delete "$serviceName" from your Page? Existing bookings will stay in your records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .collection('services')
          .doc(serviceId)
          .delete();

      messenger.showSnackBar(
        const SnackBar(content: Text('Service deleted from your Page.')),
      );
    } on FirebaseException catch (error) {
      final message = error.code == 'permission-denied'
          ? 'We could not delete this service because your Page access needs refreshing.'
          : 'We could not delete that service just now. Please try again.';

      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Services'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.serviceGreen,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .collection('services')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ServicesLoading();
          }

          if (snapshot.hasError) {
            return _ServicesMessage(
              icon: Icons.error_outline_rounded,
              title: 'We could not load your services',
              message: 'Please check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () {},
            );
          }

          final services = snapshot.data?.docs ?? [];

          if (services.isEmpty) {
            return _ServicesMessage(
              icon: Icons.handshake_outlined,
              title: 'Add your first service',
              message:
                  'Services are what people can book from your Page. Add one before sharing available time.',
              actionLabel: 'Add service',
              onAction: () => _openEditor(context),
            );
          }

          final activeCount = services.where((doc) {
            final data = doc.data();
            return data['isActive'] != false;
          }).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            children: [
              _ServicesHeader(
                activeCount: activeCount,
                totalCount: services.length,
              ),
              const SizedBox(height: 16),
              ...services.map((doc) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ServiceCard(
                    service: doc.data(),
                    onEdit: () => _openEditor(
                      context,
                      serviceId: doc.id,
                      service: doc.data(),
                    ),
                    onArchive: () => _toggleArchived(
                      context,
                      serviceId: doc.id,
                      isActive: doc.data()['isActive'] != false,
                    ),
                    onDelete: () => _deleteService(
                      context,
                      serviceId: doc.id,
                      serviceName: safeText(doc.data()['name'], 'this service'),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ServicesHeader extends StatelessWidget {
  final int activeCount;
  final int totalCount;

  const _ServicesHeader({required this.activeCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.serviceGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.design_services_outlined,
              color: AppColors.serviceGreen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your bookable services',
                  style: TextStyle(
                    color: AppColors.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$activeCount active of $totalCount total. Active services appear when you share available time.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _ServiceCard({
    required this.service,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = safeText(service['name'], 'Service');
    final details = safeText(service['details'], '');
    final price = formatPrice(service['price']);
    final duration = service['durationMinutes'];
    final imageUrl = safeText(service['imageUrl'], '');
    final isActive = service['isActive'] != false;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceThumbnail(imageUrl: imageUrl, isActive: isActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.charcoal,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ServiceStatusChip(isActive: isActive),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$price${duration == null ? '' : ' • $duration mins'}',
                      style: const TextStyle(
                        color: AppColors.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                        TextButton.icon(
                          onPressed: onArchive,
                          icon: Icon(
                            isActive
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          label: Text(isActive ? 'Hide' : 'Show'),
                        ),
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceStatusChip extends StatelessWidget {
  final bool isActive;

  const _ServiceStatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? 'Active' : 'Hidden',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ServiceThumbnail extends StatelessWidget {
  final String imageUrl;
  final bool isActive;

  const _ServiceThumbnail({required this.imageUrl, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final opacity = isActive ? 1.0 : 0.45;

    if (imageUrl.trim().isEmpty) {
      return Opacity(
        opacity: opacity,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.handshake_outlined,
            color: AppColors.serviceGreen,
          ),
        ),
      );
    }

    return Opacity(
      opacity: opacity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 54,
              height: 54,
              color: AppColors.surface,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppColors.textMuted,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ServicesLoading extends StatelessWidget {
  const _ServicesLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 14),
            Text(
              'Loading your services...',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _ServicesMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.serviceGreen),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
