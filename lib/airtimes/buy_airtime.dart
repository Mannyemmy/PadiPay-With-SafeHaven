import 'dart:convert';

import 'package:card_app/cashback/cashback_service.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class BuyAirtimePage extends StatefulWidget {
  final String? initialPhone;
  final String? initialAmount;
  final String? initialNetwork;

  const BuyAirtimePage({
    super.key,
    this.initialPhone,
    this.initialAmount,
    this.initialNetwork,
  });

  @override
  State<BuyAirtimePage> createState() => _BuyAirtimePageState();
}

class _BuyAirtimePageState extends State<BuyAirtimePage> {
  TextEditingController numberController = TextEditingController();
  TextEditingController amountController = TextEditingController();
  bool isLoading = false;
  String? selectedProvider;
  List<Map<String, dynamic>> airtimeBillers = [];
  bool isFetchingBillers = false;
  Map<String, dynamic>? userAccount;
  double cashbackBalance = 0;
  bool useCashback = false;

  double get _cashbackPreview {
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    if (amount <= 0) return 0;
    return CashbackService.calculateCashback(amount);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null)
      numberController.text = widget.initialPhone!;
    if (widget.initialAmount != null)
      amountController.text = widget.initialAmount!;
    _fetchUserAccount();
  }

  Future<void> _fetchUserAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (userDoc.exists) {
      setState(() {
        userAccount = userDoc.data()?['getAnchorData']?['virtualAccount'];
        cashbackBalance =
            (userDoc.data()?['cashback']?['balance'] as num?)?.toDouble() ?? 0;
      });
      _fetchBillers();
    }
  }

  Future<void> _refreshCashbackBalance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final balance = await CashbackService.getCashbackBalance(uid);
    if (!mounted) return;
    setState(() {
      cashbackBalance = balance;
    });
  }

  Future<void> _fetchBillers() async {
    setState(() => isFetchingBillers = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('billers')
          .doc('airtime');
      final doc = await docRef.get();
      List<Map<String, dynamic>> billerList = [];
      if (doc.exists) {
        final data = doc.data();
        billerList = List<Map<String, dynamic>>.from(data?['data'] ?? []);
      }
      if (billerList.isEmpty) {
        final result = await callCloudFunctionLogged(
          'sudoGetServiceCategories',
          source: 'buy_airtime.dart',
          payload: {'category': 'airtime'},
        );
        final response = Map<String, dynamic>.from(result.data);
        print('Airtime Billers Response: $response');
        if (response['data'] is List) {
          billerList = (response['data'] as List)
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          await docRef.set({'data': billerList});
        }
      }
      setState(() {
        airtimeBillers = billerList;
        selectedProvider = airtimeBillers.isNotEmpty
            ? airtimeBillers[0]['attributes']['slug'] as String
            : null;
        // Auto-select network from MyPadi if provided
        if (widget.initialNetwork != null && airtimeBillers.isNotEmpty) {
          final net = widget.initialNetwork!.toLowerCase();
          final matched = airtimeBillers
              .cast<Map<String, dynamic>?>()
              .firstWhere(
                (b) =>
                    (b!['attributes']['name'] as String).toLowerCase().contains(
                      net,
                    ) ||
                    (b['attributes']['slug'] as String).toLowerCase().contains(
                      net,
                    ),
                orElse: () => null,
              );
          if (matched != null) {
            selectedProvider = matched['attributes']['slug'] as String;
          }
        }
        isFetchingBillers = false;
      });
    } catch (e) {
      print('Error fetching airtime billers: $e');
      setState(() => isFetchingBillers = false);
    }
  }

  Future<void> _showProviderBottomSheet() async {
    if (isFetchingBillers) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          bottom: true,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Provider',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List of providers
                Expanded(
                  child: ListView.builder(
                    itemCount: airtimeBillers.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final biller = airtimeBillers[index];
                      final name =
                          biller['attributes']?['name'] as String? ?? 'Unknown';
                      final slug =
                          biller['attributes']?['slug'] as String? ?? '';
                      final isSelected = selectedProvider == slug;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedProvider = slug;
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // provider icon
                              Builder(
                                builder: (context) {
                                  Widget iconWidget = const SizedBox.shrink();
                                  final lower = slug.toLowerCase();
                                  print(
                                    'Determining icon for provider slug: $lower',
                                  );
                                  if (lower.contains('mtn')) {
                                    iconWidget = SvgPicture.asset(
                                      'assets/airtime_providers/mtn.svg',
                                      width: 24,
                                      height: 24,
                                    );
                                  } else if (lower.contains('glo')) {
                                    iconWidget = Image.asset(
                                      'assets/airtime_providers/glo.png',
                                      width: 24,
                                      height: 24,
                                    );
                                  } else if (lower.contains('airtel')) {
                                    iconWidget = Image.asset(
                                      'assets/airtime_providers/airtel.png',
                                      width: 24,
                                      height: 24,
                                    );
                                  } else if (lower.contains('9mobile')) {
                                    iconWidget = SvgPicture.asset(
                                      'assets/airtime_providers/9mobile.svg',
                                      width: 24,
                                      height: 24,
                                    );
                                  }
                                  return iconWidget;
                                },
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? primaryColor
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: primaryColor,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _buyAirtime() async {
    if (numberController.text.isEmpty ||
        amountController.text.isEmpty ||
        selectedProvider == null ||
        userAccount == null) {
      showSimpleDialog('Please fill all fields', Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoading = true);

    String? cashbackFundingReference;
    var cashbackUsed = 0.0;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      final uid = user.uid;

      final amount = int.parse(amountController.text);
      if (amount < 10) {
        showSimpleDialog('Minimum airtime purchase is NGN 10', Colors.red);
        return;
      }

      final selectedCashbackUsage = useCashback
          ? CashbackService.clampCashbackUsage(
              purchaseAmountNaira: amount.toDouble(),
              availableCashbackNaira: cashbackBalance,
            )
          : 0.0;

      if (selectedCashbackUsage > 0) {
        cashbackFundingReference =
            await CashbackService.fundPurchaseFromCashbackReserve(
              toAccountId: userAccount!['data']['id'].toString(),
              amountNaira: selectedCashbackUsage,
              narration: 'Cashback funding for airtime purchase',
            );
        cashbackUsed = selectedCashbackUsage;
      }

      String formattedPhone = numberController.text;
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '234${formattedPhone.substring(1)}';
      }

      final result = await callCloudFunctionLogged(
        'sudoPurchaseVas',
        source: 'buy_airtime.dart',
        payload: {
        'type': 'Airtime',
        'accountId': userAccount!['data']['id'],
        'accountType': userAccount!['data']['type'],
        'phoneNumber': formattedPhone,
        'amount': amount * 100,
        'provider': selectedProvider,
        'reference': Uuid().v4(),
      });
      final rawData = result.data;
      final response =
          json.decode(json.encode(rawData)) as Map<String, dynamic>;
      print('Buy Airtime Response: $response');

      final billData = response['data'] as Map<String, dynamic>?;
      if (billData == null) {
        showSimpleDialog('Invalid response', Colors.red);
        return;
      }
      final attributes = billData['attributes'] as Map<String, dynamic>;
      final status = (attributes['status'] as String? ?? '').toUpperCase();
      final isCompleted = status == 'COMPLETED' || status == 'SUCCESSFUL';
      final isPending =
          status == 'PENDING' ||
          status == 'PROCESSING' ||
          status == 'IN_PROGRESS';
      final isSuccessEquivalent = isCompleted || isPending;

      if (isSuccessEquivalent) {
        if (cashbackUsed > 0) {
          try {
            await CashbackService.recordCashbackSpend(
              uid: uid,
              amountNaira: cashbackUsed,
              sourceType: 'airtime',
              sourceReference: billData['id'].toString(),
            );
          } catch (cashbackSpendError) {
            print('Cashback spend recording failed: $cashbackSpendError');
            try {
              await CashbackService.rollbackCashbackFunding(
                fromAccountId: userAccount!['data']['id'].toString(),
                amountNaira: cashbackUsed,
                narration: 'Cashback rollback for airtime purchase',
              );
              cashbackUsed = 0;
            } catch (rollbackError) {
              print('Cashback rollback failed: $rollbackError');
            }
          }
        }

        double cashbackEarned = 0;
        if (isSuccessEquivalent) {
          try {
            cashbackEarned = await CashbackService.recordCashbackEarned(
              uid: uid,
              baseAmountNaira: amount.toDouble(),
              sourceType: 'airtime',
              sourceReference: billData['id'].toString(),
            );
          } catch (cashbackEarnError) {
            print('Cashback earn recording failed: $cashbackEarnError');
          }
        }

        final effectiveStatus = status.toLowerCase();

        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': uid,
          'type': 'airtime',
          'amount': attributes['amount'] / 100,
          'phoneNumber': attributes['phoneNumber'],
          'currency': 'NGN',
          'reference': billData['id'],
          'status': effectiveStatus,
          'rawStatus': status,
          'network': attributes['detail']?['provider'] ?? 'Unknown',
          'debitAmount': attributes['amount'],
          'commissionEarned': attributes['commissionAmount'] ?? 0,
          'cashbackUsed': cashbackUsed,
          'cashbackEarned': cashbackEarned,
          'cashbackFundingReference': cashbackFundingReference,
          'createdAt': attributes['createdAt'],
          'fullData': billData,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAtFirestore': FieldValue.serverTimestamp(),
        });

        await _refreshCashbackBalance();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => SuccessBottomSheet(
            actionText: "Done",
            title: "Airtime Top Up Successful",
            description: "Your number has been topped up successfully.",
            cashbackAmount: cashbackEarned,
          ),
        );
      } else {
        final failedCashback = useCashback
            ? CashbackService.clampCashbackUsage(
                purchaseAmountNaira: amount.toDouble(),
                availableCashbackNaira: cashbackBalance,
              )
            : 0.0;
        if (failedCashback > 0) {
          try {
            await CashbackService.rollbackCashbackFunding(
              fromAccountId: userAccount!['data']['id'].toString(),
              amountNaira: failedCashback,
              narration: 'Cashback rollback for failed airtime purchase',
            );
          } catch (rollbackError) {
            print('Cashback rollback on failed payment error: $rollbackError');
          }
        }
        showSimpleDialog(
          'Failed to purchase airtime: ${attributes['failureReason'] ?? 'Unknown error'}',
          Colors.red,
        );
      }
    } catch (e) {
      if (cashbackUsed > 0) {
        try {
          await CashbackService.rollbackCashbackFunding(
            fromAccountId: userAccount!['data']['id'].toString(),
            amountNaira: cashbackUsed,
            narration: 'Cashback rollback for airtime purchase error',
          );
          cashbackUsed = 0;
        } catch (rollbackError) {
          print(
            'Cashback rollback on airtime exception failed: $rollbackError',
          );
        }
      }
      print(e);
      showSimpleDialog('Error purchasing airtime: $e', Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.white,
        leading: GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
          },
          child: Icon(Icons.arrow_back_ios, color: Colors.black54, size: 20),
        ),
        centerTitle: true,
        title: Text(
          "Buy Airtime",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      "Select Provider",
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                isFetchingBillers
                    ? Center(
                        child: CircularProgressIndicator(color: primaryColor),
                      )
                    : GestureDetector(
                        onTap: _showProviderBottomSheet,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            hintText: "Select provider",
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 15,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade400,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            border: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  selectedProvider != null
                                      ? (airtimeBillers
                                                .where(
                                                  (b) =>
                                                      b['attributes']['slug'] ==
                                                      selectedProvider,
                                                )
                                                .isNotEmpty
                                            ? airtimeBillers
                                                  .where(
                                                    (b) =>
                                                        b['attributes']['slug'] ==
                                                        selectedProvider,
                                                  )
                                                  .first['attributes']['name']
                                            : selectedProvider)
                                      : 'Select provider',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                SizedBox(height: 20),
                SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      "Recipient Mobile Number",
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                TextField(
                  controller: numberController,
                  maxLength: 11,
                  style: TextStyle(fontSize: 15),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: "Enter recipient mobile number",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 15,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                SizedBox(height: 30),
                Row(
                  children: [
                    Text(
                      "Amount To Pay",
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 5,
                  mainAxisSpacing: 5,
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _buildAmountButton('100'),
                    _buildAmountButton('500'),
                    _buildAmountButton('1000'),
                    _buildAmountButton('2000'),
                    _buildAmountButton('5000'),
                    _buildAmountButton('10000'),
                  ],
                ),
                SizedBox(height: 20),
                TextField(
                  controller: amountController,
                  style: TextStyle(fontSize: 15),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: "0",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 15,
                    ),
                    prefixText: '₦',
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      "NOTE:",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Minimum Airtime purchase is ₦10",
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Mobile Number",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            numberController.text,
                            style: TextStyle(
                              color: Colors.black38,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Airtime Purchase",
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '₦${amountController.text}',
                            style: TextStyle(
                              color: Colors.black38,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade100),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wallet_outlined,
                            color: Colors.green.shade800,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Available Cashback',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.savings_outlined,
                            color: Colors.green.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cashback balance: NGN ${cashbackBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(color: Colors.green.shade100, height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.trending_up,
                            color: Colors.green.shade900,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Reward From This Payment',
                            style: TextStyle(
                              color: Colors.green.shade900,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.local_offer_outlined,
                            color: Colors.green.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cashback to earn: NGN ${_cashbackPreview.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Divider(color: Colors.green.shade100, height: 1),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Use available cashback for this payment',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'You will still earn 10% cashback after payment.',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: useCashback,
                        onChanged: cashbackBalance > 0
                            ? (value) => setState(() => useCashback = value)
                            : null,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _buyAirtime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            'Pay Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountButton(String amount) {
    bool isSelected = amountController.text == amount;
    return GestureDetector(
      onTap: () {
        amountController.text = amount;
        setState(() {});
      },
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? primaryColor
              : primaryColor.withValues(alpha: 0.15),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "₦$amount",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : primaryColor,
              ),
            ),
            SizedBox(height: 5),
            Text(
              "(Pay ₦$amount)",
              style: TextStyle(
                fontWeight: FontWeight.w100,
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withOpacity(0.8)
                    : primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    numberController.dispose();
    amountController.dispose();
    super.dispose();
  }
}
