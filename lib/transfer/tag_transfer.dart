import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

class TagTransferPage extends StatefulWidget {
  const TagTransferPage({super.key});

  @override
  State<TagTransferPage> createState() => _TagTransferPageState();
}

class _TagTransferPageState extends State<TagTransferPage> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  bool sendAnonymously = false;
  bool isLoading = false;
  bool isCheckingUsername = false;
  bool isUsernameValid = false;
  String feeText = "Free transfers";
  Map<String, dynamic>? recipientData;
  String? receiverUid;
  Timer? _usernameDebounce;
  String? counterpartyId;
  List<Map<String, dynamic>> _recentTagTransfers = [];
  bool _loadingRecents = false;
  int _currentPage = 0;

  // ── Cached user data (loaded once at init) ──────────────────────────────
  Map<String, dynamic>? _cachedUserDoc;
  double? _cachedBalance;
  bool _isFetchingBalance = false;
  Map<String, dynamic>? _cachedCompanyVa;
  String? _ownAccountNumber;

  @override
  void initState() {
    super.initState();
    amountController.addListener(_updateFee);
    usernameController.addListener(_debounceCheckUsername);
    _initAllParallel();
  }

  /// Kicks off all background loads simultaneously.
  Future<void> _initAllParallel() async {
    await Future.wait([
      _prefetchUserDoc(),
      _loadRecentTagTransfers(),
    ]);
  }

  // ── User doc + balance: loaded ONCE ─────────────────────────────────────
  Future<void> _prefetchUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _cachedUserDoc = doc.data();
      _ownAccountNumber =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data']?['attributes']?['accountNumber']
              ?.toString();

      // Fetch balance in background
      _fetchAndCacheBalance();

      // Pre-fetch company VA
      _cachedCompanyVa = await getCompanyVirtualAccount();
    } catch (e) {
      debugPrint('_prefetchUserDoc error: $e');
    }
  }

  Future<void> _fetchAndCacheBalance() async {
    if (_isFetchingBalance) return;
    _isFetchingBalance = true;
    try {
      final accountId =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data']?['id']
              ?.toString();
      if (accountId == null || accountId.isEmpty) return;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'safehavenFetchAccountBalance',
      );
      final result = await callable.call({'accountId': accountId});
      final balanceKobo =
          (result.data['data']['availableBalance'] as num?)?.toDouble() ?? 0.0;
      _cachedBalance = balanceKobo / 100;
      debugPrint('✅ Balance pre-fetched for tag transfer: ₦$_cachedBalance');
    } catch (e) {
      debugPrint('_fetchAndCacheBalance error: $e');
    } finally {
      _isFetchingBalance = false;
    }
  }

  Future<double> _getBalance() async {
    if (_cachedBalance != null) return _cachedBalance!;
    await _fetchAndCacheBalance();
    return _cachedBalance ?? 0.0;
  }

  Future<bool> _checkBalance(double amountNaira) async {
    const fee = 0.0; // Tag transfers are free
    final totalRequired = amountNaira + fee;
    final balance = await _getBalance();
    if (balance < totalRequired) {
      showSimpleDialog(
        'Insufficient balance. Balance: ₦${balance.toStringAsFixed(2)}. '
        'Required: ₦${totalRequired.toStringAsFixed(2)} (no fee)',
        Colors.red,
      );
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    if (_cachedCompanyVa != null) return _cachedCompanyVa;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('company')
          .doc('account_details')
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      final rawCompanyId =
          data['safehavenAccountId']?.toString() ??
          data['safehaven_account_id']?.toString() ??
          data['accountId']?.toString() ??
          '';
      final companyAccountNumber =
          data['safehavenAccountNumber']?.toString() ??
          data['safehaven_account_number']?.toString() ??
          data['accountNumber']?.toString() ??
          '';
      final companyBankId =
          data['safehavenBankCode']?.toString() ??
          data['safehaven_bank_code']?.toString() ??
          data['bankId']?.toString() ??
          '090286';
      final companyId =
          (rawCompanyId.isNotEmpty &&
              !rawCompanyId.toLowerCase().contains('anc_acc'))
          ? rawCompanyId
          : companyAccountNumber;
      return {
        'uid': doc.id,
        'id': companyId,
        'type':
            data['safehavenAccountType']?.toString() ??
            data['accountType']?.toString() ??
            'BankAccount',
        'bankId': companyBankId,
        'bankName':
            data['safehavenBankName']?.toString() ??
            data['bankName']?.toString() ??
            'SAFE HAVEN MICROFINANCE BANK',
        'accountNumber': companyAccountNumber,
        'accountName':
            data['safehavenAccountName']?.toString() ??
            data['accountName']?.toString() ??
            '',
      };
    } catch (e) {
      debugPrint('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  // ── Recent transfers (load once, then update on success) ────────────────
  Future<void> _loadRecentTagTransfers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingRecents = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'transfer')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      final seen = <String>{};
      final entries = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final receiverId = data['receiverId']?.toString() ?? '';
        if (receiverId.isEmpty || receiverId == 'unknown') continue;
        if (seen.contains(receiverId)) continue;
        seen.add(receiverId);
        entries.add(data);
        if (entries.length >= 10) break;
      }
      // Fetch user docs for profile info
      final enriched = <Map<String, dynamic>>[];
      for (final txn in entries) {
        final receiverId = txn['receiverId']?.toString() ?? '';
        final storedUsername = txn['username']?.toString() ?? '';
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(receiverId)
              .get();
          final userData = userDoc.data() ?? {};
          enriched.add({
            'uid': receiverId,
            'username': storedUsername.isNotEmpty
                ? storedUsername
                : userData['username']?.toString() ?? '',
            'name': txn['recipientName']?.toString() ?? '',
            'profileImage': userData['profileImage']?.toString() ?? '',
          });
        } catch (_) {
          enriched.add({
            'uid': receiverId,
            'username': storedUsername,
            'name': txn['recipientName']?.toString() ?? '',
            'profileImage': '',
          });
        }
      }
      if (mounted) setState(() => _recentTagTransfers = enriched);
    } catch (e) {
      debugPrint('loadRecentTagTransfers error: $e');
    }
    if (mounted) setState(() => _loadingRecents = false);
  }

  void _updateFee() {
    final amount = double.tryParse(amountController.text) ?? 0.0;
    setState(() {
      feeText = amount > 0 ? "Free transfer" : "Free transfers";
    });
  }

  void _debounceCheckUsername() {
    _usernameDebounce?.cancel();
    _usernameDebounce = Timer(const Duration(milliseconds: 500), _checkUsername);
  }

  Future<void> _checkUsername() async {
    final username = usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() {
        isUsernameValid = false;
        recipientData = null;
        receiverUid = null;
        isCheckingUsername = false;
      });
      return;
    }

    setState(() => isCheckingUsername = true);

    try {
      final usernameDoc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .get();

      if (!usernameDoc.exists) {
        setState(() {
          isUsernameValid = false;
          recipientData = null;
          receiverUid = null;
          isCheckingUsername = false;
        });
        return;
      }

      final uid = (usernameDoc.data() ?? {})['uid'] as String?;
      if (uid == null) {
        setState(() {
          isUsernameValid = false;
          recipientData = null;
          receiverUid = null;
          isCheckingUsername = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      setState(() {
        isUsernameValid = userDoc.exists;
        recipientData = userDoc.data();
        receiverUid = userDoc.exists ? userDoc.id : null;
        isCheckingUsername = false;
      });
    } catch (e) {
      debugPrint('Error checking username: $e');
      showSimpleDialog('Error checking username', Colors.red);
      setState(() {
        isUsernameValid = false;
        recipientData = null;
        receiverUid = null;
        isCheckingUsername = false;
      });
    }
  }

  Future<void> _createCounterparty() async {
    if (recipientData == null || !isUsernameValid) {
      showSimpleDialog('Please verify recipient tag', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final userVaData = _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      final accountId = userVaData?['id']?.toString();
      final accountType = userVaData?['type']?.toString();
      final bankIdRaw = userVaData?['attributes']?['bank']?['id']?.toString();
      final bankNameCandidate = userVaData?['attributes']?['bank']?['name']?.toString();
      final bankId = await resolveBankId(
        bankId: bankIdRaw,
        bankName: bankNameCandidate,
      );

      if (accountId == null || bankId == null || accountType == null) {
        throw Exception('User account details incomplete');
      }

      final recipientAccountNumber =
          recipientData!['safehavenData']?['virtualAccount']?['data']?['attributes']?['accountNumber']
              ?.toString();
      final recipientBankIdRaw =
          recipientData!['safehavenData']?['virtualAccount']?['data']?['attributes']?['bank']?['id'];
      final recipientBankName =
          recipientData!['safehavenData']?['virtualAccount']?['data']?['attributes']?['bank']?['name'];
      final recipientAccountName =
          recipientData!['safehavenData']?['virtualAccount']?['data']?['attributes']?['accountName'];

      final recipientBankId = await resolveBankId(
        bankId: recipientBankIdRaw?.toString(),
        bankName: recipientBankName,
      );

      if (recipientAccountNumber == null || recipientBankId == null) {
        throw Exception('Recipient missing bank details');
      }

      // Prevent self counterparty
      if (_ownAccountNumber != null && _ownAccountNumber == recipientAccountNumber) {
        showSimpleDialog('You cannot create a counterparty for your own account', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      // Check existing counterparty
      final query = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() => counterpartyId = query.docs.first.id);
        setState(() => isLoading = false);
        return;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenCreateCounterparty')
          .call({
            'accountId': accountId,
            'bankId': recipientBankId,
            'accountType': accountType,
            'accountName': recipientAccountName,
            'bankName': recipientBankName,
            'accountNumber': recipientAccountNumber,
            'bankCode': recipientBankId,
          });
      final newId = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(newId)
          .set({
            ...result.data,
            'userId': user.uid,
            'recipientAccountNumber': recipientAccountNumber,
            'recipientBankCode': recipientBankId,
            'ownerAccountId': accountId,
          });
      setState(() => counterpartyId = newId);
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showSimpleDialog('Error creating counterparty', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _safehavenTransferIntra() async {
    if (recipientData == null || amountController.text.isEmpty) return;

    final amountToSend = double.parse(amountController.text);
    if (!await _checkBalance(amountToSend)) return;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final userVaData = _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      final fromAccountId = userVaData?['id']?.toString();
      if (fromAccountId == null) throw Exception('User account ID missing');

      final recipientVaData = recipientData!['safehavenData']?['virtualAccount']?['data'];
      final toAccountId = recipientVaData?['id']?.toString();
      final recipientAccountNumber = recipientVaData?['attributes']?['accountNumber']?.toString() ?? '';

      if (toAccountId == null || toAccountId.isEmpty) {
        throw Exception('Recipient account not found');
      }

      // Prevent self transfer
      if (receiverUid == user.uid) {
        showSimpleDialog('You cannot send money to your own tag', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': fromAccountId,
            'toAccountId': toAccountId,
            'amount': amountToSend * 100,
            'currency': 'NGN',
            'narration': remarkController.text.trim().isEmpty
                ? 'Transfer to @${usernameController.text}'
                : remarkController.text,
            'idempotencyKey': const Uuid().v4(),
          });

      final status = result.data['data']['attributes']['status'];
      if (status == 'FAILED') {
        final failureReason = result.data['data']['attributes']['failureReason'];
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountName = recipientVaData?['attributes']?['accountName']?.toString() ?? '';
      final recipientBankName = recipientVaData?['attributes']?['bank']?['name']?.toString() ?? 'Safe Haven Microfinance Bank';
      final recipientBankId = recipientVaData?['attributes']?['bank']?['id']?.toString() ?? '090286';

      // Save transaction
      // await FirebaseFirestore.instance.collection('transactions').add({
      //   'userId': user.uid,
      //   'receiverId': receiverUid ?? 'unknown',
      //   'type': 'transfer',
      //   'bank_code': recipientBankId,
      //   'account_number': recipientAccountNumber,
      //   'amount': amountToSend,
      //   'reason': remarkController.text,
      //   'currency': 'NGN',
      //   'api_response': result.data,
      //   'reference': result.data['data']['id'],
      //   'recipientName': recipientAccountName,
      //   'bankName': recipientBankName,
      //   'username': usernameController.text,
      //   'timestamp': FieldValue.serverTimestamp(),
      // });

      // Refresh recent transfers after success
      _loadRecentTagTransfers();

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: 'Done',
          title: 'Payment Successful',
          description: 'Your transfer has been processed successfully.',
          recipientName: recipientAccountName,
          bankName: recipientBankName,
          bankCode: recipientBankId,
          accountNumber: recipientAccountNumber,
          reference: result.data['data']['id'],
        ),
        isScrollControlled: true,
      );

      // Clear form
      amountController.clear();
      remarkController.clear();
      setState(() {
        _currentPage = 0;
        usernameController.clear();
        recipientData = null;
        receiverUid = null;
        isUsernameValid = false;
      });
    } catch (e) {
      debugPrint('safehavenTransferIntra error: $e');
      showSimpleDialog('Error processing transfer: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _ghostTransfer() async {
    if (recipientData == null || amountController.text.isEmpty) {
      showSimpleDialog('Please complete all fields', Colors.red);
      return;
    }

    final amountToSend = double.parse(amountController.text);
    if (!await _checkBalance(amountToSend)) return;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      // Use cached user data
      final userVaData = _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      if (userVaData == null) throw Exception('User account not found');
      final userAccountId = userVaData['id']?.toString() ?? '';
      final userAccountType = userVaData['type']?.toString() ?? '';
      final userBankIdRaw = userVaData['attributes']?['bank']?['id']?.toString();
      final userBankName = userVaData['attributes']?['bank']?['name']?.toString();
      final userBankId = await resolveBankId(bankId: userBankIdRaw, bankName: userBankName) ?? '';
      if (userAccountId.isEmpty || userAccountType.isEmpty || userBankId.isEmpty) {
        throw Exception('User account details incomplete');
      }

      // Use cached company VA
      final companyVa = _cachedCompanyVa ?? await getCompanyVirtualAccount();
      if (companyVa == null || (companyVa['id'] as String).isEmpty) {
        throw Exception('Company account not found');
      }

      final recipientVaData = recipientData!['safehavenData']?['virtualAccount']?['data'];
      final recipientAccountNumber = recipientVaData?['attributes']?['accountNumber']?.toString() ?? '';
      final recipientAccountId = recipientVaData?['id']?.toString();
      final recipientBankIdRaw = recipientVaData?['attributes']?['bank']?['id'];
      final recipientBankName = recipientVaData?['attributes']?['bank']?['name']?.toString();
      final recipientAccountName = recipientVaData?['attributes']?['accountName']?.toString() ?? '';
      final recipientBankId = await resolveBankId(
        bankId: recipientBankIdRaw?.toString(),
        bankName: recipientBankName,
      );
      if (recipientAccountNumber.isEmpty || recipientBankId == null) {
        throw Exception('Recipient missing bank details');
      }
      final resolvedRecipientDestination = (recipientAccountId != null && recipientAccountId.isNotEmpty)
          ? recipientAccountId
          : recipientAccountNumber;

      // Step 1: user → company (intra)
      final amountToCompanyKobo = amountToSend * 100; // no fee for tag transfers
      final firstResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': userAccountId,
            'toAccountId': companyVa['id'],
            'amount': amountToCompanyKobo,
            'currency': 'NGN',
            'narration': 'Ghost Mode to Company: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}',
            'idempotencyKey': const Uuid().v4(),
          });
      if (firstResult.data['data']['attributes']['status'] == 'FAILED') {
        throw Exception('Transfer to company failed: ${firstResult.data['data']['attributes']['failureReason']}');
      }

      // Step 2: company → recipient (intra)
      final secondResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': companyVa['id'],
            'toAccountId': resolvedRecipientDestination,
            'toBankCode': recipientBankId,
            'amount': amountToSend * 100,
            'currency': 'NGN',
            'narration': remarkController.text.isNotEmpty ? remarkController.text : 'Ghost Mode Transfer',
            'idempotencyKey': const Uuid().v4(),
          });
      if (secondResult.data['data']['attributes']['status'] == 'FAILED') {
        throw Exception('Transfer to recipient failed: ${secondResult.data['data']['attributes']['failureReason']}');
      }

      // Log transaction
      // await FirebaseFirestore.instance.collection('transactions').add({
      //   'actualSender': user.uid,
      //   'userId': 'company',
      //   'receiverId': receiverUid ?? 'unknown',
      //   'type': 'ghost_transfer',
      //   'bank_code': recipientBankId,
      //   'account_number': recipientAccountNumber,
      //   'amount': amountToSend,
      //   'reason': remarkController.text,
      //   'currency': 'NGN',
      //   'api_response': secondResult.data,
      //   'reference': secondResult.data['data']['id'],
      //   'recipientName': recipientAccountName,
      //   'bankName': recipientBankName ?? 'Unknown Bank',
      //   'username': usernameController.text,
      //   'timestamp': FieldValue.serverTimestamp(),
      // });

      // Refresh recent transfers
      _loadRecentTagTransfers();

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: 'Done',
          title: 'Payment Successful',
          description: 'Your transfer has been processed successfully.',
          recipientName: recipientAccountName,
          bankName: recipientBankName ?? 'Unknown Bank',
          bankCode: recipientBankId,
          accountNumber: recipientAccountNumber,
          reference: secondResult.data['data']['id'],
        ),
        isScrollControlled: true,
      );

      // Clear form
      amountController.clear();
      remarkController.clear();
      setState(() {
        _currentPage = 0;
        usernameController.clear();
        recipientData = null;
        receiverUid = null;
        isUsernameValid = false;
      });
    } catch (e) {
      debugPrint('ghostTransfer error: $e');
      showSimpleDialog('Error processing ghost transfer: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    usernameController.removeListener(_debounceCheckUsername);
    _usernameDebounce?.cancel();
    amountController.dispose();
    usernameController.dispose();
    remarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            if (_currentPage == 0) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() => _currentPage = 0);
                            }
                          },
                          child: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
                        ),
                        const Spacer(),
                        Text(
                          'Send Money via Tag',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // PAGE 0: Username selection
                    if (_currentPage == 0) ...[
                      const Text('Recipient Tag'),
                      const SizedBox(height: 8),
                      TextField(
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        style: GoogleFonts.inter(fontSize: 14),
                        controller: usernameController,
                        keyboardType: TextInputType.name,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          hintText: 'username',
                          hintStyle: GoogleFonts.inter(color: Colors.grey.shade600),
                          prefixIcon: Icon(Icons.alternate_email, color: Colors.grey.shade600),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (usernameController.text.isNotEmpty && !isCheckingUsername)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              isUsernameValid ? Icons.check_circle : Icons.error,
                              size: 16,
                              color: isUsernameValid ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isUsernameValid ? 'Username found' : 'Username not found',
                              style: GoogleFonts.inter(
                                color: isUsernameValid ? Colors.green : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isCheckingUsername || !isUsernameValid ? null : () => setState(() => _currentPage = 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Next', style: GoogleFonts.inter(color: Colors.white)),
                      ),
                    ]

                    // PAGE 1: Amount & Remark
                    else if (_currentPage == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryColor.withValues(alpha: 0.12),
                              child: Text(
                                usernameController.text[0].toUpperCase(),
                                style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    usernameController.text,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  Text(
                                    '@${usernameController.text}',
                                    style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Amount to Send'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Text('₦', style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade600)),
                            ),
                            Expanded(
                              child: TextField(
                                keyboardType: TextInputType.number,
                                controller: amountController,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0.00',
                                ),
                              ),
                            ),
                            Text(feeText, style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.8,
                        children: [500, 1000, 2000, 5000, 9999, 10000].map((amt) {
                          final fmtAmt = amt.toString().replaceAllMapped(
                            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                            (m) => '${m[1]},',
                          );
                          return GestureDetector(
                            onTap: () => setState(() => amountController.text = amt.toString()),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              alignment: Alignment.center,
                              child: Text('₦$fmtAmt', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Remark'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: remarkController,
                        decoration: InputDecoration(
                          hintStyle: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          hintText: 'What is this transfer for? (optional)',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ghost Mode', style: GoogleFonts.inter(color: Colors.black26, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 5),
                              Text('Send money anonymously', style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          FlutterSwitch(
                            width: 50,
                            height: 25,
                            toggleSize: 20,
                            borderRadius: 20,
                            padding: 3,
                            value: sendAnonymously,
                            activeColor: primaryColor,
                            inactiveColor: Colors.grey.shade300,
                            onToggle: (val) => setState(() => sendAnonymously = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isLoading || (double.tryParse(amountController.text) ?? 0.0) <= 0
                            ? null
                            : () async {
                                final currentUser = FirebaseAuth.instance.currentUser;
                                if (currentUser != null && receiverUid != null && receiverUid == currentUser.uid) {
                                  showSimpleDialog('You cannot send money to your own tag', Colors.red);
                                  return;
                                }
                                if (!sendAnonymously) {
                                  await _safehavenTransferIntra();
                                } else {
                                  await _ghostTransfer();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text('Confirm', style: GoogleFonts.inter(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),

              // Recent transfers section (page 0 only)
              if (_currentPage == 0) ...[
                if (_loadingRecents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_recentTagTransfers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            child: Text(
                              'Recents',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentTagTransfers.length,
                            separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
                            itemBuilder: (context, index) {
                              final r = _recentTagTransfers[index];
                              final name = r['name']?.toString() ?? 'Unknown';
                              final username = r['username']?.toString() ?? '';
                              final profileImage = r['profileImage']?.toString() ?? '';
                              final initials = name
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .map((s) => s[0].toUpperCase())
                                  .join();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: primaryColor.withValues(alpha: 0.12),
                                  backgroundImage: profileImage.isNotEmpty ? NetworkImage(profileImage) : null,
                                  child: profileImage.isEmpty
                                      ? Text(initials, style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 14))
                                      : null,
                                ),
                                title: Text('@$username', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                onTap: () {
                                  if (username.isNotEmpty) {
                                    usernameController.text = username;
                                    setState(() => _currentPage = 1);
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}