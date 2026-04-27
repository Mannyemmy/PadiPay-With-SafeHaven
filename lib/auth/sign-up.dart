import 'dart:math';

import 'package:card_app/auth/email_otp_verification_page.dart';
import 'package:card_app/auth/sign-in.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'package:flutter/services.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> with WidgetsBindingObserver {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController referralCodeController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String countryCode = '+234';
  bool isLoading = false;
  bool _isUsernameValid = false;
  bool _isCheckingUsername = false;
  List<String> _usernameSuggestions = [];
  Timer? _usernameDebounce;

  // Referral validation
  bool _isCheckingReferral = false;
  bool _isReferralValid = false;
  String? _referrerUid;

  // Removed verification states - now only require username check

  // Password validation states
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSymbol = false;
  bool _passwordsMatch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
  }

  void _setupListeners() {
    passwordController.addListener(_validatePassword);
    confirmPasswordController.addListener(_validatePasswordMatch);
    usernameController.addListener(_checkUsernameAvailability);
    referralCodeController.addListener(_validateReferralCode);
  }

  void _validatePassword() {
    final password = passwordController.text;
    setState(() {
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
      _hasLowercase = RegExp(r'[a-z]').hasMatch(password);
      _hasNumber = RegExp(r'\d').hasMatch(password);
      _hasSymbol = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    });
    _validatePasswordMatch();
  }

  void _validatePasswordMatch() {
    final pass = passwordController.text;
    final confirm = confirmPasswordController.text;
    setState(() {
      _passwordsMatch =
          pass.isNotEmpty && confirm.isNotEmpty && pass == confirm;
    });
  }

  // Email/phone are no longer verified during signup

  void _checkUsernameAvailability() {
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(Duration(milliseconds: 500), () async {
      final username = usernameController.text.trim().toLowerCase();
      if (username.isEmpty) {
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        return;
      }

      if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        return;
      }
      setState(() {
        _isCheckingUsername = true;
      });

      try {
        final doc = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username)
            .get();

        if (!doc.exists) {
          setState(() {
            _isUsernameValid = true;
            _usernameSuggestions = [];
            _isCheckingUsername = false;
          });
        } else {
          // Generate suggestions
          List<String> suggestions = [];
          for (int i = 1; i <= 3; i++) {
            suggestions.add('$username$i');
            suggestions.add('$username${Random().nextInt(100)}');
            suggestions.add('${username}_${Random().nextInt(1000)}');
          }
          setState(() {
            _isUsernameValid = false;
            _usernameSuggestions = suggestions;
            _isCheckingUsername = false;
          });
        }
      } catch (e) {
        print(e);
        setState(() {
          _isUsernameValid = false;
          _usernameSuggestions = [];
          _isCheckingUsername = false;
        });
        showSimpleDialog("Error checking username: $e", Colors.red);
      }
    });
  }

  void _validateReferralCode() async {
    final code = referralCodeController.text.trim().toLowerCase();
    if (code.isEmpty) {
      setState(() {
        _isReferralValid = false;
        _referrerUid = null;
        _isCheckingReferral = false;
      });
      return;
    }

    setState(() {
      _isCheckingReferral = true;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(code)
          .get();

      if (doc.exists) {
        final referrerId = (doc.data() ?? {})['uid'] as String?;
        final newUsername = usernameController.text.trim().toLowerCase();

        if (referrerId == null || referrerId == FirebaseAuth.instance.currentUser?.uid || code == newUsername) {
          setState(() {
            _isReferralValid = false;
            _referrerUid = null;
          });
          showSimpleDialog("Cannot refer yourself", Colors.orange);
        } else {
          setState(() {
            _isReferralValid = true;
            _referrerUid = referrerId;
          });
        }
      } else {
        setState(() {
          _isReferralValid = false;
          _referrerUid = null;
        });
      }
    } catch (e) {
      print(e);
      setState(() {
        _isReferralValid = false;
        _referrerUid = null;
      });
      showSimpleDialog("Error validating referral code", Colors.red);
    } finally {
      setState(() {
        _isCheckingReferral = false;
      });
    }
  }

  void _showVerificationEmailBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        bottom: true,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mail_outline, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'Verify your email',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'We sent a verification link to your email. Please check your inbox and click the link to verify your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                navigateTo(context, const SignIn());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameDebounce?.cancel();
    passwordController.removeListener(_validatePassword);
    confirmPasswordController.removeListener(_validatePasswordMatch);
    usernameController.removeListener(_checkUsernameAvailability);
    referralCodeController.removeListener(_validateReferralCode);
    super.dispose();
  }

  bool _isPasswordValid() {
    return _hasUppercase &&
        _hasLowercase &&
        _hasNumber &&
        _hasSymbol &&
        passwordController.text.length >= 8 &&
        _passwordsMatch;
  }

  Future<void> _completeSignUp() async {
    // Validate all fields
    if (!_isUsernameValid) {
      showSimpleDialog("Please choose a valid username", Colors.red);
      return;
    }

    if (!_isPasswordValid()) {
      showSimpleDialog("Please enter a valid password", Colors.red);
      return;
    }

    if (emailController.text.isEmpty ||
        firstNameController.text.isEmpty ||
        lastNameController.text.isEmpty ||
        usernameController.text.isEmpty) {
      showSimpleDialog("Please fill in all required fields", Colors.red);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // 1. Create user with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text,
          );

      final String myUid = userCredential.user!.uid;
      final String myUsername = usernameController.text.trim().toLowerCase();

      // 2. Save user data to Firestore
      Map<String, dynamic> userData = {
        'email': emailController.text.trim(),
        'firstName': firstNameController.text,
        'userName': myUsername,
        'lastName': lastNameController.text,
        'countryCode': countryCode,
        'phone': phoneController.text,
        'phoneVerified': false,
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'referrals': [],
        'referredBy': _referrerUid,
      };

      WriteBatch batch = FirebaseFirestore.instance.batch();
      DocumentReference newUserRef = FirebaseFirestore.instance.collection('users').doc(myUid);
      batch.set(newUserRef, userData);

      // Reserve username (create mapping) — will fail if username doc already exists (security rules should prevent overwrite)
      DocumentReference usernameRef = FirebaseFirestore.instance.collection('usernames').doc(myUsername);
      batch.set(usernameRef, {
        'uid': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Add to referrer's referrals if valid
      if (_isReferralValid && _referrerUid != null && _referrerUid != myUid) {
        DocumentReference referrerRef = FirebaseFirestore.instance.collection('users').doc(_referrerUid);
        batch.update(referrerRef, {
          'referrals': FieldValue.arrayUnion([myUid])
        });
      }

      await batch.commit();

      // 3. Send welcome email
      final email = emailController.text.trim();
      final firstName = firstNameController.text.trim();
      try {
        await FirebaseFunctions.instance.httpsCallable('sendEmail').call({
          'to': email,
          'subject': '🎉 Welcome to PadiPay, $firstName!',
          'html':
              '<!DOCTYPE html><html><head><meta charset="UTF-8"/></head>'
              '<body style="margin:0;padding:0;background:#f0f2f5;font-family:\'Helvetica Neue\',Helvetica,Arial,sans-serif;">'
              '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:32px 0;">'
              '<tr><td align="center"><table width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;">'
              '<tr><td align="center" style="padding-bottom:20px;">'
              '<span style="font-size:26px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#4f46e5;">Pay</span></span>'
              '</td></tr>'
              '<tr><td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">'
              '<table width="100%" cellpadding="0" cellspacing="0">'
              '<tr><td style="background:linear-gradient(135deg,#4f46e5 0%,#7c3aed 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td></tr>'
              '<tr><td style="padding:36px 28px 28px;">'
              '<p style="margin:0 0 6px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#4f46e5;">Welcome my padi</p>'
              '<h1 style="margin:0 0 14px;font-size:26px;font-weight:800;color:#0f0f1a;line-height:1.2;">Hi $firstName, welcome to PadiPay! 🎉</h1>'
              '<p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.7;">'
              'We\'re excited to have you join the PadiPay family. You now have access to fast, secure, and seamless financial services designed with you in mind.'
              '</p>'
              '<table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f3ff;border-radius:12px;padding:20px;margin:0 0 24px;">'
              '<tr><td>'
              '<p style="margin:0 0 14px;font-size:15px;font-weight:700;color:#1a1a2e;">Get started in 2 easy steps:</p>'
              '<table width="100%" cellpadding="0" cellspacing="0">'
              '<tr><td style="padding:10px 0;border-bottom:1px solid #e0d9ff;">'
              '<p style="margin:0 0 4px;font-size:14px;color:#374151;">'
              '<span style="display:inline-block;background:#4f46e5;color:#fff;font-weight:700;font-size:12px;border-radius:50%;width:22px;height:22px;text-align:center;line-height:22px;margin-right:8px;">1</span>'
              '<strong>Complete your KYC</strong>'
              '</p>'
              '<p style="margin:0 0 0 30px;font-size:13px;color:#6b7280;">Verify your identity to unlock full account access and higher limits.</p>'
              '</td></tr>'
              '<tr><td style="padding:10px 0;">'
              '<p style="margin:0 0 4px;font-size:14px;color:#374151;">'
              '<span style="display:inline-block;background:#4f46e5;color:#fff;font-weight:700;font-size:12px;border-radius:50%;width:22px;height:22px;text-align:center;line-height:22px;margin-right:8px;">2</span>'
              '<strong>Create your bank account</strong>'
              '</p>'
              '<p style="margin:0 0 0 30px;font-size:13px;color:#6b7280;">Get a dedicated account number to receive payments from anyone, anywhere.</p>'
              '</td></tr>'
              '</table>'
              '</td></tr></table>'
              '<p style="margin:0 0 24px;font-size:14px;color:#6b7280;line-height:1.7;">'
              'Once verified, you\'ll enjoy transfers, bill payments, airtime top-ups, and much more — all in one place.'
              '</p>'
              '<table cellpadding="0" cellspacing="0"><tr><td style="background:#4f46e5;border-radius:10px;">'
              '<a style="display:inline-block;padding:13px 28px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;letter-spacing:0.3px;">Open PadiPay App</a>'
              '</td></tr></table>'
              '</td></tr>'
              '<tr><td style="padding:0 28px;"><div style="border-top:1px solid #f3f4f6;"></div></td></tr>'
              '<tr><td style="padding:20px 28px;">'
              '<p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay &middot; <a href="https://padipay.co" style="color:#d1d5db;text-decoration:none;">padipay.co</a></p>'
              '</td></tr>'
              '</table></td></tr>'
              '</table></td></tr>'
              '</table></body></html>',
        });
      } catch (e) {
        print('Welcome email error (non-fatal): $e');
      }

      // 4. Sign out user (they'll verify email on the next page)
      await FirebaseAuth.instance.signOut();

      // 5. Navigate to OTP verification page (OTP is sent from within that page)
      if (!mounted) return;
      navigateTo(
        context,
        EmailOtpVerificationPage(
          email: email,
          onResend: () async {
            final res = await FirebaseFunctions.instance
                .httpsCallable('sendEmailOTP')
                .call({'email': email, 'purpose': 'verify'});
            return res.data['pinId'] as String;
          },
          onVerified: () async {
            try {
              await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: email,
                password: passwordController.text,
              );
              if (!mounted) return;
              navigateTo(context, const HomePage(),
                  type: NavigationType.clearStack);
            } catch (e) {
              if (!mounted) return;
              showSimpleDialog(
                'Email verified. Please sign in to continue.',
                Colors.orange,
              );
              navigateTo(context, const SignIn(),
                  type: NavigationType.clearStack);
            }
          },
        ),
      );
    } on FirebaseAuthException catch (e) {
      print("error in send email otp $e");
      String errorMsg = 'Error creating account';
      if (e.code == 'email-already-in-use') {
        errorMsg = 'Email already registered';
      } else if (e.code == 'weak-password') {
        errorMsg = 'Password is too weak';
      }
      showSimpleDialog(errorMsg, Colors.red);
    } catch (e) {
      print(e);
      final lower = e.toString().toLowerCase();
      if (lower.contains('permission_denied') || lower.contains('permission-denied') || lower.contains('already exists') || lower.contains('already-exists') || lower.contains('duplicate')) {
        showSimpleDialog('Username not available, please choose another', Colors.red);
      } else {
        showSimpleDialog("Error: $e", Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildPasswordValidation() {
    return Column(
      children: [
        const SizedBox(height: 10),
        _buildValidationItem(
          'One uppercase letter',
          Icons.check_circle_outline,
          _hasUppercase,
        ),
        _buildValidationItem(
          'One lowercase letter',
          Icons.check_circle_outline,
          _hasLowercase,
        ),
        _buildValidationItem(
          'One number',
          Icons.check_circle_outline,
          _hasNumber,
        ),
        _buildValidationItem(
          'One special character',
          Icons.check_circle_outline,
          _hasSymbol,
        ),
        _buildValidationItem(
          'Passwords match',
          Icons.check_circle_outline,
          _passwordsMatch,
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildValidationItem(String text, IconData icon, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: isValid ? Colors.green : Colors.grey, size: 15),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isValid ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios,
                        size: 20,
                        color: Colors.black.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Enter your information just as it's shown on your identity document.",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // First Name
                    Text(
                      "First Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: firstNameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your first name",
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Last Name
                    Text(
                      "Last Name",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: lastNameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your last name",
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Username
                    Text(
                      "Username",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.none,
                      style: TextStyle(fontSize: 14),
                      controller: usernameController,
                      keyboardType: TextInputType.name,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your username",
                        prefixIcon: Icon(
                          Icons.alternate_email,
                          color: Colors.grey.shade600,
                        ),
                        suffixIcon: usernameController.text.isEmpty
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: _isCheckingUsername
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    primaryColor,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Checking...",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: primaryColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : _isUsernameValid
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle,
                                                  color: Colors.green, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Available",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.close,
                                                  color: Colors.red, size: 18),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Taken",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                              ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                      ],
                    ),
                    if (_usernameSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Suggestions:",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: _usernameSuggestions
                            .take(3)
                            .map(
                              (suggestion) => GestureDetector(
                                onTap: () {
                                  usernameController.text = suggestion;
                                  _checkUsernameAvailability();
                                },
                                child: Chip(
                                  label: Text(suggestion),
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 15),

                    // Email
                    Text(
                      "Email Address",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your email",
                      ),
                    ),

                    SizedBox(height: 15),

                    // Phone
                    Text(
                      "Phone Number",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 5),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: CountryCodePicker(
                              padding: EdgeInsetsGeometry.all(0),
                              onChanged: (country) =>
                                  countryCode = country.dialCode!,
                              initialSelection: 'NG',
                              favorite: ['+234', 'NG'],
                              showCountryOnly: false,
                              showOnlyCountryWhenClosed: false,
                              alignLeft: true,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              textInputAction: TextInputAction.next,
                              style: TextStyle(fontSize: 14),
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                hintText: "70 123 45678",
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "Referral Code (Optional)",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.none,
                      style: TextStyle(fontSize: 14),
                      controller: referralCodeController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter referral code",
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: _isCheckingReferral
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Checking...",
                                      style: TextStyle(fontSize: 12, color: primaryColor),
                                    ),
                                  ],
                                )
                              : Text(
                                  referralCodeController.text.isEmpty
                                      ? ""
                                      : (_isReferralValid ? "Valid" : "Invalid"),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isReferralValid ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                      ],
                    ),
                    SizedBox(height: 15),

                    // Password
                    Text(
                      "Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 14),
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your password",
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    _buildPasswordValidation(),
                    const SizedBox(height: 10),

                    // Confirm Password
                    Text(
                      "Confirm Password",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontSize: 14),
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Re-enter password",
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirmPassword =
                                !_obscureConfirmPassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Continue Button
                    InkWell(
                      onTap:
                          _isPasswordValid() &&
                              _isUsernameValid
                          ? _completeSignUp
                          : null,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color:
                              _isPasswordValid() &&
                                  _isUsernameValid
                              ? Colors.blue
                              : Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: isLoading
                              ? SizedBox(
                                  height: 30,
                                  width: 30,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  "Continue",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Login link
                    Center(
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        child: RichText(
                          text: TextSpan(
                            text: "Already have an account? ",
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: "Login",
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
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