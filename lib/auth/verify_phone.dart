import 'package:card_app/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerifyPhoneAsBottomSheet extends StatefulWidget {
  final Map<String, String> userData;
  final String countryCode;
  final String phoneNumber;
  final ScrollController scrollController;
  final VoidCallback onVerified;

  const VerifyPhoneAsBottomSheet({
    super.key,
    required this.userData,
    required this.countryCode,
    required this.phoneNumber,
    required this.scrollController,
    required this.onVerified,
  });

  @override
  State<VerifyPhoneAsBottomSheet> createState() => _VerifyPhoneAsBottomSheetState();
}

class _VerifyPhoneAsBottomSheetState extends State<VerifyPhoneAsBottomSheet> {
  bool _isLoading = false;

  void _sendCode() async {
    if (widget.phoneNumber.isEmpty) {
      showSimpleDialog("Phone number is required", Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    String fullPhone = widget.countryCode + widget.phoneNumber;

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: fullPhone,
      verificationCompleted: (PhoneAuthCredential credential) {
        setState(() => _isLoading = false);
        widget.userData['phone'] = fullPhone;
        FirebaseAuth.instance.currentUser?.updatePhoneNumber(credential);
        widget.onVerified();
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        showSimpleDialog(e.message ?? 'Verification failed', Colors.red);
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() => _isLoading = false);
        widget.userData['phone'] = fullPhone;
        Navigator.pop(context);
        // navigateTo(context, ConfirmOtp(
        //   verificationId: verificationId,
        //   userData: widget.userData,
        //   onVerified: widget.onVerified,
        // ));
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        setState(() => _isLoading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        controller: widget.scrollController,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 20,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 20),
              
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.arrow_back_ios, color: Colors.black),
                ),
              ]),
              
              SizedBox(height: 30),
              Text("Verify Phone Number", style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text("A code will be sent to this number for verification.", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
              SizedBox(height: 30),
              
              // Display phone number
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.phone, color: Colors.blue),
                  SizedBox(width: 10),
                  Text("${widget.countryCode} ${widget.phoneNumber}", style: TextStyle(fontSize: 16)),
                ]),
              ),
              SizedBox(height: 30),
              
              InkWell(
                onTap: _isLoading ? null : _sendCode,
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: _isLoading
                        ? CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                        : Text("Send Code", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}