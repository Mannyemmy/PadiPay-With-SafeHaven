import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:card_app/giveaway/giveaway_success.dart';
import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _kGeminiApiKey = 'AIzaSyAsQ8zSoIKzK89Qh8PwijvYOjp6486VRP8';

// ─── helpers ────────────────────────────────────────────────────────────────

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue.copyWith(text: '');
    final buf = StringBuffer();
    int count = 0;
    for (int i = raw.length - 1; i >= 0; i--) {
      buf.write(raw[i]);
      count++;
      if (count % 3 == 0 && i > 0) buf.write(',');
    }
    final formatted = buf.toString().split('').reversed.join('');
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

enum _TagStatus { checking, valid, invalid }

class _InlineTag {
  final String username;
  _TagStatus status;
  String? uid;

  _InlineTag({required this.username,required this.status});
}

// ─── main widget ────────────────────────────────────────────────────────────

class TargetedGiveawayPage extends StatefulWidget {
  final List<String>? initialTags;
  final String? initialAmountPerPerson;

  const TargetedGiveawayPage({
    super.key,
    this.initialTags,
    this.initialAmountPerPerson,
  });

  @override
  State<TargetedGiveawayPage> createState() => _TargetedGiveawayPageState();
}

class _TargetedGiveawayPageState extends State<TargetedGiveawayPage> {
  // step: 0 = collect + auto-validate tags, 1 = amount & create
  int _step = 0;

  // tag collection
  final _tagInputCtrl = TextEditingController();
  final List<_InlineTag> _tags = [];

  // extraction / validation state
  bool _isExtracting = false;
  final bool _isValidating = false;

  // amount / giveaway config (step 1)
  final _amountCtrl = TextEditingController();
  final _customCodeCtrl = TextEditingController();
  bool _isCustomCode = false;
  final double _feeRate = 0.01;
  String _whoPays = 'sender';

  // account info
  String? _balance;
  String? _accountId;
  String? _accountType;
  Map<String, dynamic>? _companyVa;
  String? _currentUserUsername;

  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserUsername();
    _fetchAccountBalance();
    _fetchCompanyVirtualAccount();
    _amountCtrl.addListener(() => setState(() {}));
    // Pre-fill from MyPadi
    if (widget.initialAmountPerPerson != null) {
      _amountCtrl.text = widget.initialAmountPerPerson!;
    }
    if (widget.initialTags != null && widget.initialTags!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final tag in widget.initialTags!) {
          final cleaned = tag.trim().toLowerCase().replaceAll('@', '');
          if (cleaned.isNotEmpty &&
              RegExp(r'^[a-z0-9_]{1,20}$').hasMatch(cleaned) &&
              !_tags.any((t) => t.username == cleaned)) {
            _addAndValidateTag(cleaned);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _tagInputCtrl.dispose();
    _amountCtrl.dispose();
    _customCodeCtrl.dispose();
    super.dispose();
  }

  // ── financial helpers ────────────────────────────────────────────────────

  bool get _isTagsChecking =>
      _tags.any((t) => t.status == _TagStatus.checking);

  bool get _hasInvalidTags =>
      _tags.any((t) => t.status == _TagStatus.invalid);

  List<_InlineTag> get _validTags =>
      _tags.where((t) => t.status == _TagStatus.valid).toList();

  double get _amountPerPerson =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0.0;

  double get _totalAmount => _amountPerPerson * _validTags.length;

  double get _fee => _totalAmount * _feeRate;

  double get _transferAmount =>
      _whoPays == 'sender' ? _totalAmount + _fee : _totalAmount;

  double get _distributePerPerson =>
      _whoPays == 'sender'
          ? _amountPerPerson
          : _amountPerPerson - (_amountPerPerson * _feeRate);

  // ── data fetching ────────────────────────────────────────────────────────

  Future<void> _fetchCurrentUserUsername() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) return;
      final data = userDoc.data()!;
      final username = data['userName'] as String?;
      if (mounted) {
        setState(() => _currentUserUsername = username);
      }
    } catch (_) {}
  }

  Future<void> _fetchAccountBalance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) return;
      final data = userDoc.data()!;
      final anchorData = data['getAnchorData'] as Map<String, dynamic>?;
      final virtualAccount =
          anchorData?['virtualAccount'] as Map<String, dynamic>?;
      final accountData =
          virtualAccount?['data'] as Map<String, dynamic>?;
      if (accountData == null) return;
      setState(() {
        _accountId = accountData['id']?.toString();
        _accountType = accountData['type']?.toString();
      });
      final callable =
          FirebaseFunctions.instance.httpsCallable('fetchAccountBalance');
      final result = await callable.call({'accountId': _accountId});
      final balanceKobo =
          result.data['data']['availableBalance']?.toDouble() ?? 0.0;
      setState(() {
        _balance =
            '₦ ${NumberFormat('#,##0.00').format(balanceKobo / 100)}';
      });
    } catch (e) {
      debugPrint('Error fetching balance: $e');
    }
  }

  Future<void> _fetchCompanyVirtualAccount() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('company')
          .doc('account_details')
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? <String, dynamic>{};
      setState(() {
        _companyVa = {
          'uid': doc.id,
          'id': data['accountId']?.toString() ?? '',
          'type': data['accountType']?.toString() ?? '',
          'bankId': data['bankId']?.toString() ?? '',
          'bankName': data['bankName']?.toString() ?? '',
          'accountNumber': data['accountNumber']?.toString() ?? '',
          'accountName': data['accountName']?.toString() ?? '',
        };
      });
    } catch (e) {
      debugPrint('Error fetching company VA: $e');
    }
  }

  // ── unique code generation ───────────────────────────────────────────────

  Future<String> _generateUniqueCode() async {
    String code;
    bool isUnique = false;
    int attempts = 0;
    do {
      code = 'PADI#${Random().nextInt(900000) + 100000}';
      final snap = await FirebaseFirestore.instance
          .collection('giveaways')
          .where('code', isEqualTo: code)
          .get();
      isUnique = snap.docs.isEmpty;
      attempts++;
    } while (!isUnique && attempts < 10);
    if (!isUnique) throw Exception('Unable to generate unique giveaway code');
    return code;
  }

  // ── Gemini extraction ────────────────────────────────────────────────────

  Future<List<String>> _extractUsernamesViaGemini({
    Uint8List? bytes,
    String? mimeType,
    String? textContent,
  }) async {
    const prompt = '''
You are extracting Padi-tag usernames from the provided content.
Padi-tags are short usernames that identify users on the Padi app.
They may appear with or without a "@" prefix.
They follow the pattern: lower-case letters, numbers, underscores, 3–20 characters.

Extract ALL usernames/tags/handles you can find. They might be:
- Listed one per line
- Comma or semicolon-separated
- @mentioned like "@john_doe"
- In a WhatsApp chat where someone typed their username
- In a spreadsheet column
- In a document or image

Return ONLY a valid JSON array of strings (no markdown, no explanation):
["username1","username2","username3"]

Normalise each: lowercase, remove "@" prefix, trim whitespace, strip surrounding punctuation.
Remove duplicates.
If none found, return an empty array: []
''';

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _kGeminiApiKey,
    );

    List<Content> content;
    if (textContent != null) {
      content = [
        Content.text('$prompt\n\nContent:\n$textContent'),
      ];
    } else {
      content = [
        Content.multi([TextPart(prompt), DataPart(mimeType!, bytes!)]),
      ];
    }

    final response = await model.generateContent(content);
    final raw = response.text?.trim() ?? '[]';
    final cleaned = raw
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .trim();

    final List<dynamic> list = jsonDecode(cleaned);
    return list
        .map((e) => e.toString().toLowerCase().trim().replaceAll('@', ''))
        .where((e) => e.isNotEmpty && RegExp(r'^[a-z0-9_]{1,20}$').hasMatch(e))
        .toSet()
        .toList();
  }

  // ── tag input helpers ────────────────────────────────────────────────────

  void _addManualTag() {
    final raw = _tagInputCtrl.text;
    if (raw.trim().isEmpty) return;

    final parts = raw
        .split(RegExp(r'[,\n]+'))
        .map((s) => s.trim().toLowerCase().replaceAll('@', ''))
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return;

    int added = 0;
    int dupes = 0;
    int invalid = 0;

    for (final tag in parts) {
      if (!RegExp(r'^[a-z0-9_]{1,20}$').hasMatch(tag)) {
        invalid++;
        continue;
      }
      if (_tags.any((t) => t.username == tag)) {
        dupes++;
        continue;
      }
      _addAndValidateTag(tag);
      added++;
    }

    _tagInputCtrl.clear();

    final msgs = <String>[];
    if (added > 0) msgs.add('$added tag(s) added');
    if (dupes > 0) msgs.add('$dupes duplicate(s) skipped');
    if (invalid > 0) msgs.add('$invalid invalid format(s) skipped');
    if (msgs.isNotEmpty && (dupes > 0 || invalid > 0)) {
      showSimpleDialog(msgs.join(' · '), Colors.orange);
    }
  }

  void _removeTag(String tag) =>
      setState(() => _tags.removeWhere((t) => t.username == tag));

  void _clearInvalidTags() =>
      setState(() => _tags.removeWhere((t) => t.status == _TagStatus.invalid));

  void _addAndValidateTag(String username) {
    final tag = _InlineTag(username: username, status: _TagStatus.checking);
    setState(() => _tags.add(tag));
    _validateSingleTag(tag);
  }

  Future<void> _validateSingleTag(_InlineTag tag) async {
    // Prevent user from adding their own username
    if (_currentUserUsername != null &&
        tag.username.toLowerCase() == _currentUserUsername!.toLowerCase()) {
      if (mounted) {
        setState(() => tag.status = _TagStatus.invalid);
      }
      showSimpleDialog(
          'You cannot add yourself as a recipient', Colors.red);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(tag.username)
          .get();
      final uid = doc.exists ? (doc.data()?['uid'] as String?) : null;
      if (mounted) {
        setState(() {
          tag.status = uid != null ? _TagStatus.valid : _TagStatus.invalid;
          tag.uid = uid;
        });
      }
    } catch (_) {
      if (mounted) setState(() => tag.status = _TagStatus.invalid);
    }
  }

  // ── file import ──────────────────────────────────────────────────────────

  Future<void> _pickFromFile() async {
    if (!await _ensureCameraGalleryConsent()) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'csv', 'txt',
        'xlsx', 'xls',
        'pdf',
        'docx', 'doc',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      showSimpleDialog('Could not read file data', Colors.red);
      return;
    }

    setState(() => _isExtracting = true);
    try {
      List<String> extracted = [];
      final ext = file.extension?.toLowerCase() ?? '';

      if (ext == 'txt' || ext == 'csv') {
        final text = utf8.decode(bytes, allowMalformed: true);
        extracted = await _extractUsernamesViaGemini(textContent: text);
      } else if (ext == 'xlsx' || ext == 'xls') {
        // Parse with excel package, flatten cells to text
        final workbook = xl.Excel.decodeBytes(bytes);
        final buf = StringBuffer();
        for (final table in workbook.tables.values) {
          for (final row in table.rows) {
            buf.writeln(
              row
                  .map((cell) => cell?.value?.toString() ?? '')
                  .where((v) => v.isNotEmpty)
                  .join(', '),
            );
          }
        }
        extracted = await _extractUsernamesViaGemini(
            textContent: buf.toString());
      } else if (ext == 'pdf') {
        extracted = await _extractUsernamesViaGemini(
          bytes: bytes,
          mimeType: 'application/pdf',
        );
      } else if (ext == 'docx' || ext == 'doc') {
        // Gemini supports OOXML — try it; fallback to raw UTF-8 read
        try {
          extracted = await _extractUsernamesViaGemini(
            bytes: bytes,
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
        } catch (_) {
          final text = utf8.decode(bytes, allowMalformed: true);
          extracted =
              await _extractUsernamesViaGemini(textContent: text);
        }
      } else {
        // Generic: attempt to decode as UTF-8 text
        final text = utf8.decode(bytes, allowMalformed: true);
        extracted = await _extractUsernamesViaGemini(textContent: text);
      }

      int newCount = 0;
      for (final tag in extracted) {
        if (tag.isNotEmpty && !_tags.any((t) => t.username == tag)) {
          _addAndValidateTag(tag);
          newCount++;
        }
      }

      final dupes = extracted.length - newCount;
      String msg;
      if (extracted.isEmpty) {
        msg = 'No usernames found in file';
      } else if (dupes > 0) {
        msg = 'Added $newCount new username(s) ($dupes duplicate(s) skipped)';
      } else {
        msg = 'Added $newCount username(s) from file';
      }
      showSimpleDialog(msg, extracted.isEmpty ? Colors.orange : Colors.green);
    } catch (e) {
      debugPrint('File extraction error: $e');
      showSimpleDialog('Failed to extract usernames from file', Colors.red);
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  // ── image import ─────────────────────────────────────────────────────────

  Future<bool> _ensureCameraGalleryConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final consented = prefs.getBool('privacy_consent_camera') ?? false;
    if (consented) return true;
    bool agreed = false;
    if (!mounted) return false;
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: PermissionType.camera,
        onContinue: () async {
          await prefs.setBool('privacy_consent_camera', true);
          await prefs.setBool('privacy_consent_gallery', true);
          agreed = true;
        },
      ),
    );
    return agreed;
  }

  Future<void> _pickFromImage() async {
    if (!await _ensureCameraGalleryConsent()) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Import From Image',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Snap or upload a screenshot of usernames / a chat',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: primaryColor,
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white),
                ),
                title: const Text('Take a Photo'),
                onTap: () =>
                    Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: primaryColor,
                  child: const Icon(Icons.photo_library,
                      color: Colors.white),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () =>
                    Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (xfile == null) return;

    setState(() => _isExtracting = true);
    try {
      final bytes = await File(xfile.path).readAsBytes();
      final ext = xfile.path.split('.').last.toLowerCase();
      final mimeType = {
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
            'heic': 'image/heic',
            'heif': 'image/heif',
          }[ext] ??
          'image/jpeg';

      final extracted = await _extractUsernamesViaGemini(
        bytes: bytes,
        mimeType: mimeType,
      );

      int newCount = 0;
      for (final tag in extracted) {
        if (tag.isNotEmpty && !_tags.any((t) => t.username == tag)) {
          _addAndValidateTag(tag);
          newCount++;
        }
      }

      final dupes = extracted.length - newCount;
      String msg;
      if (extracted.isEmpty) {
        msg = 'No usernames found in image';
      } else if (dupes > 0) {
        msg = 'Added $newCount new username(s) ($dupes duplicate(s) skipped)';
      } else {
        msg = 'Added $newCount username(s) from image';
      }
      showSimpleDialog(msg, extracted.isEmpty ? Colors.orange : Colors.green);
    } catch (e) {
      debugPrint('Image extraction error: $e');
      showSimpleDialog('Failed to extract usernames from image',
          Colors.red);
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  // ── validation (step 0 → 1 transition; tags already validated inline) ────

  void _validateTags() {
    if (_tags.isEmpty) {
      showSimpleDialog('Please add at least one tag first', Colors.red);
      return;
    }
    setState(() => _step = 1);
  }

  // ── create giveaway ──────────────────────────────────────────────────────

  Future<void> _createGiveaway() async {
    final included = _validTags;
    if (included.isEmpty) {
      showSimpleDialog('Include at least one recipient', Colors.red);
      return;
    }
    if (_amountPerPerson <= 0) {
      showSimpleDialog('Please enter a valid amount per person', Colors.red);
      return;
    }
    if (_companyVa == null) {
      showSimpleDialog('Company account not configured', Colors.red);
      return;
    }

    final balanceValue =
        double.tryParse(
              _balance?.replaceAll('₦ ', '').replaceAll(',', '') ?? '0',
            ) ??
            0.0;
    if (balanceValue < _transferAmount) {
      showSimpleDialog('Insufficient balance', Colors.red);
      return;
    }

    final pinOk = await verifyTransactionPin();
    if (!pinOk) return;

    setState(() => _isCreating = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user', Colors.red);
        return;
      }

      // Resolve or validate custom code
      String code;
      if (_isCustomCode) {
        code = _customCodeCtrl.text.trim().toUpperCase();
        if (code.isEmpty) {
          showSimpleDialog('Please enter a custom code', Colors.red);
          return;
        }
        final snap = await FirebaseFirestore.instance
            .collection('giveaways')
            .where('code', isEqualTo: code)
            .get();
        if (snap.docs.isNotEmpty) {
          showSimpleDialog('Custom code already taken', Colors.red);
          return;
        }
      } else {
        code = await _generateUniqueCode();
      }

      // Transfer to company (book transfer — both on Anchor)
      final transferAmountKobo = _transferAmount * 100;
      final transferResult = await FirebaseFunctions.instance
          .httpsCallable('createBookTransfer')
          .call({
            'fromAccountId': _accountId,
            'toAccountId': _companyVa!['id'],
            'amount': transferAmountKobo,
            'currency': 'NGN',
            'narration': 'Targeted Giveaway Funding',
            'idempotencyKey': const Uuid().v4(),
          });
      final status = transferResult.data['data']['attributes']['status'];
      if (status == 'FAILED') {
        showSimpleDialog('Transfer to company account failed', Colors.red);
        return;
      }

      final allowedUids = included
          .map((t) => t.uid)
          .whereType<String>()
          .toList();
      final allowedUsernames =
          included.map((t) => t.username).toList();

      await FirebaseFirestore.instance.collection('giveaways').add({
        'code': code,
        'type': 'targeted',
        'original_total': _totalAmount,
        'fee_rate': _feeRate,
        'who_pays': _whoPays,
        'numPeople': included.length,
        'amountPerPerson': _distributePerPerson,
        'creatorId': user.uid,
        'recipients': [],
        'allowedUids': allowedUids,
        'allowedUsernames': allowedUsernames,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': 'giveaway_create',
        'bank_code': _companyVa!['bankId'],
        'account_number': _companyVa!['accountNumber'],
        'amount': _transferAmount,
        'reason': 'Targeted Giveaway Funding - $code',
        'currency': 'NGN',
        'api_response': transferResult.data,
        'reference': transferResult.data['data']['id'],
        'recipientName': _companyVa!['accountName'],
        'bankName': _companyVa!['bankName'],
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => GiveAwaySuccessBottomSheet(
            code: code,
            title: 'Targeted Giveaway Created',
            description:
                'Your code is ready for ${included.length} recipient(s).',
          ),
        );
      }

      _fetchAccountBalance();
    } catch (e) {
      debugPrint('Error creating targeted giveaway: $e');
      showSimpleDialog('Failed to create giveaway', Colors.red);
    } finally {
      setState(() => _isCreating = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () {
            if (_step > 0) {
              setState(() => _step--);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: const Icon(Icons.arrow_back_ios,
              color: Colors.black87, size: 20),
        ),
        title: const Text(
          'Targeted Giveaway',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _step == 0
            ? _buildStepCollect()
            : _buildStepConfigure(),
      ),
    );
  }

  // ── STEP 0: collect tags ─────────────────────────────────────────────────

  Widget _buildStepCollect() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // balance card
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primaryColor.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Balance: ${_balance ?? '—'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // step indicator
          _buildStepIndicator(0),
          const SizedBox(height: 20),

          const Text(
            'Add Recipients',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter Padi-tags manually, import from a file, or scan an image.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // manual entry – textarea with comma/newline separation
          TextField(
            controller: _tagInputCtrl,
            textCapitalization: TextCapitalization.none,
            minLines: 2,
            maxLines: 5,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'[a-zA-Z0-9_@,\s]')),
            ],
            decoration: InputDecoration(
              hintText: 'e.g. john, jane_doe, alice\n(separate tags by commas or new lines)',
              hintStyle:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _addManualTag,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Add tags',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // inline tag chips with live validation status
          if (_tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((tag) {
                final isChecking = tag.status == _TagStatus.checking;
                final isValid    = tag.status == _TagStatus.valid;
                final chipColor  = isChecking
                    ? Colors.grey.shade500
                    : isValid
                        ? primaryColor
                        : const Color(0xFFFF3B30);
                return Chip(
                  avatar: isChecking
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey.shade500,
                          ),
                        )
                      : Icon(
                          isValid
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 14,
                          color: chipColor,
                        ),
                  label: Text('@${tag.username}'),
                  deleteIcon: Icon(Icons.close, size: 14, color: chipColor),
                  onDeleted: () => _removeTag(tag.username),
                  backgroundColor: chipColor.withOpacity(0.1),
                  side: BorderSide(color: chipColor.withOpacity(0.35), width: 1),
                  labelStyle: TextStyle(
                    color: chipColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${_tags.length} tag(s)\u00b7${_tags.where((t) => t.status == _TagStatus.valid).length} valid\u00b7${_tags.where((t) => t.status == _TagStatus.invalid).length} invalid',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                if (_hasInvalidTags)
                  GestureDetector(
                    onTap: _clearInvalidTags,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_sweep, size: 14, color: Color(0xFFFF3B30)),
                          SizedBox(width: 4),
                          Text(
                            'Clear invalid',
                            style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // import divider
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or import',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 16),

          // import from file
          _buildImportButton(
            icon: FontAwesomeIcons.fileCsv,
            label: 'Import from File',
            subtitle: 'CSV · TXT · Excel · PDF · DOCX',
            onTap: _isExtracting ? null : _pickFromFile,
            color: const Color(0xFF34C759),
          ),
          const SizedBox(height: 10),

          // import from image
          _buildImportButton(
            icon: FontAwesomeIcons.image,
            label: 'Import from Image / Screenshot',
            subtitle: 'Camera · Gallery — Padi AI extracts usernames',
            onTap: _isExtracting ? null : _pickFromImage,
            color: const Color(0xFFFF9500),
          ),

          // extraction loading
          if (_isExtracting) ...[
            const SizedBox(height: 16),
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  SizedBox(height: 10),
                  Text(
                    'Extracting usernames with Padi AI…',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // next button
          Builder(builder: (context) {
            final blocked = _tags.isEmpty ||
                _isExtracting ||
                _isTagsChecking ||
                _hasInvalidTags;
            final String label;
            if (_isTagsChecking) {
              label = 'Validating tags…';
            } else if (_hasInvalidTags) {
              label = 'Remove or clear invalid tags to continue';
            } else {
              label = 'Continue  →';
            }
            return GestureDetector(
              onTap: blocked ? null : _validateTags,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: blocked ? Colors.grey.shade300 : primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: blocked
                        ? Colors.grey.shade600
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildImportButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          border: Border.all(color: color.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: FaIcon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ── STEP 1: configure amount & create ────────────────────────────────────

  Widget _buildStepConfigure() {
    final fmt = NumberFormat('#,##0.00');
    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepIndicator(1),
          const SizedBox(height: 20),

          const Text(
            'Configure Giveaway',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${_validTags.length} recipient(s) will each receive the amount you set.',
            style:
                TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // amount per person
          const Text(
            'Amount Per Person (₦)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [_ThousandsFormatter()],
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'e.g. 5,000',
              prefixText: ' ₦  ',
              prefixStyle: const TextStyle(color: Colors.black87),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: primaryColor)),
            ),
          ),
          const SizedBox(height: 20),

          // who pays fee
          const Text(
            'Who Pays the Fee?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFeeToggle('sender', 'Sender (You)'),
              const SizedBox(width: 10),
              _buildFeeToggle('recipient', 'Recipients'),
            ],
          ),
          const SizedBox(height: 20),

          // fee summary
          if (_amountPerPerson > 0) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(
                      'Amount per person',
                      '₦ ${fmt.format(_amountPerPerson)}'),
                  _buildSummaryRow(
                      'Recipients', '${_validTags.length}'),
                  _buildSummaryRow(
                      'Total amount',
                      '₦ ${fmt.format(_totalAmount)}'),
                  _buildSummaryRow(
                      'Fee (1%)', '₦ ${fmt.format(_fee)}'),
                  const Divider(height: 20),
                  _buildSummaryRow(
                    'You will pay',
                    '₦ ${fmt.format(_transferAmount)}',
                    bold: true,
                  ),
                  _buildSummaryRow(
                    'Each person receives',
                    '₦ ${fmt.format(_distributePerPerson)}',
                    bold: true,
                    color: const Color(0xFF34C759),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // custom code toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Use Custom Code',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Switch(
                value: _isCustomCode,
                activeThumbColor: primaryColor,
                onChanged: (v) =>
                    setState(() => _isCustomCode = v),
              ),
            ],
          ),
          if (_isCustomCode) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customCodeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'e.g. MYCODE2025',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: primaryColor)),
              ),
            ),
          ],
          const SizedBox(height: 30),

          // balance
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Balance: ${_balance ?? '—'}',
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // create button
          GestureDetector(
            onTap: (_isCreating ||
                    _amountPerPerson <= 0 ||
                    _validTags.isEmpty)
                ? null
                : _createGiveaway,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (_isCreating ||
                        _amountPerPerson <= 0 ||
                        _validTags.isEmpty)
                    ? Colors.grey.shade300
                    : primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _isCreating
                  ? const CircularProgressIndicator(
                      color: Colors.white)
                  : const Text(
                      'Create Targeted Giveaway',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Only the ${_validTags.length} registered user(s) you selected can claim this code',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 12),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFeeToggle(String value, String label) {
    final selected = _whoPays == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _whoPays = value),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? primaryColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? primaryColor : Colors.grey.shade300,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ── step indicator ───────────────────────────────────────────────────────

  Widget _buildStepIndicator(int current) {
    const labels = ['Add Recipients', 'Configure'];
    return Row(
      children: List.generate(2, (i) {
        final done = i < current;
        final active = i == current;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? const Color(0xFF34C759)
                          : active
                              ? primaryColor
                              : Colors.grey.shade300,
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: active
                          ? primaryColor
                          : done
                              ? const Color(0xFF34C759)
                              : Colors.grey.shade400,
                      fontWeight: active || done
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: done
                        ? const Color(0xFF34C759)
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
