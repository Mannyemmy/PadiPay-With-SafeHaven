import 'package:card_app/auth/sign-in.dart';
import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/home_pages/transactions_page.dart';
import 'package:card_app/legal/legal_and_regulatory.dart';
import 'package:card_app/notifications/notification_settings.dart';
import 'package:card_app/profile/choose_upgrade_tier.dart';
import 'package:card_app/profile/edit_profile_page.dart';
import 'package:card_app/profile/customer_support_page.dart';
import 'package:card_app/referrals/referrals.dart';
import 'package:card_app/passcode/change_passcode.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_settings/app_settings.dart';
import 'dart:async';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedIndex = 3;
  String? firstName;
  String? lastName;
  String? phone;
  String? email;
  String? dob;
  String? address1;
  String? state;
  String? country;
  String? profilePhotoUrl;
  String? tier;
  bool isTouchOrFace = false;
  bool _bvnMatch = false;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  bool _deviceSupportsBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricCapability();
    _loadBiometricPreference();
    _fetchUserData();
    _listenForBvnMatch();
  }

  Future<void> _checkBiometricCapability() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      setState(() {
        _deviceSupportsBiometrics = canCheckBiometrics && isDeviceSupported;
      });
    } catch (e) {
      print('Error checking biometric capability: $e');
      setState(() => _deviceSupportsBiometrics = false);
    }
  }

  Future<void> _loadBiometricPreference() async {
    try {
      final saved = await _storage.read(key: 'biometric_enabled');
      if (saved != null && mounted) {
        setState(() => isTouchOrFace = saved == 'true');
      }
    } catch (e) {
      print('Error loading biometric preference: $e');
    }
  }

  Future<void> _toggleBiometricAuth(bool value) async {
    if (value && !_deviceSupportsBiometrics) {
      // Show bottom sheet if user tries to enable but device doesn't support
      showModalBottomSheet(
        context: context,
        builder: (BuildContext context) => SafeArea(
          bottom: true,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Biometric Not Available',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Your device does not support Touch ID or Face ID. Please enable biometric authentication in your device settings first.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        AppSettings.openAppSettings(type: AppSettingsType.security);
                      
                      },
                      child: Text('Open Settings'),
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      );
      return;
    }

    try {
      await _storage.write(
        key: 'biometric_enabled',
        value: value.toString(),
      );
      setState(() => isTouchOrFace = value);
      if (value) {
        showSimpleDialog(
          'Touch ID/Face ID login enabled',
          Colors.green,
        );
      }
    } catch (e) {
      showSimpleDialog(
        'Failed to save preference',
        Colors.red,
      );
    }
  }

  void _listenForBvnMatch() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub?.cancel();
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data() ?? <String, dynamic>{};
      final qore = data['qoreIdData'] as Map<String, dynamic>?;
      final verification = qore?['verification'] as Map<String, dynamic>?;
      final metadata = verification?['metadata'] as Map<String, dynamic>?;
      final match = metadata?['match'];
      if (!mounted) return;
      setState(() {
        _bvnMatch = match == true;
      });
    }, onError: (e) {
      print('BVN match listener error: $e');
    });
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (snap.exists) {
      var data = snap.data() as Map<String, dynamic>;
      setState(() {
        firstName = data['firstName'];
        lastName = data['lastName'];
        phone = data['phone'];
        email = data['email'];
        dob = data['dateOfBirth'];
        address1 = data['address']?['street'];
        state = data['address']?['state'];
        country = data['address']?['country'];
        profilePhotoUrl = data['profilePhotoUrl'];
        tier = (data['getAnchorData']?['tier'] ?? "0").toString();
      });
    }
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        navigateTo(context, HomePage(), type: NavigationType.clearStack);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SizedBox.expand(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 100),
                    CircleAvatar(
                      radius: 60,
                      backgroundImage:
                          profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                              ? NetworkImage(profilePhotoUrl!)
                              : const AssetImage("assets/profile_placeholder.png"),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "${firstName ?? ""} ${lastName ?? ""}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      email ?? "",
                      style: TextStyle(
                        fontWeight: FontWeight.w300,
                        fontSize: 16,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    SizedBox(height: 15),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.green.withValues(alpha: 0.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.task_alt, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              // only append a tier number if there's an actual
                              // banking tier assigned; BVN match alone is not a
                              // real tier.
                              _bvnMatch && tier == "0"
                                  ? "Identity Verified"
                                  : tier == "0"
                                      ? "KYC Not Verified"
                                      : "KYC Verified Tier $tier",
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/profile.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Edit Profile',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, EditProfilePage());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/proicons_gift.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Upgrade Account',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, ChooseUpgradeTier(tier:tier ?? "0"));
                            },
                          ),
                          // ListTile(
                          //   title: Container(
                          //     padding: EdgeInsets.symmetric(
                          //       horizontal: 10,
                          //       vertical: 8,
                          //     ),
                          //     decoration: BoxDecoration(
                          //       borderRadius: BorderRadius.circular(10),
                          //       border: Border.all(color: Colors.grey.shade300),
                          //     ),
                          //     child: Row(
                          //       children: [
                          //         Container(
                          //           padding: EdgeInsets.all(10),
                          //           decoration: BoxDecoration(
                          //             color: Colors.grey.shade100,
                          //             shape: BoxShape.circle,
                          //           ),
                          //           child: SvgPicture.asset(
                          //             'assets/proicons_gift.svg',
                          //             width: 20,
                          //             height: 20,
                          //           ),
                          //         ),
                          //         SizedBox(width: 20),
                          //         Text(
                          //           'Promos & Offers',
                          //           style: TextStyle(
                          //             fontSize: 15,
                          //             fontWeight: FontWeight.w700,
                          //             color: Colors.grey.shade700,
                          //           ),
                          //         ),
                          //         Spacer(),
                          //         Icon(
                          //           Icons.arrow_forward_ios,
                          //           size: 15,
                          //           color: Colors.grey.shade600,
                          //         ),
                          //       ],
                          //     ),
                          //   ),
                          //   onTap: () {
                          //     navigateTo(context, PromosScreen());
                          //   },
                          // ),
                          
                          
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/formkit_people.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Referrals',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, ReferralsScreen());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/hugeicons_notification-square.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Notification Settings',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, NotificationSettings());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/solar_lock-password-broken.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Change Passcode',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, ChangePasscode());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/solar_login-outline.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Login with Fingerprint / Face ID',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  FlutterSwitch(
                                    width: 40,
                                    height: 20,
                                    toggleSize: 20,
                                    borderRadius: 20,
                                    padding: 3,
                                    value: isTouchOrFace,
                                    activeColor: primaryColor,
                                    inactiveColor: Colors.grey.shade300,
                                    onToggle: (val) =>
                                        _toggleBiometricAuth(val),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/octicon_law-24.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Legal',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, LegalAndRegulatory());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: SvgPicture.asset(
                                      'assets/dashicons_admin-site-alt3.svg',
                                      width: 20,
                                      height: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Visit Our Website',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {},
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.headset_mic_outlined,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Customer Support',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () {
                              navigateTo(context, const CustomerSupportPage());
                            },
                          ),
                          ListTile(
                            title: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.logout,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    'Log Out',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Spacer(),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            onTap: () async {
                              await FirebaseAuth.instance.signOut();
                              navigateTo(context, SignIn());
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 150),
                  ],
                ),
              ),
              Positioned(
                bottom: 25,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: BottomNavBar(
                    currentIndex: _selectedIndex,
                    onTap: (index) {
                      if (index == 0) {
                        navigateTo(context, HomePage(), type: NavigationType.push);
                      }
                      if (index == 1) {
                        navigateTo(context, CardsPage(), type: NavigationType.push);
                      }
                      if (index == 2) {
                        navigateTo(context, TransactionsPage(), type: NavigationType.push);
                      } else {
                        setState(() => _selectedIndex = index);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}