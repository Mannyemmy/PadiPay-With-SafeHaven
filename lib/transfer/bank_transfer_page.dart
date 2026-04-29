import 'package:card_app/my_padi/padi_aliases_page.dart';
import 'package:card_app/ui/account_image_scanner.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  int _currentPage = 0; // 0: account details, 1: amount & remark

  @override
  void initState() {
    super.initState();
    if (widget.initialAccountNumber != null) {
      accountNumberController.text = widget.initialAccountNumber!;
    }
    if (widget.initialAmount != null) {
      amountController.text = widget.initialAmount!;
    }
    _fetchBanks();
    amountController.addListener(_updateFee);
    _loadRecentTransfers();
    _loadAliases();
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
      debugPrint('loadAliases error: \$e');
    }
  }

  Future<void> _loadRecentTransfers() async {
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

    if (result.bankName != null && result.bankName!.isNotEmpty && banks.isNotEmpty) {
      final bankNameLower = result.bankName!.toLowerCase();
      final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
        (b) => (b!['attributes']['name'] as String).toLowerCase().contains(bankNameLower) ||
               bankNameLower.contains((b['attributes']['name'] as String).toLowerCase()),
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
      final snapshot = await FirebaseFirestore.instance.collection('banks').get();
      List<Map<String, dynamic>> bankList = [];
      for (var doc in snapshot.docs) {
        bankList.add({
          'id': doc.id,
          'attributes': {'name': doc.data()['name']},
        });
      }
      if (bankList.isEmpty) {
        final result = await callCloudFunctionLogged(
          'safehavenBankList',
          source: 'bank_transfer_page.dart',
        );
        final data = result.data as Map<String, dynamic>;
        final apiBankList = data['data'] as List<dynamic>;
        final batch = FirebaseFirestore.instance.batch();
        for (var item in apiBankList) {
          final map = item as Map;
          final docRef = FirebaseFirestore.instance.collection('banks').doc(map['id'].toString());
          batch.set(docRef, {
            'name': (map['attributes'] as Map)['name']?.toString(),
          });
        }
        await batch.commit();
        // Reload from Firestore after saving
        final newSnapshot = await FirebaseFirestore.instance.collection('banks').get();
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
      // Auto-select bank from MyPadi if provided
      if (widget.initialBankName != null && banks.isNotEmpty) {
        final bName = widget.initialBankName!.toLowerCase();
        final matched = banks.cast<Map<String, dynamic>?>().firstWhere(
          (b) => (b!['attributes']['name'] as String).toLowerCase().contains(bName) ||
                 bName.contains((b['attributes']['name'] as String).toLowerCase()),
          orElse: () => null,
        );
        if (matched != null) {
          setState(() => selectedBank = matched['id'] as String);
          if (accountNumberController.text.length == 10) {
            _safehavenNameEnquiry();
          }
        }
      }
    } catch (e) {
      debugPrint('safehavenBankList error: $e');
      //showToast('Error fetching banks', Colors.red);
      setState(() => isFetchingBanks = false);
    }
  }

  Future<void> _autoLookupCounterparty(String accountNumber) async {
    debugPrint('ðŸ” _autoLookupCounterparty called with: $accountNumber');
    if (accountNumber.length != 10) {
      debugPrint(' Account number length is ${accountNumber.length}, not 10');
      return;
    }
    
    setState(() => isFetchingAccountName = true);
    try {
      // Search counterparties for matching account number across all users
      debugPrint('ðŸ”Ž Searching counterparties for recipientAccountNumber: $accountNumber');
      final querySnapshot = await FirebaseFirestore.instance
          .collection('counterparties')
          .where('recipientAccountNumber', isEqualTo: accountNumber)
          .limit(1)
          .get();

      debugPrint(' Query returned ${querySnapshot.docs.length} documents');
      
      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        debugPrint('ðŸ“‹ Document data: $data');
        
        String? bankId = data['recipientBankCode'] as String?;

        // Try multiple paths for account name
        final accountName = data['data']?['attributes']?['accountName'] as String? ??
                           data['attributes']?['accountName'] as String? ?? 
                           data['accountName'] as String?;

        // Try to extract bank name if bankId is missing
        final bankName = data['bankName'] as String? ??
                         data['data']?['attributes']?['bank']?['name'] as String?;

        debugPrint('ðŸ¦ Initial bankId: $bankId');
        debugPrint('ðŸ·ï¸ bankName: $bankName');
        debugPrint('ðŸ‘¤ Found accountName: $accountName');

        // If bankId is null but we have a bankName, try to resolve bankId via the banks collection
        if (bankId == null && bankName != null) {
          debugPrint('ðŸ” bankId missing, trying banks collection lookup by bankName: $bankName');
          try {
            // Try an equality query first
            final bankQuery = await FirebaseFirestore.instance
                .collection('banks')
                .where('name', isEqualTo: bankName)
                .limit(1)
                .get();
            if (bankQuery.docs.isNotEmpty) {
              bankId = bankQuery.docs.first.id;
              debugPrint('ðŸ” Found bankId by name (equal): $bankId');
            } else {
              // Fallback: fetch and compare case-insensitively
              final allBanks = await FirebaseFirestore.instance.collection('banks').get();
              for (var bdoc in allBanks.docs) {
                final bname = (bdoc.data()['name'] as String?) ?? '';
                if (bname.toLowerCase() == bankName.toLowerCase()) {
                  bankId = bdoc.id;
                  debugPrint('ðŸ” Found bankId by case-insensitive match: $bankId');
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('bank lookup by name error: $e');
          }
        }

        if (bankId != null && accountName != null) {
          debugPrint('âœ… Setting selectedBank to: $bankId and accountName to: $accountName');
          setState(() {
            selectedBank = bankId;
            accountNameController.text = accountName;
            isFetchingAccountName = false;
          });
          return;
        } else {
          debugPrint('âš ï¸ bankId or accountName is null. bankId=$bankId, accountName=$accountName');
        }
      } else {
        debugPrint(' No documents found for recipientAccountNumber: $accountNumber');
      }
    } catch (e) {
      debugPrint('ðŸ’¥ _autoLookupCounterparty error: $e');
    }
    setState(() => isFetchingAccountName = false);
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
    final doc = await FirebaseFirestore.instance.collection('verified_accounts').doc(docId).get();

    if (doc.exists) {
      setState(() {
        accountNameController.text = doc.data()!['accountName'];
      });
      return;
    }

    setState(() => isLoading = true);
    try {
      final result = await callCloudFunctionLogged(
          'safehavenNameEnquiry',
          source: 'bank_transfer_page.dart',
          payload: {
            'accountNumber': accountNumberController.text,
            'bankIdOrBankCode': selectedBank,
          });
      final accountName = result.data['data']['attributes']['accountName'];
      setState(() {
        accountNameController.text = accountName;
      });
      await FirebaseFirestore.instance.collection('verified_accounts').doc(docId).set({
        'accountName': accountName,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('safehavenNameEnquiry error: $e');
      showSimpleDialog('Error verifying account', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<Map<String, dynamic>?> getCompanyVirtualAccount() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('company').doc('account_details').get();
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

  Future<void> _createCounterparty() async {
    if (accountNameController.text.isEmpty || selectedBank == null) {
      showSimpleDialog('Please verify account details', Colors.red);
      return;
    }

    setState(() => isLoading = true);
    try {
      final bank = banks.firstWhere((b) => b['id'] == selectedBank);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final accountId = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['id'];
      final accountType = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['type'];
      // Prefer explicit bank id, otherwise resolve by bank name
      final bankIdRaw = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['attributes']?['bank']?['id'] as String?;
      final bankNameCandidate = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['attributes']?['bank']?['name'] as String?;
      final bankId = await resolveBankId(bankId: bankIdRaw, bankName: bankNameCandidate);
      if (bankId == null) debugPrint('ðŸ” Failed to resolve user bankId; bankName=$bankNameCandidate');

      // Make bankId available for later checks
      if (bankId != null) {
        // nothing, bankId set
      }

      final ownAccountNumber = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['attributes']?['accountNumber']?.toString();

      // Prevent sending to own account number
      if (ownAccountNumber != null && ownAccountNumber == accountNumberController.text) {
        showSimpleDialog('You cannot send money to your own account', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      if (accountId == null) {
        showSimpleDialog('Account ID not found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }
      if (bankId == null) {
        showSimpleDialog('Bank ID not found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }
      if (accountType == null) {
        showSimpleDialog('Account Type not found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Check if counterparty already exists
      final query = await FirebaseFirestore.instance.collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: accountNumberController.text)
          .where('recipientBankCode', isEqualTo: selectedBank)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          counterpartyId = query.docs.first.id;
        });
        setState(() => isLoading = false);
        return;
      }
      
      String counterPartyBankId = bank['id'];
      final payload = {
        'accountId': accountId,
        'bankId': counterPartyBankId,
        'accountType': accountType,
        'accountName': accountNameController.text,
        'bankName': bank['attributes']['name'],
        'accountNumber': accountNumberController.text,
        'bankCode': selectedBank,
      };
      print('createCounterparty payload: $payload');
      final result = await callCloudFunctionLogged(
        'safehavenCreateCounterparty',
        source: 'bank_transfer_page.dart',
        payload: payload,
      );
      final counterpartyIdd = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(counterpartyIdd)
          .set({
            ...result.data,
            'userId': user.uid,
            'recipientAccountNumber': accountNumberController.text,
            'recipientBankCode': selectedBank,
            'ownerAccountId': accountId,
          });
      setState(() {
        counterpartyId = counterpartyIdd;
      });
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showSimpleDialog('Error creating counterparty', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<void> _safehavenTransferNip() async {
    if (counterpartyId == null || amountController.text.isEmpty) {
      showSimpleDialog('Please complete all fields', Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final accountId = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['id'];
      final accountType = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['type'];
      final ownAccountNumber = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data']?['attributes']?['accountNumber']?.toString();

      // Prevent sending to own account number (in case input was prefilled / using counterparty)
      if (ownAccountNumber != null && ownAccountNumber == accountNumberController.text) {
        showSimpleDialog('You cannot send money to your own account', Colors.red);
        setState(() => isLoading = false);
        return;
      }

        final result = await callCloudFunctionLogged(
          'safehavenTransferNip',
          source: 'bank_transfer_page.dart',
          payload: {
            'accountType': accountType,
            'accountId': accountId,
            'counterpartyId': counterpartyId,
            'amount': double.parse(amountController.text) * 100,
            'currency': 'NGN',
            'narration': remarkController.text,
            'idempotencyKey': const Uuid().v4(),
          });
      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == "FAILED") {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        setState(() => isLoading = false);

        return;
      }

      final bank = banks.firstWhere((b) => b['id'] == selectedBank);
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': 'transfer',
        'bank_code': selectedBank,
        'account_number': accountNumberController.text,
        'amount': double.parse(amountController.text),
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': result.data,
        'reference': result.data['data']['id'],
        'recipientName': accountNameController.text,
        'bankName': bank['attributes']['name'],
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: "Done",
          title: "Payment Successful",
          description: "Your transfer has been processed successfully.",
          recipientName: accountNameController.text,
          bankName: bank['attributes']['name'] ?? 'Unknown Bank',
          bankCode: selectedBank ?? '',
          accountNumber: accountNumberController.text,
          reference: result.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      print('safehavenTransferNip error: $e');
      showSimpleDialog('Error processing transfer', Colors.red);
    }
    setState(() => isLoading = false);
  }

  Future<void> _ghostTransfer() async {
    if (amountController.text.isEmpty ||
        accountNameController.text.isEmpty ||
        selectedBank == null) {
      showSimpleDialog('Please complete all fields and verify account', Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userVaData = userDoc
          .data()?['safehavenData']?['virtualAccount']?['data'];
      if (userVaData == null) {
        showSimpleDialog('User account not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }
      final userAccountId = userVaData['id']?.toString() ?? '';
      final userAccountType = userVaData['type']?.toString() ?? '';
      final userBankIdRaw = userVaData['attributes']?['bank']?['id']?.toString();
      final userBankName = userVaData['attributes']?['bank']?['name']?.toString();
      final userBankId = (await resolveBankId(bankId: userBankIdRaw, bankName: userBankName)) ?? '';
      if (userAccountId.isEmpty ||
          userAccountType.isEmpty ||
          userBankId.isEmpty) {
        showSimpleDialog('User account details not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final companyVa = await getCompanyVirtualAccount();
      if (companyVa == null ||
          companyVa['id'].isEmpty ||
          companyVa['type'].isEmpty ||
          companyVa['bankId'].isEmpty ||
          companyVa['accountNumber'].isEmpty) {
        showSimpleDialog('Company account not found', Colors.red);
        setState(() => isLoading = false);
        return;
      }

      final recipientAccountNumber = accountNumberController.text;
      final recipientBankId = selectedBank;
      final recipientBankName = banks.firstWhere(
        (b) => b['id'] == selectedBank,
      )['attributes']['name'];
      final recipientAccountName = accountNameController.text;

      // Check/create counterparty for company (from user)
      final companyAccountNumber = companyVa['accountNumber'];
      final companyBankCode = companyVa['bankId'];
      final queryCompanyCp = await FirebaseFirestore.instance.collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: companyAccountNumber)
          .where('recipientBankCode', isEqualTo: companyBankCode)
          .limit(1)
          .get();

      String companyCounterpartyId;
      if (queryCompanyCp.docs.isNotEmpty) {
        companyCounterpartyId = queryCompanyCp.docs.first.id;
      } else {
        final companyPayload = {
          'accountId': userAccountId,
          'bankId': companyVa['bankId'],
          'accountType': userAccountType,
          'accountName': companyVa['accountName'],
          'bankName': companyVa['bankName'],
          'accountNumber': companyVa['accountNumber'],
          'bankCode': companyVa['bankId'],
        };
        debugPrint('createCompany counterparty payload: $companyPayload');
        try {
          final createCompanyCpResult = await callCloudFunctionLogged(
            'safehavenCreateCounterparty',
            source: 'bank_transfer_page.dart',
            payload: companyPayload,
          );
          companyCounterpartyId = createCompanyCpResult.data['data']['id'];
          await FirebaseFirestore.instance
              .collection('counterparties')
              .doc(companyCounterpartyId)
              .set({
                ...createCompanyCpResult.data,
                'userId': user.uid,
                'recipientAccountNumber': companyVa['accountNumber'],
                'recipientBankCode': companyVa['bankId'],
                'ownerAccountId': userAccountId,
              });
        } catch (e) {
          debugPrint('createCompanyCp failed: $e');
          rethrow;
        }
      }

      // First transfer: user to company
      final amountNaira = double.parse(amountController.text);
      final fee = 50.0;
      final amountToCompanyKobo = (amountNaira + fee) * 100;
      final narration1 =
          'Ghost Mode to Company: ${remarkController.text.isNotEmpty ? remarkController.text : 'Transfer'}';
      final firstPayload = {
            'accountType': userAccountType,
            'accountId': userAccountId,
            'counterpartyId': companyCounterpartyId,
            'amount': amountToCompanyKobo,
            'currency': 'NGN',
            'narration': narration1,
            'idempotencyKey': const Uuid().v4(),
          };
      debugPrint('safehavenTransferNip (to company) payload: $firstPayload');
      try {
        final firstResult = await callCloudFunctionLogged(
          'safehavenTransferNip',
          source: 'bank_transfer_page.dart',
          payload: firstPayload,
        );
        final firstStatus = firstResult.data['data']['attributes']['status'];
        final firstFailureReason =
            firstResult.data['data']['attributes']['failureReason'];
        if (firstStatus == "FAILED") {
          showSimpleDialog(
            'Transfer to company failed: $firstFailureReason',
            Colors.red,
          );
          setState(() => isLoading = false);
          return;
        }
      } catch (e) {
        debugPrint('safehavenTransferNip (to company) failed: $e');
        rethrow;
      }

      // Check/create counterparty for recipient (from company)
      final queryRecipientCp = await FirebaseFirestore.instance.collection('counterparties')
          .where('ownerAccountId', isEqualTo: companyVa['id'])
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankId)
          .limit(1)
          .get();

      String recipientCounterpartyId;
      if (queryRecipientCp.docs.isNotEmpty) {
        recipientCounterpartyId = queryRecipientCp.docs.first.id;
      } else {
        final createRecipientCpResult = await callCloudFunctionLogged(
            'safehavenCreateCounterparty',
            source: 'bank_transfer_page.dart',
            payload: {
              'bankId': recipientBankId,
              'accountType': "BankAccount",
              'accountName': recipientAccountName,
              'bankName': recipientBankName,
              'accountNumber': recipientAccountNumber,
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

      // Second transfer: company to recipient
      final amountToRecipientKobo = amountNaira * 100;
      final narration2 = remarkController.text.isNotEmpty
          ? remarkController.text
          : 'Ghost Mode Transfer';
      final secondPayload = {
            'accountType': companyVa['type'],
            'accountId': companyVa['id'],
            'counterpartyId': recipientCounterpartyId,
            'amount': amountToRecipientKobo,
            'currency': 'NGN',
            'narration': narration2,
            'idempotencyKey': const Uuid().v4(),
          };
      debugPrint('safehavenTransferNip (to recipient) payload: $secondPayload');
      dynamic secondResult;
      try {
        secondResult = await callCloudFunctionLogged(
          'safehavenTransferNip',
          source: 'bank_transfer_page.dart',
          payload: secondPayload,
        );
        final secondStatus = secondResult.data['data']['attributes']['status'];
        final secondFailureReason =
            secondResult.data['data']['attributes']['failureReason'];
        if (secondStatus == "FAILED") {
          showSimpleDialog(
            'Transfer to recipient failed: $secondFailureReason',
            Colors.red,
          );
          setState(() => isLoading = false);
          return;
        }
      } catch (e) {
        debugPrint('safehavenTransferNip (to recipient) failed: $e');
        rethrow;
      }

      // Log transaction
      await FirebaseFirestore.instance.collection('transactions').add({
        'actualSender': user.uid,
        'userId': "JfUPEtiWDDYZ3QMHRwEfewo96r12",
        'type': 'ghost_transfer',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': amountNaira,
        'reason': remarkController.text,
        'currency': 'NGN',
        'api_response': secondResult.data,
        'reference': secondResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      showModalBottomSheet(
        context: context,
        builder: (context) => PaymentSuccessfulPage(
          amount: amountController.text,
          actionText: "Done",
          title: "Payment Successful",
          description: "Your transfer has been processed successfully.",
          recipientName: recipientAccountName,
          bankName: recipientBankName ?? 'Unknown Bank',
          bankCode: recipientBankId ?? '',
          accountNumber: recipientAccountNumber,
          reference: secondResult.data['data']['id'] ?? "",
        ),
        isScrollControlled: true,
      );
    } catch (e) {
      debugPrint('ghostTransfer error: $e');
      showSimpleDialog('Error processing ghost transfer', Colors.red);
    }
    setState(() => isLoading = false);
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
                    SizedBox(height: 20),
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
                          child: Icon(
                            Icons.arrow_back_ios,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                        Spacer(),
                        Text(
                          "Bank Transfer",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        Spacer(),
                      ],
                    ),
                    SizedBox(height: 30),
                    // PAGE 1: Account details
                    if (_currentPage == 0) ...[
                      const Text('Beneficiary Account Number'),
                      const SizedBox(height: 8),
                      TextField(
                        maxLength: 10,
                        controller: accountNumberController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [LengthLimitingTextInputFormatter(10)],
                        decoration: InputDecoration(
                          counterText: "",
                          hintStyle: TextStyle(color: Colors.grey.shade600),
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
                            if (selectedBank != null) {
                              _safehavenNameEnquiry();
                            }
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
                                menuProps: MenuProps(
                                  backgroundColor: Colors.white,
                                ),
                                searchFieldProps: TextFieldProps(
                                  decoration: InputDecoration(
                                    hintText: "Search bank...",
                                    hintStyle: TextStyle(fontSize: 14),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
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
                                    (context, item, isDisabled, isSelected) {
                                      return ListTile(
                                        title: Text(
                                          item,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      );
                                    },
                              ),
                              items: (filter, infiniteScrollProps) async {
                                return banks
                                    .where(
                                      (bank) =>
                                          (bank['attributes']['name'] as String)
                                              .toLowerCase()
                                              .contains(filter.toLowerCase()),
                                    )
                                    .map(
                                      (bank) =>
                                          bank['attributes']['name'] as String,
                                    )
                                    .toList();
                              },
                              decoratorProps: DropDownDecoratorProps(
                                decoration: InputDecoration(
                                  hintText: "Select Bank",
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade600,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  selectedBank = banks.firstWhere(
                                    (b) => b['attributes']['name'] == value,
                                  )['id'];
                                  if (accountNumberController.text.length == 10) {
                                    _safehavenNameEnquiry();
                                  }
                                });
                              },
                              selectedItem: selectedBank != null
                                  ? banks.firstWhere(
                                      (b) => b['id'] == selectedBank,
                                      orElse: () =>
                                          {
                                                'attributes': {'name': null},
                                              }
                                              as Map<String, Object>,
                                    )['attributes']['name']
                                  : null,
                            ),
                      SizedBox(height: 16),
                      if (isFetchingAccountName || accountNameController.text.isNotEmpty) ...[
                        const Text('Account Name'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: accountNameController,
                          enabled: false,
                          decoration: InputDecoration(
                            hintStyle: TextStyle(color: Colors.grey.shade600),
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
                        onPressed: accountNumberController.text.length == 10 &&
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
                        child: const Text(
                          'Next',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ]
                    // PAGE 2: Amount & Remark
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
                                accountNameController.text
                                    .split(' ')
                                    .where((s) => s.isNotEmpty)
                                    .take(2)
                                    .map((s) => s[0].toUpperCase())
                                    .join(),
                                style: TextStyle(
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
                                    '${accountNumberController.text} Â· ${banks.firstWhere((b) => b['id'] == selectedBank, orElse: () => {'attributes': {'name': 'Unknown'}})['attributes']['name']}',
                                    style: TextStyle(
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
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: amountController,
                                keyboardType: const TextInputType.numberWithOptions(
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
                      // Amount presets
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
                            onTap: () => setState(() =>
                                amountController.text = amt.toString()),
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
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: 'Enter Remark',
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Ghost Mode",
                                style: GoogleFonts.inter(
                                  color: Colors.black26,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                "Send money anonymously",
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
                            onToggle: (val) async {
                              setState(() => sendAnonymously = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isLoading || (double.tryParse(amountController.text) ?? 0.0) <= 0
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
                            ? CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Confirm',
                                style: TextStyle(color: Colors.white),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              // Contacts & Recents sections - only on page 0
              if (_currentPage == 0) ...[
                // â”€â”€ Contacts (account-type aliases) â”€â”€
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
                              style: TextStyle(
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
                              final displayLabel = contact.displayName
                                      ?.isNotEmpty == true
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
                                    horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Colors.orange.withValues(alpha: 0.15),
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
                                  ].join(' Â· '),
                                  style: TextStyle(
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
                                      final matched = banks.firstWhere(
                                        (b) =>
                                            (b['name'] ?? '')
                                                .toString()
                                                .toLowerCase() ==
                                            contact.bankName!.toLowerCase(),
                                        orElse: () => {},
                                      );
                                      if (matched.isNotEmpty) {
                                        selectedBank =
                                            matched['id']?.toString();
                                      }
                                    }
                                    _currentPage = 1;
                                  });
                                  if (contact.accountNumber?.isNotEmpty ==
                                          true &&
                                      contact.displayName?.isEmpty != false) {
                                    _safehavenNameEnquiry();
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                // â”€â”€ Recents â”€â”€
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
                              style: TextStyle(
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
                              final name = r['recipientName']?.toString() ?? 'Unknown';
                              final acct = r['account_number']?.toString() ?? '';
                              final bank = r['bankName']?.toString() ?? '';
                              // Find matching alias by account number
                              final alias = _aliases.where((a) =>
                                a.type == 'account' &&
                                a.accountNumber == acct).firstOrNull;
                              final initials = name
                                  .split(' ')
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .map((s) => s[0].toUpperCase())
                                  .join();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      primaryColor.withValues(alpha: 0.12),
                                  child: Text(
                                    initials,
                                    style: TextStyle(
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
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
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
                                  '$acct Â· $bank',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  final bankCode = r['bank_code']?.toString();
                                  setState(() {
                                    accountNumberController.text = acct;
                                    accountNameController.text = name;
                                    if (bankCode != null &&
                                        banks.any((b) => b['id'] == bankCode)) {
                                      selectedBank = bankCode;
                                    }
                                    _currentPage = 1;
                                  });
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
