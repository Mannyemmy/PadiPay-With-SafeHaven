import 'package:card_app/utils.dart';
import 'package:card_app/utils/screen_security.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class ChangePinPage extends StatefulWidget {
  const ChangePinPage({super.key});

  @override
  State<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends State<ChangePinPage> {
  int _step = 1; // 1 = auth, 2 = email OTP, 3 = change PIN
  bool _isLoading = false;
  bool _usesBiometric = false;

  // Step 1: Authentication
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Step 2: Email OTP
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  String _pinId = '';
  String _userEmail = '';

  // Step 3: Change PIN
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _obscureNewPin = true;
  bool _obscureConfirmPin = true;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
    _checkBiometricPreference();
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    _passwordController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _checkBiometricPreference() async {
    try {
      final localAuth = LocalAuthentication();
      final canCheckBiometrics = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();
      if (mounted) {
        setState(() =>
            _usesBiometric = canCheckBiometrics && isDeviceSupported);
      }
    } catch (e) {
      print('Error checking biometric: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 1: Authenticate user with password or biometric
  // ──────────────────────────────────────────────────────────────────
  Future<void> _authenticateWithPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      showSimpleDialog('Please enter your password', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Re-authenticate with current email and password
      final email = user.email!;
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _userEmail = email;

      // Password verified, move to OTP step
      await _sendOtp();
      setState(() => _step = 2);
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(
        e.message ?? 'Authentication failed',
        Colors.red,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Authentication failed: $e', Colors.red);
    }
  }

  Future<void> _authenticateWithBiometric() async {
    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Verify your identity to change PIN',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        _userEmail = _auth.currentUser?.email ?? '';
        if (_userEmail.isEmpty) {
          showSimpleDialog('No email found for current user', Colors.red);
          return;
        }
        await _sendOtp();
        setState(() => _step = 2);
      }
    } catch (e) {
      showSimpleDialog('Biometric authentication failed: $e', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 2: Send and verify email OTP
  // ──────────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendEmailOTP')
          .call({'email': _userEmail, 'purpose': 'verify'});

      _pinId = result.data['pinId'] as String;
      setState(() => _isLoading = false);
      showSimpleDialog('OTP sent to $_userEmail', Colors.green);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Failed to send OTP', Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Failed to send OTP: $e', Colors.red);
    }
  }

  String get _enteredOtp =>
      _otpControllers.map((c) => c.text.trim()).join();

  Future<void> _verifyOtp() async {
    final code = _enteredOtp;
    if (code.length != 6) {
      showSimpleDialog('Please enter the full 6-digit code', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyEmailOTP')
          .call({'pinId': _pinId, 'code': code});

      final verified = result.data['verified'] == true;
      if (!verified) {
        setState(() => _isLoading = false);
        showSimpleDialog('Incorrect or expired code. Please try again.',
            Colors.red);
        return;
      }

      // OTP verified, move to change PIN step
      setState(() {
        _step = 3;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Verification failed', Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Verification failed: $e', Colors.red);
    }
  }

  Future<void> _resendOtp() async {
    await _sendOtp();
    for (final c in _otpControllers) {
      c.clear();
    }
    FocusScope.of(context).requestFocus(_focusNodes[0]);
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 3: Change PIN
  // ──────────────────────────────────────────────────────────────────
  Future<void> _changePin() async {
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (newPin.isEmpty || confirmPin.isEmpty) {
      showSimpleDialog('Please fill in all PIN fields', Colors.red);
      return;
    }

    if (newPin != confirmPin) {
      showSimpleDialog('New PINs do not match', Colors.red);
      return;
    }

    if (newPin.length < 4) {
      showSimpleDialog('PIN must be at least 4 digits', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Update PIN in Firestore (no need to verify old PIN)
      await _firestore.collection('users').doc(user.uid).update({
        'pin': newPin,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 16),
              const Text(
                'PIN Changed Successfully',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your PIN has been updated.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Failed to change PIN: $e', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // UI Builders
  // ──────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Verify Your Identity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'To change your PIN, please authenticate using your password or biometric.',
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 28),
        const Text(
          'Password',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
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
            onPressed: _isLoading ? null : _authenticateWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Verify Password',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        if (_usesBiometric) ...[
          const SizedBox(height: 16),
          const Text(
            'Or use your biometric:',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _authenticateWithBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Use Biometric'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mail_outline, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Verify Your Email',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit code to ',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
              height: 1.5,
            ),
            children: [
              TextSpan(
                text: _userEmail,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const TextSpan(text: '. It expires in 10 minutes.'),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 48,
              height: 58,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _otpControllers[i],
                  focusNode: _focusNodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  cursorColor: primaryColor,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  onChanged: (val) {
                    if (val.length == 1 && i < 5) {
                      FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
                    }
                    if (val.isEmpty && i > 0) {
                      FocusScope.of(context).requestFocus(_focusNodes[i - 1]);
                    }
                    if (_otpControllers.every((c) => c.text.length == 1)) {
                      FocusScope.of(context).unfocus();
                      _verifyOtp();
                    }
                  },
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Verify Code',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Didn't receive the code? ",
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            GestureDetector(
              onTap: _isLoading ? null : _resendOtp,
              child: Text(
                'Resend',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _isLoading ? Colors.grey : primaryColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.pin, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Set Your New PIN',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter the new PIN you want to set. It must be at least 4 digits.',
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Text(
          'New PIN',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _newPinController,
          obscureText: _obscureNewPin,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter new PIN (at least 4 digits)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNewPin ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureNewPin = !_obscureNewPin),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Confirm New PIN',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPinController,
          obscureText: _obscureConfirmPin,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Re-enter new PIN',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPin ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirmPin = !_obscureConfirmPin),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _changePin,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Change PIN',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (_step > 1) {
              setState(() => _step--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        // Step indicator
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final active = i + 1 == _step;
            final done = i + 1 < _step;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: (active || done) ? primaryColor : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: _step == 1
                  ? _buildStep1()
                  : _step == 2
                      ? _buildStep2()
                      : _buildStep3(),
            ),
          ),
        ),
      ),
    );
  }
}
