import 'package:card_app/auth/sign-in.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Three-step password reset flow using OTP via email:
///  Step 1 — user enters email → `sendPasswordResetOTP` called
///  Step 2 — user enters 6-digit OTP → `verifyPasswordResetOTP` returns resetToken
///  Step 3 — user enters new password → `resetPasswordWithOTP` called

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  int _step = 1; // 1 = email, 2 = OTP, 3 = new password

  // Step 1
  final _emailController = TextEditingController();
  String _pinId = '';
  String _resetEmail = '';

  // Step 2
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  String _resetToken = '';

  // Step 3
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 1: send OTP
  // ──────────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showSimpleDialog('Please enter a valid email address', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPasswordResetOTP')
          .call({'email': email});

      _pinId = result.data['pinId'] as String;
      _resetEmail = email.toLowerCase().trim();

      setState(() {
        _step = 2;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Failed to send reset code', Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Something went wrong. Please try again.', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 2: verify OTP
  // ──────────────────────────────────────────────────────────────────
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
          .httpsCallable('verifyPasswordResetOTP')
          .call({'pinId': _pinId, 'code': code});

      final verified = result.data['verified'] == true;
      if (!verified) {
        setState(() => _isLoading = false);
        showSimpleDialog('Incorrect or expired code. Please try again.', Colors.red);
        return;
      }

      _resetToken = result.data['resetToken'] as String;
      setState(() {
        _step = 3;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Verification failed', Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Verification failed. Please try again.', Colors.red);
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPasswordResetOTP')
          .call({'email': _resetEmail});

      _pinId = result.data['pinId'] as String;
      if (mounted) {
        setState(() => _isLoading = false);
        for (final c in _otpControllers) {
          c.clear();
        }
        FocusScope.of(context).requestFocus(_focusNodes[0]);
        showSimpleDialog('Code resent to $_resetEmail', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showSimpleDialog('Failed to resend code.', Colors.red);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Step 3: reset password
  // ──────────────────────────────────────────────────────────────────
  Future<void> _resetPassword() async {
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;

    if (newPw.isEmpty) {
      showSimpleDialog('Please enter a new password', Colors.red);
      return;
    }
    if (newPw.length < 6) {
      showSimpleDialog('Password must be at least 6 characters', Colors.red);
      return;
    }
    if (newPw != confirmPw) {
      showSimpleDialog('Passwords do not match', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('resetPasswordWithOTP')
          .call({
        'email': _resetEmail,
        'resetToken': _resetToken,
        'newPassword': newPw,
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

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
                'Password Reset Successfully',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your password has been updated. Please sign in with your new password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    navigateTo(context, const SignIn(),
                        type: NavigationType.clearStack);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Sign In',
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
    } on FirebaseFunctionsException catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog(e.message ?? 'Failed to reset password', Colors.red);
    } catch (e) {
      setState(() => _isLoading = false);
      showSimpleDialog('Failed to reset password. Please try again.', Colors.red);
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Widgets
  // ──────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_reset, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Forgot Password?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter your account email and we\'ll send you a one-time code to reset your password.',
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 28),
        const Text(
          'Email Address',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter your email',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendOtp,
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
                    'Send Reset Code',
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

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mail_outline, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Enter Reset Code',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                text: _resetEmail,
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
        const Icon(Icons.lock_outline, size: 56, color: primaryColor),
        const SizedBox(height: 20),
        const Text(
          'Set New Password',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Create a strong password. It must be at least 6 characters long.',
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 28),
        const Text(
          'New Password',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNew,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Enter new password',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Confirm Password',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Re-enter new password',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
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
                    'Reset Password',
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
