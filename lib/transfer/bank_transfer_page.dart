import 'package:card_app/my_padi/padi_aliases_page.dart';
import 'package:card_app/ui/account_image_scanner.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

class BankTransferPage extends StatefulWidget {
  final String? initialAccountNumber;
  final String? initialAmount;
  final String? initialBankName;

  const BankTransferPage({
    super.key,
    this.initialAccountNumber,
    this.initialAmount,
    this.initialBankName,
  });

  @override
  State<BankTransferPage> createState() => _BankTransferPageState();
}

class _BankTransferPageState extends State<BankTransferPage> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();

  String? selectedBank;
  List<Map<String, dynamic>> banks = [];
  bool sendAnonymously = false;
  bool isLoading = false;
  bool isFetchingBanks = false;
  bool isFetchingAccountName = false;
  String? counterpartyId;
  String feeText = "";
  List<Map<String, dynamic>> _recentTransfers = [];
  bool _loadingRecents = false;
  List<PadiAlias> _aliases = [];
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

    if (widget.initialAccountNumber != null) {
      accountNumberController.text = widget.initialAccountNumber!;
    }
    if (widget.initialAmount != null) {
      amountController.text = widget.initialAmount!;
    }

    amountController.addListener(_updateFee);

    // Fire everything in parallel — don't await, let them stream in
    _initAllParallel();
  }

  /// Kicks off all background loads simultaneously so nothing blocks the UI.
  Future<void> _initAllParallel() async {
    await Future.wait([
      _prefetchUserDoc(), // must run first so balance + own account ready
      _fetchBanks(),
      _loadRecentTransfers(),
      _loadAliases(),
    ]);

    // After userDoc is cached, pre-fill from initialBankName if needed
    if (widget.initialBankName != null && banks.isNotEmpty) {
      _autoSelectBank(widget.initialBankName!);
    }
  }

  // ── User doc + balance: loaded ONCE, reused everywhere ──────────────────

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

      // Fetch balance in background right after we have the accountId
      _fetchAndCacheBalance();

      // Also pre-fetch company VA
      _cachedCompanyVa = await getCompanyVirtualAccount();
    } catch (e) {
      debugPrint('_prefetchUserDoc error: $e');
    }
  }

  String _getBankName() {
    if (selectedBank == null || banks.isEmpty) return 'Unknown Bank';
    try {
      final bank = banks.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['id'] == selectedBank,
        orElse: () => <String, dynamic>{
          'attributes': <String, dynamic>{'name': 'Unknown Bank'},
        },
      );
      final name = (bank['attributes']?['name'] as String?)?.trim();
      return (name?.isNotEmpty == true) ? name! : 'Unknown Bank';
    } catch (_) {
      return 'Unknown Bank';
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
      debugPrint('✅ Balance pre-fetched: ₦$_cachedBalance');
    } catch (e) {
      debugPrint('_fetchAndCacheBalance error: $e');
    } finally {
      _isFetchingBalance = false;
    }
  }

  /// Returns the cached balance, or fetches fresh if not yet available.
  Future<double> _getBalance() async {
    if (_cachedBalance != null) return _cachedBalance!;
    // Not ready yet — wait (rare, only if transfer initiated very fast)
    await _fetchAndCacheBalance();
    return _cachedBalance ?? 0.0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _updateFee() {
    final amount = double.tryParse(amountController.text) ?? 0.0;
    setState(() {
      feeText = amount > 0 ? "Fee: ₦50.00" : "";
    });
  }

  void _autoSelectBank(String bankName) {
    if (banks.isEmpty) return;
    final bName = bankName.toLowerCase();
    final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
      (b) =>
          b?['attributes']['name']?.toLowerCase().contains(bName) == true ||
          bName.contains(b?['attributes']['name']?.toLowerCase() ?? ''),
      orElse: () => null,
    );
    if (matched != null && mounted) {
      setState(() => selectedBank = matched['id'] as String);
      if (accountNumberController.text.length == 10) _safehavenNameEnquiry();
    }
  }

  Future<void> _loadAliases() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('padi_aliases')
          .orderBy('alias')
          .get();
      if (mounted) {
        setState(() {
          _aliases = snapshot.docs.map(PadiAlias.fromDoc).toList();
        });
      }
    } catch (e) {
      debugPrint('loadAliases error: $e');
    }
  }

  Future<void> _loadRecentTransfers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (mounted) setState(() => _loadingRecents = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'transfer')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      final seen = <String>{};
      final recents = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final acct = data['account_number']?.toString() ?? '';
        final bank = data['bank_code']?.toString() ?? '';
        if (acct.isEmpty) continue;
        final key = '${acct}_$bank';
        if (!seen.contains(key)) {
          seen.add(key);
          recents.add(data);
          if (recents.length >= 10) break;
        }
      }
      if (mounted) setState(() => _recentTransfers = recents);
    } catch (e) {
      debugPrint('loadRecentTransfers error: $e');
    }
    if (mounted) setState(() => _loadingRecents = false);
  }

  Future<void> _onScanAccountImage() async {
    final result = await scanAccountFromImage(context);
    if (result == null) return;

    if (result.accountNumber != null && result.accountNumber!.isNotEmpty) {
      setState(() => accountNumberController.text = result.accountNumber!);
    }

    if (result.bankName != null &&
        result.bankName!.isNotEmpty &&
        banks.isNotEmpty) {
      _autoSelectBank(result.bankName!);
    }

    if (accountNumberController.text.length == 10) {
      _autoLookupCounterparty(accountNumberController.text);
      if (selectedBank != null) _safehavenNameEnquiry();
    }
  }

  Future<void> _fetchBanks() async {
    if (mounted) setState(() => isFetchingBanks = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banks')
          .get();
      List<Map<String, dynamic>> bankList = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'attributes': <String, dynamic>{'name': doc.data()['name']},
        };
      }).toList();

      if (bankList.isEmpty) {
        final result = await callCloudFunctionLogged(
          'safehavenBankList',
          source: 'bank_transfer_page.dart',
        );
        final apiBankList = (result.data as Map)['data'] as List<dynamic>;
        final batch = FirebaseFirestore.instance.batch();
        for (var item in apiBankList) {
          final map = item as Map;
          final docRef = FirebaseFirestore.instance
              .collection('banks')
              .doc(map['id'].toString());
          batch.set(docRef, {
            'name': (map['attributes'] as Map)['name']?.toString(),
          });
          bankList.add({
            'id': map['id'].toString(),
            'attributes': <String, dynamic>{
              'name': (map['attributes'] as Map)['name']?.toString(),
            },
          });
        }
        await batch.commit();
      }

      if (mounted) {
        setState(() {
          banks = bankList;
          isFetchingBanks = false;
        });
      }
    } catch (e) {
      debugPrint('safehavenBankList error: $e');
      if (mounted) setState(() => isFetchingBanks = false);
    }
  }

  Future<void> _autoLookupCounterparty(String accountNumber) async {
    if (accountNumber.length != 10) return;
    if (mounted) setState(() => isFetchingAccountName = true);
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('recipientAccountNumber', isEqualTo: accountNumber)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        String? bankId = data['recipientBankCode'] as String?;
        final accountName =
            data['data']?['attributes']?['accountName'] as String? ??
            data['attributes']?['accountName'] as String? ??
            data['accountName'] as String?;
        final bankName =
            data['bankName'] as String? ??
            data['data']?['attributes']?['bank']?['name'] as String?;

        if (bankId == null && bankName != null) {
          bankId = await _resolveBankIdByName(bankName);
        }

        if (bankId != null && accountName != null && mounted) {
          setState(() {
            selectedBank = bankId;
            accountNameController.text = accountName;
            isFetchingAccountName = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('_autoLookupCounterparty error: $e');
    }
    if (mounted) setState(() => isFetchingAccountName = false);
  }

  Future<String?> _resolveBankIdByName(String bankName) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('banks')
          .where('name', isEqualTo: bankName)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      // Fallback: search loaded banks list first (no extra Firestore read)
      for (final b in banks) {
        final bname = (b['attributes']['name'] as String? ?? '').toLowerCase();
        if (bname == bankName.toLowerCase()) return b['id'] as String;
      }
    } catch (e) {
      debugPrint('_resolveBankIdByName error: $e');
    }
    return null;
  }

  Future<void> _safehavenNameEnquiry() async {
    if (accountNumberController.text.length != 10 || selectedBank == null) {
      showSimpleDialog(
        'Please enter valid account number and select a bank',
        Colors.red,
      );
      return;
    }

    final docId = '${selectedBank}_${accountNumberController.text}';

    // Check cache first
    final doc = await FirebaseFirestore.instance
        .collection('verified_accounts')
        .doc(docId)
        .get();
    if (doc.exists) {
      if (mounted)
        setState(() => accountNameController.text = doc.data()!['accountName']);
      return;
    }

    if (mounted) setState(() => isFetchingAccountName = true);
    try {
      final result = await callCloudFunctionLogged(
        'safehavenNameEnquiry',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountNumber': accountNumberController.text,
          'bankIdOrBankCode': selectedBank,
        },
      );
      final accountName = result.data['data']['attributes']['accountName'];
      if (mounted) setState(() => accountNameController.text = accountName);

      // Cache so we never hit the API for this account again
      await FirebaseFirestore.instance
          .collection('verified_accounts')
          .doc(docId)
          .set({
            'accountName': accountName,
            'verifiedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('safehavenNameEnquiry error: $e');
      if (mounted) showSimpleDialog('Error verifying account', Colors.red);
    }
    if (mounted) setState(() => isFetchingAccountName = false);
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
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

  // ── Balance guard (runs before every transfer) ───────────────────────────

  /// Returns true if balance is sufficient; shows error and returns false otherwise.
  Future<bool> _checkBalance(double amountNaira) async {
    const fee = 50.0;
    final totalRequired = amountNaira + fee;
    final balance = await _getBalance();
    if (balance < totalRequired) {
      showSimpleDialog(
        'Insufficient balance. Balance: ₦${balance.toStringAsFixed(2)}. '
        'Required: ₦${totalRequired.toStringAsFixed(2)} (includes ₦50 fee)',
        Colors.red,
      );
      return false;
    }
    return true;
  }

  // ── Counterparty (create or reuse) ───────────────────────────────────────

  Future<void> _createCounterparty() async {
    if (accountNameController.text.isEmpty || selectedBank == null) {
      showSimpleDialog('Please verify account details', Colors.red);
      return;
    }
    if (mounted) setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return;
      }

      final userVaData =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      final accountId = userVaData?['id']?.toString();
      final accountType = userVaData?['type']?.toString();
      final bankIdRaw = userVaData?['attributes']?['bank']?['id']?.toString();
      final bankNameCandidate = userVaData?['attributes']?['bank']?['name']
          ?.toString();
      final bankId = await resolveBankId(
        bankId: bankIdRaw,
        bankName: bankNameCandidate,
      );

      if (_ownAccountNumber != null &&
          _ownAccountNumber == accountNumberController.text) {
        showSimpleDialog(
          'You cannot send money to your own account',
          Colors.red,
        );
        return;
      }
      if (accountId == null || bankId == null || accountType == null) {
        showSimpleDialog('Account details incomplete', Colors.red);
        return;
      }

      // Check if counterparty already exists
      final query = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where(
            'recipientAccountNumber',
            isEqualTo: accountNumberController.text,
          )
          .where('recipientBankCode', isEqualTo: selectedBank)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        if (mounted) setState(() => counterpartyId = query.docs.first.id);
        return;
      }

      final bank = banks.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['id'] == selectedBank,
        orElse: () => <String, dynamic>{
          'attributes': <String, dynamic>{'name': 'Unknown'},
        },
      );

      final payload = {
        'accountId': accountId,
        'bankId': selectedBank,
        'accountType': accountType,
        'accountName': accountNameController.text,
        'bankName': bank['attributes']['name'] ?? 'Unknown',
        'accountNumber': accountNumberController.text,
        'bankCode': selectedBank,
      };

      final result = await callCloudFunctionLogged(
        'safehavenCreateCounterparty',
        source: 'bank_transfer_page.dart',
        payload: payload,
      );
      final newId = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(newId)
          .set({
            ...result.data,
            'userId': user.uid,
            'recipientAccountNumber': accountNumberController.text,
            'recipientBankCode': selectedBank,
            'ownerAccountId': accountId,
          });
      if (mounted) setState(() => counterpartyId = newId);
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      if (mounted) showSimpleDialog('Error creating counterparty', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  } // ── Transfer ─────────────────────────────────────────────────────────────

  Future<void> _safehavenTransferNip() async {
    if (counterpartyId == null || amountController.text.isEmpty) {
      showSimpleDialog('Please complete all fields', Colors.red);
      return;
    }

    final amountToSend = double.parse(amountController.text);
    if (!await _checkBalance(amountToSend)) return;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    if (mounted) setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return;
      }

      final userVaData =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      final accountId = userVaData?['id']?.toString();
      final accountType = userVaData?['type']?.toString();

      final selectedBankName = banks
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (b) => b?['id'] == selectedBank,
            orElse: () => null,
          )?['attributes']?['name']
          ?.toString();

      if (_ownAccountNumber != null &&
          _ownAccountNumber == accountNumberController.text) {
        showSimpleDialog(
          'You cannot send money to your own account',
          Colors.red,
        );
        return;
      }

      final isSafehavenBank =
          (selectedBank == '090286') ||
          (selectedBankName?.toLowerCase().contains('safe haven') ?? false);

      if (isSafehavenBank) {
        await _doIntraTransfer(user, accountId, amountToSend);
        return;
      }

      final result = await callCloudFunctionLogged(
        'safehavenTransferNip',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountType': accountType,
          'accountId': accountId,
          'counterpartyId': counterpartyId,
          'amount': amountToSend * 100,
          'currency': 'NGN',
          'narration': remarkController.text,
          'idempotencyKey': const Uuid().v4(),
        },
      );

      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == 'FAILED') {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        return;
      }

      final bank = banks.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['id'] == selectedBank,
        orElse: () => <String, dynamic>{
          'attributes': <String, dynamic>{'name': 'Unknown'},
        },
      );

      // await _logTransaction(
      //   user,
      //   result.data,
      //   bank['attributes']['name'] ?? 'Unknown',
      //   amountToSend,
      //   'transfer',
      // );
      _showSuccess(result.data, bank['attributes']['name'] ?? 'Unknown');
    } catch (e) {
      debugPrint('safehavenTransferNip error: $e');
      if (mounted) showSimpleDialog('Error processing transfer', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _doIntraTransfer(
    User user,
    String? accountId,
    double amountNaira,
  ) async {
    final intraResult = await callCloudFunctionLogged(
      'safehavenTransferIntra',
      source: 'bank_transfer_page.dart',
      payload: {
        'fromAccountId': accountId,
        'toAccountId': accountNumberController.text.trim(),
        'amount': amountNaira * 100,
        'narration': remarkController.text.isNotEmpty
            ? remarkController.text
            : 'Transfer',
        'idempotencyKey': const Uuid().v4(),
      },
    );
    final status = intraResult.data['data']['attributes']['status'];
    if (status == 'FAILED') {
      showSimpleDialog(
        'Transfer failed: ${intraResult.data['data']['attributes']['failureReason']}',
        Colors.red,
      );
      return;
    }

    // FIXED: Safe firstWhere
    final bank = banks.cast<Map<String, dynamic>>().firstWhere(
      (b) => b['id'] == selectedBank,
      orElse: () => <String, dynamic>{
        'attributes': <String, dynamic>{'name': 'Unknown'},
      },
    );

    // await _logTransaction(
    //   user,
    //   intraResult.data,
    //   bank['attributes']['name'] ?? 'Unknown',
    //   amountNaira,
    //   'transfer',
    // );
    _showSuccess(intraResult.data, bank['attributes']['name'] ?? 'Unknown');
  }

  Future<void> _ghostTransfer() async {
    if (amountController.text.isEmpty ||
        accountNameController.text.isEmpty ||
        selectedBank == null) {
      showSimpleDialog(
        'Please complete all fields and verify account',
        Colors.red,
      );
      return;
    }

    final amountNaira = double.parse(amountController.text);
    if (!await _checkBalance(amountNaira)) return; // ← guard BEFORE pin

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    if (mounted) setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return;
      }

      final userVaData =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      final userAccountId = userVaData?['id']?.toString() ?? '';
      final userAccountType = userVaData?['type']?.toString() ?? '';
      final userBankIdRaw = userVaData?['attributes']?['bank']?['id']
          ?.toString();
      final userBankName = userVaData?['attributes']?['bank']?['name']
          ?.toString();
      final userBankId =
          (await resolveBankId(
            bankId: userBankIdRaw,
            bankName: userBankName,
          )) ??
          '';

      if (userAccountId.isEmpty ||
          userAccountType.isEmpty ||
          userBankId.isEmpty) {
        showSimpleDialog('User account details not found', Colors.red);
        return;
      }

      // Use cached company VA
      final companyVa = _cachedCompanyVa ?? await getCompanyVirtualAccount();
      if (companyVa == null ||
          (companyVa['id'] as String).isEmpty ||
          (companyVa['type'] as String).isEmpty ||
          (companyVa['bankId'] as String).isEmpty ||
          (companyVa['accountNumber'] as String).isEmpty) {
        showSimpleDialog('Company account not found', Colors.red);
        return;
      }

      final recipientAccountNumber = accountNumberController.text;
      final recipientBankId = selectedBank;
      // FIXED:
      final recipientBank = banks.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['id'] == selectedBank,
        orElse: () => <String, dynamic>{
          'attributes': <String, dynamic>{'name': 'Unknown Bank'},
        },
      );
      final recipientBankName =
          recipientBank['attributes']['name'] as String? ?? 'Unknown Bank';
      final recipientAccountName = accountNameController.text;

      // Step 1: user → company (intra)
      final amountToCompanyKobo = (amountNaira + 50.0) * 100;
      final firstResult = await callCloudFunctionLogged(
        'safehavenTransferIntra',
        source: 'bank_transfer_page.dart',
        payload: {
          'fromAccountId': userAccountId,
          'toAccountId': companyVa['id'],
          'toBankCode': companyVa['bankId'],
          'amount': amountToCompanyKobo,
          'currency': 'NGN',
          'narration':
              'Ghost Mode: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}',
          'idempotencyKey': const Uuid().v4(),
        },
      );
      if (firstResult.data['data']['attributes']['status'] == 'FAILED') {
        showSimpleDialog(
          'Transfer to company failed: ${firstResult.data['data']['attributes']['failureReason']}',
          Colors.red,
        );
        return;
      }

      // Step 2: find/create recipient counterparty from company
      final queryRecipientCp = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('ownerAccountId', isEqualTo: companyVa['id'])
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();

      String recipientCounterpartyId;
      if (queryRecipientCp.docs.isNotEmpty) {
        recipientCounterpartyId = queryRecipientCp.docs.first.id;
      } else {
        final cpResult = await callCloudFunctionLogged(
          'safehavenCreateCounterparty',
          source: 'bank_transfer_page.dart',
          payload: {
            'bankId': recipientBankId,
            'accountType': 'BankAccount',
            'accountName': recipientAccountName,
            'bankName': recipientBankName,
            'accountNumber': recipientAccountNumber,
          },
        );
        recipientCounterpartyId = cpResult.data['data']['id'];
        await FirebaseFirestore.instance
            .collection('counterparties')
            .doc(recipientCounterpartyId)
            .set({
              ...cpResult.data,
              'userId': companyVa['uid'],
              'recipientAccountNumber': recipientAccountNumber,
              'recipientBankCode': recipientBankId,
              'ownerAccountId': companyVa['id'],
            });
      }

      // Step 3: company → recipient (NIP)
      final secondResult = await callCloudFunctionLogged(
        'safehavenTransferNip',
        source: 'bank_transfer_page.dart',
        payload: {
          'accountType': companyVa['type'],
          'accountId': companyVa['id'],
          'debitAccountId': companyVa['id'],
          'debitAccountType': companyVa['type'],
          'counterpartyId': recipientCounterpartyId,
          'amount': amountNaira * 100,
          'currency': 'NGN',
          'narration': remarkController.text.isNotEmpty
              ? remarkController.text
              : 'Ghost Mode Transfer',
          'idempotencyKey': const Uuid().v4(),
        },
      );

      if (secondResult.data['data']['attributes']['status'] == 'FAILED') {
        showSimpleDialog(
          'Transfer to recipient failed: ${secondResult.data['data']['attributes']['failureReason']}',
          Colors.red,
        );
        return;
      }

      // await FirebaseFirestore.instance.collection('transactions').add({
      //   'actualSender': user.uid,
      //   'userId': user.uid,
      //   'type': 'ghost_transfer',
      //   'bank_code': recipientBankId,
      //   'account_number': recipientAccountNumber,
      //   'amount': amountNaira,
      //   'reason': remarkController.text,
      //   'currency': 'NGN',
      //   'api_response': secondResult.data,
      //   'reference': secondResult.data['data']['id'],
      //   'recipientName': recipientAccountName,
      //   'bankName': recipientBankName,
      //   'timestamp': FieldValue.serverTimestamp(),
      // });

      _showSuccess(
        secondResult.data,
        recipientBankName,
        recipientName: recipientAccountName,
        bankCode: recipientBankId ?? '',
        accountNumber: recipientAccountNumber,
      );
    } catch (e) {
      debugPrint('ghostTransfer error: $e');
      if (mounted)
        showSimpleDialog('Error processing ghost transfer', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Shared helpers ───────────────────────────────────────────────────────

  Future<void> _logTransaction(
    User user,
    Map data,
    String bankName,
    double amount,
    String type,
  ) async {
    await FirebaseFirestore.instance.collection('transactions').add({
      'userId': user.uid,
      'type': type,
      'bank_code': selectedBank,
      'account_number': accountNumberController.text,
      'amount': amount,
      'reason': remarkController.text,
      'currency': 'NGN',
      'api_response': data,
      'reference': data['data']['id'],
      'recipientName': accountNameController.text,
      'bankName': bankName,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _showSuccess(
    Map data,
    String bankName, {
    String? recipientName,
    String? bankCode,
    String? accountNumber,
  }) {
    final ref = data['data']['id'] ?? '';
    print("📱 PaymentSuccessfulPage: Using reference = $ref");
    showModalBottomSheet(
      context: context,
      builder: (context) => PaymentSuccessfulPage(
        amount: amountController.text,
        actionText: 'Done',
        title: 'Payment Successful',
        description: 'Your transfer has been processed successfully.',
        recipientName: recipientName ?? accountNameController.text,
        bankName: bankName,
        bankCode: bankCode ?? selectedBank ?? '',
        accountNumber: accountNumber ?? accountNumberController.text,
        reference: data['data']['id'] ?? '',
      ),
      isScrollControlled: true,
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    amountController.dispose();
    accountNumberController.dispose();
    remarkController.dispose();
    accountNameController.dispose();
    super.dispose();
  }

  // ── UI ───────────────────────────────────────────────────────────────────

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
                          child: const Icon(
                            Icons.arrow_back_ios,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Bank Transfer',
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

                    // ── PAGE 0: Account details ──────────────────────────
                    if (_currentPage == 0) ...[
                      const Text('Beneficiary Account Number'),
                      const SizedBox(height: 8),
                      TextField(
                        maxLength: 10,
                        controller: accountNumberController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [LengthLimitingTextInputFormatter(10)],
                        decoration: InputDecoration(
                          counterText: '',
                          hintStyle: GoogleFonts.inter(
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Account number',
                          suffixIcon: IconButton(
                            tooltip: 'Scan account details from photo',
                            icon: const Icon(Icons.camera_alt_outlined),
                            onPressed: _onScanAccountImage,
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length == 10) {
                            _autoLookupCounterparty(value);
                            if (selectedBank != null) _safehavenNameEnquiry();
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Beneficiary Bank'),
                      const SizedBox(height: 8),
                      isFetchingBanks
                          ? Center(
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            )
                          : DropdownSearch<String>(
                              popupProps: PopupProps.menu(
                                menuProps: const MenuProps(
                                  backgroundColor: Colors.white,
                                ),
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: 'Search bank...',
                                    hintStyle: GoogleFonts.inter(fontSize: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                showSearchBox: true,
                                fit: FlexFit.loose,
                                constraints: BoxConstraints(
                                  maxHeight: 300,
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.9,
                                ),
                                itemBuilder:
                                    (context, item, isDisabled, isSelected) =>
                                        ListTile(
                                          title: Text(
                                            item,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                              ),
                              items: (filter, _) async => banks
                                  .where(
                                    (b) => (b['attributes']['name'] as String)
                                        .toLowerCase()
                                        .contains(filter.toLowerCase()),
                                  )
                                  .map((b) => b['attributes']['name'] as String)
                                  .toList(),
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintText: 'Select Bank',
                                  hintStyle: GoogleFonts.inter(
                                    color: Colors.grey.shade600,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  final matched = banks
                                      .cast<Map<String, dynamic>>()
                                      .firstWhere(
                                        (b) => b['attributes']['name'] == value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                  selectedBank = matched['id'] as String?;

                                  if (accountNumberController.text.length ==
                                          10 &&
                                      selectedBank != null) {
                                    _safehavenNameEnquiry();
                                  }
                                });
                              },
                              selectedItem: selectedBank != null
                                  ? banks
                                            .cast<Map<String, dynamic>?>()
                                            .firstWhere(
                                              (b) => b?['id'] == selectedBank,
                                              orElse: () => null,
                                            )?['attributes']?['name']
                                        as String?
                                  : null,
                            ),
                      const SizedBox(height: 16),
                      if (isFetchingAccountName ||
                          accountNameController.text.isNotEmpty) ...[
                        const Text('Account Name'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: accountNameController,
                          enabled: false,
                          decoration: InputDecoration(
                            hintStyle: GoogleFonts.inter(
                              color: Colors.grey.shade600,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintText: 'Account name',
                            suffixIcon: isFetchingAccountName
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              primaryColor,
                                            ),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed:
                            accountNumberController.text.length == 10 &&
                                selectedBank != null &&
                                accountNameController.text.isNotEmpty
                            ? () => setState(() => _currentPage = 1)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Next',
                          style: GoogleFonts.inter(color: Colors.white),
                        ),
                      ),
                    ]
                    // ── PAGE 1: Amount & Remark ──────────────────────────
                    else if (_currentPage == 1) ...[
                      // NEW FIXED CODE - Paste this instead
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryColor.withValues(
                                alpha: 0.12,
                              ),
                              child: Text(
                                accountNameController.text
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .take(2)
                                    .map((s) => s[0].toUpperCase())
                                    .join(),
                                style: GoogleFonts.inter(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    accountNameController.text,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${accountNumberController.text} · ${_getBankName()}',
                                    style: GoogleFonts.inter(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '₦',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0.00',
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              feeText,
                              style: GoogleFonts.inter(
                                color: primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                        children: [500, 1000, 2000, 5000, 9999, 10000].map((
                          amt,
                        ) {
                          final fmtAmt = amt.toString().replaceAllMapped(
                            RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                            (m) => '${m[1]},',
                          );
                          return GestureDetector(
                            onTap: () => setState(
                              () => amountController.text = amt.toString(),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '₦$fmtAmt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
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
                          hintStyle: GoogleFonts.inter(
                            color: Colors.grey.shade600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Enter Remark',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ghost Mode',
                                style: GoogleFonts.inter(
                                  color: Colors.black26,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Send money anonymously',
                                style: GoogleFonts.inter(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
                            onToggle: (val) =>
                                setState(() => sendAnonymously = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed:
                            isLoading ||
                                (double.tryParse(amountController.text) ??
                                        0.0) <=
                                    0
                            ? null
                            : () async {
                                if (sendAnonymously) {
                                  await _ghostTransfer();
                                } else {
                                  await _createCounterparty();
                                  await _safehavenTransferNip();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                'Confirm',
                                style: GoogleFonts.inter(color: Colors.white),
                              ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Contacts & Recents (page 0 only) ────────────────────────
              if (_currentPage == 0) ...[
                if (_aliases.where((a) => a.type == 'account').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                              'Contacts',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _aliases
                                .where((a) => a.type == 'account')
                                .length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final contact = _aliases
                                  .where((a) => a.type == 'account')
                                  .toList()[index];
                              final displayLabel =
                                  contact.displayName?.isNotEmpty == true
                                  ? contact.displayName!
                                  : contact.accountNumber ?? '';
                              final initials = contact.alias
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .map((s) => s[0].toUpperCase())
                                  .join();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.orange.withValues(
                                    alpha: 0.15,
                                  ),
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  contact.alias,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (displayLabel.isNotEmpty) displayLabel,
                                    if (contact.bankName?.isNotEmpty == true)
                                      contact.bankName!,
                                  ].join(' · '),
                                  style: GoogleFonts.inter(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    accountNumberController.text =
                                        contact.accountNumber ?? '';
                                    if (contact.displayName?.isNotEmpty ==
                                        true) {
                                      accountNameController.text =
                                          contact.displayName!;
                                    }

                                    if (contact.bankName?.isNotEmpty == true) {
                                      final matched = banks
                                          .cast<Map<String, dynamic>>()
                                          .firstWhere(
                                            (b) =>
                                                (b['attributes']['name']
                                                            as String? ??
                                                        '')
                                                    .toLowerCase()
                                                    .contains(
                                                      contact.bankName!
                                                          .toLowerCase(),
                                                    ) ||
                                                (b['attributes']['name']
                                                                as String? ??
                                                            '')
                                                        .toLowerCase() ==
                                                    contact.bankName!
                                                        .toLowerCase(),
                                            orElse: () => <String, dynamic>{
                                              'attributes': <String, dynamic>{},
                                            },
                                          );
                                      if (matched.isNotEmpty &&
                                          matched['id'] != null) {
                                        selectedBank = matched['id'] as String?;
                                      }
                                    }

                                    _currentPage = 1;
                                  });

                                  // Auto verify name
                                  if (contact.accountNumber?.isNotEmpty ==
                                          true &&
                                      selectedBank != null) {
                                    Future.delayed(
                                      const Duration(milliseconds: 150),
                                      () {
                                        if (mounted) _safehavenNameEnquiry();
                                      },
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_loadingRecents)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_recentTransfers.isNotEmpty)
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
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentTransfers.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final r = _recentTransfers[index];
                              final name =
                                  r['recipientName']?.toString() ?? 'Unknown';
                              final acct =
                                  r['account_number']?.toString() ?? '';
                              final bank = r['bankName']?.toString() ?? '';
                              final alias = _aliases
                                  .where(
                                    (a) =>
                                        a.type == 'account' &&
                                        a.accountNumber == acct,
                                  )
                                  .firstOrNull;
                              final initials = name
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .map((s) => s[0].toUpperCase())
                                  .join();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: primaryColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  child: Text(
                                    initials,
                                    style: GoogleFonts.inter(
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (alias != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          '~${alias.alias}',
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '$acct · $bank',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  final bankCode = r['bank_code']?.toString();
                                  final bankNameFromRecent = r['bankName']
                                      ?.toString();

                                  setState(() {
                                    accountNumberController.text = acct;
                                    accountNameController.text = name;

                                    if (bankCode != null &&
                                        bankCode.isNotEmpty) {
                                      final matchedBank = banks
                                          .cast<Map<String, dynamic>>()
                                          .firstWhere(
                                            (b) => b['id'] == bankCode,
                                            orElse: () => <String, dynamic>{},
                                          );
                                      if (matchedBank.isNotEmpty &&
                                          matchedBank['id'] != null) {
                                        selectedBank = bankCode;
                                      } else if (bankNameFromRecent != null &&
                                          bankNameFromRecent.isNotEmpty) {
                                        final nameMatched = banks
                                            .cast<Map<String, dynamic>>()
                                            .firstWhere(
                                              (b) =>
                                                  (b['attributes']['name']
                                                              as String? ??
                                                          '')
                                                      .toLowerCase() ==
                                                  bankNameFromRecent
                                                      .toLowerCase(),
                                              orElse: () => <String, dynamic>{},
                                            );
                                        if (nameMatched.isNotEmpty) {
                                          selectedBank =
                                              nameMatched['id'] as String?;
                                        }
                                      }

                                      if (matchedBank.isNotEmpty &&
                                          matchedBank['id'] != null) {
                                        selectedBank = bankCode;
                                      } else if (bankNameFromRecent != null &&
                                          bankNameFromRecent.isNotEmpty) {
                                        final nameMatched = banks.firstWhere(
                                          (b) =>
                                              (b['attributes']['name']
                                                          as String? ??
                                                      '')
                                                  .toLowerCase() ==
                                              bankNameFromRecent.toLowerCase(),
                                          orElse: () => <String, dynamic>{
                                            'attributes': <String, dynamic>{},
                                          },
                                        );
                                        if (nameMatched.isNotEmpty) {
                                          selectedBank =
                                              nameMatched['id'] as String?;
                                        }
                                      }
                                    }

                                    _currentPage = 1; // Make sure this runs
                                  });

                                  // Small delay to ensure state is updated before calling name enquiry
                                  Future.delayed(
                                    const Duration(milliseconds: 100),
                                    () {
                                      if (acct.length == 10 &&
                                          selectedBank != null &&
                                          mounted) {
                                        _safehavenNameEnquiry();
                                      }
                                    },
                                  );
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
