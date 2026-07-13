import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/opportunity_map_view.dart';

class OpportunityMapScreen extends StatelessWidget {
  const OpportunityMapScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: OpportunityMapView(),
            ),

            Positioned(
              top: 12,
              left: 16,
              child: Material(
                color: Colors.white,
                elevation: 6,
                borderRadius:
                    BorderRadius.circular(18),
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(18),
                  onTap: () {
                    Navigator.pop(context);
                  },
                  child: const Padding(
                    padding:
                        EdgeInsets.all(12),
                    child: Icon(
                      Icons.arrow_back,
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