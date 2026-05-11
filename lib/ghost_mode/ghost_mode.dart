import 'package:card_app/ui/account_image_scanner.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

class GhostModeTransfer extends StatefulWidget {
  const GhostModeTransfer({super.key});

  @override
  State<GhostModeTransfer> createState() => _GhostModeTransferState();
}

class _GhostModeTransferState extends State<GhostModeTransfer> {
  final TextEditingController amountController = TextEditingController();
  final TextEditingController accountNumberController = TextEditingController();
  final TextEditingController remarkController = TextEditingController();
  final TextEditingController accountNameController = TextEditingController();

  String? selectedBank;
  List<Map<String, dynamic>> banks = [];
  bool isLoading = false;
  bool isFetchingBanks = false;
  bool isFetchingAccountName = false;
  String feeText = "Fee: ₦50.00";
  int _currentPage = 0;

  // ── Cached user data ─────────────────────────────────────────────────────
  Map<String, dynamic>? _cachedUserDoc;
  double? _cachedBalance;
  bool _isFetchingBalance = false;
  Map<String, dynamic>? _cachedCompanyVa;
  String? _ownAccountNumber;

  @override
  void initState() {
    super.initState();
    amountController.addListener(_updateFee);
    _initAllParallel();
  }

  /// Load user doc, balance, company VA, and banks in parallel.
  Future<void> _initAllParallel() async {
    await Future.wait([
      _prefetchUserDoc(),
      _fetchBanks(),
      _prefetchCompanyVa(),
    ]);
  }

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
      _fetchAndCacheBalance();
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
      debugPrint('✅ Ghost mode balance pre-fetched: ₦$_cachedBalance');
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

  Future<void> _prefetchCompanyVa() async {
    _cachedCompanyVa = await getCompanyVirtualAccount();
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    // If already cached, return immediately
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

  void _updateFee() {
    final amount = double.tryParse(amountController.text) ?? 0.0;
    final fee = amount > 0 ? 50.0 : 0.0;
    setState(() {
      feeText = "Fee: ₦${fee.toStringAsFixed(2)}";
    });
  }

  Future<void> _onScanAccountImage() async {
    final result = await scanAccountFromImage(context);
    if (result == null) return;

    if (result.accountNumber != null && result.accountNumber!.isNotEmpty) {
      setState(() {
        accountNumberController.text = result.accountNumber!;
      });
    }

    if (result.bankName != null &&
        result.bankName!.isNotEmpty &&
        banks.isNotEmpty) {
      final bankNameLower = result.bankName!.toLowerCase();
      final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
        (b) =>
            (b!['attributes']['name'] as String).toLowerCase().contains(
              bankNameLower,
            ) ||
            bankNameLower.contains(
              (b['attributes']['name'] as String).toLowerCase(),
            ),
        orElse: () => null,
      );
      if (matched != null) {
        setState(() => selectedBank = matched['id'] as String);
      }
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
        final result = await FirebaseFunctions.instance
            .httpsCallable('safehavenBankList')
            .call();
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
      if (mounted) showSimpleDialog('Error fetching banks', Colors.red);
      if (mounted) setState(() => isFetchingBanks = false);
    }
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
      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenNameEnquiry')
          .call({
            'accountNumber': accountNumberController.text,
            'bankIdOrBankCode': selectedBank,
          });
      final accountName = result.data['data']['attributes']['accountName'];
      if (mounted) setState(() => accountNameController.text = accountName);
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
          // Try to resolve bankId from banks collection
          final bankQuery = await FirebaseFirestore.instance
              .collection('banks')
              .where('name', isEqualTo: bankName)
              .limit(1)
              .get();
          if (bankQuery.docs.isNotEmpty) {
            bankId = bankQuery.docs.first.id;
          } else if (banks.isNotEmpty) {
            final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
              (b) =>
                  (b!['attributes']['name'] as String).toLowerCase() ==
                  bankName.toLowerCase(),
              orElse: () => null,
            );
            if (matched != null) bankId = matched['id'] as String;
          }
        }

        if (bankId != null && accountName != null && mounted) {
          setState(() {
            selectedBank = bankId;
            accountNameController.text = accountName;
            isFetchingAccountName = false;
          });
          _safehavenNameEnquiry();
          return;
        }
      }
    } catch (e) {
      debugPrint('_autoLookupCounterparty error: $e');
    }
    if (mounted) setState(() => isFetchingAccountName = false);
  }

  // ── Main Transfer Logic (uses cached data) ──────────────────────────────

  Future<void> _safehavenTransferNip() async {
    final accountName = accountNameController.text;
    final selectedBankValue = selectedBank;
    final amountText = amountController.text;
    if (accountName.isEmpty ||
        selectedBankValue == null ||
        amountText.isEmpty) {
      showSimpleDialog('Please complete and verify all fields', Colors.red);
      return;
    }
    final amountNaira = double.tryParse(amountText);
    if (amountNaira == null || amountNaira <= 0) {
      showSimpleDialog('Please enter a valid amount', Colors.red);
      return;
    }

    // Check balance using cached balance
    if (!await _checkBalance(amountNaira)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSimpleDialog('No authenticated user found', Colors.red);
      return;
    }

    // Verify PIN
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    if (mounted) setState(() => isLoading = true);

    String? firstTransferId;
    bool firstTransferCompleted = false;

    try {
      // Use cached user data
      final userVaData =
          _cachedUserDoc?['safehavenData']?['virtualAccount']?['data'];
      if (userVaData == null) throw Exception('User account not found');

      final userAccountId = userVaData['id']?.toString() ?? '';
      final userAccountType = userVaData['type']?.toString() ?? '';
      final userBankIdRaw = userVaData['attributes']?['bank']?['id']
          ?.toString();
      final userBankName = userVaData['attributes']?['bank']?['name']
          ?.toString();
      final userBankId =
          await resolveBankId(bankId: userBankIdRaw, bankName: userBankName) ??
          '';

      if (userAccountId.isEmpty ||
          userAccountType.isEmpty ||
          userBankId.isEmpty) {
        throw Exception('User account details incomplete');
      }

      // Use cached company VA
      final companyVa = _cachedCompanyVa ?? await getCompanyVirtualAccount();
      if (companyVa == null ||
          (companyVa['id'] as String).isEmpty ||
          (companyVa['accountNumber'] as String).isEmpty) {
        throw Exception('Company account not found');
      }

      final recipientAccountNumber = accountNumberController.text;
      final recipientBank = banks.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['id'] == selectedBank,
        orElse: () => <String, dynamic>{
          'attributes': <String, dynamic>{'name': 'Unknown'},
        },
      );
      final recipientBankId = recipientBank['id'] as String;
      final recipientBankName = recipientBank['attributes']['name'] as String;

      final isRecipientSafeHaven =
          recipientBankId == '090286' ||
          recipientBankName.toLowerCase().contains('safe haven');

      // Step 1: user → company (intra)
      final fee = 50.0;
      final amountToCompanyKobo = (amountNaira + fee) * 100;
      final narration1 =
          'Ghost Mode to Company: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}';
      final firstResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': userAccountId,
            'toAccountId': companyVa['id'],
            'amount': amountToCompanyKobo,
            'currency': 'NGN',
            'narration': narration1,
            'idempotencyKey': const Uuid().v4(),
          });

      firstTransferId = firstResult.data['data']['id'];
      final firstStatus = firstResult.data['data']['attributes']['status'];
      final firstFailureReason =
          firstResult.data['data']['attributes']['failureReason'];
      if (firstStatus == 'FAILED') {
        throw Exception('Transfer to company failed: $firstFailureReason');
      }
      firstTransferCompleted = true;

      // Step 2: company → recipient
      final amountToRecipientKobo = amountNaira * 100;
      final narration2 = remarkController.text.isNotEmpty
          ? remarkController.text
          : 'Ghost Mode Transfer';
      dynamic secondResult;

      if (isRecipientSafeHaven) {
        // Intra-bank transfer (find recipient's Safe Haven account ID)
        final recipientUserQuery = await FirebaseFirestore.instance
            .collection('users')
            .where(
              'safehavenData.virtualAccount.data.attributes.accountNumber',
              isEqualTo: recipientAccountNumber,
            )
            .limit(1)
            .get();

        String? recipientSafeHavenAccountId;
        if (recipientUserQuery.docs.isNotEmpty) {
          recipientSafeHavenAccountId = recipientUserQuery.docs.first
              .data()['safehavenData']?['virtualAccount']?['data']?['id']
              ?.toString();
        }

        if (recipientSafeHavenAccountId == null) {
          await _refundUser(
            userAccountId,
            companyVa['id'],
            amountToCompanyKobo,
            firstTransferId!,
          );
          throw Exception(
            'Could not find recipient Safe Haven account. Funds refunded.',
          );
        }

        secondResult = await FirebaseFunctions.instance
            .httpsCallable('safehavenTransferIntra')
            .call({
              'fromAccountId': companyVa['id'],
              'toAccountId': recipientSafeHavenAccountId,
              'amount': amountToRecipientKobo,
              'currency': 'NGN',
              'narration': narration2,
              'idempotencyKey': const Uuid().v4(),
            });
      } else {
        // Inter-bank NIP transfer: create counterparty from company
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
          final createCpResult = await FirebaseFunctions.instance
              .httpsCallable('safehavenCreateCounterparty')
              .call({
                'accountId': companyVa['id'],
                'bankId': recipientBankId,
                'accountType': companyVa['type'],
                'accountName': accountName,
                'bankName': recipientBankName,
                'accountNumber': recipientAccountNumber,
                'bankCode': recipientBankId,
              });
          recipientCounterpartyId = createCpResult.data['data']['id'];
          await FirebaseFirestore.instance
              .collection('counterparties')
              .doc(recipientCounterpartyId)
              .set({
                ...createCpResult.data,
                'userId': companyVa['uid'],
                'recipientAccountNumber': recipientAccountNumber,
                'recipientBankCode': recipientBankId,
                'ownerAccountId': companyVa['id'],
              });
        }

        secondResult = await FirebaseFunctions.instance
            .httpsCallable('safehavenTransferNip')
            .call({
              'accountType': companyVa['type'],
              'accountId': companyVa['id'],
              'debitAccountId': companyVa['id'],
              'debitAccountType': companyVa['type'],
              'counterpartyId': recipientCounterpartyId,
              'amount': amountToRecipientKobo,
              'currency': 'NGN',
              'narration': narration2,
              'idempotencyKey': const Uuid().v4(),
            });
      }

      final secondStatus = secondResult.data['data']['attributes']['status'];
      final secondFailureReason =
          secondResult.data['data']['attributes']['failureReason'];
      if (secondStatus == 'FAILED') {
        await _refundUser(
          userAccountId,
          companyVa['id'],
          amountToCompanyKobo,
          firstTransferId!,
        );
        throw Exception(
          'Transfer to recipient failed: $secondFailureReason. Funds refunded.',
        );
      }

      // Log transaction
      await FirebaseFirestore.instance.collection('transactions').add({
        'actualSender': user.uid,
        'userId': 'company',
        'type': 'ghost_transfer',
        'bank_code': selectedBank,
        'account_number': accountNumberController.text,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': secondResult.data,
        'reference': secondResult.data['data']['id'],
        'recipientName': accountName,
        'bankName': recipientBankName,
        'firstTransferId': firstTransferId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Clear form and go back to first page
      amountController.clear();
      accountNumberController.clear();
      remarkController.clear();
      accountNameController.clear();
      setState(() {
        _currentPage = 0;
        selectedBank = null;
      });

      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (context) => const SuccessBottomSheet(
            actionText: "Done",
            title: "Transfer Successful",
            description: "Your transfer has been processed successfully.",
          ),
          isScrollControlled: true,
        );
      }
    } catch (e) {
      debugPrint('Ghost mode transfer error: $e');
      if (mounted) {
        showSimpleDialog(e.toString(), Colors.red);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _refundUser(
    String userAccountId,
    String companyAccountId,
    double amountKobo,
    String originalTransferId,
  ) async {
    debugPrint('Refunding user $userAccountId amount $amountKobo kobo');
    final refundResult = await FirebaseFunctions.instance
        .httpsCallable('safehavenTransferIntra')
        .call({
          'fromAccountId': companyAccountId,
          'toAccountId': userAccountId,
          'amount': amountKobo,
          'currency': 'NGN',
          'narration':
              'REFUND: Ghost mode transfer failed (Original: $originalTransferId)',
          'idempotencyKey': const Uuid().v4(),
        });

    final refundStatus = refundResult.data['data']['attributes']['status'];
    if (refundStatus == 'FAILED') {
      throw Exception(
        'Refund failed: ${refundResult.data['data']['attributes']['failureReason']}',
      );
    }

    await FirebaseFirestore.instance.collection('transactions').add({
      'type': 'ghost_mode_refund',
      'userId': 'company',
      'recipientId': userAccountId,
      'amount': amountKobo / 100,
      'originalTransferId': originalTransferId,
      'reason': 'Automatic refund for failed ghost mode transfer',
      'currency': 'NGN',
      'api_response': refundResult.data,
      'reference': refundResult.data['data']['id'],
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    amountController.removeListener(_updateFee);
    amountController.dispose();
    accountNumberController.dispose();
    remarkController.dispose();
    accountNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(
        255,
        67,
        66,
        66,
      ).withValues(alpha: 0.2),
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            SizedBox.expand(child: Image.asset("assets/mdi_anonymous.png")),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_currentPage == 0) {
                              Navigator.of(context).pop();
                            } else {
                              setState(() => _currentPage = 0);
                            }
                          },
                          child: const Icon(
                            Icons.arrow_back_ios,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "Ghost Mode",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                            "Your account details will be kept confidential and not shared with the recipient.",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // PAGE 0: Account details
                    if (_currentPage == 0) ...[
                      Text(
                        'Beneficiary Account Number',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        maxLength: 10,
                        controller: accountNumberController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [LengthLimitingTextInputFormatter(10)],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                        decoration: InputDecoration(
                          counterText: "",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Account number',
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w100,
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Scan account details from photo',
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white70,
                            ),
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
                      Text(
                        'Beneficiary Bank',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      const SizedBox(height: 8),
                      isFetchingBanks
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : DropdownSearch<String>(
                              popupProps: PopupProps.menu(
                                menuProps: const MenuProps(
                                  backgroundColor: Color.fromARGB(
                                    255,
                                    67,
                                    66,
                                    66,
                                  ),
                                ),
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: "Search bank...",
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: Colors.white54,
                                    ),
                                    border: const OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(8),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                                showSearchBox: true,
                                fit: FlexFit.loose,
                                constraints: const BoxConstraints(
                                  maxHeight: 300,
                                ),
                                itemBuilder:
                                    (context, item, isDisabled, isSelected) {
                                      return ListTile(
                                        title: Text(
                                          item,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                              items: (filter, _) async => banks
                                  .where(
                                    (bank) =>
                                        ((bank['attributes'] as Map?)?['name']
                                                    as String? ??
                                                '')
                                            .toLowerCase()
                                            .contains(filter.toLowerCase()),
                                  )
                                  .map(
                                    (bank) =>
                                        (bank['attributes'] as Map?)?['name']
                                            as String? ??
                                        '',
                                  )
                                  .toList(),
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintStyle: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w100,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              dropdownBuilder: (context, selectedItem) => Text(
                                selectedItem ?? "Select Bank",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  selectedBank =
                                      banks
                                              .cast<Map<String, dynamic>>()
                                              .firstWhere(
                                                (b) =>
                                                    (b['attributes']['name']
                                                        as String) ==
                                                    value,
                                                orElse: () =>
                                                    <String, dynamic>{},
                                              )['id']
                                          as String?;
                                  if (accountNumberController.text.length ==
                                      10) {
                                    _safehavenNameEnquiry();
                                  }
                                });
                              },
                              selectedItem: selectedBank != null
                                  ? banks
                                            .cast<Map<String, dynamic>>()
                                            .firstWhere(
                                              (b) => b['id'] == selectedBank,
                                              orElse: () => <String, dynamic>{
                                                'attributes': <String, dynamic>{
                                                  'name': '',
                                                },
                                              },
                                            )['attributes']['name']
                                        as String?
                                  : null,
                            ),
                      const SizedBox(height: 16),
                      Text(
                        'Account Name',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: accountNameController,
                        enabled: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                        decoration: InputDecoration(
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w100,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Account name',
                          suffixIcon: isFetchingAccountName
                              ? Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed:
                            accountNumberController.text.length == 10 &&
                                selectedBank != null &&
                                accountNameController.text.isNotEmpty
                            ? () => setState(() => _currentPage = 1)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Next',
                          style: GoogleFonts.inter(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ]
                    // PAGE 1: Amount & Remark
                    else if (_currentPage == 1) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white30,
                              child: Text(
                                accountNameController.text
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .take(2)
                                    .map((s) => s[0].toUpperCase())
                                    .join(),
                                style: const TextStyle(
                                  color: Colors.white,
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
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '${accountNumberController.text} · ${_getBankName()}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
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
                      Text(
                        'Amount to Send',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '₦',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: amountController,
                                keyboardType: TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w100,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: '0.00',
                                  hintStyle: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                            Text(
                              feeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Remark',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: remarkController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w100,
                        ),
                        decoration: InputDecoration(
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w100,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Enter Remark',
                        ),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed:
                            isLoading ||
                                (double.tryParse(amountController.text) ??
                                        0.0) <=
                                    0
                            ? null
                            : () async {
                                await _safehavenTransferNip();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
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
                                style: GoogleFonts.inter(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getBankName() {
    if (selectedBank == null || banks.isEmpty) return 'Unknown Bank';
    final bank = banks.cast<Map<String, dynamic>>().firstWhere(
      (b) => b['id'] == selectedBank,
      orElse: () => <String, dynamic>{
        'attributes': <String, dynamic>{'name': 'Unknown Bank'},
      },
    );
    return (bank['attributes']['name'] as String?) ?? 'Unknown Bank';
  }
}
