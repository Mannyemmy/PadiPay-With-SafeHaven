import 'package:card_app/ui/account_image_scanner.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchBanks();
    amountController.addListener(_updateFee);
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
    setState(() => isFetchingBanks = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banks')
          .get();
      List<Map<String, dynamic>> bankList = [];
      for (var doc in snapshot.docs) {
        bankList.add({
          'id': doc.id,
          'attributes': {'name': doc.data()['name']},
        });
      }
      if (bankList.isEmpty) {
        final result = await FirebaseFunctions.instance
            .httpsCallable('safehavenBankList')
            .call();
        final data = result.data as Map<String, dynamic>;
        final apiBankList = data['data'] as List<dynamic>;
        final batch = FirebaseFirestore.instance.batch();
        for (var item in apiBankList) {
          final map = item as Map;
          final docRef = FirebaseFirestore.instance
              .collection('banks')
              .doc(map['id'].toString());
          batch.set(docRef, {
            'name': (map['attributes'] as Map)['name']?.toString(),
          });
        }
        await batch.commit();
        // Reload from Firestore after saving
        final newSnapshot = await FirebaseFirestore.instance
            .collection('banks')
            .get();
        for (var doc in newSnapshot.docs) {
          bankList.add({
            'id': doc.id,
            'attributes': {'name': doc.data()['name']},
          });
        }
      }
      setState(() {
        banks = bankList;
        isFetchingBanks = false;
      });
    } catch (e) {
      debugPrint('safehavenBankList error: $e');
      showSimpleDialog('Error fetching banks', Colors.red);
      setState(() => isFetchingBanks = false);
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
      setState(() {
        accountNameController.text = doc.data()!['accountName'];
      });
      return;
    }

    setState(() => isLoading = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('safehavenNameEnquiry')
          .call({
            'accountNumber': accountNumberController.text,
            'bankIdOrBankCode': selectedBank,
          });
      final accountName = result.data['data']['attributes']['accountName'];
      setState(() {
        accountNameController.text = accountName;
      });
      await FirebaseFirestore.instance
          .collection('verified_accounts')
          .doc(docId)
          .set({
            'accountName': accountName,
            'verifiedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('safehavenNameEnquiry error: $e');
      showSimpleDialog('Error verifying account', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<void> _autoLookupCounterparty(String accountNumber) async {
    debugPrint('ðŸ” _autoLookupCounterparty called with: $accountNumber');
    if (accountNumber.length != 10) {
      debugPrint(' Account number length is ${accountNumber.length}, not 10');
      return;
    }
    setState(() => isFetchingAccountName = true);
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('recipientAccountNumber', isEqualTo: accountNumber)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        debugPrint('ðŸ“‹ Document data: $data');

        String? bankId = data['recipientBankCode'] as String?;
        final accountName =
            data['data']?['attributes']?['accountName'] as String? ??
            data['attributes']?['accountName'] as String? ??
            data['accountName'] as String?;
        final bankName =
            data['bankName'] as String? ??
            data['data']?['attributes']?['bank']?['name'] as String?;

        debugPrint('ðŸ¦ Initial bankId: $bankId');
        debugPrint('ðŸ·ï¸ bankName: $bankName');
        debugPrint('ðŸ‘¤ Found accountName: $accountName');

        if (bankId == null && bankName != null) {
          debugPrint(
            'ðŸ” bankId missing, trying banks collection lookup by bankName: $bankName',
          );
          try {
            final bankQuery = await FirebaseFirestore.instance
                .collection('banks')
                .where('name', isEqualTo: bankName)
                .limit(1)
                .get();
            if (bankQuery.docs.isNotEmpty) {
              bankId = bankQuery.docs.first.id;
              debugPrint('ðŸ” Found bankId by name (equal): $bankId');
            } else if (banks.isNotEmpty) {
              // Use already-loaded banks list instead of reading entire collection again
              final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
                (b) =>
                    (b!['attributes']['name'] as String).toLowerCase() ==
                    bankName.toLowerCase(),
                orElse: () => null,
              );
              if (matched != null) {
                bankId = matched['id'] as String;
                debugPrint('ðŸ” Found bankId by cached banks match: $bankId');
              }
            }
          } catch (e) {
            debugPrint('bank lookup by name error: $e');
          }
        }

        if (bankId != null && accountName != null) {
          setState(() {
            selectedBank = bankId;
            accountNameController.text = accountName;
            isFetchingAccountName = false;
          });
          // Also verify via remote if bank is available
          _safehavenNameEnquiry();
          return;
        } else {
          debugPrint(
            'âš ï¸ bankId or accountName is null. bankId=$bankId, accountName=$accountName',
          );
        }
      } else {
        debugPrint(
          ' No documents found for recipientAccountNumber: $accountNumber',
        );
      }
    } catch (e) {
      debugPrint('ðŸ’¥ _autoLookupCounterparty error: $e');
    }
    setState(() => isFetchingAccountName = false);
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('company')
          .doc('account_details')
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      return {
        'uid': doc.id,
        'id': data['accountId']?.toString() ?? '',
        'type': data['accountType']?.toString() ?? '',
        'bankId': data['bankId']?.toString() ?? '',
        'bankName': data['bankName']?.toString() ?? '',
        'accountNumber': data['accountNumber']?.toString() ?? '',
        'accountName': data['accountName']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('getCompanyVirtualAccount error: $e');
      return null;
    }
  }



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

  // Verify PIN before proceeding
  final pinVerified = await verifyTransactionPin();
  if (!pinVerified) {
    return;
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    showSimpleDialog('No authenticated user found', Colors.red);
    return;
  }

  setState(() => isLoading = true);
  
  String? firstTransferId;
  bool firstTransferCompleted = false;
  
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userVaData = userDoc
        .data()?['safehavenData']?['virtualAccount']?['data'];
    if (userVaData == null) {
      showSimpleDialog('User account not found', Colors.red);
      return;
    }
    final userAccountId = userVaData['id']?.toString() ?? '';
    final userAccountType = userVaData['type']?.toString() ?? '';
    final userBankIdRaw = userVaData['attributes']?['bank']?['id']
        ?.toString();
    final userBankName = userVaData['attributes']?['bank']?['name']
        ?.toString();
    final userBankId =
        (await resolveBankId(
          bankId: userBankIdRaw,
          bankName: userBankName,
        )) ??
        '';

    // Check user balance first
    final balanceResult = await FirebaseFunctions.instance
        .httpsCallable('safehavenFetchAccountBalance')
        .call({'accountId': userAccountId});
    final userBalanceKobo = balanceResult.data['data']['availableBalance']?.toDouble() ?? 0.0;
    final fee = 50.0;
    final totalRequiredKobo = (amountNaira + fee) * 100;
    
    if (userBalanceKobo < totalRequiredKobo) {
      showSimpleDialog(
        'Insufficient balance. Your balance is ₦${(userBalanceKobo / 100).toStringAsFixed(2)}. Required: ₦${(totalRequiredKobo / 100).toStringAsFixed(2)}',
        Colors.red,
      );
      setState(() => isLoading = false);
      return;
    }

    // Fetch company account details directly from SafeHaven API via Cloud Function
    final companyResult = await FirebaseFunctions.instance
        .httpsCallable('fetchCompanySafehavenAccounts')
        .call({'isSubAccount': false, 'page': 0, 'limit': 100});

    final companyData = companyResult.data;
    final companyAccount = companyData['companyAccount'];

    if (companyAccount == null ||
        companyAccount['id'] == null ||
        companyAccount['accountNumber'] == null) {
      showSimpleDialog(
        'Company account not found. Please try again.',
        Colors.red,
      );
      setState(() => isLoading = false);
      return;
    }

    final companyVa = {
      'id': companyAccount['id'],
      'accountNumber': companyAccount['accountNumber'],
      'accountName': companyAccount['accountName'] ?? 'PadiPay Limited',
      'type': companyAccount['accountType'] ?? 'BankAccount',
      'bankId': '090286',
      'bankName': 'SAFE HAVEN MICROFINANCE BANK',
      'uid': 'company',
    };

    final recipientAccountNumber = accountNumberController.text;
    final recipientBank = banks.firstWhere((b) => b['id'] == selectedBank);
    final recipientBankId = recipientBank['id'];
    final recipientBankName = recipientBank['attributes']['name'];
    
    // Check if recipient bank is Safe Haven MFB (code 090286)
    final isRecipientSafeHaven = recipientBankId == '090286' || 
                                   recipientBankId == '999240' ||
                                   recipientBankName.toLowerCase().contains('safe haven');

    // First transfer: user to company (book transfer)
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
    final firstFailureReason = firstResult.data['data']['attributes']['failureReason'];
    
    if (firstStatus == "FAILED") {
      showSimpleDialog(
        'Transfer to company failed: $firstFailureReason',
        Colors.red,
      );
      return;
    }
    
    firstTransferCompleted = true;

    final amountToRecipientKobo = amountNaira * 100;
    final narration2 = remarkController.text.isNotEmpty
        ? remarkController.text
        : 'Ghost Mode Transfer';
    
    dynamic secondResult;
    
    if (isRecipientSafeHaven) {
      // Intra-bank transfer (same Safe Haven MFB)
      print('Using intra-bank transfer to Safe Haven account: $recipientAccountNumber');
      
      // For intra-bank, we need the recipient's Safe Haven account ID
      final recipientUserQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('safehavenData.virtualAccount.data.attributes.accountNumber', isEqualTo: recipientAccountNumber)
          .limit(1)
          .get();
      
      String? recipientSafeHavenAccountId;
      if (recipientUserQuery.docs.isNotEmpty) {
        recipientSafeHavenAccountId = recipientUserQuery.docs.first
            .data()['safehavenData']?['virtualAccount']?['data']?['id']?.toString();
      }
      
      if (recipientSafeHavenAccountId == null) {
        // Refund user since we can't complete the transfer
        await _refundUser(userAccountId, companyVa['id'], amountToCompanyKobo, firstTransferId!);
        showSimpleDialog(
          'Could not find recipient\'s Safe Haven account ID. Your funds have been refunded.',
          Colors.red,
        );
        return;
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
      // Inter-bank NIP transfer
      print('Using NIP transfer to external bank: $recipientBankName');
      
      // Check/create counterparty for recipient (from company)
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
        final createRecipientCpResult = await FirebaseFunctions.instance
            .httpsCallable('safehavenCreateCounterparty')
            .call({
              'accountId': companyVa['id'],
              'bankId': recipientBankId,
              'accountType': companyVa['type'],
              'accountName': accountName,
              'bankName': recipientBankName,
              'accountNumber': accountNumberController.text,
              'bankCode': selectedBank,
            });
        recipientCounterpartyId = createRecipientCpResult.data['data']['id'];
        await FirebaseFirestore.instance
            .collection('counterparties')
            .doc(recipientCounterpartyId)
            .set({
              ...createRecipientCpResult.data,
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
            'counterpartyId': recipientCounterpartyId,
            'amount': amountToRecipientKobo,
            'currency': 'NGN',
            'narration': narration2,
            'idempotencyKey': const Uuid().v4(),
          });
    }
    
    final secondStatus = secondResult.data['data']['attributes']['status'];
    final secondFailureReason = secondResult.data['data']['attributes']['failureReason'];
    
    if (secondStatus == "FAILED") {
      // Second transfer failed - refund the user
      await _refundUser(userAccountId, companyVa['id'], amountToCompanyKobo, firstTransferId!);
      showSimpleDialog(
        'Transfer to recipient failed: $secondFailureReason. Your funds have been refunded.',
        Colors.red,
      );
      return;
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

    // Clear form after successful transfer
    amountController.clear();
    accountNumberController.clear();
    remarkController.clear();
    accountNameController.clear();
    setState(() {
      _currentPage = 0;
      selectedBank = null;
    });

    showModalBottomSheet(
      context: context,
      builder: (context) => const SuccessBottomSheet(
        actionText: "Done",
        title: "Transfer Successful",
        description: "Your transfer has been processed successfully.",
      ),
      isScrollControlled: true,
    );
  } catch (e) {
    print('safehavenTransferNip error: $e');
    
    // If first transfer completed but something else failed, attempt refund
    if (firstTransferCompleted) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();
        final userVaData = userDoc.data()?['safehavenData']?['virtualAccount']?['data'];
        final userAccountId = userVaData?['id']?.toString() ?? '';
        
        final companyResult = await FirebaseFunctions.instance
            .httpsCallable('fetchCompanySafehavenAccounts')
            .call({'isSubAccount': false, 'page': 0, 'limit': 100});
        final companyAccount = companyResult.data['companyAccount'];
        final companyId = companyAccount?['id'];
        
        if (userAccountId.isNotEmpty && companyId != null) {
          await _refundUser(userAccountId, companyId, (amountNaira + 50) * 100, firstTransferId!);
          showSimpleDialog(
            'An error occurred but your funds have been refunded: ${e.toString()}',
            Colors.red,
          );
        } else {
          showSimpleDialog('Error processing transfer: ${e.toString()}', Colors.red);
        }
      } catch (refundErr) {
        print('Refund error: $refundErr');
        showSimpleDialog(
          'CRITICAL: Transfer failed and automatic refund failed. Please contact support immediately. Error: ${e.toString()}',
          Colors.red,
        );
      }
    } else {
      showSimpleDialog('Error processing transfer: ${e.toString()}', Colors.red);
    }
  } finally {
    setState(() => isLoading = false);
  }
}

// Helper method to refund user from company
Future<void> _refundUser(String userAccountId, String companyAccountId, double amountKobo, String originalTransferId) async {
  print('Initiating refund: user=$userAccountId, amount=$amountKobo kobo, originalTransfer=$originalTransferId');
  
  final refundResult = await FirebaseFunctions.instance
      .httpsCallable('safehavenTransferIntra')
      .call({
        'fromAccountId': companyAccountId,
        'toAccountId': userAccountId,
        'amount': amountKobo,
        'currency': 'NGN',
        'narration': 'REFUND: Ghost mode transfer failed (Original: $originalTransferId)',
        'idempotencyKey': const Uuid().v4(),
      });
  
  final refundStatus = refundResult.data['data']['attributes']['status'];
  if (refundStatus == "FAILED") {
    throw Exception('Refund transfer failed: ${refundResult.data['data']['attributes']['failureReason']}');
  }
  
  // Log the refund transaction
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
  
  print('Refund successful: $refundResult');
} @override
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
                        const Text(
                          "Ghost Mode",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w300,
                            ),
                            "Your account details will be kept confidential and not shared with the recipient.",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    // PAGE 1: Account details
                    if (_currentPage == 0) ...[
                      const Text(
                        'Beneficiary Account Number',
                        style: TextStyle(
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
                            if (selectedBank != null) {
                              _safehavenNameEnquiry();
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Beneficiary Bank',
                        style: TextStyle(
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
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white54,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(8),
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  style: TextStyle(color: Colors.white),
                                ),
                                showSearchBox: true,
                                fit: FlexFit.loose,
                                constraints: BoxConstraints(maxHeight: 300),
                                itemBuilder:
                                    (context, item, isDisabled, isSelected) {
                                      return ListTile(
                                        title: Text(
                                          item,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                              items: (filter, _) async {
                                return banks
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
                                    .toList();
                              },
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w100,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              dropdownBuilder: (context, selectedItem) {
                                return Text(
                                  selectedItem ?? "Select Bank",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                );
                              },
                              onChanged: (value) {
                                setState(() {
                                  selectedBank =
                                      banks.firstWhere(
                                            (b) =>
                                                ((b['attributes']
                                                        as Map?)?['name']
                                                    as String?) ==
                                                value,
                                          )['id']
                                          as String?;
                                  if (accountNumberController.text.length ==
                                      10) {
                                    _safehavenNameEnquiry();
                                  }
                                });
                              },
                              selectedItem: selectedBank != null
                                  ? ((banks.firstWhere(
                                              (b) => b['id'] == selectedBank,
                                              orElse: () => <String, dynamic>{
                                                'attributes': <String, dynamic>{
                                                  'name': '',
                                                },
                                              },
                                            )['attributes']
                                            as Map?)?['name']
                                        as String?)
                                  : null,
                            ),
                      const SizedBox(height: 16),
                      const Text(
                        'Account Name',
                        style: TextStyle(
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
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
                        child: const Text(
                          'Next',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ]
                    // PAGE 2: Amount & Remark
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
                                    '${accountNumberController.text} Â· ${banks.firstWhere((b) => b['id'] == selectedBank, orElse: () => {
                                      'attributes': {'name': 'Unknown'},
                                    })['attributes']['name']}',
                                    style: TextStyle(
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
                      const Text(
                        'Amount to Send',
                        style: TextStyle(
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
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
                      const Text(
                        'Remark',
                        style: TextStyle(
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
                            : const Text(
                                'Confirm',
                                style: TextStyle(
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
}
