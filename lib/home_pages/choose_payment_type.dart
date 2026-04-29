// ignore_for_file: unused_field, unused_local_variable, dead_code

import 'dart:async';

import 'package:card_app/nfc_prompt_bottom_sheet.dart';
import 'package:card_app/transfer/bank_transfer_page.dart';
import 'package:card_app/transfer/tag_transfer.dart';
import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:card_app/wifi_payment/wifi_payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChoosePaymentTypeBottomSheet extends StatefulWidget {
  final Map<String, dynamic> card;
  const ChoosePaymentTypeBottomSheet({super.key, required this.card});
  @override
  State<ChoosePaymentTypeBottomSheet> createState() =>
      _ChoosePaymentTypeBottomSheetState();
}

class _ChoosePaymentTypeBottomSheetState
    extends State<ChoosePaymentTypeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  String? _nfcStatus = 'checking';
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
    _checkNfcAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkNfcAvailability() async {
    try {
      final bool isAvailable = await NfcManager.instance.isAvailable();
      setState(() {
        _nfcStatus = isAvailable ? 'available' : 'disabled';
      });
    } catch (e) {
      if (e is PlatformException && e.code == 'not_supported') {
        setState(() {
          _nfcStatus = 'unsupported';
        });
      } else {
        setState(() {
          _nfcStatus = 'error';
        });
      }
    }
  }

  void _showScanPromptBottomSheet(BuildContext ctx, Map<String, dynamic> card) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (context) =>
          const DevicesListScreen(deviceType: DeviceType.browser),
    );
  }

  /// Shows the privacy consent sheet the first time the user accesses a
  /// sensitive feature. The [action] receives a valid root context to use
  /// for showing subsequent bottom sheets after this sheet has been closed.
  Future<void> _requirePrivacyConsent(
    PermissionType type,
    String prefKey,
    void Function(BuildContext rootCtx) action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool(prefKey) ?? false;
    if (alreadyConsented) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close this bottom sheet
      final rootCtx = navigatorKey.currentContext!;
      action(rootCtx);
      return;
    }
    // Show consent on top of this sheet using the root navigator context so
    // that this sheet's context stays valid inside onContinue.
    final rootCtx = navigatorKey.currentContext!;
    await showModalBottomSheet(
      context: rootCtx,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: type,
        onContinue: () async {
          await prefs.setBool(prefKey, true);
          if (!mounted) return;
          Navigator.of(context).pop(); // close this bottom sheet
          final newCtx = navigatorKey.currentContext!;
          action(newCtx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Payment Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, TagTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.tag,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                          
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, BankTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via bank transfer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use bank transfer to send money to a previous or new recipient',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),

                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, TagTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via tag/username',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use tag/username to send money to a PadiPay user',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.nfc,
                          'privacy_consent_nfc',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            builder: (context) => const NFCPromptBottomSheet(),
                            isScrollControlled: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.touch_app,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tap to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Make payments instantly using your phone\'s NFC chip.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => _showScanPromptBottomSheet(rootCtx, widget.card),
                        );
                      },
                      onLongPress: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            isScrollControlled: true,
                            builder: (context) => const DevicesListScreen(
                              deviceType: DeviceType.advertiser,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.wifi,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scan to Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Send or receive money instantly through a secure Wi-Fi connection.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChooseTransferTypeBottomSheet extends StatefulWidget {
  const ChooseTransferTypeBottomSheet({super.key});
  @override
  State<ChooseTransferTypeBottomSheet> createState() =>
      _ChooseTransferTypeBottomSheetState();
}

class _ChooseTransferTypeBottomSheetState
    extends State<ChooseTransferTypeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  String? _nfcStatus = 'checking';
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
    _checkNfcAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkNfcAvailability() async {
    try {
      final bool isAvailable = await NfcManager.instance.isAvailable();
      setState(() {
        _nfcStatus = isAvailable ? 'available' : 'disabled';
      });
    } catch (e) {
      if (e is PlatformException && e.code == 'not_supported') {
        setState(() {
          _nfcStatus = 'unsupported';
        });
      } else {
        setState(() {
          _nfcStatus = 'error';
        });
      }
    }
  }

  void _showScanPromptBottomSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (context) =>
          const DevicesListScreen(deviceType: DeviceType.browser),
    );
  }

  Future<void> _requirePrivacyConsent(
    PermissionType type,
    String prefKey,
    void Function(BuildContext rootCtx) action,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyConsented = prefs.getBool(prefKey) ?? false;
    if (alreadyConsented) {
      if (!mounted) return;
      Navigator.of(context).pop();
      final rootCtx = navigatorKey.currentContext!;
      action(rootCtx);
      return;
    }
    final rootCtx = navigatorKey.currentContext!;
    await showModalBottomSheet(
      context: rootCtx,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: type,
        onContinue: () async {
          await prefs.setBool(prefKey, true);
          if (!mounted) return;
          Navigator.of(context).pop();
          final newCtx = navigatorKey.currentContext!;
          action(newCtx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Payment Type',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, TagTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.tag,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via tag/username',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use tag/username to send money to a PadiPay user',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        // TODO: Implement bank transfer
                        navigateTo(context, BankTransferPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.account_balance,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send via bank transfer',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Use bank transfer to send money to a previous or new recipient',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.nfc,
                          'privacy_consent_nfc',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            builder: (context) =>
                                const NFCPromptBottomSheet(isReader: true),
                            isScrollControlled: true,
                          ),
                        );
                      },
                      onLongPress: () {
                        _requirePrivacyConsent(
                          PermissionType.nfc,
                          'privacy_consent_nfc',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            builder: (context) =>
                                const NFCPromptBottomSheet(isReader: false),
                            isScrollControlled: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.touch_app,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Tap to Pay',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        "Watch Tutorial",
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontSize: 12,
                                          decoration: TextDecoration.underline,
                                          decorationColor: primaryColor
                                        ),
                                      ),
                                    ],
                                  ),SizedBox(height: 5,),
                                  Text(
                                    'Make payments instantly using your phone\'s NFC chip.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => _showScanPromptBottomSheet(rootCtx),
                        );
                      },
                      onLongPress: () {
                        _requirePrivacyConsent(
                          PermissionType.wifiPayment,
                          'privacy_consent_wifi_payment',
                          (rootCtx) => showModalBottomSheet(
                            context: rootCtx,
                            isScrollControlled: true,
                            builder: (context) => const DevicesListScreen(
                              deviceType: DeviceType.advertiser,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.wifi,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Scan to Pay',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),Text(
                                        "Watch Tutorial",
                                        style: TextStyle(
                                          color: primaryColor,
                                          fontSize: 12,
                                          decoration: TextDecoration.underline,
                                          decorationColor: primaryColor
                                        ),
                                      ),
                                    ],
                                  ),SizedBox(height: 5,),
                                  Text(
                                    'Send or receive money instantly through a secure Wi-Fi connection.',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

