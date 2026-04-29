import 'dart:io' show Platform;

import 'package:card_app/utils.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:cloudcard_flutter/cloudcard_flutter.dart';
// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet that walks a user through registering their virtual card
/// for NFC tap-to-pay at physical POS terminals.
///
/// Flow:
///  1. Check device support, NFC enabled, default payment app.
///  2. Call `sudoDigitalizeCard` Cloud Function to get the JWT token.
///  3. Register the card with [CloudCardFlutter.registerCard].
///  4. Prompt user to set the app as default payment app if needed.
class NfcPosSheet extends StatefulWidget {
  /// The Sudo card ID (card_id from Firestore card document).
  final String cardId;

  /// Optional card details for display (cardholder name, last-four, etc.).
  final String? cardholderName;
  final String? lastFour;
  final String? expiryDate;

  const NfcPosSheet({
    super.key,
    required this.cardId,
    this.cardholderName,
    this.lastFour,
    this.expiryDate,
  });

  @override
  State<NfcPosSheet> createState() => _NfcPosSheetState();
}

class _NfcPosSheetState extends State<NfcPosSheet> {
  final _cloudCard = CloudCardFlutter();

  _Step _step = _Step.checking;
  String? _errorMessage;

  // Health-check results
  bool? _deviceSupported;
  bool? _nfcEnabled;
  bool? _isDefaultApp;

  String _firstStringForKeys(dynamic node, Set<String> targetKeys) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString().toLowerCase();
        final value = entry.value;
        if (targetKeys.contains(key) && value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      for (final value in node.values) {
        final found = _firstStringForKeys(value, targetKeys);
        if (found.isNotEmpty) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _firstStringForKeys(value, targetKeys);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }

  Future<String> _getOrCreatePaymentAppInstanceId() async {
    const key = 'cloudcard_payment_app_instance_id';
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final generated = const Uuid().v4();
    await prefs.setString(key, generated);
    return generated;
  }

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    if (!Platform.isAndroid) {
      setState(() {
        _step = _Step.unsupportedPlatform;
      });
      return;
    }

    setState(() => _step = _Step.checking);

    try {
      final supported = await _cloudCard.isDeviceSupported();
      final nfcEnabled = await _cloudCard.isNfcEnabled();
      final isDefault = await _cloudCard.isDefaultPaymentApp();

      if (mounted) {
        setState(() {
          _deviceSupported = supported;
          _nfcEnabled = nfcEnabled;
          _isDefaultApp = isDefault;

          if (supported != true) {
            _step = _Step.deviceNotSupported;
          } else if (nfcEnabled != true) {
            _step = _Step.nfcDisabled;
          } else {
            _step = _Step.readyToRegister;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _Step.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _registerCard() async {
    setState(() => _step = _Step.registering);

    try {
      // 1. Fetch the digitalization payload from the backend.
      final callable = cf.FirebaseFunctions.instance.httpsCallable(
        'sudoDigitalizeCard',
      );
      final response = await callable.call({
        'cardId': widget.cardId,
        'platform': 'android',
      });

      // The Cloud Function should return { walletId, paymentAppInstanceId,
      // accountId, jwtToken } — or a plain JWT string if the backend wraps it.
      final data = response.data;
      var walletId = '';
      var paymentAppInstanceId = '';
      var accountId = '';
      var jwtToken = '';
      var secret = '';
      final accountIdCandidates = <String>[];

      if (data is Map) {
        final map = Map<String, dynamic>.from(data as Map);
        // Support both flat and nested { data: { ... } } structures.
        final inner = (map['data'] is Map)
            ? Map<String, dynamic>.from(map['data'] as Map)
            : map;
        walletId = _firstStringForKeys(inner, {
          'walletid',
          'wallet_id',
        });
        paymentAppInstanceId = _firstStringForKeys(inner, {
          'paymentappinstanceid',
          'payment_app_instance_id',
          'paymentappinstance_id',
        });
        accountId = _firstStringForKeys(inner, {
          'accountid',
          'account_id',
          'cardid',
          'card_id',
        });
        jwtToken = _firstStringForKeys(inner, {
          'jwttoken',
          'jwt_token',
          'token',
          'onboardingtoken',
          'onboarding_token',
          'digitalizationtoken',
          'digitalization_token',
        });
        secret = _firstStringForKeys(inner, {
          'secret',
        });

        final candidatesRaw = inner['accountIdCandidates'];
        if (candidatesRaw is List) {
          for (final item in candidatesRaw) {
            final v = item.toString().trim();
            if (v.isNotEmpty && !accountIdCandidates.contains(v)) {
              accountIdCandidates.add(v);
            }
          }
        }
      } else {
        // Fallback: treat raw string response as the JWT token.
        jwtToken = data.toString();
        walletId = '';
        paymentAppInstanceId = '';
        accountId = widget.cardId;
        secret = '';
      }

        final resolvedAccountId = accountId.isEmpty ? widget.cardId : accountId;
        final originalAccountId = widget.cardId;
      final resolvedPaymentAppInstanceId = paymentAppInstanceId.isEmpty
          ? await _getOrCreatePaymentAppInstanceId()
          : paymentAppInstanceId;

      if (!accountIdCandidates.contains(resolvedAccountId)) {
        accountIdCandidates.insert(0, resolvedAccountId);
      }
      if (!accountIdCandidates.contains(originalAccountId)) {
        accountIdCandidates.add(originalAccountId);
      }

      debugPrint(
        '[CloudCard] digitalize parsed keys: '
        'walletId=${walletId.isNotEmpty} '
        'paymentAppInstanceId=${resolvedPaymentAppInstanceId.isNotEmpty} '
        'accountId=$resolvedAccountId '
        'candidateCount=${accountIdCandidates.length} '
        'jwtTokenLen=${jwtToken.length} '
        'secretLen=${secret.length}',
      );

      if (jwtToken.isEmpty) {
        throw Exception(
          'Digitalization token is empty. '
          'Check that your sudoDigitalizeCard Cloud Function returns '
          'jwtToken/onboardingToken/token in its payload.',
        );
      }

      if (walletId.isEmpty) {
        throw Exception('Digitalization payload missing walletId.');
      }

      Future<CCResult> registerOnce({
        required String attemptAccountId,
        required bool includeSecret,
      }) {
        final registrationData = RegistrationData(
          walletId: walletId,
          paymentAppInstanceId: resolvedPaymentAppInstanceId,
          accountId: attemptAccountId,
          jwtToken: jwtToken,
          secret: includeSecret ? secret : '',
        );
        debugPrint(
          '[CloudCard] registerCard attempt accountId=$attemptAccountId includeSecret=$includeSecret '
          'secretLen=${includeSecret ? secret.length : 0}',
        );
        return _cloudCard.registerCard(registrationData);
      }

      // 2. Register the card with the Sudo Cloud Card SDK.
      // Iterate all candidate IDs with secret first, then without secret.
      CCResult? lastResult;
      Future<bool> tryMode(bool includeSecret) async {
        for (final candidate in accountIdCandidates) {
          final result = await registerOnce(
            attemptAccountId: candidate,
            includeSecret: includeSecret,
          );
          lastResult = result;
          if (result.status == Status.SUCCESS) {
            return true;
          }
        }
        return false;
      }

      var success = await tryMode(secret.isNotEmpty);
      if (!success && secret.isNotEmpty) {
        debugPrint('[CloudCard] retrying all candidate IDs without secret');
        success = await tryMode(false);
      }

      final result = lastResult;
      if (result == null) {
        throw Exception('CloudCard registration did not return a result.');
      }

      debugPrint('[CloudCard] registerCard result: status=${result.status} message=${result.message}');

      if (!mounted) return;

      if (result.status == Status.SUCCESS) {
        setState(() => _step = _Step.success);
      } else {
        setState(() {
          _step = _Step.error;
          _errorMessage = result.message;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('[CloudCard] PlatformException code=${e.code} message=${e.message} details=${e.details}');
      if (mounted) {
        setState(() {
          _step = _Step.error;
          _errorMessage = 'CloudCard SDK error: ${e.message ?? e.code}';
        });
      }
    } catch (e) {
      debugPrint('[CloudCard] register flow error: $e');
      if (mounted) {
        setState(() {
          _step = _Step.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _openDefaultPaymentSettings() async {
    await _cloudCard.launchDefaultPaymentAppSettings();
    // Re-check after the user returns from settings.
    await _runChecks();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_step) {
      case _Step.unsupportedPlatform:
        return _MessageView(
          icon: Icons.smartphone_outlined,
          iconColor: Colors.orange,
          title: 'Android Only',
          message:
              'NFC tap-to-pay at POS terminals is currently supported on Android devices only.',
          actions: [_closeButton(context)],
        );

      case _Step.deviceNotSupported:
        return _MessageView(
          icon: Icons.nfc_outlined,
          iconColor: Colors.red,
          title: 'Device Not Supported',
          message:
              'Your device does not meet the requirements for NFC tap-to-pay. '
              'An NFC-enabled Android phone with API level 21+ is required.',
          actions: [_closeButton(context)],
        );

      case _Step.nfcDisabled:
        return _MessageView(
          icon: Icons.nfc_outlined,
          iconColor: Colors.orange,
          title: 'NFC Is Off',
          message:
              'Please enable NFC in your device settings to use tap-to-pay.',
          actions: [
            ElevatedButton(
              onPressed: () async {
                await _cloudCard.launchDefaultPaymentAppSettings();
                await _runChecks();
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Open NFC Settings',
                  style: TextStyle(color: Colors.white)),
            ),
            _closeButton(context),
          ],
        );

      case _Step.checking:
        return const _LoadingView(message: 'Checking device compatibility…');

      case _Step.registering:
        return const _LoadingView(message: 'Setting up your card for tap-to-pay…');

      case _Step.readyToRegister:
        return _ReadyView(
          cardholderName: widget.cardholderName,
          lastFour: widget.lastFour,
          isDefaultApp: _isDefaultApp ?? false,
          onSetupTap: _registerCard,
          onDefaultPaymentTap: _openDefaultPaymentSettings,
          onClose: () => Navigator.pop(context),
        );

      case _Step.success:
        return _SuccessView(
          isDefaultApp: _isDefaultApp ?? false,
          onSetDefaultTap: _openDefaultPaymentSettings,
          onClose: () => Navigator.pop(context),
        );

      case _Step.error:
        return _MessageView(
          icon: Icons.error_outline,
          iconColor: Colors.red,
          title: 'Something Went Wrong',
          message: _errorMessage ?? 'An unknown error occurred.',
          actions: [
            ElevatedButton(
              onPressed: _runChecks,
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child:
                  const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
            _closeButton(context),
          ],
        );
    }
  }

  Widget _closeButton(BuildContext context) => TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      );
}

// ---------------------------------------------------------------------------
// Sub-step enum
// ---------------------------------------------------------------------------

enum _Step {
  checking,
  unsupportedPlatform,
  deviceNotSupported,
  nfcDisabled,
  readyToRegister,
  registering,
  success,
  error,
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        const CircularProgressIndicator(color: primaryColor),
        const SizedBox(height: 24),
        Text(
          message,
          style: const TextStyle(fontSize: 16, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;

  const _MessageView({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        ...actions.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(width: double.infinity, child: a),
            )),
      ],
    );
  }
}

class _ReadyView extends StatelessWidget {
  final String? cardholderName;
  final String? lastFour;
  final bool isDefaultApp;
  final VoidCallback onSetupTap;
  final VoidCallback onDefaultPaymentTap;
  final VoidCallback onClose;

  const _ReadyView({
    required this.cardholderName,
    required this.lastFour,
    required this.isDefaultApp,
    required this.onSetupTap,
    required this.onDefaultPaymentTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 20),
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Center(
          child: Icon(Icons.contactless_outlined, size: 64, color: primaryColor),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Set Up Tap-to-Pay',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            cardholderName != null && lastFour != null
                ? 'Card ending in $lastFour will be enabled for NFC\npayments at any contactless POS terminal.'
                : 'Your virtual card will be enabled for NFC\npayments at any contactless POS terminal.',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        if (!isDefaultApp) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For tap-to-pay to work, Padi Pay must be set as your default payment app.',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDefaultPaymentTap,
              child: const Text('Set as Default Payment App'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onSetupTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Enable Tap-to-Pay',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final bool isDefaultApp;
  final VoidCallback onSetDefaultTap;
  final VoidCallback onClose;

  const _SuccessView({
    required this.isDefaultApp,
    required this.onSetDefaultTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.check_circle_outline, size: 72, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Card Ready for Tap-to-Pay!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Hold the back of your phone near any contactless POS terminal to pay.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (!isDefaultApp) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Padi Pay is not your default payment app yet. Tap below to set it — otherwise NFC payments will use a different app.',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSetDefaultTap,
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Set as Default Payment App',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: onClose,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
