import 'package:flutter/material.dart';
import 'package:fieldlog_mobile/app_typography.dart';
import '../services/link_service.dart';
import '../theme/app_colors.dart';

class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => LinkService.openUrl(LinkService.privacyPolicyUrl),
        style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
        child: Text(
          'Privacy policy',
          style: AppTypography.textStyle(
            fontSize: 13,
            color: AppColors.textTertiary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
