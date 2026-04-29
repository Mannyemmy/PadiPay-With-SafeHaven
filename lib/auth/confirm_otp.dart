// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:card_app/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';

class ConfirmOtpBottomSheet extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final User user; // Email user to link phone to
  final VoidCallback onVerified;

  const ConfirmOtpBottomSheet({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    required this.user,
    required this.onVerified,
  });

  @override
  State<ConfirmOtpBottomSheet> createState() => _ConfirmOtpBottomSheetState();
}

class _ConfirmOtpBottomSheetState extends State<ConfirmOtpBottomSheet> {
  late String _verificationId;
  final List<TextEditingController> otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
  }

  void _showPhoneVerificationDialog() {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.zero, // removes the default margins
        alignment: Alignment.bottomCenter,
        backgroundColor:
            Colors.transparent, // so rounded corners still show cleanly
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [Image.asset("assets/Featured icon.png", height: 70)],
              ),
              SizedBox(height: 20),
              Text(
                "Verification Successful",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 12),
              Text(
                "Your code has been verified successfully.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: Colors.grey.shade700,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onVerified();
                  },
                  child: Text(
                    "Proceed",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _verifyOtp() async {
    String smsCode = otpControllers.map((c) => c.text).join();
    if (smsCode.length != 6) {
      showSimpleDialog('Please enter full 6-digit code', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: smsCode,
    );

    try {
      // Link phone credential to the existing email user
      await widget.user.linkWithCredential(credential);
      setState(() => _isLoading = false);
      Navigator.pop(context);
      widget.onVerified();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        print(e);
        Navigator.pop(context);
        widget.onVerified();
      } else {
        showSimpleDialog('Invalid OTP: ${e.message}', Colors.red);
      }
    } catch (e) {
      showSimpleDialog('Verification failed: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resendCode() async {
    setState(() => _isLoading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await widget.user.linkWithCredential(credential);
          setState(() => _isLoading = false);
          Navigator.pop(context);
          widget.onVerified();
        } catch (e) {
          setState(() => _isLoading = false);
          showSimpleDialog('Auto verification failed', Colors.red);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        showSimpleDialog(e.message ?? 'Resend failed', Colors.red);
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() {
          _verificationId = verificationId;
          _isLoading = false;
        });
        showSimpleDialog('Code resent', Colors.green);
        // Clear OTP fields
        for (var controller in otpControllers) {
          controller.clear();
        }
        FocusScope.of(context).requestFocus(focusNodes[0]);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var node in focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: SafeArea(bottom: true,
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      "Confirm OTP Code",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    text: "We've just sent a code to ",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                      color: Colors.black45,
                    ),
                    children: [
                      TextSpan(
                        text: widget.phoneNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const TextSpan(text: ". Enter the 6 digit code below."),
                    ],
                  ),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return Container(
                      width: 50,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        controller: otpControllers[index],
                        focusNode: focusNodes[index],
                        textInputAction: index < 5
                            ? TextInputAction.next
                            : TextInputAction.done,
                        cursorColor: Colors.blue,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onChanged: (value) {
                          if (value.length == 1 && index < 5) {
                            FocusScope.of(
                              context,
                            ).requestFocus(focusNodes[index + 1]);
                          }
                          if (value.isEmpty && index > 0) {
                            FocusScope.of(
                              context,
                            ).requestFocus(focusNodes[index - 1]);
                          }
                          if (otpControllers.every((c) => c.text.length == 1)) {
                            FocusScope.of(context).unfocus();
                            _verifyOtp();
                          }
                        },
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Text(
                      "Didn't get a code? ",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    InkWell(
                      onTap: _isLoading ? null : _resendCode,
                      child: const Text(
                        "Resend",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.43,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            "No, Cancel",
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _isLoading ? null : _verifyOtp,
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.43,
                        height: 50,
                        decoration: BoxDecoration(
                          color: _isLoading ? Colors.grey : Colors.blue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                )
                              : const Text(
                                  "Continue",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
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
