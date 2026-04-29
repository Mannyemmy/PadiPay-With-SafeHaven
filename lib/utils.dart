import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:card_app/ui/keypad.dart';
import 'package:card_app/utils/screen_security.dart';
import 'package:card_app/utils/jailbreak_detector.dart';

// global navigator key used for showing persistent UI elements like toasts/bottom sheets
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const Color primaryColor = Color(0xFF007AFF);
const Color darkBlue = Color(0xFF00008B);
const Color royalBlue = Color(0xFF002366);
const Color oxfordBlue = Color(0xFF14213D);
const Color midnightBlue = Color(0xFF191970);
const Color navyBlue = Color(0xFF242550);

Future<HttpsCallableResult<dynamic>> callCloudFunctionLogged(
  String functionName, {
  dynamic payload,
  FirebaseFunctions? functions,
  String source = 'app',
}) async {
  final fx = functions ?? FirebaseFunctions.instance;
  final traceId = DateTime.now().microsecondsSinceEpoch.toString();
  final payloadKeys = payload is Map
      ? payload.keys.map((e) => e.toString()).toList()
      : <String>[];

  debugPrint(
    '[CF:$functionName][$source][$traceId] start keys=$payloadKeys',
  );

  try {
    final callable = fx.httpsCallable(functionName);
    final result = await callable.call(payload);
    debugPrint('[CF:$functionName][$source][$traceId] success');
    return result;
  } on FirebaseFunctionsException catch (e) {
    debugPrint(
      '[CF:$functionName][$source][$traceId] FirebaseFunctionsException code=${e.code} message=${e.message}',
    );
    rethrow;
  } catch (e) {
    debugPrint('[CF:$functionName][$source][$traceId] error=$e');
    rethrow;
  }
}

enum NavigationType { push, replace, clearStack }

void navigateTo(
  BuildContext context,
  Widget page, {
  NavigationType type = NavigationType.push,
  Duration duration = const Duration(milliseconds: 400),
}) {
  final route = PageRouteBuilder(
    transitionDuration: duration,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      // Slide from right with a gentle fade
      final offsetAnimation = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      final opacityAnimation = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeIn));

      return SlideTransition(
        position: offsetAnimation,
        child: FadeTransition(opacity: opacityAnimation, child: child),
      );
    },
  );

  switch (type) {
    case NavigationType.push:
      Navigator.push(context, route);
      break;

    case NavigationType.replace:
      Navigator.pushReplacement(context, route);
      break;

    case NavigationType.clearStack:
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
      break;
  }
}

void showSimpleDialog(String msg, Color color) {
  final BuildContext? context = navigatorKey.currentContext;
  if (context == null) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (ctx) {
      return SafeArea(
        bottom: true,
        child: Container(
          margin: const EdgeInsets.all(16.0),
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20.0),
              SizedBox(
                width: double.infinity,
                height: 48.0,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Log error to Firestore with userId and timestamp
Future<void> logErrorToFirestore(
  String errorMessage,
  String errorType,
  StackTrace? stackTrace,
) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final timestamp = DateTime.now();

    await FirebaseFirestore.instance.collection('error_logs').add({
      'userId': userId,
      'email': user?.email,
      'timestamp': timestamp,
      'errorMessage': errorMessage,
      'errorType': errorType,
      'stackTrace': stackTrace?.toString() ?? 'No stack trace',
    });

    print('❌ Error logged: $errorType - $errorMessage');
  } catch (e) {
    print('Failed to log error to Firestore: $e');
  }
}

/// Show generic error message to user and log actual error
void showGenericError({
  String userMessage = 'Something went wrong. Please try again.',
  required String errorMessage,
  required String errorType,
  StackTrace? stackTrace,
}) {
  // Log the actual error
  logErrorToFirestore(errorMessage, errorType, stackTrace);

  // Show generic message to user
  showSimpleDialog(userMessage, Colors.red);
}

/// Check PIN and show appropriate passcode sheet
/// Returns true if PIN verification successful, false otherwise
Future<bool> verifyTransactionPin() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSimpleDialog('User not authenticated', Colors.red);
      return false;
    }

    // Check if user has a passcode saved
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      showSimpleDialog('User document not found', Colors.red);
      return false;
    }

    final savedPasscode = userDoc.data()?['passcode'] as String?;
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) return false;

    // If no passcode exists, show create passcode sheet
    if (savedPasscode == null || savedPasscode.isEmpty) {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return const CreatePasscodeSheetForTransaction();
        },
      );
      return result ?? false;
    }

    // If passcode exists, show enter passcode sheet
    final enteredPasscode = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return const EnterPasscodeSheetForTransaction();
      },
    );

    // Verify the entered passcode
    if (enteredPasscode == null) {
      // User cancelled
      return false;
    } else if (enteredPasscode == 'BIOMETRIC_SUCCESS') {
      // Biometric authentication was successful
      return true;
    } else if (enteredPasscode == savedPasscode) {
      return true;
    } else {
      showSimpleDialog('Incorrect passcode. Please try again.', Colors.red);
      return false;
    }
  } catch (e) {
    print('Error verifying transaction PIN: $e');
    showSimpleDialog('Error verifying PIN', Colors.red);
    return false;
  }
}

Future<void> saveUserDeviceToken(String userId) async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Do not trigger OS notification dialogs here. Permission prompt is handled
  // centrally via firebaseLocalPermission() with PermissionExplanationSheet.
  final current = await messaging.getNotificationSettings();
  final settings = current;

  if (settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional) {
    // Get FCM token
    final String? token = await messaging.getToken();

    if (token != null) {
      // Check for other users with the same token and invalidate (remove) it
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceToken', isEqualTo: token)
          .get();

      for (var doc in querySnapshot.docs) {
        if (doc.id != userId) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .update({'deviceToken': FieldValue.delete()});
        }
      }

      // Save token in user's document
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'deviceToken': token,
      }, SetOptions(merge: true));

      print('✅ Device token saved for user: $userId');
    } else {
      print('⚠️ Failed to get FCM token');
    }
  } else {
    print('🚫 Notification permission not granted');
  }
}

Future<void> fetchCustomerAccount() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('User not authenticated');
      return;
    }

    final uid = user.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) {
      print('User document not found');
      return;
    }

    final data = userDoc.data()!;
    final safehavenData = data['safehavenData'] as Map<String, dynamic>?;
    if (safehavenData == null) {
      print('safehavenData not found in user document');
      return;
    }

    final virtualAccount =
        safehavenData['virtualAccount'] as Map<String, dynamic>?;
    if (virtualAccount == null) {
      print('virtualAccount not found in safehavenData');
      return;
    }

    final accountId = virtualAccount['data']['id']?.toString();
    if (accountId == null || accountId.isEmpty) {
      print('Account ID not found in virtualAccount');
      return;
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'fetchCustomerAccount',
    );
    final response = await callable.call(<String, dynamic>{
      'accountId': accountId,
    });

    print('Response: ${response.data}');
  } catch (e) {
    print('Error fetching customer account: $e');
  }
}

// Cache for bank name -> id lookups to avoid repeated full collection scans.
final Map<String, String> _bankIdCache = {};

// Resolve a bank id given either a candidate bankId or a bankName. If bankId is present
// it is returned; otherwise we try an equality query on bank name followed by
// a cached case-insensitive scan. Returns null if not found.
Future<String?> resolveBankId({String? bankId, String? bankName}) async {
  try {
    if (bankId != null && bankId.isNotEmpty) return bankId;
    if (bankName == null || bankName.isEmpty) return null;

    final nameLower = bankName.toLowerCase();

    // Check local cache first
    if (_bankIdCache.containsKey(nameLower)) return _bankIdCache[nameLower];

    // Exact name match first
    final bankQuery = await FirebaseFirestore.instance
        .collection('banks')
        .where('name', isEqualTo: bankName)
        .limit(1)
        .get();
    if (bankQuery.docs.isNotEmpty) {
      final id = bankQuery.docs.first.id;
      _bankIdCache[nameLower] = id;
      return id;
    }

    // Fallback: load all banks once into cache, then look up
    if (_bankIdCache.isEmpty) {
      final allBanks = await FirebaseFirestore.instance.collection('banks').get();
      for (var bdoc in allBanks.docs) {
        final bname = (bdoc.data()['name'] as String?) ?? '';
        _bankIdCache[bname.toLowerCase()] = bdoc.id;
      }
    }
    return _bankIdCache[nameLower];
  } catch (e) {
    print('resolveBankId error: $e');
  }
  return null;
}

Future<void> createSudoCustomerIfNeeded() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('[SUDO] Skipping Sudo customer creation: no authenticated user');
      return;
    }

    final userDocSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDocSnap.exists) {
      throw Exception('User document not found');
    }
    final userData = userDocSnap.data()!;

    final existingCustomer = userData['sudoCustomer'];
    final existingId =
        (existingCustomer?['data'] as Map?)?['_id']?.toString() ??
        (existingCustomer as Map?)?['_id']?.toString();
    if (existingId != null) {
      print('[SUDO] Sudo customer already exists: $existingId');
      return;
    }

    final String firstName = userData['firstName']?.toString() ?? '';
    final String lastName = userData['lastName']?.toString() ?? '';
    final String phone = userData['phone']?.toString() ?? '';
    final String email = userData['email']?.toString() ?? '';
    final addressRaw = userData['address'] as Map<String, dynamic>?;

    if (firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      print('[SUDO] Missing required fields for Sudo customer creation. Skipping.');
      return;
    }

    final payload = {
      'type': 'individual',
      'name': '$firstName $lastName'.trim(),
      'phoneNumber': phone,
      'status': 'active',
      'emailAddress': email,
      'billingAddress': {
        'line1': addressRaw?['street']?.toString() ?? '',
        'city': addressRaw?['city']?.toString() ?? '',
        'state': addressRaw?['state']?.toString() ?? '',
        'country': addressRaw?['country']?.toString() ?? 'NG',
        'postalCode': addressRaw?['postalCode']?.toString() ?? '',
      },
      'individual': {
        'firstName': firstName,
        'lastName': lastName,
      },
    };
    print('[SUDO] Sending sudoCreateCustomer payload: $payload');

    final callable =
        FirebaseFunctions.instance.httpsCallable('sudoCreateCustomer');
    final response = await callable.call(payload);
    print('[SUDO] sudoCreateCustomer response: ${response.data}');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'sudoCustomer': response.data});
    print('[SUDO] Sudo customer saved to Firestore');
  } catch (e) {
    print('[SUDO] Error creating Sudo customer: $e');
  }
}

Future<void> createSudoAccountIfNeeded() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('[SUDO] Skipping Sudo account creation: no authenticated user');
      return;
    }

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(uid);
    final userDocSnap = await userDocRef.get();
    if (!userDocSnap.exists) return;
    final userData = userDocSnap.data()!;

    // Check if account already exists
    final existingAccount = userData['sudoAccount'];
    final existingAccountId =
        (existingAccount?['data'] as Map?)?['_id']?.toString() ??
        (existingAccount as Map?)?['_id']?.toString();
    if (existingAccountId != null) {
      print('[SUDO] Sudo account already exists: $existingAccountId');
      return;
    }

    // Need a customer first
    final existingCustomer = userData['sudoCustomer'];
    final customerId =
        (existingCustomer?['data'] as Map?)?['_id']?.toString() ??
        (existingCustomer as Map?)?['_id']?.toString();
    if (customerId == null) {
      print('[SUDO] No Sudo customer found; skipping account creation');
      return;
    }

    print('[SUDO] Creating Sudo account for customer: $customerId');
    final callable =
        FirebaseFunctions.instance.httpsCallable('sudoCreateAccount');
    final response = await callable.call({
      'customerId': customerId,
      'type': 'account',
      'currency': 'NGN',
      'accountType': 'Savings',
    });
    print('[SUDO] sudoCreateAccount response: ${response.data}');

    await userDocRef.update({'sudoAccount': response.data});
    print('[SUDO] Sudo account saved to Firestore');
  } catch (e) {
    print('[SUDO] Error creating Sudo account: $e');
  }
}

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll('/', '');
    if (newText.length > 8) return oldValue;

    String formatted = '';
    // Year (positions 0-3)
    if (newText.isNotEmpty) formatted += newText.substring(0, 1);
    if (newText.length >= 2) formatted += newText.substring(1, 2);
    if (newText.length >= 3) formatted += newText.substring(2, 3);
    if (newText.length >= 4) formatted += newText.substring(3, 4);
    if (newText.length >= 5) formatted += '/';
    // Month (positions 4-5)
    if (newText.length >= 5) formatted += newText.substring(4, 5);
    if (newText.length >= 6) formatted += newText.substring(5, 6);
    if (newText.length >= 7) formatted += '/';
    // Day (positions 6-7)
    if (newText.length >= 7) formatted += newText.substring(6, 7);
    if (newText.length >= 8) formatted += newText.substring(7, 8);

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class MissingDataBottomSheet extends StatefulWidget {
  final Map<String, String> missingFields;

  const MissingDataBottomSheet({super.key, required this.missingFields});

  @override
  State<MissingDataBottomSheet> createState() => _MissingDataBottomSheetState();
}

class _MissingDataBottomSheetState extends State<MissingDataBottomSheet> {
  late TextEditingController ninController;
  late TextEditingController dobController;
  late TextEditingController line1Controller;
  late TextEditingController cityController;
  late TextEditingController stateController;

  @override
  void initState() {
    super.initState();
    ninController = TextEditingController(
      text: widget.missingFields['nin'] ?? '',
    );
    dobController = TextEditingController(
      text: widget.missingFields['dob'] ?? '',
    );
    line1Controller = TextEditingController(
      text: widget.missingFields['line1'] ?? '',
    );
    cityController = TextEditingController(
      text: widget.missingFields['city'] ?? '',
    );
    stateController = TextEditingController(
      text: widget.missingFields['state'] ?? '',
    );
  }

  @override
  void dispose() {
    ninController.dispose();
    dobController.dispose();
    line1Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Complete Your Profile',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 30),
          if (widget.missingFields.containsKey('nin')) ...[
            const Text('NIN (National Identification Number):'),
            const SizedBox(height: 10),
            TextField(
              maxLength: 11,
              controller: ninController,
              decoration: const InputDecoration(
                counterText: "",
                hintText: 'Enter your NIN',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('dob')) ...[
            const Text('Date of Birth (YYYY/MM/DD):'),
            const SizedBox(height: 10),
            TextField(
              controller: dobController,
              inputFormatters: [DateInputFormatter()],
              decoration: const InputDecoration(hintText: 'e.g., 2000/10/27'),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('line1')) ...[
            const Text('Street Address:'),
            const SizedBox(height: 10),
            TextField(
              controller: line1Controller,
              decoration: const InputDecoration(
                hintText: 'Enter street address',
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('city')) ...[
            const Text('City:'),
            const SizedBox(height: 10),
            TextField(
              controller: cityController,
              decoration: const InputDecoration(hintText: 'Enter city'),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.missingFields.containsKey('state')) ...[
            const Text('State:'),
            const SizedBox(height: 10),
            TextField(
              controller: stateController,
              decoration: const InputDecoration(hintText: 'Enter state'),
            ),
            const SizedBox(height: 16),
          ],
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (widget.missingFields.containsKey('nin')) {
                      widget.missingFields['nin'] = ninController.text;
                    }
                    if (widget.missingFields.containsKey('dob')) {
                      widget.missingFields['dob'] = dobController.text;
                    }
                    if (widget.missingFields.containsKey('line1')) {
                      widget.missingFields['line1'] = line1Controller.text;
                    }
                    if (widget.missingFields.containsKey('city')) {
                      widget.missingFields['city'] = cityController.text;
                    }
                    if (widget.missingFields.containsKey('state')) {
                      widget.missingFields['state'] = stateController.text;
                    }
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

Future<void> _showCustomMissingDataBottomSheet(
  BuildContext context,
  Map<String, String> missingFields,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext bottomSheetContext) =>
        MissingDataBottomSheet(missingFields: missingFields),
  );
}

/// Passcode sheet for entering existing PIN before transaction
class EnterPasscodeSheetForTransaction extends StatefulWidget {
  const EnterPasscodeSheetForTransaction({super.key});

  @override
  State<EnterPasscodeSheetForTransaction> createState() =>
      _EnterPasscodeSheetForTransactionState();
}

class _EnterPasscodeSheetForTransactionState
    extends State<EnterPasscodeSheetForTransaction> {
  String pin = '';
  bool _useBiometric = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricAttempted = false;
  bool _showPinKeypad = false;
  bool _biometricLoading = false;

  final _localAuth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
    _initializeBiometric();
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    super.dispose();
  }

  Future<void> _initializeBiometric() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final biometricEnabled =
          await _storage.read(key: 'biometric_enabled') == 'true';

      if (mounted) {
        setState(() {
          _biometricAvailable = canCheckBiometrics && isDeviceSupported;
          _biometricEnabled = biometricEnabled;
          _useBiometric = _biometricAvailable && _biometricEnabled;
        });

        if (_useBiometric) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _authenticateWithBiometric();
          });
        } else {
          if (mounted) setState(() => _showPinKeypad = true);
        }
      }
    } catch (e) {
      print('Error initializing biometric: $e');
      if (mounted) setState(() => _showPinKeypad = true);
    }
  }

  Future<void> _authenticateWithBiometric() async {
    if (_biometricAttempted || !_useBiometric) return;

    setState(() {
      _biometricLoading = true;
      _biometricAttempted = true;
    });

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to proceed with transaction',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        // Biometric successful, pop with success indicator
        Navigator.pop(context, 'BIOMETRIC_SUCCESS');
      } else if (mounted) {
        // Biometric failed or cancelled, show PIN keypad
        setState(() => _showPinKeypad = true);
      }
    } on PlatformException catch (e) {
      print('Biometric error: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() => _showPinKeypad = true);
      }
    } catch (e) {
      print('Biometric authentication error: $e');
      if (mounted) {
        setState(() => _showPinKeypad = true);
      }
    } finally {
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  void _switchToPin() {
    setState(() {
      _useBiometric = false;
      _showPinKeypad = true;
      pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isComplete = pin.length == 4;

    // Show biometric loading state
    if (_biometricLoading || (_useBiometric && !_showPinKeypad)) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 32),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context, null),
                      child: Icon(Icons.close_rounded,
                          color: Colors.grey.shade500, size: 26),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fingerprint,
                      color: primaryColor, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Authenticating',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use your fingerprint or face to verify',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 32),
                const CircularProgressIndicator(color: primaryColor),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _switchToPin,
                  child: Text(
                    'Use PIN instead',
                    style: TextStyle(
                      fontSize: 13,
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }

    // Show PIN keypad
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag handle + close icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32), // Spacer for alignment
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, null),
                    child: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Lock icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded, color: primaryColor, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter Passcode',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your 4-digit passcode to continue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool isFilled = index < pin.length;
                  final bool isCurrent = index == pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: isCurrent ? 18 : 16,
                    height: isCurrent ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? primaryColor : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? primaryColor
                            : isCurrent
                                ? primaryColor
                                : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              // Keypad with backspace on left (red) and tick on right (green)
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    } else if (pin.length < 4) {
                      pin += val;
                    }
                  });
                },
                rightChild: AnimatedScale(
                  scale: isComplete ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: isComplete ? () => Navigator.pop(context, pin) : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isComplete ? Colors.green : Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: isComplete ? Colors.white : Colors.grey.shade400,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Use biometric button if available
              if (_biometricAvailable && _biometricEnabled && _showPinKeypad)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _useBiometric = true;
                        _showPinKeypad = false;
                        _biometricLoading = false;
                        _biometricAttempted = false;
                      });
                      _authenticateWithBiometric();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint,
                            size: 18, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Use Biometric',
                          style: TextStyle(
                            fontSize: 13,
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passcode sheet for creating new PIN before transaction
class CreatePasscodeSheetForTransaction extends StatefulWidget {
  const CreatePasscodeSheetForTransaction({super.key});

  @override
  State<CreatePasscodeSheetForTransaction> createState() =>
      _CreatePasscodeSheetForTransactionState();
}

class _CreatePasscodeSheetForTransactionState
    extends State<CreatePasscodeSheetForTransaction> {
  String pin = '';
  String confirmPin = '';
  bool isConfirming = false;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    super.dispose();
  }

  void _showConfirmScreen() {
    setState(() {
      isConfirming = true;
      confirmPin = '';
    });
  }

  Future<void> _savePasscode() async {
    if (pin == confirmPin) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({"passcode": pin}, SetOptions(merge: true));
          Navigator.pop(context, true);
        }
      } catch (e) {
        print('Error saving passcode: $e');
        showSimpleDialog('Error saving passcode', Colors.red);
      }
    } else {
      showSimpleDialog('Passcodes do not match. Please try again.', Colors.red);
      setState(() {
        isConfirming = false;
        pin = '';
        confirmPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = isConfirming ? confirmPin : pin;
    final title = isConfirming ? 'Confirm Passcode' : 'Create Passcode';
    final subtitle = isConfirming
        ? 'Re-enter your 4-digit passcode'
        : 'Create a 4-digit passcode to secure your transactions';
    final bool isComplete = currentPin.length == 4;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Drag handle + close icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32), // Spacer for alignment
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Lock icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConfirming
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_outlined,
                  color: primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 32),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool isFilled = index < currentPin.length;
                  final bool isCurrent = index == currentPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: isCurrent ? 18 : 16,
                    height: isCurrent ? 18 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? primaryColor : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? primaryColor
                            : isCurrent
                                ? primaryColor
                                : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 28),
              // Keypad with backspace on left (red) and tick on right (green)
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (currentPin.isNotEmpty) {
                        if (isConfirming) {
                          confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                        } else {
                          pin = pin.substring(0, pin.length - 1);
                        }
                      }
                    } else if (currentPin.length < 4) {
                      if (isConfirming) {
                        confirmPin += val;
                      } else {
                        pin += val;
                      }
                    }
                  });
                },
                rightChild: AnimatedScale(
                  scale: isComplete ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 180),
                  child: GestureDetector(
                    onTap: isComplete
                        ? () {
                            if (isConfirming) {
                              _savePasscode();
                            } else {
                              _showConfirmScreen();
                            }
                          }
                        : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isComplete ? Colors.green : Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: isComplete ? Colors.white : Colors.grey.shade400,
                        size: 26,
                      ),
                    ),
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
}

/// Plugin-backed root/jailbreak check.
Future<bool> isDeviceRootedOrJailbroken() async {
  try {
    return await JailbreakDetector.isDeviceRootedOrJailbroken();
  } catch (_) {
    return false;
  }
}

// Secure storage helpers
final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

Future<void> secureSet(String key, String value) async {
  try {
    await _secureStorage.write(key: key, value: value);
  } catch (e) {
    print('secureSet error: $e');
  }
}

Future<String?> secureGet(String key) async {
  try {
    return await _secureStorage.read(key: key);
  } catch (e) {
    print('secureGet error: $e');
    return null;
  }
}

Future<void> secureDelete(String key) async {
  try {
    await _secureStorage.delete(key: key);
  } catch (e) {
    print('secureDelete error: $e');
  }
}