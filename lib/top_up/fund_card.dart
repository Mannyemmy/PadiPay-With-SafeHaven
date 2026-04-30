
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class FundCard extends StatefulWidget {
  final Map<String, dynamic> card;
  final String currency;
  const FundCard({super.key, required this.card, required this.currency});

  @override
  State<FundCard> createState() => _FundCardState();
}

class _FundCardState extends State<FundCard> {
  final TextEditingController _amountController = TextEditingController();
  String _inputAmount = "0.00";
  double _usdToNairaRate = 0.0;
  double _availableBalance = 0.0;
  String _maskedAccountNumber = '';
  bool _isRateLoading = true;
  bool _isBalanceLoading = true;
  bool _isAccountLoading = true;
  bool get isUSD => widget.currency.toUpperCase().contains('USD');
  String get currencySymbol => isUSD ? '\$' : '₦';

  double get inputAmount =>
      double.tryParse(_inputAmount.replaceAll(',', '')) ?? 0.0;
  double get displayAmount => isUSD ? inputAmount : inputAmount;
  double get nairaAmount =>
      isUSD ? (inputAmount * _usdToNairaRate) : inputAmount;
  double get fee => isUSD
      ? (nairaAmount * 0.1)
      : (inputAmount * 0.05); // 10% for USD (on NGN equiv), 5% for NGN
  double get totalAmount => nairaAmount + fee;

  Future<Map<String, dynamic>> getCurrentAccountIdAndType() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return {
        'accountId': null,
        'accountType': null,
        'bankId': null,
        'accountNumber': null,
        'bankName': null,
        'accountName': null,
      };
    }

    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userSnap.exists && userSnap.data() != null) {
      final data = userSnap.data()!;
      final Map<String, dynamic>? virtualAccData =
          data['safehavenData']?['virtualAccount']?['data']
              as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final bankMap =
            virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
        final String? bankId = bankMap?['id']?.toString();
        final String? accountNumber =
            virtualAccData['attributes']?['accountNumber']?.toString();
        final String? bankName = bankMap?['name']?.toString();
        final String? accountName =
            virtualAccData['attributes']?['accountName']?.toString() ??
            data['fullName'] ??
            '';

        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': bankId,
          'accountNumber': accountNumber,
          'bankName': bankName,
          'accountName': accountName,
        };
      }
    }

    return {
      'accountId': null,
      'accountType': null,
      'bankId': null,
      'accountNumber': null,
      'bankName': null,
      'accountName': null,
    };
  }

  Widget _shimmerPlaceholder({required double width, double height = 16.0}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
      );

  Future<void> _fetchBalance() async {
    try {
      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountNumber = details['accountNumber'];

      if (accountId == null) throw Exception('Account ID not found');

      final callable = FirebaseFunctions.instance.httpsCallable(
        'safehavenFetchAccountBalance',
      );
      final result = await callable.call({'accountId': accountId});

      var balance = result.data['data']['availableBalance']?.toDouble() ?? 0.0;
      balance /= 100;

      String masked = '';
      if (accountNumber != null && accountNumber.length > 4) {
        masked =
            '*' * (accountNumber.length - 4) +
            accountNumber.substring(accountNumber.length - 4);
      } else {
        masked = accountNumber ?? '';
      }

      if (mounted) {
        setState(() {
          _availableBalance = balance;
          _maskedAccountNumber = masked;
          _isBalanceLoading = false;
          _isAccountLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching balance: $e');
      if (mounted) {
        setState(() {
          _isBalanceLoading = false;
          _isAccountLoading = false;
        });
      }
    }
  }

  Future<void> _fetchRate() async {
    if (!isUSD) {
      if (mounted) setState(() => _isRateLoading = false);
      return;
    }
    try {
      double rate = 0.0;
      final companySnap = await FirebaseFirestore.instance
          .collection('company')
          .doc('sudoAccountDetails')
          .get();
      final companyData = companySnap.data();
      final rawRate = companyData?['usdNgnRate'];
      if (rawRate is num && rawRate > 0) {
        rate = rawRate.toDouble();
      } else if (rawRate is String) {
        final parsed = double.tryParse(rawRate);
        if (parsed != null && parsed > 0) {
          rate = parsed;
        }
      }
      if (mounted) {
        setState(() {
          _usdToNairaRate = rate;
          _isRateLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching FX rate: $e');
      if (mounted) setState(() => _isRateLoading = false);
    }
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
      print('getCompanyVirtualAccount error: $e');
      return null;
    }
  }

  Future<bool> _refundToUser(
    Map<String, dynamic> userDetails,
    Map<String, dynamic> companyVa,
    double totalAmount,
  ) async {
    try {
      final String? userAccountId = userDetails['accountId'];
      if (userAccountId == null || userAccountId.isEmpty) {
        print('Refund skipped: Missing user accountId');
        return false;
      }

      // Refund: company to user via SafeHaven book transfer.
      final refundResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': companyVa['id'],
            'toAccountId': userAccountId,
            'amount': (totalAmount * 100).toInt(),
            'currency': 'NGN',
            'narration': 'Refund for failed card funding - ${widget.currency}',
            'idempotencyKey': const Uuid().v4(),
          });

      if (refundResult.data['data']['attributes']['status'] == 'FAILED') {
        print('Refund transfer failed: ${refundResult.data['message']}');
        return false;
      }
      print('Refund transfer: ${refundResult.data}');
      return true;
    } catch (e) {
      print('Refund error: $e');
      return false;
    }
  }

  void _updateAmounts() {
    setState(() {
      _inputAmount = _amountController.text.isEmpty
          ? "0.00"
          : _amountController.text;
    });
  }

  String _formatCurrency(double amount) {
    return NumberFormat('#,###.00', 'en_US').format(amount);
  }

  Future<void> _performFunding() async {
    if (inputAmount <= 0) {
      showSimpleDialog('Enter a valid amount', Colors.red);
      return;
    }
    if (isUSD) {
      showSimpleDialog('USD card funding is currently unavailable', Colors.red);
      return;
    }
    if (totalAmount > _availableBalance) {
      showSimpleDialog('Insufficient funds', Colors.red);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    bool transferSuccess = false;
    Map<String, dynamic>? userDetails;
    Map<String, dynamic>? companyVa;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      userDetails = await getCurrentAccountIdAndType();
      final String? accountId = userDetails['accountId'];
      final String? accountType = userDetails['accountType'];
      final String? bankId = userDetails['bankId'];

      if (accountId == null || accountType == null || bankId == null) {
        throw Exception('Account details not found');
      }

      companyVa = await getCompanyVirtualAccount();
      if (companyVa == null) throw Exception('Company account not found');

      // Transfer total NGN to company VA via SafeHaven book transfer.
      final transferResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
            'fromAccountId': accountId,
            'toAccountId': companyVa['id'],
            'amount': (totalAmount * 100).toInt(),
            'currency': 'NGN',
            'narration': 'Card Funding - ${widget.currency}',
            'idempotencyKey': const Uuid().v4(),
          });

      if (transferResult.data['data']['attributes']['status'] == 'FAILED') {
        throw Exception('Transfer failed');
      }

      transferSuccess = true;

      final String transactionRef = const Uuid().v4();
      // Local funding for NGN: update balance and transaction after successful transfer
      try {
        final QuerySnapshot query = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('cards')
            .where('card_id', isEqualTo: widget.card['card_id'])
            .get();
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          await doc.reference.update({
            'balance': FieldValue.increment(inputAmount),
          });
        }

        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': user.uid,
          'card_id': widget.card['card_id'],
          'type': 'fund',
          'amount': inputAmount,
          'currency': widget.currency,
          'status': 'success',
          'timestamp': FieldValue.serverTimestamp(),
          'reference': transactionRef,
        });
      } catch (updateError) {
        print('Error updating balance or transaction: $updateError');
        // Proceed to success UI as transfer succeeded
      }

      Navigator.pop(context); // Close loading
      navigateTo(
        context,
        SuccessBottomSheet(
          actionText: 'Done',
          title: 'Success',
          description:
              'Your card has been funded successfully with $currencySymbol${_formatCurrency(displayAmount)}',
        ),
      );
    } catch (e) {
      bool refunded = false;
      if (transferSuccess && userDetails != null && companyVa != null) {
        refunded = await _refundToUser(userDetails, companyVa, totalAmount);
      }
      Navigator.pop(context);
      final errorMsg = e.toString().contains('Account name is required')
          ? e.toString()
          : 'Funding failed';
      if (refunded) {
        showSimpleDialog('$errorMsg, but amount refunded', Colors.orange);
      } else {
        showSimpleDialog(
          transferSuccess
              ? '$errorMsg and refund failed - contact support'
              : errorMsg,
          Colors.red,
        );
      }
      print('Error in funding: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_updateAmounts);
    _fetchBalance();
    _fetchRate();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,###.00', 'en_US');
    final balanceFormatter = NumberFormat('#,###', 'en_US');

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fund Card',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 20),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Amount",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black45,
                          ),
                        ),
                        SizedBox(height: 10),
                        TextField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            hintText: "0.00",
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 8,
                              ),
                              child: Text(
                                currencySymbol,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 0,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade100,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        if (isUSD) ...[
                          SizedBox(height: 20),
                          _isRateLoading
                              ? _shimmerPlaceholder(width: 200, height: 20)
                              : Text(
                                  "Rate = \$1 = ₦${_formatCurrency(_usdToNairaRate)}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                        ],
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Amount",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              isUSD
                                  ? "\$${displayAmount.toStringAsFixed(2)} (₦${_formatCurrency(nairaAmount)})"
                                  : "$currencySymbol${_formatCurrency(displayAmount)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Fee",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              "₦${_formatCurrency(fee)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Total Amount",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              "₦${_formatCurrency(totalAmount)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 30),
                        Text(
                          "Fund From",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black45,
                          ),
                        ),
                        SizedBox(height: 10),
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Default Wallet",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  _isAccountLoading
                                      ? _shimmerPlaceholder(
                                          width: 80,
                                          height: 20,
                                        )
                                      : Text(
                                          _maskedAccountNumber,
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "Available",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  _isBalanceLoading
                                      ? _shimmerPlaceholder(
                                          width: 100,
                                          height: 20,
                                        )
                                      : Text(
                                          "₦${balanceFormatter.format(_availableBalance)}",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w800,
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
                  SizedBox(height: 30),
                  InkWell(
                    onTap: _performFunding,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "Fund Now",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

