import 'dart:async';
import 'dart:math';

import 'package:card_app/auth/identity_verification_constants.dart';
import 'package:card_app/ui/feedback.dart';
import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qoreidsdk/qoreidsdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String _step1ClientId = kStep1ClientId;
const int _step1FlowId = kStep1FlowId;

class IdentityVerificationStep1Page extends StatefulWidget {
  const IdentityVerificationStep1Page({super.key});

  @override
  State<IdentityVerificationStep1Page> createState() =>
      _IdentityVerificationStep1PageState();
}

class _IdentityVerificationStep1PageState
    extends State<IdentityVerificationStep1Page> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final String _selectedIdOption = 'BVN';
  bool _isChecking = true;
  bool _isUploading = false;
  bool _idVerified = false;
  bool _idSubmitted = false;
  bool _agreedToPrivacy = false;

  @override
  void initState() {
    super.initState();
    _listenForResult();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _listenForResult() {
    Qoreidsdk.onResult((dynamic result) async {
      await _handleResult(result as Map<dynamic, dynamic>?);
    });
  }

  Future<void> _loadProfile() async {
    try {
      setState(() => _isChecking = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSnackBar(context, 'Not logged in', Colors.red);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        _firstNameController.text = data['firstName'] ?? '';
        _lastNameController.text = data['lastName'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        final qoreData = data['qoreIdData'] as Map<String, dynamic>?;
        if (qoreData != null) {
          final verification = qoreData['verification'] as Map<String, dynamic>?;
          if (verification != null) {
            _idVerified = verification['verified'] == true;
            _idSubmitted = verification['submitted'] == true;
          }
        }
    }} catch (e) {
      showSnackBar(context, 'Error loading profile: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  bool _isPhoneValid(String phone) {
    final normalized = phone.trim();
    // Accept formats: +234XXXXXXXXXX, 0XXXXXXXXXX (11 digits), or XXXXXXXXXX (10 digits)
    final regex = RegExp(r'^(?:\+234[0-9]{10}|0[0-9]{10}|[0-9]{10})$');
    return regex.hasMatch(normalized);
  }

  String _formatPhoneNumber(String phone) {
    final normalized = phone.trim();
    // If already in international format, return as-is
    if (normalized.startsWith('+234')) {
      return normalized;
    }
    // If starts with 0, replace with +234
    if (normalized.startsWith('0')) {
      return '+234${normalized.substring(1)}';
    }
    // If it's 10 digits, add +234
    if (RegExp(r'^[0-9]{10}$').hasMatch(normalized)) {
      return '+234$normalized';
    }
    // Otherwise return trimmed input
    return normalized;
  }

  Future<void> _requestCameraPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final consented = prefs.getBool('privacy_consent_camera') ?? false;
    if (!consented) {
      bool agreed = false;
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isDismissible: true,
        builder: (ctx) => PermissionExplanationSheet(
          type: PermissionType.camera,
          onContinue: () async {
            await prefs.setBool('privacy_consent_camera', true);
            agreed = true;
          },
        ),
      );
      if (!agreed) return;
    }
    final status = await Permission.camera.request();
    if (status.isDenied && mounted) {
      showSnackBar(
        context,
        'Camera permission is required for verification',
        Colors.red,
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  String randomLetters(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    final rand = Random();

    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> _onSubmit() async {
    if (_isUploading) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    var phone = _phoneController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      showSnackBar(context, 'All fields are required', Colors.red);
      return;
    }

    // Auto-format phone number
    phone = _formatPhoneNumber(phone);

    if (!_isPhoneValid(phone)) {
      showSnackBar(
        context,
        'Phone must be 10-11 digits (e.g., 08123456789 or +2348123456789)',
        Colors.red,
      );
      return;
    }
    if (!_agreedToPrivacy) {
      showSnackBar(context, 'Please agree to the privacy policy', Colors.red);
      return;
    }


    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSnackBar(context, 'Not logged in', Colors.red);
      return;
    }

    final customerReference = user.email!;
    if (user.email == null || user.email!.isEmpty) {
      showSnackBar(
        context,
        'User email is required for verification',
        Colors.red,
      );
      return;
    }
    final applicantData = {
      "email": customerReference,
      "firstName": firstName,
      "lastName": lastName,
      "phoneNumber": phone,
    };

    // Log applicant data for debugging before sending to QoreID
    print('QoreID applicantData: $applicantData');

    final qoreidData = QoreidData(
      clientId: _step1ClientId,
      flowId: _step1FlowId,
      customerReference: customerReference,
      applicantData: applicantData,
      productCode: kIdVerificationProductCodes[_selectedIdOption] ?? '',
     
    );

    try {
      setState(() => _isUploading = true);

      // Request camera permission
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isDenied) {
        setState(() => _isUploading = false);
        _requestCameraPermission();
        return;
      } else if (cameraStatus.isPermanentlyDenied) {
        setState(() => _isUploading = false);
        showSnackBar(
          context,
          'Camera permission is required. Please enable it in settings.',
          Colors.red,
        );
        return;
      }

      await _persistApplicant(user.uid, firstName, lastName, phone);
      await Qoreidsdk.launchQoreid(qoreidData);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      showSnackBar(context, 'Unable to start verification: $e', Colors.red);
    }
  }

  Future<void> _persistApplicant(
    String uid,
    String firstName,
    String lastName,
    String phone,
  ) async {
    final fullName = '$firstName $lastName'.trim();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'phone': phone,
    }, SetOptions(merge: true));
  }

  Future<void> _persistIdStatus({
    required String uid,
    required String firstName,
    required String lastName,
    required String phone,
    required String productCode,
  }) async {
    final fullName = '$firstName $lastName'.trim();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'phone': phone,
      'qoreIdData': {
        'verification': {
          'submitted': true,
          'verified': true,
          'approved': 'approved',
          'productCode': productCode,
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> _persistIdInitiated({
    required String uid,
    required String firstName,
    required String lastName,
    required String phone,
    required String productCode,
    String? verificationId,
    String? flowId,
    String? state,
  }) async {
    final fullName = '$firstName $lastName'.trim();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'phone': phone,
      'qoreIdData': {
        'verification': {
          'submitted': true,
          'verified': false,
          'approved': 'pending',
          'productCode': productCode,
          if (verificationId != null) 'id': verificationId,
          if (flowId != null) 'flowId': flowId,
          if (state != null) 'state': state,
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> _handleResult(Map<dynamic, dynamic>? result) async {
    print("result: $result");
    if (!mounted || result == null) return;

    final code = result['code']?.toString();
    final message = result['message']?.toString() ?? '';
    final productCode =
        result['productCode']?.toString() ??
        kIdVerificationProductCodes[_selectedIdOption] ??
        '';

    // Extract nested data if present
    final dataMap = (result['data'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final verificationMap = (dataMap['verification'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final verificationId = verificationMap['id']?.toString();
    final verificationState = verificationMap['state']?.toString() ?? '';
    final flowId = dataMap['flowId']?.toString();

    if (code == 'E_USER_CANCELED') {
      setState(() => _isUploading = false);
      showSnackBar(context, 'Verification cancelled', Colors.orange);
      return;
    }

    final normalizedMessage = message.toLowerCase();
    final isAlreadyInitiated = normalizedMessage.contains(
      'already been initiated',
    );
    final isSuccess = normalizedMessage.contains('verification successful');

    // Consider "in progress" states reported by QoreID
    final isInProgress = normalizedMessage.contains('verification submitted');

    if (isAlreadyInitiated || isSuccess) {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final phone = _phoneController.text.trim();

      await _persistIdStatus(
        uid: FirebaseAuth.instance.currentUser!.uid,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        productCode: productCode,
      );

      if (!mounted) return;
      setState(() {
        _idVerified = true;
        _idSubmitted = true;
        _isUploading = false;
      });
      showSnackBar(context, 'ID verification successful', Colors.green);
     Navigator.of(context).pop();
      return;
    }

    if (isInProgress) {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final phone = _phoneController.text.trim();

      await _persistIdInitiated(
        uid: FirebaseAuth.instance.currentUser!.uid,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        productCode: productCode,
        verificationId: verificationId,
        flowId: flowId,
        state: verificationState,
      );

      if (!mounted) return;
      setState(() {
        _idSubmitted = true;
        _idVerified = false;
        _isUploading = false;
      });

      Navigator.of(context).pop();
      return;
    }

    setState(() => _isUploading = false);
    showSnackBar(
      context,
      message.isNotEmpty ? message : 'Verification failed',
      Colors.red,
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showSnackBar(context, 'Could not open privacy policy', Colors.red);
      }
    }
  }

  Widget _buildStepHeader() {
    final themeColor = primaryColor;
    return Row(
      children: [
        _StepCircle(label: '1', isActive: true, isDone: _idVerified),
        Expanded(
          child: Container(
            height: 2,
            color: _idVerified ? themeColor : Colors.grey.shade300,
          ),
        ),
        _StepCircle(label: '2', isActive: false, isDone: false),
        const SizedBox(width: 8),
        const Text('Liveness'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identity Verification')),
      body: SafeArea(
        bottom: true,
        child: _isChecking
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStepHeader(),
                    const SizedBox(height: 16),
                    Text(
                      'Step 1: Verify your ID',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Provide your correct legal details to start verification. Use the phone number linked to your BVN',
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      textCapitalization: TextCapitalization.words,
                      keyboardType: TextInputType.name,
                      controller: _firstNameController,
                      style: TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      textCapitalization: TextCapitalization.words,
                      keyboardType: TextInputType.name,
                      controller: _lastNameController,
                      style: TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Phone (+234...)',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _agreedToPrivacy,
                          onChanged: (v) =>
                              setState(() => _agreedToPrivacy = v ?? false),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('I agree to the '),
                              InkWell(
                                onTap: _openPrivacyPolicy,
                                child: Text(
                                  'privacy policy',
                                  style: TextStyle(color: primaryColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isUploading ? null : _onSubmit,
                        child: _isUploading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Start ID Verification'),
                      ),
                    ),
                    if (_idVerified) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'ID verification completed successfully',
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                        Navigator.of(context).pop();
                        },
                        child: const Text('Go Home'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;

  const _StepCircle({
    required this.label,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = primaryColor;
    final Color baseColor = Colors.grey.shade400;
    final bool showCheck = isDone;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: showCheck
            ? Colors.green
            : (isActive ? activeColor.withOpacity(0.15) : Colors.white),
        border: Border.all(
          color: showCheck
              ? Colors.green
              : (isActive ? activeColor : baseColor),
        ),
      ),
      alignment: Alignment.center,
      child: showCheck
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : baseColor,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
