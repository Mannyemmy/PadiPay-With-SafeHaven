import 'package:card_app/auth/email_otp_verification_page.dart';
import 'package:card_app/auth/forgot_password_page.dart';
import 'package:card_app/auth/sign-up.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isBiometricLoading = false;

  final _storage = const FlutterSecureStorage();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _biometricEnabled = false;
  bool _deviceSupportsBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadStoredEmail();
    _checkBiometricCapability();
    _loadBiometricPreference();
  }

  Future<void> _checkBiometricCapability() async {
    try {
      final localAuth = LocalAuthentication();
      final canCheckBiometrics = await localAuth.canCheckBiometrics;
      final isDeviceSupported = await localAuth.isDeviceSupported();
      final isSupported = canCheckBiometrics && isDeviceSupported;

      if (mounted) {
        setState(() {
          _deviceSupportsBiometrics = isSupported;
        });
      }
    } catch (e) {
      print('Error checking biometric capability: $e');
      if (mounted) setState(() => _deviceSupportsBiometrics = false);
    }
  }

  Future<void> _loadBiometricPreference() async {
    try {
      final saved = await _storage.read(key: 'biometric_enabled');
      if (mounted) {
        setState(() => _biometricEnabled = saved == 'true');
      }
    } catch (e) {
      print('Error loading biometric preference: $e');
    }
  }

  Future<void> _loadStoredEmail() async {
    String? email = await _storage.read(key: 'email');
    if (email != null) {
      emailController.text = email;
    }
  }

  Future<Map<String, dynamic>?> _getLocationData() async {
    try {
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'city': data['city'] ?? 'Unknown',
          'country': data['country_name'] ?? 'Unknown',
          'region': data['region'] ?? 'Unknown',
          'org': data['org'] ?? 'Unknown',
          'ip': data['ip'] ?? 'Unknown',
        };
      }
    } catch (e) {
      print('Error getting location: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
        return {
          'device': androidInfo.model,
          'os': 'Android ${androidInfo.version.release}',
          'manufacturer': androidInfo.manufacturer,
        };
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
        return {
          'device': iosInfo.model,
          'os': 'iOS ${iosInfo.systemVersion}',
          'manufacturer': 'Apple',
        };
      }
    } catch (e) {
      print('Error getting device info: $e');
    }
    return {'device': 'Unknown', 'os': 'Unknown', 'manufacturer': 'Unknown'};
  }

  Future<void> _sendLoginNotificationEmail({
    required String email,
    required bool success,
    String? location,
    String? errorReason,
  }) async {
    final notificationsEnabled = await _isLoginEmailNotificationEnabled(
      email: email,
    );
    if (!notificationsEnabled) {
      return;
    }

    try {
      final timestamp = DateTime.now().toString();

      String subject;
      String htmlBody;

      if (success) {
        subject = '✓ Successful Login to Your PadiPay Account';
        htmlBody =
            '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Successful Login</title>
</head>
<body style="margin:0;padding:0;background-color:#f0f2f5;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0f2f5;padding:40px 0;">
    <tr>
      <td align="center">
        <table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <span style="font-size:22px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#10b981;">Pay</span></span>
            </td>
          </tr>
          <tr>
            <td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">
              <tr>
                <td style="background:linear-gradient(135deg,#10b981 0%,#059669 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td>
              </tr>
              <tr>
                <td style="padding:40px 48px 36px;">
                  <p style="margin:0 0 8px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#10b981;">Account Access</p>
                  <h1 style="margin:0 0 16px;font-size:26px;font-weight:700;color:#0f0f1a;line-height:1.2;">Sign-in Confirmed</h1>
                  <p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.6;">You successfully signed in to your PadiPay account.</p>
                  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f9fafb;border-left:4px solid #10b981;border-radius:8px;padding:16px;margin:24px 0;">
                    <tr>
                      <td>
                        <p style="margin:0;font-size:13px;color:#374151;"><strong>Location:</strong> $location</p>
                        <p style="margin:8px 0 0;font-size:13px;color:#374151;"><strong>Time:</strong> $timestamp</p>
                      </td>
                    </tr>
                  </table>
                  <p style="margin:24px 0 0;font-size:13px;color:#9ca3af;line-height:1.6;">If this wasn't you, please change your password immediately and contact our support team.</p>
                </td>
              </tr>
              <tr>
                <td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td>
              </tr>
              <tr>
                <td style="padding:24px 48px;">
                  <p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay &middot; <a href="https://padipay.co" style="color:#d1d5db;text-decoration:none;">padipay.co</a></p>
                </td>
              </tr>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
      } else {
        subject = '⚠ Failed Login Attempt on Your PadiPay Account';
        htmlBody =
            '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Failed Login Attempt</title>
</head>
<body style="margin:0;padding:0;background-color:#f0f2f5;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f0f2f5;padding:40px 0;">
    <tr>
      <td align="center">
        <table width="520" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;">
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <span style="font-size:22px;font-weight:700;color:#1a1a2e;letter-spacing:-0.5px;">Padi<span style="color:#ef4444;">Pay</span></span>
            </td>
          </tr>
          <tr>
            <td style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.07);">
              <tr>
                <td style="background:linear-gradient(135deg,#ef4444 0%,#dc2626 100%);height:5px;font-size:0;line-height:0;">&nbsp;</td>
              </tr>
              <tr>
                <td style="padding:40px 48px 36px;">
                  <p style="margin:0 0 8px;font-size:13px;font-weight:600;letter-spacing:1.2px;text-transform:uppercase;color:#ef4444;">Security Alert</p>
                  <h1 style="margin:0 0 16px;font-size:26px;font-weight:700;color:#0f0f1a;line-height:1.2;">Failed Login Attempt</h1>
                  <p style="margin:0 0 24px;font-size:15px;color:#6b7280;line-height:1.6;">We detected a failed login attempt on your account.</p>
                  <table width="100%" cellpadding="0" cellspacing="0" style="background:#fef2f2;border-left:4px solid #ef4444;border-radius:8px;padding:16px;margin:24px 0;">
                    <tr>
                      <td>
                        <p style="margin:0;font-size:13px;color:#374151;"><strong>Location:</strong> $location</p>
                        <p style="margin:8px 0 0;font-size:13px;color:#374151;"><strong>Reason:</strong> $errorReason</p>
                        <p style="margin:8px 0 0;font-size:13px;color:#374151;"><strong>Time:</strong> $timestamp</p>
                      </td>
                    </tr>
                  </table>
                  <p style="margin:24px 0 0;font-size:13px;color:#9ca3af;line-height:1.6;">If this was you, you can safely ignore this alert. If this wasn't you, please secure your account by changing your password immediately.</p>
                </td>
              </tr>
              <tr>
                <td style="padding:0 48px;"><div style="border-top:1px solid #f3f4f6;"></div></td>
              </tr>
              <tr>
                <td style="padding:24px 48px;">
                  <p style="margin:0;font-size:12px;color:#d1d5db;">&copy; 2026 PadiPay &middot; <a href="https://padipay.co" style="color:#d1d5db;text-decoration:none;">padipay.co</a></p>
                </td>
              </tr>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
      }

      await FirebaseFunctions.instance.httpsCallable('sendEmail').call({
        'to': email,
        'subject': subject,
        'html': htmlBody,
      });
    } catch (e) {
      print('Error sending login notification email: $e');
      // Don't show error to user, silently fail
    }
  }

  Future<bool> _isLoginEmailNotificationEnabled({String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var enabled = prefs.getBool('loginNotification') ?? false;

      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        userDoc = await _firestore.collection('users').doc(uid).get();
      } else if (email != null && email.trim().isNotEmpty) {
        final trimmedEmail = email.trim();
        final query = await _firestore
            .collection('users')
            .where('email', isEqualTo: trimmedEmail.toLowerCase())
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          userDoc = query.docs.first;
        } else {
          final fallbackQuery = await _firestore
              .collection('users')
              .where('email', isEqualTo: trimmedEmail)
              .limit(1)
              .get();
          if (fallbackQuery.docs.isNotEmpty) {
            userDoc = fallbackQuery.docs.first;
          }
        }
      }

      final data = userDoc?.data();
      final notificationPrefs =
          data?['notificationPreferences'] as Map<String, dynamic>?;
      final cloudValue = notificationPrefs?['loginNotification'];
      if (cloudValue is bool) {
        enabled = cloudValue;
        await prefs.setBool('loginNotification', cloudValue);
      }

      return enabled;
    } catch (e) {
      print('Error resolving login notification preference: $e');
      return false;
    }
  }

  Future<void> _saveLoginLog({
    required String email,
    required bool success,
    String? errorMessage,
    String? ipAddress,
    Map<String, dynamic>? location,
  }) async {
    try {
      Map<String, dynamic> deviceInfo = await _getDeviceInfo();
      var connectivityResult = await Connectivity().checkConnectivity();
      String networkType = connectivityResult.toString();

      final logData = {
        'email': email,
        'success': success,
        'errorMessage': errorMessage,
        'ip': ipAddress ?? 'Unknown',
        'location':
            location ??
            {
              'city': 'Unknown',
              'country': 'Unknown',
              'region': 'Unknown',
              'org': 'Unknown',
            },
        'deviceInfo': deviceInfo,
        'networkType': networkType,
        'timestamp': FieldValue.serverTimestamp(),
        'userAgent': 'Flutter App',
        'appType': 'user',
      };

      await _firestore.collection('loginLogs').add(logData);

      // Save login notification for successful logins
      if (success) {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          final city = (location?['city'] ?? 'Unknown').toString();
          final country = (location?['country'] ?? 'Unknown').toString();
          await _firestore
              .collection('users')
              .doc(uid)
              .collection('notifications')
              .add({
                'title': 'New Login Detected',
                'body': 'New sign-in from $city, $country',
                'type': 'login',
                'amount': null,
                'read': false,
                'timestamp': FieldValue.serverTimestamp(),
              });
        }
      }
    } catch (e) {
      print('Error saving login log: $e');
      // Don't show error to user, just log it
    }
  }

  // Check if email is blocked
  // Check if email is blocked
  Future<bool> _isEmailBlocked(String email) async {
    try {
      final emailKey = email.toLowerCase().trim();
      final blockedDoc = await _firestore
          .collection('blockedLogins')
          .doc(emailKey)
          .get();

      if (!blockedDoc.exists) {
        return false;
      }

      final data = blockedDoc.data();
      if (data == null) return false;

      final blockedUntil = data['blockedUntil'] as Timestamp?;
      if (blockedUntil == null) return false;

      final now = DateTime.now();
      final blockedDate = blockedUntil.toDate();

      if (now.isAfter(blockedDate)) {
        // Block expired → clean up
        await _firestore.collection('blockedLogins').doc(emailKey).delete();
        return false;
      }

      return true;
    } catch (e) {
      print('Error checking blocked status: $e');
      return false;
    }
  } // Get remaining blocked time

  // Get remaining block time (returns null if not blocked)
  Future<Duration?> _getRemainingBlockTime(String email) async {
    try {
      final emailKey = email.toLowerCase().trim();
      final doc = await _firestore
          .collection('blockedLogins')
          .doc(emailKey)
          .get();

      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      final blockedUntil = data['blockedUntil'] as Timestamp?;
      if (blockedUntil == null) return null;

      final blockedDate = blockedUntil.toDate();
      final now = DateTime.now();

      if (now.isAfter(blockedDate)) return null;

      return blockedDate.difference(now);
    } catch (e) {
      print('Error getting remaining time: $e');
      return null;
    }
  } // Update failed login attempts

  // Update failed login attempts
  // Most important fix — failed attempt counter + block only after 3
  Future<void> _updateFailedAttempts(String email, bool isSuccessful) async {
    final emailKey = email.toLowerCase().trim();

    if (isSuccessful) {
      // Successful login → clear everything
      try {
        await _firestore.collection('blockedLogins').doc(emailKey).delete();
        print('Cleared failed attempts & block for $email');
      } catch (e) {
        print('Error clearing block: $e');
      }
      return;
    }

    // ── Failed attempt ────────────────────────────────────────────────
    final blockedRef = _firestore.collection('blockedLogins').doc(emailKey);

    try {
      final doc = await blockedRef.get();
      final now = DateTime.now();

      int attempts = 0;
      Timestamp? firstFailedAt;

      if (doc.exists) {
        final data = doc.data()!;
        attempts = (data['failedAttempts'] as int?) ?? 0;
        firstFailedAt = data['firstFailedAt'] as Timestamp?;
      }

      attempts += 1;

      firstFailedAt ??= Timestamp.fromDate(now);

      final updateData = <String, dynamic>{
        'email': email,
        'failedAttempts': attempts,
        'firstFailedAt': firstFailedAt,
        'lastFailedAt': Timestamp.fromDate(now),
        'appType': 'user',
      };

      // Block only after 3 or more failed attempts
      if (attempts >= 3) {
        final blockedUntil = Timestamp.fromDate(
          now.add(const Duration(hours: 1)),
        );
        updateData['blockedUntil'] = blockedUntil;
        print('BLOCKING $email until $blockedUntil (attempts: $attempts)');

        // Notify admin/security team
        _sendBlockNotification(email);
      }

      await blockedRef.set(updateData, firestore.SetOptions(merge: true));
      print('Failed attempts updated → $attempts for $email');
    } catch (e) {
      print('Error updating failed attempts: $e');
    }
  }

  Future<void> _sendBlockNotification(String email) async {
    try {
      await _firestore.collection('securityEvents').add({
        'type': 'login_blocked',
        'email': email,
        'reason': 'Too many failed login attempts',
        'blockedUntil': DateTime.now().add(Duration(hours: 1)),
        'timestamp': FieldValue.serverTimestamp(),
        'appType': 'user',
      });
    } catch (e) {
      print('Error sending block notification: $e');
    }
  }

  // Check if user exists
  // Better method: Check Firestore for user/business existence
  Future<bool> _checkUserExists(String email) async {
    try {
      // For user app:
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking user in Firestore: $e');
      return true; // Assume exists for safety
    }
  }

  void _signIn() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      showSimpleDialog("Please fill all fields", Colors.red);
      return;
    }

    final email = emailController.text.trim();

    setState(() => _isLoading = true);

    final isBlocked = await _isEmailBlocked(email);

    if (isBlocked) {
      setState(() => _isLoading = false);
      final remaining = await _getRemainingBlockTime(email);
      _showBlockedBottomSheet(email, remaining);
      return;
    }

    String? ipAddress;
    Map<String, dynamic>? locationData;

    try {
      locationData = await _getLocationData();
      ipAddress = locationData?['ip'];
    } catch (_) {}

    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );

      await _updateFailedAttempts(email, true);

      // Send success login notification email
      final locationStr =
          '${locationData?['city'] ?? 'Unknown'}, ${locationData?['country'] ?? 'Unknown'}';
      await _sendLoginNotificationEmail(
        email: email,
        success: true,
        location: locationStr,
      );

      if (!_auth.currentUser!.emailVerified) {
        // Send OTP to email for verification instead of Firebase email link
        try {
          final otpResult = await FirebaseFunctions.instance
              .httpsCallable('sendEmailOTP')
              .call({'email': email, 'purpose': 'verify'});
          final pinId = otpResult.data['pinId'] as String;

          await _auth.signOut();

          if (!mounted) return;
          setState(() => _isLoading = false);
          navigateTo(
            context,
            EmailOtpVerificationPage(
              email: email,
              pinId: pinId,
              onResend: () async {
                final res = await FirebaseFunctions.instance
                    .httpsCallable('sendEmailOTP')
                    .call({'email': email, 'purpose': 'verify'});
                return res.data['pinId'] as String;
              },
              onVerified: () async {
                // Re-sign in now that email is verified
                final password =
                    await _storage.read(key: 'password') ??
                    passwordController.text;
                try {
                  await _auth.signInWithEmailAndPassword(
                    email: email,
                    password: password,
                  );
                  if (mounted) navigateTo(context, const HomePage());
                } catch (_) {
                  if (mounted) {
                    navigateTo(
                      context,
                      const SignIn(),
                      type: NavigationType.clearStack,
                    );
                  }
                }
              },
            ),
          );
          return; // ← IMPORTANT: Don't continue with normal login flow
        } catch (e) {
          await _auth.signOut();
          setState(() => _isLoading = false);
          showSimpleDialog(
            'Please verify your email. Failed to send OTP.',
            Colors.red,
          );
          return; // ← IMPORTANT: Exit on OTP send failure
        }
      }

      // Only reach here if email is already verified
      await _storage.write(key: 'email', value: email);
      await _storage.write(key: 'password', value: passwordController.text);

      await _saveLoginLog(
        email: email,
        success: true,
        errorMessage: null,
        ipAddress: ipAddress,
        location: locationData,
      );

      navigateTo(context, const HomePage());
    } on FirebaseAuthException catch (e) {
      String msg;
      bool countAsFailed = false;

      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          final exists = await _checkUserExists(email);
          if (exists) countAsFailed = true;
          break;
        case 'wrong-password':
          msg = 'Incorrect password';
          countAsFailed = true;
          break;
        case 'invalid-email':
          msg = 'Invalid email format';
          break;
        case 'user-disabled':
          msg = 'Account has been disabled';
          break;
        default:
          msg = e.message ?? 'Login failed';
          countAsFailed = true; // ← most other errors also count
      }

      if (countAsFailed) {
        await _updateFailedAttempts(email, false);

        // Send failed login notification email
        final locationStr =
            '${locationData?['city'] ?? 'Unknown'}, ${locationData?['country'] ?? 'Unknown'}';
        await _sendLoginNotificationEmail(
          email: email,
          success: false,
          location: locationStr,
          errorReason: msg,
        );

        final attempts = await _getCurrentFailedAttempts(email);

        if (attempts >= 3) {
          final remaining = await _getRemainingBlockTime(email);
          setState(() => _isLoading = false);
          _showBlockedBottomSheet(email, remaining);
          return;
        } else if (attempts == 1 || attempts == 2) {
          setState(() => _isLoading = false);
          _showFailedAttemptWarning(email, attempts);
          showSimpleDialog(msg, Colors.red);
        } else {
          showSimpleDialog(msg, Colors.red);
        }
      } else {
        showSimpleDialog(msg, Colors.red);
      }

      await _saveLoginLog(
        email: email,
        success: false,
        errorMessage: msg,
        ipAddress: ipAddress,
        location: locationData,
      );
    } catch (e) {
      showSimpleDialog("An error occurred", Colors.red);
      print(e);

      // Count unexpected errors as failed attempts too
      await _updateFailedAttempts(email, false);
      final attempts = await _getCurrentFailedAttempts(email);
      if (attempts > 0 && attempts < 3) {
        _showFailedAttemptWarning(email, attempts);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<int> _getCurrentFailedAttempts(String email) async {
    try {
      final doc = await _firestore
          .collection('blockedLogins')
          .doc(email.toLowerCase().trim())
          .get();

      if (doc.exists) {
        return (doc.data()?['failedAttempts'] as int?) ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  void _showFailedAttemptWarning(String email, int attempts) {
    if (attempts < 1 || attempts >= 3) return;

    final remainingAttempts = 3 - attempts;
    String message;

    if (remainingAttempts == 2) {
      message =
          'Incorrect credentials.\n\nYou have **2 more attempts** before your account is temporarily blocked for 1 hour.';
    } else if (remainingAttempts == 1) {
      message =
          'Incorrect credentials.\n\n**1 more attempt** and your account will be blocked for 1 hour.';
    } else {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
              const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                'Warning',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
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

  // Add this method to show bottom sheet when blocked
  void _showBlockedBottomSheet(String email, Duration? remainingTime) {
    String message =
        'Your account has been temporarily blocked due to too many failed login attempts.';

    if (remainingTime != null) {
      final minutes = remainingTime.inMinutes;
      if (minutes > 0) {
        message +=
            '\n\nPlease try again in $minutes minute${minutes > 1 ? 's' : ''}.';
      } else {
        final seconds = remainingTime.inSeconds;
        message +=
            '\n\nPlease try again in $seconds second${seconds > 1 ? 's' : ''}.';
      }
    } else {
      message += '\n\nPlease try again later.';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
              const Icon(Icons.lock_clock, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Account Blocked',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmailVerificationBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                'We sent a verification link to your email. Please check your inbox and click the link to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
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

  Future<void> _biometricAuth() async {
    // Prevent multi-tap - set loading immediately
    if (_isBiometricLoading) return;

    setState(() {
      _isBiometricLoading = true;
    });

    final LocalAuthentication auth = LocalAuthentication();
    bool authenticated = false;

    String? ipAddress;
    Map<String, dynamic>? location;

    try {
      location = await _getLocationData();
      ipAddress = location?['ip'];
    } catch (e) {
      print('Error fetching location: $e');
    }

    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to sign in',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      if (mounted) {
        showSimpleDialog("Authentication failed: $e", Colors.red);
      }
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
      return;
    }

    if (authenticated) {
      String? email = await _storage.read(key: 'email');
      String? password = await _storage.read(key: 'password');
      if (email != null && password != null) {
        // Check if email is blocked
        final isBlocked = await _isEmailBlocked(email);
        // In the biometric auth method, after checking if blocked:
        if (isBlocked) {
          final remainingTime = await _getRemainingBlockTime(email);
          if (mounted) {
            _showBlockedBottomSheet(email, remainingTime);
            setState(() => _isBiometricLoading = false);
          }
          return;
        }

        try {
          await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );

          // Reset failed attempts on successful login
          await _updateFailedAttempts(email, true);

          // Send success login notification email
          final locationStr =
              '${location?['city'] ?? 'Unknown'}, ${location?['country'] ?? 'Unknown'}';
          await _sendLoginNotificationEmail(
            email: email,
            success: true,
            location: locationStr,
          );

          if (!_auth.currentUser!.emailVerified) {
            // Send OTP to email for verification instead of Firebase email link
            try {
              final otpResult = await FirebaseFunctions.instance
                  .httpsCallable('sendEmailOTP')
                  .call({'email': email, 'purpose': 'verify'});
              final pinId = otpResult.data['pinId'] as String;

              await _auth.signOut();
              if (mounted) {
                setState(() => _isLoading = false);
              }

              if (!mounted) return;
              navigateTo(
                context,
                EmailOtpVerificationPage(
                  email: email,
                  pinId: pinId,
                  onResend: () async {
                    final res = await FirebaseFunctions.instance
                        .httpsCallable('sendEmailOTP')
                        .call({'email': email, 'purpose': 'verify'});
                    return res.data['pinId'] as String;
                  },
                  onVerified: () async {
                    // Re-sign in now that email is verified
                    final pw = await _storage.read(key: 'password') ?? '';
                    try {
                      await _auth.signInWithEmailAndPassword(
                        email: email,
                        password: pw,
                      );
                      if (mounted) navigateTo(context, const HomePage());
                    } catch (_) {
                      if (mounted) {
                        navigateTo(
                          context,
                          const SignIn(),
                          type: NavigationType.clearStack,
                        );
                      }
                    }
                  },
                ),
              );
              return; // ← IMPORTANT: Don't continue with normal login flow
            } catch (e) {
              await _auth.signOut();
              if (mounted) {
                setState(() => _isLoading = false);
              }
              showSimpleDialog(
                'Please verify your email. Failed to send OTP.',
                Colors.red,
              );
              return; // ← IMPORTANT: Exit on OTP send failure
            }
          }

          // Only reach here if email is already verified
          // Log successful biometric login
          await _saveLoginLog(
            email: email,
            success: true,
            errorMessage: null,
            ipAddress: ipAddress,
            location: location,
          );

          navigateTo(context, HomePage());
        } on FirebaseAuthException catch (e) {
          String errorMessage;
          bool shouldCountAsFailed = false;

          switch (e.code) {
            case 'user-not-found':
              errorMessage = 'No account exists for this email';
              final userExists = await _checkUserExists(email);
              if (userExists) {
                shouldCountAsFailed = true;
              }
              break;
            case 'wrong-password':
              errorMessage = 'Incorrect password';
              shouldCountAsFailed = true;
              break;
            case 'invalid-email':
              errorMessage = 'Invalid email format';
              break;
            case 'user-disabled':
              errorMessage = 'This account has been disabled';
              break;
            default:
              errorMessage = 'Login failed: ${e.message}';
          }

          // Update failed attempts for biometric failures
          if (shouldCountAsFailed) {
            await _updateFailedAttempts(email, false);

            // Send failed login notification email
            final locationStr =
                '${location?['city'] ?? 'Unknown'}, ${location?['country'] ?? 'Unknown'}';
            await _sendLoginNotificationEmail(
              email: email,
              success: false,
              location: locationStr,
              errorReason: errorMessage,
            );

            // Check if account is now blocked
            final isNowBlocked = await _isEmailBlocked(email);
            if (isNowBlocked) {
              final remainingTime = await _getRemainingBlockTime(email);
              if (remainingTime != null) {
                errorMessage =
                    'Too many failed attempts. Account is temporarily blocked. Please try again in ${remainingTime.inMinutes} minute${remainingTime.inMinutes > 1 ? 's' : ''}.';
              }
            }
          }

          showSimpleDialog(errorMessage, Colors.red);

          // Log failed biometric login
          await _saveLoginLog(
            email: email ?? 'Unknown',
            success: false,
            errorMessage: 'Biometric: $errorMessage',
            ipAddress: ipAddress,
            location: location,
          );
        } finally {
          if (mounted) {
            setState(() {
              _isBiometricLoading = false;
            });
          }
        }
      } else {
        showSimpleDialog(
          "No previous saved account, please sign in",
          Colors.red,
        );

        // Log biometric attempt with no saved credentials
        await _saveLoginLog(
          email: 'Unknown',
          success: false,
          errorMessage: 'No saved credentials for biometric login',
          ipAddress: ipAddress,
          location: location,
        );
        if (mounted) {
          setState(() => _isBiometricLoading = false);
        }
      }
    } else {
      // Log failed biometric authentication
      await _saveLoginLog(
        email: emailController.text.isNotEmpty
            ? emailController.text
            : 'Unknown',
        success: false,
        errorMessage: 'Biometric authentication failed or cancelled',
        ipAddress: ipAddress,
        location: location,
      );
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Icon(
                        Icons.arrow_back_ios,
                        size: 20,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "Welcome Back",
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Welcome back, enter your credentials to access your account",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Email Address",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      style: TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: "Enter your email",
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Password",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      style: TextStyle(fontSize: 15),
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
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              navigateTo(context, const ForgotPasswordPage()),
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    InkWell(
                      onTap: (_isLoading || _isBiometricLoading)
                          ? null
                          : _signIn,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isLoading
                              ? CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                )
                              : Text(
                                  "Log In",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    InkWell(
                      onTap: () {
                        navigateTo(context, SignUp());
                      },
                      child: Center(
                        child: RichText(
                          text: TextSpan(
                            text: "Don't have an account? ",
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black,
                              fontWeight: FontWeight.w400,
                            ),
                            children: [
                              TextSpan(
                                text: "Create Account",
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                if (_biometricEnabled && _deviceSupportsBiometrics)
                  Center(
                    child: GestureDetector(
                      onTap: _isBiometricLoading ? null : _biometricAuth,
                      child: SizedBox(
                        height: 100,
                        width: 100,
                        child: Center(
                          child: _isBiometricLoading
                              ? const SizedBox(
                                  height: 36,
                                  width: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.fingerprint,
                                  size: 72,
                                  color: Colors.blue,
                                ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
