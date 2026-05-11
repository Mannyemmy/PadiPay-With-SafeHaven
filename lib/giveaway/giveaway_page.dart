import 'dart:math';
import 'package:card_app/giveaway/giveaway_success.dart';
import 'package:card_app/giveaway/targeted_giveaway_page.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll(',', '');
    if (newText.isEmpty) return newValue.copyWith(text: '');
    final buffer = StringBuffer();
    int count = 0;
    for (int i = newText.length - 1; i >= 0; i--) {
      buffer.write(newText[i]);
      count++;
      if (count % 3 == 0 && i > 0) buffer.write(',');
    }
    final formattedText = buffer.toString().split('').reversed.join();
    return newValue.copyWith(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class GiveAwayPage extends StatefulWidget {
  const GiveAwayPage({super.key});
  @override
  State<GiveAwayPage> createState() => _GiveAwayPageState();
}

class _GiveAwayPageState extends State<GiveAwayPage> {
  int? selectedGiveAwayType;
  int sendOrReceiveGiveAway = 0;
  bool codeGenerated = false;
  bool isLoading = false;
  bool isCustomCode = false;
  double feeRate = 0.01;
  String whoPays = 'sender';
  String? generatedCode;
  String? balance = '₦ 0.00';
  String? accountId;
  String? accountType;
  String? bankId;
  String? accountNumber;
  String? accountName;
  String? bankName;
  Map<String, dynamic>? companyVa;
  final TextEditingController totalAmountController = TextEditingController();
  final TextEditingController numPeoplePoolController = TextEditingController();
  final TextEditingController amountPerPersonController =
      TextEditingController();
  final TextEditingController numPeopleIndividualController =
      TextEditingController();
  final TextEditingController promoCodeController = TextEditingController();
  final TextEditingController customCodeController = TextEditingController();

  // ── Cached data for performance ─────────────────────────────────────────
  Map<String, dynamic>? _cachedUserDoc;
  double? _cachedBalance;
  bool _isFetchingBalance = false;
  Map<String, dynamic>? _cachedCompanyVa;

  @override
  void initState() {
    super.initState();
    totalAmountController.addListener(_updateCalculations);
    numPeoplePoolController.addListener(_updateCalculations);
    amountPerPersonController.addListener(_updateCalculations);
    numPeopleIndividualController.addListener(_updateCalculations);
    _initAllParallel();
  }

  Future<void> _initAllParallel() async {
    await Future.wait([
      _prefetchUserDataAndBalance(),
      _prefetchCompanyVirtualAccount(),
    ]);
  }

  Future<void> _prefetchUserDataAndBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      _cachedUserDoc = doc.data();

      final safehavenData =
          _cachedUserDoc?['safehavenData'] as Map<String, dynamic>?;
      final accountData =
          safehavenData?['virtualAccount']?['data'] as Map<String, dynamic>?;

      String? resolvedAccountId = accountData?['id']?.toString();
      String? resolvedAccountType = accountData?['type']?.toString();
      String? resolvedAccountNumber =
          accountData?['attributes']?['accountNumber']?.toString();
      String? resolvedAccountName = accountData?['attributes']?['accountName']
          ?.toString();
      String? resolvedBankName = accountData?['attributes']?['bank']?['name']
          ?.toString();
      String? rawBankId = accountData?['attributes']?['bank']?['id']
          ?.toString();

      // Fallback to safehavenUserSetup when safehavenData is unavailable
      if (resolvedAccountId == null) {
        final setupDoc = await FirebaseFirestore.instance
            .collection('safehavenUserSetup')
            .doc(user.uid)
            .get();
        if (setupDoc.exists) {
          final setup = setupDoc.data()!;
          resolvedAccountId = setup['accountId']?.toString();
          resolvedAccountNumber = setup['safehavenAccountNumber']?.toString();
          resolvedAccountName = setup['safehavenAccountName']?.toString();
          resolvedBankName = setup['safehavenBankName']?.toString();
          rawBankId = setup['safehavenBankCode']?.toString();
        }
      }

      if (resolvedAccountId == null) {
        debugPrint('Virtual account not found for giveaway');
        return;
      }

      final resolvedBankId = await resolveBankId(
        bankId: rawBankId,
        bankName: resolvedBankName,
      );
      if (resolvedBankId == null)
        debugPrint('Failed to resolve bank id for giveaway account');

      setState(() {
        accountId = resolvedAccountId;
        accountType = resolvedAccountType;
        bankId = resolvedBankId;
        accountNumber = resolvedAccountNumber;
        accountName = resolvedAccountName;
        bankName = resolvedBankName;
      });

      _fetchAndCacheBalance();
    } catch (e) {
      debugPrint('_prefetchUserDataAndBalance error: $e');
    }
  }

  Future<void> _fetchAndCacheBalance() async {
    if (_isFetchingBalance) return;
    _isFetchingBalance = true;
    try {
      if (accountId == null) return;
      final result = await callCloudFunctionLogged(
        'safehavenFetchAccountBalance',
        source: 'giveaway_page.dart',
        payload: {'accountId': accountId},
      );
      final balanceKobo =
          result.data['data']['availableBalance']?.toDouble() ?? 0.0;
      final balanceNaira = balanceKobo / 100;
      _cachedBalance = balanceNaira;
      setState(() {
        balance = '₦ ${NumberFormat('#,##0.00').format(balanceNaira)}';
      });
      debugPrint('✅ Giveaway balance pre-fetched: ₦$_cachedBalance');
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

  Future<void> _prefetchCompanyVirtualAccount() async {
    try {
      final result = await callCloudFunctionLogged(
        'fetchCompanySafehavenAccounts',
        source: 'giveaway_page.dart',
        payload: {'isSubAccount': false, 'page': 0, 'limit': 100},
      );

      final data = result.data;
      final companyAccount = data['companyAccount'];

      if (companyAccount != null) {
        setState(() {
          _cachedCompanyVa = {
            'uid': 'company',
            'id': companyAccount['id'],
            'type': 'BankAccount',
            'bankId': '090286',
            'bankName': 'SAFE HAVEN MICROFINANCE BANK',
            'accountNumber': companyAccount['accountNumber'],
            'accountName': companyAccount['accountName'] ?? 'PadiPay Limited',
          };
          companyVa = _cachedCompanyVa;
        });
        debugPrint(
          'Fetched company account: ${companyAccount['accountNumber']}',
        );
        return;
      }

      // Fallback: try to get default account
      final defaultAccount = data['defaultAccount'];
      if (defaultAccount != null) {
        setState(() {
          _cachedCompanyVa = {
            'uid': 'company',
            'id': defaultAccount['id'],
            'type': 'BankAccount',
            'bankId': '090286',
            'bankName': 'SAFE HAVEN MICROFINANCE BANK',
            'accountNumber': defaultAccount['accountNumber'],
            'accountName': defaultAccount['accountName'] ?? 'PadiPay Limited',
          };
          companyVa = _cachedCompanyVa;
        });
        return;
      }

      // Final fallback – Firestore cache
      final doc = await FirebaseFirestore.instance
          .collection('company')
          .doc('safehavenAccountDetails')
          .get();
      if (doc.exists) {
        final dataFallback = doc.data() ?? <String, dynamic>{};
        final companyAccountNumber =
            dataFallback['safehavenAccountNumber']?.toString() ?? '';
        if (companyAccountNumber.isNotEmpty) {
          setState(() {
            _cachedCompanyVa = {
              'uid': doc.id,
              'id': dataFallback['safehavenAccountId']?.toString() ?? '',
              'type':
                  dataFallback['safehavenAccountType']?.toString() ??
                  'BankAccount',
              'bankId':
                  dataFallback['safehavenBankCode']?.toString() ?? '090286',
              'bankName':
                  dataFallback['safehavenBankName']?.toString() ??
                  'SAFE HAVEN MICROFINANCE BANK',
              'accountNumber': companyAccountNumber,
              'accountName':
                  dataFallback['safehavenAccountName']?.toString() ??
                  'PadiPay Limited',
            };
            companyVa = _cachedCompanyVa;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching company virtual account: $e');
    }
  }

  double getTotalAmount() {
    if (selectedGiveAwayType == 0) {
      return double.tryParse(totalAmountController.text.replaceAll(',', '')) ??
          0.0;
    } else {
      final per =
          double.tryParse(amountPerPersonController.text.replaceAll(',', '')) ??
          0.0;
      final num = int.tryParse(numPeopleIndividualController.text) ?? 0;
      return per * num;
    }
  }

  int getNumPeople() {
    if (selectedGiveAwayType == 0) {
      return int.tryParse(numPeoplePoolController.text) ?? 0;
    } else {
      return int.tryParse(numPeopleIndividualController.text) ?? 0;
    }
  }

  double getFee() => getTotalAmount() * feeRate;

  double getTransferAmount() =>
      whoPays == 'sender' ? getTotalAmount() + getFee() : getTotalAmount();

  double getDistributeTotal() =>
      whoPays == 'sender' ? getTotalAmount() : getTotalAmount() - getFee();

  double getAmountPerPerson() {
    final num = getNumPeople();
    if (num == 0) return 0.0;
    return getDistributeTotal() / num;
  }

  void _updateCalculations() => setState(() {});

  Future<String> _generateUniqueCode() async {
    String code;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 10;
    do {
      code = 'PADI#${Random().nextInt(900000) + 100000}';
      final snapshot = await FirebaseFirestore.instance
          .collection('giveaways')
          .where('code', isEqualTo: code)
          .get();
      isUnique = snapshot.docs.isEmpty;
      attempts++;
    } while (!isUnique && attempts < maxAttempts);
    if (!isUnique) throw Exception('Unable to generate unique giveaway code');
    return code;
  }

  Future<void> _createGiveaway() async {
    if (selectedGiveAwayType == null) {
      showSimpleDialog('Please select a giveaway type', Colors.red);
      return;
    }
    final totalAmount = getTotalAmount();
    final numPeople = getNumPeople();
    final amountPerPerson = getAmountPerPerson();
    if (totalAmount <= 0 || numPeople <= 0 || amountPerPerson <= 0) {
      showSimpleDialog('Invalid amount or number of people', Colors.red);
      return;
    }

    final balanceValue = await _getBalance();
    final transferAmount = getTransferAmount();
    if (balanceValue < transferAmount) {
      showSimpleDialog('Insufficient balance', Colors.red);
      return;
    }

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      String code;
      if (isCustomCode) {
        code = customCodeController.text.trim().toUpperCase();
        if (code.isEmpty) throw Exception('Please enter a custom code');
        final snapshot = await FirebaseFirestore.instance
            .collection('giveaways')
            .where('code', isEqualTo: code)
            .get();
        if (snapshot.docs.isNotEmpty)
          throw Exception('Custom code already exists');
      } else {
        code = await _generateUniqueCode();
      }

      final companyDestination = (companyVa!['id']?.toString() ?? '').trim();
      if (companyDestination.isEmpty)
        throw Exception('Company SafeHaven account not configured');

      final transferAmountKobo = transferAmount * 100;
      final transferResult = await callCloudFunctionLogged(
        'safehavenTransferIntra',
        source: 'giveaway_page.dart',
        payload: {
          'fromAccountId': accountId,
          'toAccountId': companyDestination,
          'toBankCode': companyVa!['bankId'] ?? '090286',
          'amount': transferAmountKobo,
          'currency': 'NGN',
          'narration': 'Giveaway Funding',
          'idempotencyKey': const Uuid().v4(),
        },
      );
      final status = transferResult.data['data']['attributes']['status'];
      if (status == 'FAILED')
        throw Exception('Transfer to company account failed');

      await FirebaseFirestore.instance.collection('giveaways').add({
        'code': code,
        'type': selectedGiveAwayType == 0 ? 'pool' : 'individual',
        'original_total': totalAmount,
        'fee_rate': feeRate,
        'who_pays': whoPays,
        'numPeople': numPeople,
        'amountPerPerson': amountPerPerson,
        'creatorId': user.uid,
        'recipients': [],
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': 'giveaway_create',
        'bank_code': companyVa!['bankId'],
        'account_number': companyVa!['accountNumber'],
        'amount': transferAmount,
        'reason': 'Giveaway Funding - $code',
        'currency': 'NGN',
        'api_response': transferResult.data,
        'reference': transferResult.data['data']['id'],
        'recipientName': companyVa!['accountName'],
        'bankName': companyVa!['bankName'],
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        generatedCode = code;
        codeGenerated = true;
      });

      // Refresh balance after creation
      await _fetchAndCacheBalance();

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => GiveAwaySuccessBottomSheet(
            code: generatedCode!,
            title: "Successful",
            description: "Giveaway created successfully.",
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating giveaway: $e');
      showSimpleDialog(
        'Failed to create giveaway: ${e.toString()}',
        Colors.red,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _claimGiveaway() async {
    final code = promoCodeController.text.trim();
    if (code.isEmpty) {
      showSimpleDialog('Please enter a promo code', Colors.red);
      return;
    }

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) return;

    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final snapshot = await FirebaseFirestore.instance
          .collection('giveaways')
          .where('code', isEqualTo: code)
          .where('status', isEqualTo: 'active')
          .get();
      if (snapshot.docs.isEmpty)
        throw Exception('Invalid or expired giveaway code');

      final giveaway = snapshot.docs.first;
      final giveawayData = giveaway.data();
      if (giveawayData['creatorId'] == user.uid)
        throw Exception('You cannot claim your own giveaway');

      if (giveawayData['type'] == 'targeted') {
        final allowedUids = List<String>.from(
          giveawayData['allowedUids'] ?? [],
        );
        if (!allowedUids.contains(user.uid))
          throw Exception('You are not on the recipient list');
      }

      final recipients = List<String>.from(giveawayData['recipients'] ?? []);
      if (recipients.contains(user.uid))
        throw Exception('You have already claimed this giveaway');
      if (recipients.length >= giveawayData['numPeople'])
        throw Exception('Giveaway has reached maximum participants');

      // Explicit type declaration
      final userDoc =
          (_cachedUserDoc ??
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .get())
              as DocumentSnapshot<Map<String, dynamic>>;

      final safehavenVa =
          userDoc.data()?['safehavenData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;

      final recipientAccountId = safehavenVa?['id']?.toString();
      final recipientBankId =
          safehavenVa?['attributes']?['bank']?['id']?.toString() ?? '090286';
      final recipientAccountName =
          safehavenVa?['attributes']?['accountName']?.toString() ?? '';
      final recipientBankName =
          safehavenVa?['attributes']?['bank']?['name']?.toString() ??
          'Safe Haven Microfinance Bank';
      final recipientAccountNumber =
          safehavenVa?['attributes']?['accountNumber']?.toString() ?? '';

      if (companyVa == null) throw Exception('Company account not configured');
      final resolvedRecipientDestination =
          (recipientAccountId?.isNotEmpty ?? false)
          ? recipientAccountId!
          : recipientAccountNumber;

      final amountKobo = (giveawayData['amountPerPerson'] * 100).toInt();
      final transferResult = await callCloudFunctionLogged(
        'safehavenTransferIntra',
        source: 'giveaway_page.dart',
        payload: {
          'fromAccountId': companyVa!['id'],
          'toAccountId': resolvedRecipientDestination,
          'toBankCode': recipientBankId,
          'amount': amountKobo,
          'currency': 'NGN',
          'narration': 'Giveaway Claim - $code',
          'idempotencyKey': const Uuid().v4(),
        },
      );
      final status = transferResult.data['data']['attributes']['status'];
      if (status == 'FAILED') throw Exception('Transfer failed');

      recipients.add(user.uid);
      await giveaway.reference.update({
        'recipients': recipients,
        'status': recipients.length >= giveawayData['numPeople']
            ? 'completed'
            : 'active',
      });

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': 'giveaway_claim',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': giveawayData['amountPerPerson'],
        'reason': 'Giveaway Claim - $code',
        'currency': 'NGN',
        'api_response': transferResult.data,
        'reference': transferResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (context) => PaymentSuccessfulPage(
            amount: NumberFormat(
              '#,##0.00',
            ).format(giveawayData['amountPerPerson']),
            actionText: "Done",
            title: "Giveaway Claimed",
            description: "You have successfully claimed the giveaway.",
            recipientName: recipientAccountName,
            bankName: recipientBankName,
            bankCode: recipientBankId,
            accountNumber: recipientAccountNumber,
            reference: transferResult.data['data']['id'] ?? "",
          ),
          isScrollControlled: true,
        );
      }
    } catch (e) {
      debugPrint('Error claiming giveaway: $e');
      showSimpleDialog('Failed to claim giveaway: ${e.toString()}', Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    totalAmountController.removeListener(_updateCalculations);
    numPeoplePoolController.removeListener(_updateCalculations);
    amountPerPersonController.removeListener(_updateCalculations);
    numPeopleIndividualController.removeListener(_updateCalculations);
    totalAmountController.dispose();
    numPeoplePoolController.dispose();
    amountPerPersonController.dispose();
    numPeopleIndividualController.dispose();
    promoCodeController.dispose();
    customCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('#,##0.00');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.black87),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const GiveawaysHistoryPage(),
                ),
              );
            },
          ),
        ],
        title: Text(
          "Giveaway",
          style: GoogleFonts.inter(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => sendOrReceiveGiveAway = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: sendOrReceiveGiveAway == 0
                            ? primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Text(
                        "Send Giveaway",
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sendOrReceiveGiveAway == 0
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => setState(() => sendOrReceiveGiveAway = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: sendOrReceiveGiveAway == 1
                            ? primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Text(
                        "Receive Giveaway",
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sendOrReceiveGiveAway == 1
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (sendOrReceiveGiveAway == 1)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        offset: const Offset(1, 1.5),
                      ),
                    ],
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Claim Your Reward",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Enter your promo code to claim your giveaway funds",
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w200,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Promo Code",
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        textCapitalization: TextCapitalization.characters,
                        controller: promoCodeController,
                        onChanged: (value) => setState(() {}),
                        keyboardType: TextInputType.text,
                        style: GoogleFonts.inter(fontSize: 15),
                        decoration: InputDecoration(
                          fillColor: Colors.white,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 15,
                          ),
                          hintStyle: GoogleFonts.inter(color: Colors.grey),
                          hintText: "Enter code PADI#123456",
                          prefixStyle: GoogleFonts.inter(color: Colors.black),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: primaryColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: isLoading ? null : _claimGiveaway,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  "Claim Reward",
                                  style: GoogleFonts.inter(color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (sendOrReceiveGiveAway == 0)
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        offset: const Offset(1, 1.5),
                      ),
                    ],
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Giveaway Details",
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Choose how you'd like to distribute your funds",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Text(
                                  "Select Giveaway Type",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet<int?>(
                                  context: context,
                                  builder: (context) =>
                                      const ChooseGiveAwayTypeBottomSheet(),
                                  isScrollControlled: true,
                                ).then((value) {
                                  if (value == null) return;
                                  if (value == 2) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const TargetedGiveawayPage(),
                                      ),
                                    );
                                  } else {
                                    setState(
                                      () => selectedGiveAwayType = value,
                                    );
                                  }
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.grey.shade100,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selectedGiveAwayType == null
                                            ? "Choose a giveaway type"
                                            : (selectedGiveAwayType == 0
                                                  ? "Pool Giveaway - Distribute a total amount among many people"
                                                  : "Individual Giveaway - Give a set amount to each person"),
                                        style: GoogleFonts.inter(
                                          color: selectedGiveAwayType == null
                                              ? Colors.grey
                                              : Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 3,
                                        softWrap: false,
                                      ),
                                    ),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Colors.grey.shade400,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            if (selectedGiveAwayType == 0)
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Total Amount to Give Away",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: totalAmountController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [ThousandsFormatter()],
                                    style: GoogleFonts.inter(fontSize: 15),
                                    decoration: InputDecoration(
                                      fillColor: Colors.white,
                                      filled: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 0,
                                            vertical: 15,
                                          ),
                                      hintStyle: GoogleFonts.inter(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                      hintText:
                                          "Enter total spending amount e.g 1,000,000",
                                      prefixText: " ₦ ",
                                      prefixStyle: GoogleFonts.inter(
                                        color: Colors.black,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: primaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    children: [
                                      Text(
                                        "Number of People",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: numPeoplePoolController,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.inter(fontSize: 15),
                                    decoration: InputDecoration(
                                      fillColor: Colors.white,
                                      filled: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 15,
                                          ),
                                      hintStyle: GoogleFonts.inter(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                      hintText:
                                          "Enter number of recipients (e.g 200)",
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: primaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (selectedGiveAwayType == 1)
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Amount per Person",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: amountPerPersonController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [ThousandsFormatter()],
                                    style: GoogleFonts.inter(fontSize: 15),
                                    decoration: InputDecoration(
                                      fillColor: Colors.white,
                                      filled: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 0,
                                            vertical: 15,
                                          ),
                                      hintStyle: GoogleFonts.inter(
                                        color: Colors.grey,
                                      ),
                                      hintText: "Enter amount e.g 20,000",
                                      prefixText: " ₦ ",
                                      prefixStyle: GoogleFonts.inter(
                                        color: Colors.black,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: primaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    children: [
                                      Text(
                                        "Number of People",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: numPeopleIndividualController,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.inter(fontSize: 15),
                                    decoration: InputDecoration(
                                      fillColor: Colors.white,
                                      filled: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 15,
                                          ),
                                      hintStyle: GoogleFonts.inter(
                                        color: Colors.grey,
                                      ),
                                      hintText:
                                          "Enter number of recipients (e.g 200)",
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: primaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 20),
                            if (selectedGiveAwayType != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Customize Giveaway Code",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                      FlutterSwitch(
                                        width: 50,
                                        height: 25,
                                        toggleSize: 20,
                                        borderRadius: 20,
                                        padding: 3,
                                        value: isCustomCode,
                                        activeColor: primaryColor,
                                        inactiveColor: Colors.grey.shade300,
                                        onToggle: (val) {
                                          setState(() {
                                            isCustomCode = val;
                                            feeRate = val ? 0.02 : 0.01;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (isCustomCode)
                                    TextField(
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      controller: customCodeController,
                                      keyboardType: TextInputType.text,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.deny(
                                          RegExp(r'\s'),
                                        ),
                                      ],
                                      style: GoogleFonts.inter(fontSize: 15),
                                      decoration: InputDecoration(
                                        fillColor: Colors.white,
                                        filled: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 15,
                                            ),
                                        hintStyle: GoogleFonts.inter(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                        hintText:
                                            "Enter custom code e.g. MY_GIVEAWAY",
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: primaryColor,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 15),
                                  Text(
                                    "Who Pays the Fee?",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => whoPays = 'sender',
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: whoPays == 'sender'
                                                  ? primaryColor
                                                  : Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(25),
                                            ),
                                            child: Center(
                                              child: Text(
                                                "I Pay",
                                                style: GoogleFonts.inter(
                                                  color: whoPays == 'sender'
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => whoPays = 'receivers',
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: whoPays == 'receivers'
                                                  ? primaryColor
                                                  : Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(25),
                                            ),
                                            child: Center(
                                              child: Text(
                                                "Receivers",
                                                style: GoogleFonts.inter(
                                                  color: whoPays == 'receivers'
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 25),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: primaryColor,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      color: primaryColor.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.calculate,
                                              color: primaryColor,
                                              size: 25,
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              "Summary:",
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey.shade600,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "Fee (${(feeRate * 100).toStringAsFixed(0)}%): ₦${numberFormat.format(getFee())}",
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          "Total Transfer: ₦${numberFormat.format(getTransferAmount())}",
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          "Each Receives: ₦${numberFormat.format(getAmountPerPerson())}",
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 25),
                                  Row(
                                    children: [
                                      Text(
                                        "Select Wallet",
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: Colors.grey.shade100,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Default Wallet",
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          balance ?? '₦ 0.00',
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (codeGenerated)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              generatedCode!,
                                              style: GoogleFonts.inter(
                                                fontSize: 16,
                                                color: primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.content_copy,
                                              color: Colors.grey.shade600,
                                            ),
                                            onPressed: () => Clipboard.setData(
                                              ClipboardData(
                                                text: generatedCode!,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 30),
                                  GestureDetector(
                                    onTap: isLoading ? null : _createGiveaway,
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: primaryColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: isLoading
                                          ? const CircularProgressIndicator(
                                              color: Colors.white,
                                            )
                                          : Text(
                                              "Generate Code",
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    textAlign: TextAlign.center,
                                    "You'll receive a unique code to share with recipients",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 30),
                            if (selectedGiveAwayType == null)
                              Column(
                                children: [
                                  Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: primaryColor.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.calculate,
                                      color: primaryColor,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    textAlign: TextAlign.center,
                                    "Select a giveaway type above to get started",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChooseGiveAwayTypeBottomSheet extends StatefulWidget {
  const ChooseGiveAwayTypeBottomSheet({super.key});
  @override
  State<ChooseGiveAwayTypeBottomSheet> createState() =>
      _ChooseGiveAwayTypeBottomSheetState();
}

class _ChooseGiveAwayTypeBottomSheetState
    extends State<ChooseGiveAwayTypeBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'Choose GiveAway Type',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                Column(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                FontAwesomeIcons.peopleGroup,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pool Giveaway',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Distribute a total amount among many people',
                                    style: GoogleFonts.inter(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(1),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Individual Giveaway',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Give a set amount to each person',
                                    style: GoogleFonts.inter(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(2),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F4FC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.verified_user,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Targeted Giveaway',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'Only specific Padi users you choose can claim',
                                    style: GoogleFonts.inter(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GiveawaysHistoryPage extends StatelessWidget {
  const GiveawaysHistoryPage({super.key});

  DateTime _parseDate(Map<String, dynamic> data) {
    final ts =
        data['createdAt'] ?? data['createdAtFirestore'] ?? data['timestamp'];
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is String) {
      try {
        return DateTime.parse(ts);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Giveaways History')),
        body: const Center(child: Text('Please sign in to view giveaways')),
      );
    }

    final createdStream = FirebaseFirestore.instance
        .collection('giveaways')
        .where('creatorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    final claimedStream = FirebaseFirestore.instance
        .collection('giveaways')
        .where('recipients', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('Giveaways History'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: createdStream,
        builder: (context, createdSnap) {
          if (createdSnap.hasError) {
            return Center(child: Text('Error: ${createdSnap.error}'));
          }
          final createdDocs = createdSnap.data?.docs ?? [];
          return StreamBuilder<QuerySnapshot>(
            stream: claimedStream,
            builder: (context, claimedSnap) {
              if (claimedSnap.hasError) {
                return Center(child: Text('Error: ${claimedSnap.error}'));
              }
              final claimedDocs = claimedSnap.data?.docs ?? [];
              final List<Map<String, dynamic>> items = [];

              for (var d in createdDocs) {
                items.add({'doc': d, 'role': 'created'});
              }
              for (var d in claimedDocs) {
                if (!items.any((it) => it['doc'].id == d.id)) {
                  items.add({'doc': d, 'role': 'claimed'});
                }
              }
              items.sort((a, b) {
                final aDate = _parseDate(
                  a['doc'].data() as Map<String, dynamic>,
                );
                final bDate = _parseDate(
                  b['doc'].data() as Map<String, dynamic>,
                );
                return bDate.compareTo(aDate);
              });

              if (items.isEmpty) {
                return const Center(child: Text('No giveaways found'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final doc = items[index]['doc'] as QueryDocumentSnapshot;
                  final role = items[index]['role'] as String;
                  final data = doc.data() as Map<String, dynamic>;
                  final code = data['code'] ?? 'N/A';
                  final type = data['type'] ?? 'unknown';
                  final total =
                      (data['original_total'] ?? data['amountPerPerson'] ?? 0);
                  final numPeople = data['numPeople'] ?? 0;
                  final status = data['status'] ?? '';
                  final createdAt = _parseDate(data);
                  final formattedDate = DateFormat(
                    'MMM d, yyyy HH:mm',
                  ).format(createdAt);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: primaryColor,
                      child: Icon(FontAwesomeIcons.gift, color: Colors.white),
                    ),
                    title: Text('$code • ${type.toString().toUpperCase()}'),
                    subtitle: Text(
                      '$formattedDate • ${role == 'created' ? 'Creator' : 'Claimed'} • Status: $status',
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₦ ${NumberFormat('#,##0.00').format(total)}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '$numPeople ppl',
                          style: GoogleFonts.inter(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) {
                          return Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Giveaway $code',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text('Type: $type'),
                                SizedBox(height: 4),
                                Text('Status: $status'),
                                SizedBox(height: 4),
                                Text(
                                  'Total: ₦ ${NumberFormat('#,##0.00').format(total)}',
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Recipients claimed: ${(data['recipients'] as List?)?.length ?? 0} / $numPeople',
                                ),
                                SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    child: Text('Close'),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
