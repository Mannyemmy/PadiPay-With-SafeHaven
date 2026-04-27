import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/home_pages/transactions_page.dart';
import 'package:card_app/main.dart'
    show simulateIncomingPaymentNotification, simulateIncomingVoiceAlert;
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  static const String _voiceAlertGenderPreferenceKey = 'voiceAlertGender';
  static const String _voiceAlertLanguagePreferenceKey = 'voiceAlertLanguage';
  static const MethodChannel _notificationMethodChannel = MethodChannel(
    'com.allgoodtech.padipay/notifications',
  );

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
  bool pushNotification = true;
  bool loginNotification = false;
  bool paymentConfirmation = false;
  bool voiceAlerts = true;
  bool voiceAlertSpeakAmount = true;
  String voiceAlertGender = 'female';
  String voiceAlertLanguage = 'english';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pushNotification = prefs.getBool('pushNotification') ?? true;
      loginNotification = prefs.getBool('loginNotification') ?? false;
      paymentConfirmation = prefs.getBool('paymentConfirmation') ?? false;
      voiceAlerts = prefs.getBool('voiceAlerts') ?? true;
      voiceAlertSpeakAmount = prefs.getBool('voiceAlertSpeakAmount') ?? true;
      voiceAlertGender =
          (prefs.getString(_voiceAlertGenderPreferenceKey) ?? 'female') ==
              'male'
          ? 'male'
          : 'female';
      voiceAlertLanguage =
          (prefs.getString(_voiceAlertLanguagePreferenceKey) ?? 'english') ==
              'pidgin'
          ? 'pidgin'
          : 'english';
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = userDoc.data();
        final cloudLoginPref = data?['notificationPreferences'] is Map
            ? (data?['notificationPreferences'] as Map)['loginNotification']
            : null;
        if (cloudLoginPref is bool && mounted) {
          setState(() => loginNotification = cloudLoginPref);
          await prefs.setBool('loginNotification', cloudLoginPref);
        }
      } catch (_) {}
    }
  }

  Future<void> _updateVoiceAlertGender(String value) async {
    setState(() => voiceAlertGender = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceAlertGenderPreferenceKey, value);
  }

  Future<void> _updateVoiceAlertLanguage(String value) async {
    setState(() => voiceAlertLanguage = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceAlertLanguagePreferenceKey, value);
  }

  Future<void> _persistLoginNotificationPreference(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notificationPreferences': {'loginNotification': value},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _openTtsSettings() async {
    try {
      final opened = await _notificationMethodChannel.invokeMethod<bool>(
        'openTtsSettings',
      );
      if (opened == true) return;
      if (!mounted) return;
      showSimpleDialog(
        'Unable to open TTS settings on this device.',
        Colors.red,
      );
    } catch (_) {
      if (!mounted) return;
      showSimpleDialog(
        'Unable to open TTS settings on this device.',
        Colors.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: navyBlue,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 100),
                      Text(
                        'Notification Settings',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Padding(
                      padding: const EdgeInsets.all(0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Push Notification',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        "Get instant transaction push notifications on this device",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                FlutterSwitch(
                                  width: 50,
                                  height: 25,
                                  toggleSize: 20,
                                  borderRadius: 20,
                                  padding: 3,
                                  value: pushNotification,
                                  activeColor: primaryColor,
                                  inactiveColor: Colors.grey.shade300,
                                  onToggle: (val) async {
                                    setState(() => pushNotification = val);
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setBool('pushNotification', val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Login Notification',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        "Enable login notifications on your email each time you login",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                FlutterSwitch(
                                  width: 50,
                                  height: 25,
                                  toggleSize: 20,
                                  borderRadius: 20,
                                  padding: 3,
                                  value: loginNotification,
                                  activeColor: primaryColor,
                                  inactiveColor: Colors.grey.shade300,
                                  onToggle: (val) async {
                                    setState(() => loginNotification = val);
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setBool('loginNotification', val);
                                    await _persistLoginNotificationPreference(
                                      val,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Payment Confirmation',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        "Require approval before accepting incoming wifi payments",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                FlutterSwitch(
                                  width: 50,
                                  height: 25,
                                  toggleSize: 20,
                                  borderRadius: 20,
                                  padding: 3,
                                  value: paymentConfirmation,
                                  activeColor: primaryColor,
                                  inactiveColor: Colors.grey.shade300,
                                  onToggle: (val) async {
                                    setState(() => paymentConfirmation = val);
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setBool('paymentConfirmation', val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Voice Alerts',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        'Speak incoming payment alerts',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                FlutterSwitch(
                                  width: 50,
                                  height: 25,
                                  toggleSize: 20,
                                  borderRadius: 20,
                                  padding: 3,
                                  value: voiceAlerts,
                                  activeColor: primaryColor,
                                  inactiveColor: Colors.grey.shade300,
                                  onToggle: (val) async {
                                    setState(() => voiceAlerts = val);
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    prefs.setBool('voiceAlerts', val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          if (voiceAlerts)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Voice Language',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    'Choose the spoken language for incoming payment alerts.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('English'),
                                          selected:
                                              voiceAlertLanguage == 'english',
                                          onSelected: (selected) {
                                            if (selected) {
                                              _updateVoiceAlertLanguage(
                                                'english',
                                              );
                                            }
                                          },
                                          selectedColor: primaryColor
                                              .withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color:
                                                voiceAlertLanguage == 'english'
                                                ? primaryColor
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          side: BorderSide(
                                            color:
                                                voiceAlertLanguage == 'english'
                                                ? primaryColor
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('Pidgin'),
                                          selected:
                                              voiceAlertLanguage == 'pidgin',
                                          onSelected: (selected) {
                                            if (selected) {
                                              _updateVoiceAlertLanguage(
                                                'pidgin',
                                              );
                                            }
                                          },
                                          selectedColor: primaryColor
                                              .withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color:
                                                voiceAlertLanguage == 'pidgin'
                                                ? primaryColor
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          side: BorderSide(
                                            color:
                                                voiceAlertLanguage == 'pidgin'
                                                ? primaryColor
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    'Voice Style',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    'Choose the voice the app should try to use for alerts. Availability depends on your device TTS engine.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('Female'),
                                          selected:
                                              voiceAlertGender == 'female',
                                          onSelected: (selected) {
                                            if (selected) {
                                              _updateVoiceAlertGender('female');
                                            }
                                          },
                                          selectedColor: primaryColor
                                              .withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color: voiceAlertGender == 'female'
                                                ? primaryColor
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          side: BorderSide(
                                            color: voiceAlertGender == 'female'
                                                ? primaryColor
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('Male'),
                                          selected: voiceAlertGender == 'male',
                                          onSelected: (selected) {
                                            if (selected) {
                                              _updateVoiceAlertGender('male');
                                            }
                                          },
                                          selectedColor: primaryColor
                                              .withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color: voiceAlertGender == 'male'
                                                ? primaryColor
                                                : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          side: BorderSide(
                                            color: voiceAlertGender == 'male'
                                                ? primaryColor
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Speak Amount in Voice Alert',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        'Example: Five thousand naira received in PadiPay',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                FlutterSwitch(
                                  width: 50,
                                  height: 25,
                                  toggleSize: 20,
                                  borderRadius: 20,
                                  padding: 3,
                                  value: voiceAlertSpeakAmount,
                                  activeColor: primaryColor,
                                  inactiveColor: Colors.grey.shade300,
                                  onToggle: voiceAlerts
                                      ? (val) async {
                                          setState(
                                            () => voiceAlertSpeakAmount = val,
                                          );
                                          final prefs =
                                              await SharedPreferences.getInstance();
                                          prefs.setBool(
                                            'voiceAlertSpeakAmount',
                                            val,
                                          );
                                        }
                                      : (_) {},
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final result =
                                      await simulateIncomingPaymentNotification(
                                        amountNaira: 5000,
                                        senderName: 'John',
                                        todayTotalReceivedNaira: 200000,
                                      );

                                  final reason =
                                      result['reason']?.toString() ?? '';
                                  final engineLabel = result['engineLabel']
                                      ?.toString();
                                  final enginePackage = result['enginePackage']
                                      ?.toString();
                                  final voiceName = result['voiceName']
                                      ?.toString();
                                  final usingSyntheticMaleProfile =
                                      result['usingSyntheticMaleProfile'] ==
                                      true;

                                  showSimpleDialog(
                                    'Incoming notification simulation sent.\n\nExpected style:\n- \u20A65,000 received from John\n- Total today: \u20A6200,000\n\n${voiceName == null || voiceName.isEmpty ? '' : 'Voice engine: $voiceName\n'}${usingSyntheticMaleProfile ? 'Male fallback profile active.\n' : ''}$reason',
                                    Colors.green,
                                  );
                                },
                                icon: const Icon(
                                  Icons.notifications_active_outlined,
                                ),
                                label: const Text(
                                  'Simulate Incoming Notification',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),SizedBox(height: 12),
                          // Padding(
                          //   padding: const EdgeInsets.symmetric(
                          //     horizontal: 18,
                          //     vertical: 12,
                          //   ),
                          //   child: SizedBox(
                          //     width: double.infinity,
                          //     child: OutlinedButton.icon(
                          //       onPressed: _openTtsSettings,
                          //       icon: const Icon(Icons.settings_voice_outlined),
                          //       label: const Text('Open TTS Settings'),
                          //       style: OutlinedButton.styleFrom(
                          //         foregroundColor: primaryColor,
                          //         side: BorderSide(color: primaryColor),
                          //         padding: const EdgeInsets.symmetric(
                          //           vertical: 14,
                          //         ),
                          //         shape: RoundedRectangleBorder(
                          //           borderRadius: BorderRadius.circular(10),
                          //         ),
                          //       ),
                          //     ),
                          //   ),
                          // ),
                          // Padding(
                          //   padding: const EdgeInsets.symmetric(
                          //     horizontal: 18,
                          //     vertical: 12,
                          //   ),
                          //   child: SizedBox(
                          //     width: double.infinity,
                          //     child: OutlinedButton.icon(
                          //       onPressed: () async {
                          //         final result =
                          //             await simulateIncomingVoiceAlert();
                          //         final spoken = result['spoken']?.toString();
                          //         final reason =
                          //             result['reason']?.toString() ?? '';
                          //         final configured = result['ttsConfigured'];
                          //         final voicePreference =
                          //             result['voicePreference']?.toString() ??
                          //             voiceAlertGender;
                          //         final enginePreference =
                          //             result['enginePreference']?.toString() ??
                          //             'neural';
                          //         final voiceLanguage =
                          //             result['voiceLanguage']?.toString() ??
                          //             voiceAlertLanguage;
                          //         final engineUsed = result['engineUsed']
                          //             ?.toString();
                          //         final engineLabel = result['engineLabel']
                          //             ?.toString();
                          //         final enginePackage = result['enginePackage']
                          //             ?.toString();
                          //         final googleEngineAvailable =
                          //             result['googleEngineAvailable'] == true;
                          //         final voiceName = result['voiceName']
                          //             ?.toString();
                          //         final pitch = result['pitch'];
                          //         final speechRate = result['speechRate'];
                          //         final usingSyntheticMaleProfile =
                          //             result['usingSyntheticMaleProfile'] ==
                          //             true;
                          //         final ok = result['ok'] == true;

                          //         showSimpleDialog(
                          //           ok
                          //               ? 'Voice alert simulation sent.\n\nSpoken: ${spoken ?? 'N/A'}\nEngine preference: $enginePreference${engineUsed == null || engineUsed.isEmpty ? '' : '\nEngine used: $engineUsed'}\nVoice language: $voiceLanguage\nVoice style: $voicePreference${engineLabel == null || engineLabel.isEmpty ? '' : '\nTTS engine: $engineLabel'}${enginePackage == null || enginePackage.isEmpty ? '' : '\nEngine package: $enginePackage'}${voiceName == null || voiceName.isEmpty ? '' : '\nVoice name: $voiceName'}${pitch == null ? '' : '\nPitch: $pitch'}${speechRate == null ? '' : '\nSpeech rate: $speechRate'}${!googleEngineAvailable ? '\nGoogle TTS is not available on this device, so Android is using a fallback engine.' : ''}${usingSyntheticMaleProfile ? '\nMale fallback profile is active because this engine did not expose a true male voice.' : ''}\nTTS configured: ${configured ?? false}'
                          //               : 'Voice alert simulation failed.\n\nReason: $reason\nSpoken: ${spoken ?? 'N/A'}\nEngine preference: $enginePreference${engineUsed == null || engineUsed.isEmpty ? '' : '\nEngine used: $engineUsed'}\nVoice language: $voiceLanguage\nVoice style: $voicePreference${engineLabel == null || engineLabel.isEmpty ? '' : '\nTTS engine: $engineLabel'}${enginePackage == null || enginePackage.isEmpty ? '' : '\nEngine package: $enginePackage'}${voiceName == null || voiceName.isEmpty ? '' : '\nVoice name: $voiceName'}${pitch == null ? '' : '\nPitch: $pitch'}${speechRate == null ? '' : '\nSpeech rate: $speechRate'}${!googleEngineAvailable ? '\nGoogle TTS is not available on this device, so Android is using a fallback engine.' : ''}${usingSyntheticMaleProfile ? '\nMale fallback profile is active because this engine did not expose a true male voice.' : ''}\nTTS configured: ${configured ?? false}',
                          //           ok ? Colors.green : Colors.red,
                          //         );
                          //       },
                          //       icon: const Icon(
                          //         Icons.record_voice_over_outlined,
                          //       ),
                          //       label: const Text('Test Voice Alert'),
                          //       style: OutlinedButton.styleFrom(
                          //         foregroundColor: primaryColor,
                          //         side: BorderSide(color: primaryColor),
                          //         padding: const EdgeInsets.symmetric(
                          //           vertical: 14,
                          //         ),
                          //         shape: RoundedRectangleBorder(
                          //           borderRadius: BorderRadius.circular(10),
                          //         ),
                          //       ),
                          //     ),
                          //   ),
                          // ),
                       
                       
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
                      navigateTo(
                        context,
                        HomePage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 1) {
                      navigateTo(
                        context,
                        CardsPage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 2) {
                      navigateTo(
                        context,
                        TransactionsPage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 3) {
                      navigateTo(
                        context,
                        ProfilePage(),
                        type: NavigationType.push,
                      );
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
    );
  }
}
