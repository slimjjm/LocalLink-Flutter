import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class BookingServiceSummary extends StatelessWidget {
  final String serviceName;
  final String price;
  final dynamic durationMinutes;

  const BookingServiceSummary({
    super.key,
    required this.serviceName,
    required this.price,
    required this.durationMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final durationText =
        durationMinutes == null ? null : '${durationMinutes.toString()} mins';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            durationText == null ? price : '$price • $durationText',
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class StaffSelector extends StatelessWidget {
  final String businessId;
  final String? selectedStaffId;
  final ValueChanged<String> onSelected;

  const StaffSelector({
    super.key,
    required this.businessId,
    required this.selectedStaffId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .collection('staff')
           .where('isActive', isEqualTo: true)
.orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Staff error: ${snapshot.error}'),
            );
          }

          final staff = snapshot.data?.docs ?? [];

          if (staff.isEmpty) {
            return const Center(
              child: Text('No active staff available'),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: staff.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final data = (staff[index].data() as Map<String, dynamic>?) ?? {};
              final staffId = staff[index].id;
              final name = safeText(data['name'], 'Staff');
              final isSelected = selectedStaffId == staffId;

              return ChoiceChip(
                selected: isSelected,
                label: Text(name),
                onSelected: (_) => onSelected(staffId),
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SlotSelector extends StatelessWidget {
  final String businessId;
  final String? selectedStaffId;
  final String? selectedSlotId;
  final ValueChanged<String> onSelected;

  const SlotSelector({
    super.key,
    required this.businessId,
    required this.selectedStaffId,
    required this.selectedSlotId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedStaffId == null) {
      return const Center(
        child: Text('Select staff first'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
    .collection('businesses')
    .doc(businessId)
    .collection('staff')
    .doc(selectedStaffId)
    .collection('availableSlots')
    .where('isBooked', isEqualTo: false)
    .where('startTime', isGreaterThan: Timestamp.now())
    .orderBy('startTime')
    .snapshots()
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Slot error: ${snapshot.error}'),
          );
        }

        final slots = snapshot.data?.docs ?? [];

        if (slots.isEmpty) {
          return const Center(
            child: Text('No slots available'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: slots.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = (slots[index].data() as Map<String, dynamic>?) ?? {};
            final slotId = slots[index].id;
            final isSelected = selectedSlotId == slotId;

            return Card(
              elevation: isSelected ? 3 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isSelected ? Colors.orange : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ListTile(
                title: Text(formatSlotTime(data['startTime'])),
                subtitle: data['endTime'] == null
                    ? null
                    : Text('Ends ${formatSlotTime(data['endTime'])}'),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.orange)
                    : const Icon(Icons.circle_outlined),
                onTap: () => onSelected(slotId),
              ),
            );
          },
        );
      },
    );
  }
}

class PaymentMethodSelector extends StatelessWidget {
  final List<String> paymentMethods;
  final String? selectedPaymentMethod;
  final ValueChanged<String> onChanged;

  const PaymentMethodSelector({
    super.key,
    required this.paymentMethods,
    required this.selectedPaymentMethod,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (paymentMethods.length <= 1) {
      final method = paymentMethods.isEmpty ? 'cash' : paymentMethods.first;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.payment),
            const SizedBox(width: 8),
            Text(
              method == 'stripe' ? 'Payment: Card' : 'Payment: Cash',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          const Text(
            'Payment:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          ...paymentMethods.map((method) {
            final isSelected = selectedPaymentMethod == method;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: isSelected,
                label: Text(method == 'stripe' ? 'Card' : 'Cash'),
                selectedColor: Colors.orange,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                ),
                onSelected: (_) => onChanged(method),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ConfirmBookingButton extends StatelessWidget {
  final bool isLoading;
  final bool enabled;
  final VoidCallback onPressed;

  const ConfirmBookingButton({
    super.key,
    required this.isLoading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm Booking',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}