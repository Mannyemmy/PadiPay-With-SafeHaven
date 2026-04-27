import 'package:card_app/ui/keypad.dart';
import 'package:card_app/utils.dart';
import 'package:card_app/utils/screen_security.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class ChangePasscode extends StatefulWidget {
  const ChangePasscode({super.key});

  @override
  State<ChangePasscode> createState() => _ChangePasscodeState();
}

class _ChangePasscodeState extends State<ChangePasscode> {
  // 0 = verify identity, 1 = new passcode, 2 = confirm passcode
  int _step = 0;

  // Step 0 — identity verification
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isVerifying = false;
  bool _deviceSupportsBiometrics = false;

  // Step 1 & 2 — passcode entry
  String _newPin = '';
  String _confirmPin = '';

  bool _isSaving = false;

  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final can = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      final biometricEnabled =
          await _storage.read(key: 'biometric_enabled') == 'true';
      if (mounted) {
        setState(() =>
            _deviceSupportsBiometrics = can && supported && biometricEnabled);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Step 0 ─────────────────────────────────────────────────────────────────

  Future<void> _verifyWithPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      showSimpleDialog('Please enter your password.', Colors.red);
      return;
    }
    setState(() => _isVerifying = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) throw Exception('Not signed in');
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      setState(() {
        _step = 1;
        _newPin = '';
        _isVerifying = false;
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _isVerifying = false);
      final msg =
          e.code == 'wrong-password' || e.code == 'invalid-credential'
              ? 'Incorrect password. Please try again.'
              : 'Verification failed: ${e.message}';
      showSimpleDialog(msg, Colors.red);
    } catch (_) {
      setState(() => _isVerifying = false);
      showSimpleDialog('Verification failed. Please try again.', Colors.red);
    }
  }

  Future<void> _verifyWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Confirm your identity to change passcode',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
      if (authenticated && mounted) {
        setState(() {
          _step = 1;
          _newPin = '';
        });
      }
    } catch (_) {
      showSimpleDialog('Biometric authentication failed.', Colors.red);
    }
  }

  // ── Step 2 → save ──────────────────────────────────────────────────────────

  Future<void> _savePasscode() async {
    if (_newPin != _confirmPin) {
      showSimpleDialog('Passcodes do not match. Please try again.', Colors.red);
      setState(() {
        _step = 1;
        _newPin = '';
        _confirmPin = '';
      });
      return;
    }
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'passcode': _newPin}, SetOptions(merge: true));
      if (mounted) {
        // Show success dialog and wait for user to tap OK
        await showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          builder: (ctx) {
            return SafeArea(
              bottom: true,
              child: Container(
                margin: const EdgeInsets.all(16.0),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_outline,
                          color: Colors.green, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Passcode Updated',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 16.0,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your passcode has been changed successfully.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20.0),
                    SizedBox(
                      width: double.infinity,
                      height: 48.0,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        // Close the page after dialog is dismissed
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      setState(() => _isSaving = false);
      showSimpleDialog(
          'Failed to save passcode. Please try again.', Colors.red);
    }
  }

  // ── Shared PIN dot row ─────────────────────────────────────────────────────

  Widget _buildPinDots(String currentPin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final filled = index < currentPin.length;
        final current = index == currentPin.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: current ? 18 : 16,
          height: current ? 18 : 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? primaryColor : Colors.transparent,
            border: Border.all(
              color: filled
                  ? primaryColor
                  : current
                      ? primaryColor
                      : Colors.grey.shade400,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  // ── Step widgets ───────────────────────────────────────────────────────────

  Widget _buildVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.verified_user_outlined, color: primaryColor, size: 30),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Verify Your Identity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Enter your login password to continue',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Login Password',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey.shade500,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isVerifying ? null : _verifyWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isVerifying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
        if (_deviceSupportsBiometrics) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or',
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: _isVerifying ? null : _verifyWithBiometric,
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.grey.shade300, width: 1.5),
                      color: Colors.grey.shade50,
                    ),
                    child: Icon(Icons.fingerprint, size: 30, color: primaryColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use Fingerprint / Face ID',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPinStep({
    required String title,
    required String subtitle,
    required String currentPin,
    required IconData icon,
    required void Function(String?) onKey,
    required void Function() onConfirm,
  }) {
    final isComplete = currentPin.length == 4;
    return Column(
      children: [
        const SizedBox(height: 30),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryColor, size: 28),
          ),
        ),
        const SizedBox(height: 16),
        Text(title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 32),
        _buildPinDots(currentPin),
        const SizedBox(height: 28),
        Keypad(
          onPressed: onKey,
          rightChild: AnimatedScale(
            scale: isComplete ? 1.0 : 0.85,
            duration: const Duration(milliseconds: 180),
            child: GestureDetector(
              onTap: isComplete ? onConfirm : null,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isComplete ? Colors.green : Colors.grey.shade200,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: isComplete ? Colors.white : Colors.grey.shade400,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
        if (_isSaving)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
          ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Back arrow
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_step == 0) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() {
                          _step = _step - 1;
                          if (_step == 1) _newPin = '';
                        });
                      }
                    },
                    child: const Icon(Icons.arrow_back_ios,
                        color: Colors.black45, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Change Passcode',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              // Step progress indicator
              Row(
                children: List.generate(3, (i) {
                  final active = i == _step;
                  final done = i < _step;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 6),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: done || active
                          ? primaryColor
                          : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
              // Step content with slide+fade transition
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.2, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOut)),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _step == 0
                      ? _buildVerifyStep()
                      : _step == 1
                          ? _buildPinStep(
                              title: 'Set New Passcode',
                              subtitle: 'Enter a new 4-digit passcode',
                              currentPin: _newPin,
                              icon: Icons.lock_open_outlined,
                              onKey: (val) {
                                setState(() {
                                  if (val == null) {
                                    if (_newPin.isNotEmpty) {
                                      _newPin = _newPin.substring(
                                          0, _newPin.length - 1);
                                    }
                                  } else if (_newPin.length < 4) {
                                    _newPin += val;
                                  }
                                });
                              },
                              onConfirm: () => setState(() {
                                _step = 2;
                                _confirmPin = '';
                              }),
                            )
                          : _buildPinStep(
                              title: 'Confirm Passcode',
                              subtitle:
                                  'Re-enter your new 4-digit passcode',
                              currentPin: _confirmPin,
                              icon: Icons.lock_outline_rounded,
                              onKey: (val) {
                                setState(() {
                                  if (val == null) {
                                    if (_confirmPin.isNotEmpty) {
                                      _confirmPin = _confirmPin.substring(
                                          0, _confirmPin.length - 1);
                                    }
                                  } else if (_confirmPin.length < 4) {
                                    _confirmPin += val;
                                  }
                                });
                              },
                              onConfirm: _savePasscode,
                            ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
