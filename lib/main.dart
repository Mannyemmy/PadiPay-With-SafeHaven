import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'dart:convert';
import 'dart:math';

import 'package:card_app/auth/sign-in.dart';
import 'package:card_app/firebase_options.dart';
import 'package:card_app/utils.dart';
import 'package:card_app/withdrawal_approval_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloudcard_flutter/cloudcard_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui' as ui;
import 'package:card_app/utils/jailbreak_detector.dart';
import 'package:in_app_update/in_app_update.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final FlutterTts _flutterTts = FlutterTts();
final AudioPlayer _neuralAudioPlayer = AudioPlayer();
bool _ttsConfigured = false;
String? _ttsConfiguredVoicePreference;
String? _ttsConfiguredVoiceName;
String? _ttsConfiguredEnginePackage;
String? _ttsConfiguredEngineLabel;
double? _ttsConfiguredPitch;
double? _ttsConfiguredSpeechRate;
bool _ttsUsingSyntheticMaleProfile = false;
bool _ttsGoogleEngineAvailable = false;

const String _voiceAlertsPreferenceKey = 'voiceAlerts';
const String _voiceAlertSpeakAmountPreferenceKey = 'voiceAlertSpeakAmount';
const String _voiceAlertGenderPreferenceKey = 'voiceAlertGender';
const String _voiceAlertLanguagePreferenceKey = 'voiceAlertLanguage';
const MethodChannel _notificationMethodChannel = MethodChannel(
  'com.allgoodtech.padipay/notifications',
);

final ValueNotifier<String?> pendingApprovalNotifier = ValueNotifier(null);
// navigatorKey is defined in utils.dart; imported above

// =========================================================
// BACKGROUND HANDLER
// =========================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _showNotification(message);

  if (message.data['type'] == 'kyc_awaiting_document') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('open_kyb_upgrade', true);
  }
}

// =========================================================
// NOTIFICATION CHANNEL
// =========================================================
Future<void> _createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'padi_transactions_channel',
    'Transactions Notifications',
    description: 'This channel is used for transactions notifications.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidPlugin?.createNotificationChannel(channel);
}

// =========================================================
// SHOW LOCAL NOTIFICATION
// =========================================================
Future<void> _showNotification(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  final bool enablePush = prefs.getBool('pushNotification') ?? true;
  if (!enablePush) return;

  final isIncomingPayment = _isIncomingPaymentPayloadLike(
    message.data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
  );

  final senderName = _extractIncomingSenderName(message.data);
  final amountNaira = _parseAmountNairaFromPayload(
    message.data,
    fallbackBody: message.notification?.body,
  );
  final todayTotalNaira = await _resolveTodayReceivedTotalNaira(
    data: message.data,
  );

  final incomingBodyLine = amountNaira != null && amountNaira > 0
      ? '${_formatNaira(amountNaira)} received${senderName == null ? '' : ' from $senderName'}'
      : (message.data['body'] ??
                message.notification?.body ??
                'Payment received')
            .toString();
  final incomingSummaryLine = todayTotalNaira != null && todayTotalNaira > 0
      ? 'Total today: ${_formatNaira(todayTotalNaira)}'
      : null;
  const incomingTitle = 'Cash Just Landed! \uD83D\uDCB0';
  final incomingBigText = [
    '<b>$incomingBodyLine</b>',
    if (incomingSummaryLine != null) incomingSummaryLine,
    '<i>Tap to view transaction details</i>',
  ].join('<br/>');

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (isIncomingPayment) {
      final shownByNative = await _showIncomingPaymentNotificationNative(
        amountNaira: amountNaira,
        senderName: senderName,
        todayTotalNaira: todayTotalNaira,
        title: incomingTitle,
      );
      if (shownByNative) {
        return;
      }
    }
  }

  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'padi_transactions_channel',
    'Transactions Notifications',
    channelDescription: 'Used for transaction notifications.',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    autoCancel: true,
  );

  if (isIncomingPayment) {
    androidDetails = AndroidNotificationDetails(
      'padi_transactions_channel',
      'Transactions Notifications',
      channelDescription: 'Used for transaction notifications.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      category: AndroidNotificationCategory.message,
      color: const Color(0xFF16C79A),
      colorized: true,
      subText: 'Padi Pay Incoming',
      styleInformation: BigTextStyleInformation(
        incomingBigText,
        htmlFormatBigText: true,
        contentTitle: '<b>$incomingTitle</b>',
        htmlFormatContentTitle: true,
        summaryText: incomingSummaryLine ?? 'Padi Pay',
        htmlFormatSummaryText: true,
      ),
    );
  }

  if (message.data['type'] == 'withdrawal_request') {
    androidDetails = AndroidNotificationDetails(
      'padi_transactions_channel',
      'Transactions Notifications',
      channelDescription: 'Used for withdrawal notifications.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      //   actions: [approveAction, declineAction],
    );
  }

  final NotificationDetails platform = NotificationDetails(
    android: androidDetails,
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  await flutterLocalNotificationsPlugin.show(
    Random().nextInt(2147483647),
    isIncomingPayment
        ? incomingTitle
        : (message.data['title'] ??
                  message.notification?.title ??
                  'Notification')
              .toString(),
    isIncomingPayment
        ? ([
            incomingBodyLine,
            if (incomingSummaryLine != null) incomingSummaryLine,
          ].join('\n'))
        : (message.data['body'] ?? message.notification?.body ?? '').toString(),
    platform,
    payload: jsonEncode(message.data),
  );
}

Future<bool> _showIncomingPaymentNotificationNative({
  required double? amountNaira,
  required String? senderName,
  required double? todayTotalNaira,
  required String title,
}) async {
  try {
    final result = await _notificationMethodChannel
        .invokeMethod<bool>('showIncomingPaymentNotification', {
          'title': title,
          'amountNaira': amountNaira ?? 0,
          'senderName': senderName ?? 'Customer',
          if (todayTotalNaira != null) 'todayTotalNaira': todayTotalNaira,
        });
    return result == true;
  } catch (e) {
    debugPrint('Native incoming notification fallback: $e');
    return false;
  }
}

String _formatNaira(double amount) {
  return '\u20A6${NumberFormat('#,##0').format(amount)}';
}

String? _extractIncomingSenderName(Map<String, dynamic> data) {
  const senderKeys = ['senderName', 'fromName', 'sender', 'payerName', 'name'];
  for (final key in senderKeys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

Future<double?> _resolveTodayReceivedTotalNaira({
  required Map<String, dynamic> data,
}) async {
  const totalKeys = [
    'todayTotalReceived',
    'today_total_received',
    'totalTodayReceived',
    'total_today',
  ];
  for (final key in totalKeys) {
    final value = data[key];
    if (value == null) continue;
    if (value is num && value > 0) return value.toDouble();
    final parsed = double.tryParse(value.toString().replaceAll(',', ''));
    if (parsed != null && parsed > 0) return parsed;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));

  try {
    final query = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .get();

    double total = 0;
    for (final doc in query.docs) {
      final tx = doc.data();
      if (!_isIncomingTransactionLike(tx)) continue;
      final amount = _parseAmountNairaFromPayload(tx);
      if (amount != null && amount > 0) {
        total += amount;
      }
    }
    return total > 0 ? total : null;
  } catch (_) {
    return null;
  }
}

bool _isIncomingTransactionLike(Map<String, dynamic> tx) {
  final status = (tx['status'] ?? tx['rawStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (status.contains('failed') || status.contains('declined')) {
    return false;
  }

  final text = [
    tx['type'],
    tx['category'],
    tx['title'],
    tx['description'],
    tx['narration'],
  ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

  final incomingHit = [
    'received',
    'credit',
    'credited',
    'deposit',
    'incoming',
  ].any(text.contains);
  final outgoingHit = [
    'debit',
    'debited',
    'withdraw',
    'transfer sent',
    'payment sent',
    'airtime',
    'bill',
  ].any(text.contains);

  return incomingHit && !outgoingHit;
}

String _normalizeVoicePreference(String? value) {
  final normalized = (value ?? 'female').trim().toLowerCase();
  if (normalized == 'male') return 'male';
  return 'female';
}

String _normalizeVoiceLanguagePreference(String? value) {
  final normalized = (value ?? 'english').trim().toLowerCase();
  if (normalized == 'pidgin') return 'pidgin';
  return 'english';
}

Future<Map<String, dynamic>> _speakWithNeuralTts({
  required String text,
  required String voiceStyle,
  required String voiceLanguage,
}) async {
  try {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'synthesizeNeuralSpeech',
    );
    final response = await callable.call({
      'text': text,
      'voiceStyle': voiceStyle,
      'voiceLanguage': voiceLanguage,
    });

    final data = Map<String, dynamic>.from(
      (response.data as Map?) ?? const <String, dynamic>{},
    );
    final base64Audio = data['audioContentBase64']?.toString() ?? '';
    if (base64Audio.isEmpty) {
      return {
        'ok': false,
        'engineUsed': 'neural',
        'reason': 'Neural TTS returned empty audio payload.',
      };
    }

    final bytes = base64Decode(base64Audio);
    await _neuralAudioPlayer.stop();
    await _neuralAudioPlayer.play(BytesSource(bytes));

    return {
      'ok': true,
      'engineUsed': 'neural',
      'engineLabel': data['engine']?.toString() ?? 'google-cloud-neural',
      'voiceName': data['voiceName']?.toString(),
    };
  } catch (e) {
    return {
      'ok': false,
      'engineUsed': 'neural',
      'reason': 'Neural TTS failed: $e',
    };
  }
}

Future<Map<String, dynamic>> _speakIncomingText({
  required String text,
  required String voiceLanguage,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final voicePreference = _normalizeVoicePreference(
    prefs.getString(_voiceAlertGenderPreferenceKey),
  );

  final neuralResult = await _speakWithNeuralTts(
    text: text,
    voiceStyle: voicePreference,
    voiceLanguage: voiceLanguage,
  );
  if (neuralResult['ok'] == true) {
    return {
      ...neuralResult,
      'voicePreference': voicePreference,
      'enginePreference': 'neural',
    };
  }

  await _configureTtsIfNeeded();
  await _flutterTts.stop();
  final speakResult = await _flutterTts.speak(text);
  return {
    'ok': true,
    'engineUsed': 'device',
    'enginePreference': 'neural',
    'voicePreference': _ttsConfiguredVoicePreference ?? voicePreference,
    'enginePackage': _ttsConfiguredEnginePackage,
    'engineLabel': _ttsConfiguredEngineLabel,
    'voiceName': _ttsConfiguredVoiceName,
    'pitch': _ttsConfiguredPitch,
    'speechRate': _ttsConfiguredSpeechRate,
    'usingSyntheticMaleProfile': _ttsUsingSyntheticMaleProfile,
    'speakResult': speakResult?.toString(),
  };
}

double _pitchForVoicePreference(String preference) {
  return preference == 'male' ? 0.62 : 1.04;
}

double _speechRateForVoicePreference(String preference) {
  return preference == 'male' ? 0.37 : 0.45;
}

bool _looksLikeMaleVoiceMetadata(String text) {
  final normalized = text.toLowerCase();
  const maleKeywords = [
    'male',
    'man',
    'david',
    'daniel',
    'michael',
    'james',
    'guy',
    'en-m',
  ];
  return maleKeywords.any(normalized.contains);
}

bool _isVoiceLikelyMale(Map<String, dynamic> voice) {
  final nameValue = (voice['name'] ?? voice['voice'] ?? '').toString();
  final identifierValue = (voice['identifier'] ?? '').toString();
  final genderValue = (voice['gender'] ?? voice['sex'] ?? '').toString();
  final searchable = '$nameValue $identifierValue $genderValue';
  return _looksLikeMaleVoiceMetadata(searchable);
}

int _voiceLocaleScore(String localeValue) {
  if (localeValue.contains('en-ng') || localeValue.contains('en_ng')) {
    return 60;
  }
  if (localeValue.contains('en-gb') || localeValue.contains('en_gb')) {
    return 45;
  }
  if (localeValue.contains('en-us') || localeValue.contains('en_us')) {
    return 35;
  }
  if (localeValue.startsWith('en')) {
    return 20;
  }
  return 0;
}

int _voicePreferenceScore({
  required Map<String, dynamic> voice,
  required String preference,
}) {
  final localeValue = (voice['locale'] ?? voice['language'] ?? '')
      .toString()
      .toLowerCase();
  final nameValue = (voice['name'] ?? voice['voice'] ?? '')
      .toString()
      .toLowerCase();
  final identifierValue = (voice['identifier'] ?? '').toString().toLowerCase();
  final genderValue = (voice['gender'] ?? voice['sex'] ?? '')
      .toString()
      .toLowerCase();
  final searchable = '$nameValue $identifierValue $genderValue';

  const maleKeywords = [
    'male',
    'man',
    'david',
    'daniel',
    'michael',
    'james',
    'guy',
    'en-m',
  ];
  const femaleKeywords = [
    'female',
    'woman',
    'zira',
    'hazel',
    'susan',
    'samantha',
    'girl',
    'en-f',
  ];

  final preferredKeywords = preference == 'male'
      ? maleKeywords
      : femaleKeywords;
  final oppositeKeywords = preference == 'male' ? femaleKeywords : maleKeywords;

  var score = _voiceLocaleScore(localeValue);

  if (genderValue.contains(preference)) {
    score += 120;
  }
  if (preferredKeywords.any(searchable.contains)) {
    score += 60;
  }
  if (searchable.contains('network') ||
      searchable.contains('neural') ||
      searchable.contains('wavenet')) {
    score += 20;
  }
  if (searchable.contains('local')) {
    score -= 8;
  }
  if (oppositeKeywords.any(searchable.contains)) {
    score -= 30;
  }
  if (localeValue.isEmpty) {
    score -= 10;
  }

  return score;
}

Map<String, String>? _parseTtsEngine(dynamic engine) {
  if (engine is String) {
    final trimmed = engine.trim();
    if (trimmed.isEmpty) return null;
    return {'package': trimmed, 'label': trimmed};
  }

  if (engine is Map) {
    final mapped = Map<String, dynamic>.from(engine);
    final packageName =
        (mapped['name'] ??
                mapped['engine'] ??
                mapped['packageName'] ??
                mapped['package'] ??
                mapped['id'] ??
                '')
            .toString()
            .trim();
    if (packageName.isEmpty) return null;

    final label =
        (mapped['label'] ??
                mapped['displayName'] ??
                mapped['name'] ??
                packageName)
            .toString()
            .trim();
    return {'package': packageName, 'label': label};
  }

  return null;
}

int _ttsEngineScore(Map<String, String> engine) {
  final searchable = '${engine['package'] ?? ''} ${engine['label'] ?? ''}'
      .toLowerCase();

  if (searchable.contains('com.google.android.tts') ||
      searchable.contains('google text-to-speech') ||
      searchable.contains('google tts') ||
      searchable.contains('speech services by google')) {
    return 300;
  }
  if (searchable.contains('speech services')) {
    return 250;
  }
  if (searchable.contains('samsung')) {
    return 80;
  }
  return 10;
}

Future<Map<String, String>?> _pickPreferredTtsEngine() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    _ttsGoogleEngineAvailable = false;
    return null;
  }

  try {
    final engines = await _flutterTts.getEngines;
    if (engines is! List) {
      _ttsGoogleEngineAvailable = false;
      return null;
    }

    Map<String, String>? bestEngine;
    var bestScore = -1 << 20;
    var googleAvailable = false;

    for (final engine in engines) {
      final parsed = _parseTtsEngine(engine);
      if (parsed == null) continue;

      final searchable = '${parsed['package'] ?? ''} ${parsed['label'] ?? ''}'
          .toLowerCase();
      if (searchable.contains('com.google.android.tts') ||
          searchable.contains('google')) {
        googleAvailable = true;
      }

      final score = _ttsEngineScore(parsed);
      if (score > bestScore) {
        bestScore = score;
        bestEngine = parsed;
      }
    }

    _ttsGoogleEngineAvailable = googleAvailable;
    return bestEngine;
  } catch (e) {
    debugPrint('TTS engine lookup failed: $e');
    _ttsGoogleEngineAvailable = false;
    return null;
  }
}

Future<Map<String, String>?> _pickPreferredVoice(String preference) async {
  try {
    final voices = await _flutterTts.getVoices;
    if (voices is! List) return null;

    Map<String, dynamic>? bestVoice;
    var bestScore = -1 << 20;

    for (final voice in voices) {
      if (voice is! Map) continue;
      final mapped = Map<String, dynamic>.from(voice);
      final name = (mapped['name'] ?? mapped['voice'] ?? '').toString();
      final locale = (mapped['locale'] ?? mapped['language'] ?? '').toString();
      if (name.isEmpty || locale.isEmpty) continue;

      final score = _voicePreferenceScore(
        voice: mapped,
        preference: preference,
      );
      if (score > bestScore) {
        bestScore = score;
        bestVoice = mapped;
      }
    }

    if (bestVoice == null || bestScore < 20) {
      return null;
    }

    // Some engines expose only one en-NG network voice that sounds female.
    // If male was requested but metadata does not look male, force fallback profile.
    if (preference == 'male' && !_isVoiceLikelyMale(bestVoice)) {
      return null;
    }

    return {
      'name': (bestVoice['name'] ?? bestVoice['voice'] ?? '').toString(),
      'locale': (bestVoice['locale'] ?? bestVoice['language'] ?? '').toString(),
    };
  } catch (e) {
    debugPrint('TTS voice lookup failed: $e');
    return null;
  }
}

Future<void> _configureTtsIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  final preferredVoice = _normalizeVoicePreference(
    prefs.getString(_voiceAlertGenderPreferenceKey),
  );
  final preferredEngine = await _pickPreferredTtsEngine();
  final preferredEnginePackage = preferredEngine?['package'];

  if (_ttsConfigured &&
      _ttsConfiguredVoicePreference == preferredVoice &&
      _ttsConfiguredEnginePackage == preferredEnginePackage) {
    return;
  }

  try {
    var activeEnginePackage = preferredEnginePackage;
    var activeEngineLabel = preferredEngine?['label'];

    if (activeEnginePackage != null && activeEnginePackage.isNotEmpty) {
      try {
        await _flutterTts.setEngine(activeEnginePackage);
      } catch (e) {
        debugPrint('TTS engine selection failed for $activeEnginePackage: $e');
        activeEnginePackage = null;
        activeEngineLabel = null;
      }
    }

    final configured =
        await _flutterTts.setLanguage('en-NG') == 1 ||
        await _flutterTts.setLanguage('en-GB') == 1 ||
        await _flutterTts.setLanguage('en-US') == 1;
    final configuredPitch = _pitchForVoicePreference(preferredVoice);
    final configuredSpeechRate = _speechRateForVoicePreference(preferredVoice);
    final selectedVoice = await _pickPreferredVoice(preferredVoice);
    var usingSyntheticMaleProfile = false;

    if (selectedVoice != null) {
      await _flutterTts.setVoice(selectedVoice);
      _ttsConfiguredVoiceName =
          (selectedVoice['name'] ?? selectedVoice['voice'])?.toString();
    } else {
      _ttsConfiguredVoiceName = null;
      if (preferredVoice == 'male') {
        usingSyntheticMaleProfile = true;
      }
    }
    await _flutterTts.setSpeechRate(configuredSpeechRate);
    await _flutterTts.setPitch(configuredPitch);
    await _flutterTts.awaitSpeakCompletion(false);
    _ttsConfigured = configured;
    _ttsConfiguredEnginePackage = activeEnginePackage;
    _ttsConfiguredEngineLabel = activeEngineLabel;
    _ttsConfiguredVoicePreference = preferredVoice;
    _ttsConfiguredPitch = configuredPitch;
    _ttsConfiguredSpeechRate = configuredSpeechRate;
    _ttsUsingSyntheticMaleProfile = usingSyntheticMaleProfile;
  } catch (e) {
    debugPrint('TTS configuration failed: $e');
  }
}

double? _parseAmountNairaFromPayload(
  Map<String, dynamic> data, {
  String? fallbackBody,
}) {
  final directCandidates = [
    data['amount'],
    data['amountNaira'],
    data['amount_naira'],
    data['displayAmount'],
    data['value'],
  ];

  for (final candidate in directCandidates) {
    if (candidate == null) continue;
    if (candidate is num) return candidate.toDouble();
    final cleaned = candidate.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed != null && parsed > 0) return parsed;
  }

  final body = (data['body'] ?? fallbackBody ?? '').toString();
  final match = RegExp(r'([0-9][0-9,]*\.?[0-9]*)').firstMatch(body);
  if (match != null) {
    final parsed = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

String _numberToWords(int number) {
  const ones = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
  ];
  const teens = [
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  const tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  if (number < 10) return ones[number];
  if (number < 20) return teens[number - 10];
  if (number < 100) {
    final t = number ~/ 10;
    final r = number % 10;
    return r == 0 ? tens[t] : '${tens[t]} ${ones[r]}';
  }
  if (number < 1000) {
    final h = number ~/ 100;
    final r = number % 100;
    return r == 0
        ? '${ones[h]} hundred'
        : '${ones[h]} hundred ${_numberToWords(r)}';
  }
  if (number < 1000000) {
    final th = number ~/ 1000;
    final r = number % 1000;
    return r == 0
        ? '${_numberToWords(th)} thousand'
        : '${_numberToWords(th)} thousand ${_numberToWords(r)}';
  }
  if (number < 1000000000) {
    final m = number ~/ 1000000;
    final r = number % 1000000;
    return r == 0
        ? '${_numberToWords(m)} million'
        : '${_numberToWords(m)} million ${_numberToWords(r)}';
  }
  return number.toString();
}

bool _isIncomingPaymentPayloadLike(
  Map<String, dynamic> data, {
  String? notificationTitle,
  String? notificationBody,
}) {
  final type = (data['type'] ?? '').toString().toLowerCase();
  final title = (data['title'] ?? notificationTitle ?? '')
      .toString()
      .toLowerCase();
  final body = (data['body'] ?? notificationBody ?? '')
      .toString()
      .toLowerCase();
  final text = '$type $title $body';

  final includesIncomingKeyword = [
    'received',
    'credited',
    'deposit',
    'payment received',
    'transfer received',
  ].any(text.contains);

  final includesOutgoingKeyword = [
    'debited',
    'withdrawal',
    'declined',
    'failed',
  ].any(text.contains);

  if (type == 'payment_received' || type == 'deposit') {
    return true;
  }

  return includesIncomingKeyword && !includesOutgoingKeyword;
}

String? _buildIncomingAlertSpeech({
  required Map<String, dynamic> data,
  String? notificationTitle,
  String? notificationBody,
  required bool speakAmount,
  required String voiceLanguage,
}) {
  if (!_isIncomingPaymentPayloadLike(
    data,
    notificationTitle: notificationTitle,
    notificationBody: notificationBody,
  )) {
    return null;
  }

  final amount = _parseAmountNairaFromPayload(
    data,
    fallbackBody: notificationBody,
  );

  if (speakAmount && amount != null && amount > 0) {
    final rounded = amount.round();
    if (voiceLanguage == 'pidgin') {
      return '${_numberToWords(rounded)} naira don land for your PadiPay account';
    }
    return '${_numberToWords(rounded)} naira received in your PadiPay account';
  }

  if (voiceLanguage == 'pidgin') {
    return 'Payment don land for your PadiPay account';
  }

  return 'Payment received in your PadiPay account';
}

Future<void> _speakIncomingAlert(RemoteMessage message) async {
  final prefs = await SharedPreferences.getInstance();
  final enableVoice = prefs.getBool(_voiceAlertsPreferenceKey) ?? true;
  if (!enableVoice) return;

  final speakAmount =
      prefs.getBool(_voiceAlertSpeakAmountPreferenceKey) ?? true;
  final voiceLanguage = _normalizeVoiceLanguagePreference(
    prefs.getString(_voiceAlertLanguagePreferenceKey),
  );
  final spoken = _buildIncomingAlertSpeech(
    data: message.data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
    speakAmount: speakAmount,
    voiceLanguage: voiceLanguage,
  );
  if (spoken == null) return;

  try {
    await _speakIncomingText(text: spoken, voiceLanguage: voiceLanguage);
  } catch (e) {
    debugPrint('TTS speak error: $e');
  }
}

Future<Map<String, dynamic>> simulateIncomingVoiceAlert({
  double amountNaira = 5000,
}) async {
  return simulateIncomingPaymentNotification(amountNaira: amountNaira);
}

Future<Map<String, dynamic>> simulateIncomingPaymentNotification({
  double amountNaira = 5000,
  String senderName = 'John',
  double todayTotalReceivedNaira = 200000,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final enableVoice = prefs.getBool(_voiceAlertsPreferenceKey) ?? true;
  final speakAmount =
      prefs.getBool(_voiceAlertSpeakAmountPreferenceKey) ?? true;
  final voiceLanguage = _normalizeVoiceLanguagePreference(
    prefs.getString(_voiceAlertLanguagePreferenceKey),
  );
  final payload = <String, dynamic>{
    'type': 'payment_received',
    'title': 'Payment Received',
    'body': 'You received ${amountNaira.toStringAsFixed(0)} from $senderName',
    'amount': amountNaira.toStringAsFixed(2),
    'senderName': senderName,
    'todayTotalReceived': todayTotalReceivedNaira.toStringAsFixed(2),
  };

  final spoken = _buildIncomingAlertSpeech(
    data: payload,
    notificationTitle: payload['title']?.toString(),
    notificationBody: payload['body']?.toString(),
    speakAmount: speakAmount,
    voiceLanguage: voiceLanguage,
  );

  try {
    await _showNotification(RemoteMessage.fromMap({'data': payload}));
  } catch (_) {}

  if (!enableVoice) {
    return {
      'ok': true,
      'reason':
          'Notification simulation sent. Voice Alerts is turned off in settings.',
      'spoken': spoken,
      'voiceLanguage': voiceLanguage,
      'notificationSent': true,
      'voiceAttempted': false,
    };
  }

  try {
    final speechResult = spoken == null
        ? <String, dynamic>{
            'ok': false,
            'reason': 'No incoming alert speech was generated.',
          }
        : await _speakIncomingText(text: spoken, voiceLanguage: voiceLanguage);
    final usedDeviceEngine =
        (speechResult['engineUsed']?.toString() ?? '') == 'device';
    return {
      'ok': spoken != null && speechResult['ok'] == true,
      'ttsConfigured': _ttsConfigured,
      'voicePreference': _ttsConfiguredVoicePreference,
      'voiceLanguage': voiceLanguage,
      'enginePreference': 'neural',
      'engineUsed': speechResult['engineUsed']?.toString(),
      'enginePackage': _ttsConfiguredEnginePackage,
      'engineLabel': usedDeviceEngine
          ? _ttsConfiguredEngineLabel
          : speechResult['engineLabel']?.toString(),
      'googleEngineAvailable': _ttsGoogleEngineAvailable,
      'voiceName': usedDeviceEngine
          ? _ttsConfiguredVoiceName
          : speechResult['voiceName']?.toString(),
      'pitch': usedDeviceEngine ? _ttsConfiguredPitch : null,
      'speechRate': usedDeviceEngine ? _ttsConfiguredSpeechRate : null,
      'usingSyntheticMaleProfile': usedDeviceEngine
          ? _ttsUsingSyntheticMaleProfile
          : false,
      'spoken': spoken,
      'speakResult': speechResult['speakResult']?.toString(),
      'notificationSent': true,
      'voiceAttempted': true,
      'neuralFallbackReason': speechResult['reason']?.toString(),
      'reason': spoken == null
          ? 'The sample payload did not match the incoming payment voice rule.'
          : 'Incoming notification and voice simulation sent.',
    };
  } catch (e) {
    return {
      'ok': false,
      'ttsConfigured': _ttsConfigured,
      'voicePreference': _ttsConfiguredVoicePreference,
      'voiceLanguage': voiceLanguage,
      'enginePackage': _ttsConfiguredEnginePackage,
      'engineLabel': _ttsConfiguredEngineLabel,
      'googleEngineAvailable': _ttsGoogleEngineAvailable,
      'voiceName': _ttsConfiguredVoiceName,
      'pitch': _ttsConfiguredPitch,
      'speechRate': _ttsConfiguredSpeechRate,
      'usingSyntheticMaleProfile': _ttsUsingSyntheticMaleProfile,
      'spoken': spoken,
      'notificationSent': true,
      'voiceAttempted': true,
      'reason': 'TTS speak failed: $e',
    };
  }
}

// =========================================================
// MAIN
// =========================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await _createNotificationChannel();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (response) {
      _handleNotificationTap(response.payload, response.actionId);
    },
  );

  FirebaseMessaging.onMessage.listen((message) async {
    await _showNotification(message);
    await _speakIncomingAlert(message);
  });

  // IMPORTANT FIX:
  // Handles taps when app is already open or in foreground.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationTap(jsonEncode(message.data), null);
  });

  preloadBanks();
  preloadBalance();

  // Initialize Sudo Cloud Card SDK for NFC tap-to-pay at POS terminals.
  // isSandBox: set to false before going to production.
  try {
    await CloudCardFlutter().init(
      isSandBox: false,
      onCardScanned: (CloudCardEvent event) {
        debugPrint(
          '[CloudCard] scan started: ${event.eventType} ${event.message}',
        );
      },
      onScanComplete: (CloudCardEvent event) {
        debugPrint(
          '[CloudCard] scan complete: success=${event.isSuccess} amount=${event.amount}',
        );
      },
    );
  } catch (e) {
    debugPrint('[CloudCard] SDK init failed (non-fatal): $e');
  }

  runApp(const MainApp());

  // Check for Play Store updates after the first frame so we have a navigator/context.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return;
          final doUpdate = await showDialog<bool>(
            context: ctx,
            builder: (context) => AlertDialog(
              title: const Text('Update available'),
              content: const Text('A newer version is available on Google Play. Update now?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Later'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Update'),
                ),
              ],
            ),
          );

          if (doUpdate == true) {
            try {
              await InAppUpdate.performImmediateUpdate();
            } catch (e) {
              debugPrint('Immediate update failed: $e');
              try {
                await InAppUpdate.startFlexibleUpdate();
                await InAppUpdate.completeFlexibleUpdate();
              } catch (e2) {
                debugPrint('Flexible update failed: $e2');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('In-app update check failed: $e');
      }
    });
  }
}

// =========================================================
// LOCAL PERMISSIONS
// =========================================================
Future<void> firebaseLocalPermission() async {
  // Check if notification permission is already granted
  final settings = await FirebaseMessaging.instance.getNotificationSettings();
  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    // Already granted, do nothing
    return;
  }
  // Show explanation bottom sheet before requesting notification permission
  await showModalBottomSheet(
    context: navigatorKey.currentContext!,
    isDismissible: false,
    builder: (context) => PermissionExplanationSheet(
      type: PermissionType.notification,
      onContinue: () async {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();

        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);

        await FirebaseMessaging.instance.requestPermission();
      },
    ),
  );
}

// =========================================================
// UNIVERSAL NOTIFICATION TAP HANDLER
// =========================================================
Future<void> _handleNotificationTap(String? payload, String? actionId) async {
  if (payload == null) return;

  final data = jsonDecode(payload);

  final type = data['type'];
  final requestId = data['requestId'];

  if (type == 'withdrawal_request') {
    if (actionId == null || actionId == 'APPROVE_ACTION') {
      pendingApprovalNotifier.value = requestId;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => WithdrawalApprovalPage(requestId: requestId),
        ),
      );
      return;
    }

    if (actionId == 'DECLINE_ACTION') {
      await FirebaseFunctions.instance
          .httpsCallable('cancelWithdrawalRequest')
          .call({
            'requestId': requestId,
            'reason': 'declined_via_notification',
          });

      showSimpleDialog('Withdrawal request declined.', Colors.orange);
    }
  }
}

// =========================================================
// PRELOADS
// =========================================================
Future<void> preloadBanks() async {
  try {
    final snapshot = await FirebaseFirestore.instance.collection('banks').get();
    if (snapshot.docs.isEmpty) {
      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenBankList')
          .call();

      final data = result.data['data'] as List;
      final batch = FirebaseFirestore.instance.batch();
      for (var item in data) {
        final doc = FirebaseFirestore.instance
            .collection('banks')
            .doc(item['id'].toString());
        batch.set(doc, {'name': item['attributes']['name']});
      }
      await batch.commit();
    }
  } catch (_) {}
}

Future<void> preloadBalance() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final sudo = userDoc.data()?['safehavenData'];
    if (sudo == null) return;

    final accountId = sudo['virtualAccount']?['data']?['id']?.toString();
    if (accountId == null) return;

    final callable = FirebaseFunctions.instance.httpsCallable(
      'safehavenFetchAccountBalance',
    );
    final result = await callable.call({'accountId': accountId});

    double balance = result.data['data']['availableBalance']?.toDouble() ?? 0.0;
    balance /= 100;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_balance', balance);
  } catch (_) {}
}

// =========================================================
// MAIN APP
// =========================================================
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: primaryColor, width: 2),
          ),
        ),
      ),
      home: const AppLauncher(),
    );
  }
}

// =========================================================
// LAUNCHER
// =========================================================
class AppLauncher extends StatefulWidget {
  const AppLauncher({super.key});

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> with WidgetsBindingObserver {
  bool _showPrivacyOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      firebaseLocalPermission();

      // Run plugin-based jailbreak/root detection
      Future.microtask(() async {
        try {
          final compromised = await JailbreakDetector.isDeviceRootedOrJailbroken();
          if (compromised && mounted) {
            showDialog(
              context: navigatorKey.currentContext!,
              barrierDismissible: false,
              builder: (ctx) {
                return AlertDialog(
                  title: const Text('Security Warning'),
                  content: const Text('This device appears to be rooted or jailbroken. For your security, certain features may be disabled.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Continue'),
                    ),
                    TextButton(
                      onPressed: () {
                        SystemNavigator.pop();
                      },
                      child: const Text('Exit'),
                    ),
                  ],
                );
              },
            );
          }
        } catch (e) {
          debugPrint('Root/jailbreak check failed: $e');
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldShow = state != AppLifecycleState.resumed;
    if (mounted && _showPrivacyOverlay != shouldShow) {
      setState(() {
        _showPrivacyOverlay = shouldShow;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SignIn(),
        if (_showPrivacyOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: const Center(child: SizedBox.shrink()),
              ),
            ),
          ),
      ],
    );
  }
}

