import 'package:card_app/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// A full-screen page that handles email OTP verification.
///
/// - [email]     : The email address the OTP was sent to.
/// - [pinId]     : Optional. If provided, the page uses it directly without
///                 sending an OTP. If null, the page auto-sends an OTP on init.
/// - [onVerified]: Called when the OTP is confirmed successfully.
/// - [onResend]  : Called when user taps "Resend". Must return a new [pinId].
class EmailOtpVerificationPage extends StatefulWidget {
  final String email;
  final String? pinId;
  final Future<String> Function() onResend;
  final VoidCallback onVerified;

  const EmailOtpVerificationPage({
    super.key,
    required this.email,
    this.pinId,
    required this.onResend,
    required this.onVerified,
  });

  @override
  State<EmailOtpVerificationPage> createState() =>
      _EmailOtpVerificationPageState();
}

class _EmailOtpVerificationPageState extends State<EmailOtpVerificationPage> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  String? _pinId;
  bool _isSending = true; // true while sending the initial OTP

  @override
  void initState() {
    super.initState();
    if (widget.pinId != null) {
      // pinId was provided by caller — use it directly, no need to send
      _pinId = widget.pinId;
      _isSending = false;
    } else {
      _sendInitialOtp();
    }
  }

  Future<void> _sendInitialOtp() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendEmailOTP')
          .call({'email': widget.email, 'purpose': 'verify'});
      if (mounted) {
        setState(() {
          _pinId = result.data['pinId'] as String;
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        showSimpleDialog('Failed to send verification code: $e', Colors.red);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredCode =>
      _controllers.map((c) => c.text.trim()).join();

  Future<void> _verify() async {
    final code = _enteredCode;
    if (code.length != 6) {
      showSimpleDialog('Please enter the full 6-digit code', Colors.red);
      return;
    }
    if (_pinId == null) {
      showSimpleDialog('Verification code not received yet. Please wait or resend.', Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyEmailOTP')
          .call({'pinId': _pinId, 'code': code});

      final verified = result.data['verified'] == true;
      if (!verified) {
        showSimpleDialog('Incorrect or expired code. Please try again.',
            Colors.red);
        return;
      }

      widget.onVerified();
    } on FirebaseFunctionsException catch (e) {
      showSimpleDialog(e.message ?? 'Verification failed', Colors.red);
    } catch (e) {
      showSimpleDialog('Verification failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isLoading = true);
    try {
      final newPinId = await widget.onResend();
      if (mounted) {
        setState(() {
          _pinId = newPinId;
          _isLoading = false;
        });
        for (final c in _controllers) {
          c.clear();
        }
        FocusScope.of(context).requestFocus(_focusNodes[0]);
        showSimpleDialog('Code resent to ${widget.email}', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showSimpleDialog('Failed to resend code: $e', Colors.red);
      }
    }
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Icon(Icons.mail_outline, size: 56, color: primaryColor),
              const SizedBox(height: 20),
              const Text(
                'Check your email',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  text: 'We sent a 6-digit verification code to ',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const TextSpan(text: '. Enter it below.'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (_isSending)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: primaryColor),
                      SizedBox(height: 12),
                      Text('Sending code...', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                )
              else ...[
                // OTP input boxes
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
                        controller: _controllers[i],
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
                            FocusScope.of(context)
                                .requestFocus(_focusNodes[i + 1]);
                          }
                          if (val.isEmpty && i > 0) {
                            FocusScope.of(context)
                                .requestFocus(_focusNodes[i - 1]);
                          }
                          if (_controllers.every((c) => c.text.length == 1)) {
                            FocusScope.of(context).unfocus();
                            _verify();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              // Verify button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
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
                          'Verify Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              // Resend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Didn't receive the code? ",
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  GestureDetector(
                    onTap: _isLoading ? null : _resend,
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
              ], // end else block
            ],
          ),
        ),
      ),
    );
  }
}
