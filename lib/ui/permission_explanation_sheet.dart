import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

enum PermissionType { location, notification, bluetooth, nfc, wifiPayment, camera, gallery }

class PermissionExplanationSheet extends StatelessWidget {
  final PermissionType type;
  final VoidCallback onContinue;

  const PermissionExplanationSheet({
    super.key,
    required this.type,
    required this.onContinue,
  });

  static const _privacyPolicyUrl = 'https://padipay.co/privacy-policy';

  bool get _showsPrivacyPolicy =>
      type == PermissionType.nfc ||
      type == PermissionType.wifiPayment ||
      type == PermissionType.camera ||
      type == PermissionType.gallery;

  String get _title {
    switch (type) {
      case PermissionType.location:
        return 'Location Permission Required';
      case PermissionType.notification:
        return 'Notification Permission Required';
      case PermissionType.bluetooth:
        return 'Nearby/Bluetooth Permission Required';
      case PermissionType.nfc:
        return 'NFC & Data Privacy Notice';
      case PermissionType.wifiPayment:
        return 'WiFi Payment & Data Privacy Notice';
      case PermissionType.camera:
        return 'Camera Permission Required';
      case PermissionType.gallery:
        return 'Photo Library Permission Required';
    }
  }

  String get _description {
    switch (type) {
      case PermissionType.location:
        return 'We need access to your location to help autofill your address and provide location-based services. Your location data is only used to enhance your experience.';
      case PermissionType.notification:
        return 'We need permission to send you notifications about important account activity, security alerts, and updates. You can control notification preferences in your settings.';
      case PermissionType.bluetooth:
        return 'We need access to Bluetooth and nearby device permissions to enable secure device-to-device transfers and connections. This is only used for WiFi/Bluetooth-based payments and transfers.';
      case PermissionType.nfc:
        return 'Tap to Pay uses your device\'s NFC chip to securely exchange payment data with nearby devices. No personal data is stored or shared beyond what is needed to complete the transaction. By continuing, you agree to our data handling practices.';
      case PermissionType.wifiPayment:
        return 'Scan to Pay uses Wi-Fi and nearby device discovery to establish a secure local connection for payments. Your device\'s location and Bluetooth permissions are required for this feature. No personal data is shared with third parties beyond what is needed to complete the transaction. By continuing, you agree to our data handling practices.';
      case PermissionType.camera:
        return 'We need camera access to let you take photos for identity verification or profile updates. Photos are only used for the purpose you initiate and are not shared without your consent.';
      case PermissionType.gallery:
        return 'We need access to your photo library so you can upload images for identity verification, profile photos, or document uploads. Images are only used for the purpose you initiate and are not shared without your consent.';
    }
  }

  IconData get _icon {
    switch (type) {
      case PermissionType.location:
        return Icons.location_on;
      case PermissionType.notification:
        return Icons.notifications_active;
      case PermissionType.bluetooth:
        return Icons.bluetooth;
      case PermissionType.nfc:
        return Icons.tap_and_play;
      case PermissionType.wifiPayment:
        return Icons.wifi;
      case PermissionType.camera:
        return Icons.camera_alt;
      case PermissionType.gallery:
        return Icons.photo_library;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 48, color: Theme.of(context).primaryColor),
          const SizedBox(height: 16),
          Text(
            _title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            _description,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (_showsPrivacyPolicy) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(_privacyPolicyUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                'View Privacy Policy',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.7)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Not Now',
                    style: GoogleFonts.inter(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onContinue();
                  },
                  child: Text(
                    _showsPrivacyPolicy ? 'I Understand' : 'Allow Access',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
