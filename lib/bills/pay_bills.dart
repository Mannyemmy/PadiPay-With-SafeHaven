import 'dart:convert';

import 'package:card_app/cashback/cashback_service.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

class PayBillsPage extends StatefulWidget {
  final String? initialBillType;

  const PayBillsPage({super.key, this.initialBillType});

  @override
  State<PayBillsPage> createState() => _PayBillsPageState();
}

class _PayBillsPageState extends State<PayBillsPage> {
  String? selectedBill;
  // Data bundle states
  String? selectedDataNetwork;
  String? selectedDataBundle;
  List<Map<String, dynamic>> dataBillers = [];
  List<Map<String, dynamic>> dataBundles = [];
  TextEditingController mobileNumberController = TextEditingController();
  bool isFetchingDataBillers = false;
  bool isFetchingDataBundles = false;
  bool isLoadingData = false;
  // Cable states
  String? selectedCableOperator;
  String? selectedCablePackage;
  List<Map<String, dynamic>> cableBillers = [];
  List<Map<String, dynamic>> cableSubscriptions = [];
  TextEditingController cardNumberController = TextEditingController();
  TextEditingController cableAmountController = TextEditingController();
  bool isFetchingCableBillers = false;
  bool isFetchingCableSubscriptions = false;
  bool isLoadingCable = false;
  // Electricity states
  String? selectedDisco;
  List<Map<String, dynamic>> electricityBillers = [];
  TextEditingController meterNumberController = TextEditingController();
  TextEditingController electricityAmountController = TextEditingController();
  bool isFetchingElectricityBillers = false;
  bool isLoadingElectricity = false;
  Map<String, dynamic>? userAccount;
  double cashbackBalance = 0;
  bool useCashback = false;

  @override
  void initState() {
    super.initState();
    selectedBill = _mapBillType(widget.initialBillType) ?? 'data_bundle';
    _fetchUserAccount();
  }

  String? _mapBillType(String? type) {
    if (type == null) return null;
    final t = type.toLowerCase();
    if (t.contains('data') || t.contains('internet')) return 'data_bundle';
    if (t.contains('cable') || t.contains('tv')) return 'cable_tv';
    if (t.contains('electric') || t.contains('power')) return 'electricity';
    return null;
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

  double _selectedCashbackUsage(double amountNaira) {
    if (!useCashback) return 0;
    return CashbackService.clampCashbackUsage(
      purchaseAmountNaira: amountNaira,
      availableCashbackNaira: cashbackBalance,
    );
  }

  Future<void> _rollbackCashbackIfNeeded({
    required double cashbackUsed,
    required String accountId,
    required String narration,
  }) async {
    if (cashbackUsed <= 0) return;
    await CashbackService.rollbackCashbackFunding(
      fromAccountId: accountId,
      amountNaira: cashbackUsed,
      narration: narration,
    );
  }

  Future<Map<String, double>> _settleCashbackAfterSuccess({
    required String uid,
    required double cashbackUsed,
    required String accountId,
    required String sourceType,
    required String sourceReference,
    required double purchaseAmountNaira,
  }) async {
    var appliedCashbackUsed = cashbackUsed;

    if (appliedCashbackUsed > 0) {
      try {
        await CashbackService.recordCashbackSpend(
          uid: uid,
          amountNaira: appliedCashbackUsed,
          sourceType: sourceType,
          sourceReference: sourceReference,
        );
      } catch (cashbackSpendError) {
        print('Cashback spend recording failed: $cashbackSpendError');
        try {
          await _rollbackCashbackIfNeeded(
            cashbackUsed: appliedCashbackUsed,
            accountId: accountId,
            narration: 'Cashback rollback for $sourceType payment',
          );
          appliedCashbackUsed = 0;
        } catch (rollbackError) {
          print('Cashback rollback failed: $rollbackError');
        }
      }
    }

    var cashbackEarned = 0.0;
    try {
      cashbackEarned = await CashbackService.recordCashbackEarned(
        uid: uid,
        baseAmountNaira: purchaseAmountNaira,
        sourceType: sourceType,
        sourceReference: sourceReference,
      );
    } catch (cashbackEarnError) {
      print('Cashback earn recording failed: $cashbackEarnError');
    }

    await _refreshCashbackBalance();
    return {'used': appliedCashbackUsed, 'earned': cashbackEarned};
  }

  Future<void> _fetchBillers() async {
    setState(() {
      isFetchingDataBillers = true;
      isFetchingCableBillers = true;
      isFetchingElectricityBillers = true;
    });

    try {
      // Fetch all biller categories in parallel
      await Future.wait([
        _fetchCategoryBillers('data', (list) {
          dataBillers = list;
          selectedDataNetwork = dataBillers.isNotEmpty
              ? (dataBillers[0]['attributes']?['slug'] as String?) ??
                    (dataBillers[0]['id'] as String)
              : null;
          isFetchingDataBillers = false;
          if (selectedDataNetwork != null) {
            _fetchProducts(dataBillers[0]['id'] as String, 'data');
          }
        }),
        _fetchCategoryBillers('television', (list) {
          cableBillers = list;
          selectedCableOperator = cableBillers.isNotEmpty
              ? (cableBillers[0]['attributes']?['slug'] as String?) ??
                    (cableBillers[0]['id'] as String)
              : null;
          isFetchingCableBillers = false;
          if (selectedCableOperator != null) {
            _fetchProducts(cableBillers[0]['id'] as String, 'television');
          }
        }),
        _fetchCategoryBillers('electricity', (list) {
          electricityBillers = list;
          selectedDisco = electricityBillers.isNotEmpty
              ? electricityBillers[0]['id']
              : null;
          isFetchingElectricityBillers = false;
        }),
      ]);
    } catch (e) {
      print('Error fetching billers: $e');
      setState(() {
        isFetchingDataBillers = false;
        isFetchingCableBillers = false;
        isFetchingElectricityBillers = false;
      });
    }
  }

  Future<void> _fetchCategoryBillers(
    String category,
    Function(List<Map<String, dynamic>>) setList,
  ) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('billers')
          .doc(category);
      final doc = await docRef.get();
      List<Map<String, dynamic>> billerList = [];
      if (doc.exists) {
        final data = doc.data();
        billerList = List<Map<String, dynamic>>.from(data?['data'] ?? []);
      }
      if (billerList.isEmpty) {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'listBillers',
        );
        final result = await callable.call({'category': category});
        final response = Map<String, dynamic>.from(result.data);
        print('$category Billers Response: $response');
        if (response['data'] is List) {
          billerList = (response['data'] as List)
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          await docRef.set({'data': billerList});
        }
      }
      setState(() {
        setList(billerList);
      });
    } catch (e) {
      print('Error fetching $category billers: $e');
    }
  }

  Future<void> _fetchProducts(String billerId, String category) async {
    if (category == 'data') {
      setState(() {
        isFetchingDataBundles = true;
      });
    } else if (category == 'television') {
      setState(() {
        isFetchingCableSubscriptions = true;
      });
    }

    try {
      final docId = '${category}_$billerId';
      final docRef = FirebaseFirestore.instance
          .collection('products')
          .doc(docId);
      final doc = await docRef.get();
      List<Map<String, dynamic>> productList = [];
      if (doc.exists) {
        final data = doc.data();
        productList = List<Map<String, dynamic>>.from(data?['data'] ?? []);
      }
      if (productList.isEmpty) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'getBillerProducts',
          );
          final result = await callable.call({'billerId': billerId});
          final response = Map<String, dynamic>.from(result.data);
          print('Products Response for $category: $response');
          if (response['data'] is List) {
            productList = (response['data'] as List)
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            await docRef.set({'data': productList});
          }
        } catch (e) {
          print(
            'Error calling getBillerProducts for $category with billerId=$billerId: $e',
          );
          rethrow;
        }
      }
      if (category == 'data') {
        setState(() {
          dataBundles = productList;
          selectedDataBundle = dataBundles.isNotEmpty
              ? dataBundles[0]['attributes']['slug']
              : null;
          isFetchingDataBundles = false;
        });
      } else if (category == 'television') {
        setState(() {
          cableSubscriptions = productList;
          selectedCablePackage = cableSubscriptions.isNotEmpty
              ? cableSubscriptions[0]['attributes']['slug']
              : null;
          if (selectedCablePackage != null && cableSubscriptions.isNotEmpty) {
            final selectedSub = cableSubscriptions.firstWhere(
              (sub) => sub['attributes']['slug'] == selectedCablePackage,
              orElse: () => cableSubscriptions[0],
            );
            cableAmountController.text =
                (selectedSub['attributes']['price']['minimumAmount'] / 100)
                    .toStringAsFixed(0);
          }
          isFetchingCableSubscriptions = false;
        });
      }
    } catch (e) {
      print('Error fetching products: $e');
      // Set empty lists to avoid loading forever
      if (category == 'data') {
        setState(() {
          dataBundles = [];
          selectedDataBundle = null;
          isFetchingDataBundles = false;
        });
      } else if (category == 'television') {
        setState(() {
          cableSubscriptions = [];
          selectedCablePackage = null;
          isFetchingCableSubscriptions = false;
        });
      }
    }
  }

  Future<String?> _showSelectionBottomSheet({
    required String title,
    required List<Map<String, dynamic>> items,
    required String? selectedId,
    required String Function(Map<String, dynamic>) idExtractor,
    required String Function(Map<String, dynamic>) nameExtractor,
    String? Function(Map<String, dynamic>)? subtitleExtractor,
  }) async {
    if (items.isEmpty) return null;

    // Declare searchQuery outside the builder to persist across rebuilds
    String searchQuery = '';

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          bottom: true,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final filteredItems = items.where((item) {
                final name = nameExtractor(item).toLowerCase();
                return name.contains(searchQuery.toLowerCase());
              }).toList();

              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
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
                          Text(
                            title,
                            style: const TextStyle(
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
                    // Search field
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        onChanged: (value) {
                          setModalState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // List of items
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Text(
                                'No results found',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredItems.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final id = idExtractor(item);
                                final name = nameExtractor(item);
                                final subtitle = subtitleExtractor?.call(item);
                                final isSelected = selectedId == id;

                                return GestureDetector(
                                  onTap: () => Navigator.pop(context, id),
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
                                        // optionally display provider/network icon
                                        Builder(
                                          builder: (context) {
                                            Widget iconWidget =
                                                const SizedBox.shrink();
                                            // Try exact logo lookup first (network/cable logos)
                                            final netLogo = _getNetworkLogo(id);
                                            if (netLogo.isNotEmpty) {
                                              return Image.network(
                                                netLogo,
                                                width: 24,
                                                height: 24,
                                                cacheWidth: 48,
                                                cacheHeight: 48,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                      Icons.image,
                                                      size: 24,
                                                    ),
                                              );
                                            }
                                            final cableLogo = _getCableLogo(id);
                                            if (cableLogo.isNotEmpty) {
                                              return Image.network(
                                                cableLogo,
                                                width: 24,
                                                height: 24,
                                                cacheWidth: 48,
                                                cacheHeight: 48,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(
                                                      Icons.image,
                                                      size: 24,
                                                    ),
                                              );
                                            }
                                            // Fall back to substring matching for local provider assets
                                            final lower = id.toLowerCase();
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
                                            } else if (lower.contains(
                                              'airtel',
                                            )) {
                                              iconWidget = Image.asset(
                                                'assets/airtime_providers/airtel.png',
                                                width: 24,
                                                height: 24,
                                              );
                                            } else if (lower.contains(
                                              '9mobile',
                                            )) {
                                              iconWidget = SvgPicture.asset(
                                                'assets/airtime_providers/9mobile.svg',
                                                width: 24,
                                                height: 24,
                                              );
                                            } else if (lower.contains('dstv')) {
                                              iconWidget = Image.asset(
                                                'assets/cable_providers/dstv.png',
                                                width: 24,
                                                height: 24,
                                              );
                                            } else if (lower.contains('gotv')) {
                                              iconWidget = Image.asset(
                                                'assets/cable_providers/gotv.png',
                                                width: 24,
                                                height: 24,
                                              );
                                            } else if (lower.contains(
                                              'startimes',
                                            )) {
                                              iconWidget = Image.asset(
                                                'assets/cable_providers/startimes.png',
                                                width: 24,
                                                height: 24,
                                              );
                                            }
                                            return iconWidget;
                                          },
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
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
                                              if (subtitle != null &&
                                                  subtitle.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  subtitle,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ],
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
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _buyData() async {
    if (mobileNumberController.text.isEmpty ||
        selectedDataNetwork == null ||
        selectedDataBundle == null ||
        userAccount == null) {
      showSimpleDialog('Please fill all fields', Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoadingData = true);

    var cashbackUsed = 0.0;
    String? cashbackFundingReference;
    final accountId = userAccount!['data']['id'].toString();

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final selectedBundle = dataBundles.firstWhere(
        (bundle) => bundle['attributes']['slug'] == selectedDataBundle,
      );
      final amount =
          (selectedBundle['attributes']['price']['minimumAmount'] / 100)
              .toInt();

      final selectedCashbackUsage = _selectedCashbackUsage(amount.toDouble());
      if (selectedCashbackUsage > 0) {
        cashbackFundingReference =
            await CashbackService.fundPurchaseFromCashbackReserve(
              toAccountId: accountId,
              amountNaira: selectedCashbackUsage,
              narration: 'Cashback funding for data purchase',
            );
        cashbackUsed = selectedCashbackUsage;
      }

      String formattedPhone = mobileNumberController.text;
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '234${formattedPhone.substring(1)}';
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'initiateBillPayment',
      );
      final result = await callable.call({
        'type': 'Data',
        'accountId': userAccount!['data']['id'],
        'accountType': userAccount!['data']['type'],
        'phoneNumber': formattedPhone,
        'amount': amount * 100,
        'productSlug': selectedDataBundle,
        'reference': Uuid().v4(),
      });
      final rawData = result.data;
      final response =
          json.decode(json.encode(rawData)) as Map<String, dynamic>;
      print('Buy Data Response: $response');

      final billData = response['data'] as Map<String, dynamic>?;
      if (billData == null) {
        showSimpleDialog('Invalid response', Colors.red);
        return;
      }
      final attributes = billData['attributes'] as Map<String, dynamic>;
      final status = (attributes['status'] as String? ?? '').toUpperCase();
      final isAccepted =
          status == 'COMPLETED' ||
          status == 'SUCCESSFUL' ||
          status == 'PENDING' ||
          status == 'PROCESSING' ||
          status == 'IN_PROGRESS';

      if (isAccepted) {
        final cashbackSettlement = await _settleCashbackAfterSuccess(
          uid: uid,
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          sourceType: 'data',
          sourceReference: billData['id'].toString(),
          purchaseAmountNaira: amount.toDouble(),
        );

        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': uid,
          'type': 'data',
          'amount': attributes['amount'] / 100,
          'phoneNumber': attributes['phoneNumber'],
          'currency': 'NGN',
          'reference': billData['id'],
          'status': status.toLowerCase(),
          'rawStatus': status,
          'network': attributes['detail']?['provider'] ?? 'Unknown',
          'bundle': attributes['detail']?['product'] ?? 'Unknown',
          'debitAmount': attributes['amount'],
          'commissionEarned': attributes['commissionAmount'] ?? 0,
          'cashbackUsed': cashbackSettlement['used'] ?? 0,
          'cashbackEarned': cashbackSettlement['earned'] ?? 0,
          'cashbackFundingReference': cashbackFundingReference,
          'createdAt': attributes['createdAt'],
          'fullData': attributes,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAtFirestore': FieldValue.serverTimestamp(),
        });

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => SuccessBottomSheet(
            actionText: "Done",
            title: "Data Purchase Successful",
            description: "Your data bundle has been purchased successfully.",
            cashbackAmount: cashbackSettlement['earned'],
          ),
        );
      } else {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for failed data purchase',
        );
        showSimpleDialog(
          'Failed to purchase data: ${attributes['failureReason'] ?? attributes['message'] ?? 'Unknown error'}',
          Colors.red,
        );
      }
    } catch (e) {
      try {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for data purchase error',
        );
      } catch (rollbackError) {
        print('Cashback rollback on data exception failed: $rollbackError');
      }
      if (e.toString().contains("an error processing the request")) {
        showSimpleDialog("Network Downtime", Colors.red);
        return;
      }
      print(e);
      showSimpleDialog('Error purchasing data: $e', Colors.red);
    } finally {
      setState(() => isLoadingData = false);
    }
  }

  Future<void> _buyCable() async {
    if (cardNumberController.text.isEmpty ||
        selectedCableOperator == null ||
        selectedCablePackage == null ||
        cableAmountController.text.isEmpty ||
        userAccount == null) {
      showSimpleDialog('Please fill all fields', Colors.red);
      return;
    }
    if (int.parse(cableAmountController.text) < 100) {
      showSimpleDialog("Amount should not be less than 100 Naira", Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoadingCable = true);
    var cashbackUsed = 0.0;
    String? cashbackFundingReference;
    final accountId = userAccount!['data']['id'].toString();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) {
      showSimpleDialog('User data not found', Colors.red);
      return;
    }
    String? phone = userDoc.data()?['phone'];
    if (phone == null || phone.isEmpty) {
      showSimpleDialog('Phone number not found', Colors.red);
      return;
    }
    // Normalize phone number
    if (phone.startsWith('0')) {
      phone = '234${phone.substring(1)}';
    } else {
      phone = '234$phone';
    }
    try {
      final amount = int.parse(cableAmountController.text);

      final selectedCashbackUsage = _selectedCashbackUsage(amount.toDouble());
      if (selectedCashbackUsage > 0) {
        cashbackFundingReference =
            await CashbackService.fundPurchaseFromCashbackReserve(
              toAccountId: accountId,
              amountNaira: selectedCashbackUsage,
              narration: 'Cashback funding for cable purchase',
            );
        cashbackUsed = selectedCashbackUsage;
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'initiateBillPayment',
      );
      final result = await callable.call({
        'type': 'Television',
        'accountId': userAccount!['data']['id'],
        'accountType': userAccount!['data']['type'],
        'smartCardNumber': cardNumberController.text,
        'amount': amount * 100,
        'productSlug': selectedCablePackage,
        'reference': Uuid().v4(),
        'phoneNumber': phone,
      });
      final rawData = result.data;
      final response =
          json.decode(json.encode(rawData)) as Map<String, dynamic>;
      print('Buy Cable Response: $response');

      final billData = response['data'] as Map<String, dynamic>?;
      if (billData == null) {
        showSimpleDialog('Invalid response', Colors.red);
        return;
      }
      final attributes = billData['attributes'] as Map<String, dynamic>;
      final status = (attributes['status'] as String? ?? '').toUpperCase();
      final isAccepted =
          status == 'COMPLETED' ||
          status == 'SUCCESSFUL' ||
          status == 'PENDING' ||
          status == 'PROCESSING' ||
          status == 'IN_PROGRESS';

      if (isAccepted) {
        final cashbackSettlement = await _settleCashbackAfterSuccess(
          uid: uid,
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          sourceType: 'cable',
          sourceReference: billData['id'].toString(),
          purchaseAmountNaira: amount.toDouble(),
        );

        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': uid,
          'type': 'cable',
          'amount': attributes['amount'] / 100,
          'serialNumber':
              attributes['smartCardNumber'] ??
              attributes['detail']?['smartCardNumber'],
          'currency': 'NGN',
          'reference': billData['id'],
          'status': status.toLowerCase(),
          'rawStatus': status,
          'network': attributes['detail']?['provider'] ?? 'Unknown',
          'plan': attributes['detail']?['product'] ?? 'Unknown',
          'debitAmount': attributes['amount'],
          'commissionEarned': attributes['commissionAmount'] ?? 0,
          'cashbackUsed': cashbackSettlement['used'] ?? 0,
          'cashbackEarned': cashbackSettlement['earned'] ?? 0,
          'cashbackFundingReference': cashbackFundingReference,
          'createdAt': attributes['createdAt'],
          'fullData': attributes,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAtFirestore': FieldValue.serverTimestamp(),
        });

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => SuccessBottomSheet(
            actionText: "Done",
            title: "Cable Subscription Successful",
            description:
                "Your cable subscription has been purchased successfully.",
            cashbackAmount: cashbackSettlement['earned'],
          ),
        );
      } else {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for failed cable purchase',
        );
        showSimpleDialog(
          'Failed to purchase cable: ${attributes['failureReason'] ?? attributes['message'] ?? 'Unknown error'}',
          Colors.red,
        );
      }
    } catch (e) {
      try {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for cable purchase error',
        );
      } catch (rollbackError) {
        print('Cashback rollback on cable exception failed: $rollbackError');
      }
      if (e.toString().contains("an error processing")) {
        showSimpleDialog("Network Downtime", Colors.red);
        return;
      }
      print(e);
      showSimpleDialog('Error purchasing cable: $e', Colors.red);
    } finally {
      setState(() => isLoadingCable = false);
    }
  }

  Future<void> _buyElectricity() async {
    if (meterNumberController.text.isEmpty ||
        selectedDisco == null ||
        electricityAmountController.text.isEmpty ||
        userAccount == null) {
      showSimpleDialog('Please fill all fields', Colors.red);
      return;
    }

    final amount = int.tryParse(electricityAmountController.text);
    if (amount == null || amount <= 0) {
      showSimpleDialog('Invalid amount', Colors.red);
      return;
    }
    if (amount < 900) {
      showSimpleDialog("Amount can't be less than ₦900", Colors.red);
      return;
    }

    // Verify PIN before proceeding
    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    setState(() => isLoadingElectricity = true);
    var cashbackUsed = 0.0;
    String? cashbackFundingReference;
    final accountId = userAccount!['data']['id'].toString();

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists) {
        showSimpleDialog('User data not found', Colors.red);
        return;
      }
      String? phone = userDoc.data()?['phone'];
      if (phone == null || phone.isEmpty) {
        showSimpleDialog('Phone number not found', Colors.red);
        return;
      }
      // Normalize phone number
      if (phone.startsWith('0')) {
        phone = '234${phone.substring(1)}';
      } else {
        phone = '234$phone';
      }

      final selectedCashbackUsage = _selectedCashbackUsage(amount.toDouble());
      if (selectedCashbackUsage > 0) {
        cashbackFundingReference =
            await CashbackService.fundPurchaseFromCashbackReserve(
              toAccountId: accountId,
              amountNaira: selectedCashbackUsage,
              narration: 'Cashback funding for electricity purchase',
            );
        cashbackUsed = selectedCashbackUsage;
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'initiateBillPayment',
      );
      final result = await callable.call({
        'type': 'Electricity',
        'accountId': userAccount!['data']['id'],
        'accountType': userAccount!['data']['type'],
        'meterAccountNumber': meterNumberController.text,
        'amount': amount * 100,
        'reference': Uuid().v4(),
        'phoneNumber': phone,
        'productSlug':
            electricityBillers.firstWhere(
                  (b) => b['id'] == selectedDisco,
                  orElse: () => {
                    'attributes': {'slug': 'N/A'},
                  },
                )['attributes']['slug']
                as String? ??
            'N/A',
      });

      final rawData = result.data;
      final response =
          json.decode(json.encode(rawData)) as Map<String, dynamic>;
      print('Buy Electricity Response: $response');

      final billData = response['data'] as Map<String, dynamic>?;
      if (billData == null) {
        showSimpleDialog('Invalid response', Colors.red);
        return;
      }
      final attributes = billData['attributes'] as Map<String, dynamic>;
      final status = (attributes['status'] as String? ?? '').toUpperCase();
      final isAccepted =
          status == 'COMPLETED' ||
          status == 'SUCCESSFUL' ||
          status == 'PENDING' ||
          status == 'PROCESSING' ||
          status == 'IN_PROGRESS';

      if (isAccepted) {
        final cashbackSettlement = await _settleCashbackAfterSuccess(
          uid: uid,
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          sourceType: 'electricity',
          sourceReference: billData['id'].toString(),
          purchaseAmountNaira: amount.toDouble(),
        );

        await FirebaseFirestore.instance.collection('transactions').add({
          'userId': uid,
          'type': 'electricity',
          'amount': attributes['amount'] / 100,
          'meterNumber': attributes['meterNumber'],
          'currency': 'NGN',
          'reference': billData['id'],
          'status': status.toLowerCase(),
          'rawStatus': status,
          'disco': attributes['detail']?['provider'] ?? 'Unknown',
          'token': attributes['detail']?['token'] ?? 'N/A',
          'units': attributes['detail']?['units'] ?? 'N/A',
          'debitAmount': attributes['amount'],
          'commissionEarned': attributes['commissionAmount'] ?? 0,
          'cashbackUsed': cashbackSettlement['used'] ?? 0,
          'cashbackEarned': cashbackSettlement['earned'] ?? 0,
          'cashbackFundingReference': cashbackFundingReference,
          'createdAt': attributes['createdAt'],
          'fullData': attributes,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAtFirestore': FieldValue.serverTimestamp(),
        });

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => SuccessBottomSheet(
            actionText: "Done",
            title: "Electricity Purchase Successful",
            description: "Your electricity bill has been paid successfully.",
            cashbackAmount: cashbackSettlement['earned'],
          ),
        );
      } else {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for failed electricity purchase',
        );
        showSimpleDialog(
          'Failed to purchase electricity: ${attributes['failureReason'] ?? attributes['message'] ?? 'Unknown error'}',
          Colors.red,
        );
      }
    } catch (e) {
      try {
        await _rollbackCashbackIfNeeded(
          cashbackUsed: cashbackUsed,
          accountId: accountId,
          narration: 'Cashback rollback for electricity purchase error',
        );
      } catch (rollbackError) {
        print(
          'Cashback rollback on electricity exception failed: $rollbackError',
        );
      }
      if (e.toString().contains("an error processing")) {
        showSimpleDialog("Network Downtime", Colors.red);
        return;
      }
      if (e.toString().contains("Precondition Failed") ||
          e.toString().contains("Product not found")) {
        showSimpleDialog("Meter number not found", Colors.red);
        return;
      }
      print(e);
      showSimpleDialog('Error purchasing electricity: $e', Colors.red);
    } finally {
      setState(() => isLoadingElectricity = false);
    }
  }

  Widget _buildDataBundleForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Buy Data Bundle",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          "Select Network",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        isFetchingDataBillers
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : GestureDetector(
                onTap: () async {
                  final id = await _showSelectionBottomSheet(
                    title: 'Select Network',
                    items: dataBillers,
                    selectedId: selectedDataNetwork,
                    idExtractor: (b) =>
                        (b['attributes']?['slug'] as String?) ??
                        (b['id'] as String),
                    nameExtractor: (b) =>
                        (b['attributes']?['name'] as String?) ?? 'Unknown',
                  );
                  if (id != null) {
                    setState(() {
                      selectedDataNetwork = id;
                      selectedDataBundle = null;
                    });
                    final biller = dataBillers.firstWhere(
                      (b) =>
                          ((b['attributes']?['slug'] as String?) ?? b['id']) ==
                          id,
                      orElse: () => {'id': id},
                    );
                    _fetchProducts(biller['id'] as String, 'data');
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (selectedDataNetwork != null) ...[
                        _iconForId(selectedDataNetwork!),
                        const SizedBox(width: 8),
                      ],
                      // let the name take up remaining space, then push arrow to end
                      Expanded(
                        child: Text(
                          dataBillers.firstWhere(
                                    (b) {
                                      final slug =
                                          b['attributes']?['slug'] as String?;
                                      return slug == selectedDataNetwork ||
                                          b['id'] == selectedDataNetwork;
                                    },
                                    orElse: () => {
                                      'attributes': {'name': 'N/A'},
                                    },
                                  )['attributes']['name']
                                  as String? ??
                              'Select network',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),

        const SizedBox(height: 16),
        const Text(
          "Select Data Volume",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        isFetchingDataBundles
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : GestureDetector(
                onTap: () async {
                  if (dataBundles.isEmpty) {
                    showSimpleDialog(
                      'This service is temporarily unavailable. Please check back later.',
                      Colors.orange,
                    );
                    return;
                  }
                  final id = await _showSelectionBottomSheet(
                    title: 'Select Data Volume',
                    items: dataBundles,
                    selectedId: selectedDataBundle,
                    idExtractor: (b) =>
                        (b['attributes']?['slug'] as String?) ?? '',
                    nameExtractor: (b) {
                      final name =
                          (b['attributes']?['name'] as String?) ?? 'N/A';
                      final price =
                          ((b['attributes']?['price']?['minimumAmount']
                                  as num?) ??
                              0) /
                          100;
                      return '$name - ₦${price.toStringAsFixed(0)}';
                    },
                  );
                  if (id != null) setState(() => selectedDataBundle = id);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          selectedDataBundle == null
                              ? 'Select bundle'
                              : dataBundles.firstWhere(
                                          (b) =>
                                              (b['attributes']?['slug']
                                                  as String?) ==
                                              selectedDataBundle,
                                          orElse: () => {
                                            'attributes': {
                                              'name': 'N/A',
                                              'price': {'minimumAmount': 0},
                                            },
                                          },
                                        )['attributes']['name']
                                        as String? ??
                                    'Select bundle',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 16),

        const Text(
          "Recipient Mobile Number",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        TextFormField(
          maxLength: 11,
          controller: mobileNumberController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: "",
            hintText: "Enter recipient mobile number",
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
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
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Network',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      dataBillers.firstWhere(
                                (b) {
                                  final slug =
                                      b['attributes']?['slug'] as String?;
                                  return slug == selectedDataNetwork ||
                                      b['id'] == selectedDataNetwork;
                                },
                                orElse: () => {
                                  'attributes': {'name': 'N/A'},
                                },
                              )['attributes']['name']
                              as String? ??
                          'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Mobile Number',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      mobileNumberController.text.isEmpty
                          ? 'N/A'
                          : mobileNumberController.text,
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Data Purchase',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      dataBundles.firstWhere(
                                (b) =>
                                    b['attributes']['slug'] ==
                                    selectedDataBundle,
                                orElse: () => {
                                  'attributes': {'name': 'N/A'},
                                },
                              )['attributes']['name']
                              as String? ??
                          'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildCashbackUsageBox(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: isLoadingData ? null : _buyData,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: isLoadingData
              ? CircularProgressIndicator(color: Colors.white)
              : const Text(
                  'Pay Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCableForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Buy Cable",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          "Select Operator",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        isFetchingCableBillers
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : GestureDetector(
                onTap: () async {
                  final id = await _showSelectionBottomSheet(
                    title: 'Select Operator',
                    items: cableBillers,
                    selectedId: selectedCableOperator,
                    idExtractor: (b) =>
                        (b['attributes']?['slug'] as String?) ??
                        (b['id'] as String),
                    nameExtractor: (b) =>
                        (b['attributes']?['name'] as String?) ?? 'Unknown',
                  );
                  if (id != null) {
                    setState(() {
                      selectedCableOperator = id;
                      selectedCablePackage = null;
                      cableAmountController.text = '';
                    });
                    final biller = cableBillers.firstWhere(
                      (b) =>
                          ((b['attributes']?['slug'] as String?) ?? b['id']) ==
                          id,
                      orElse: () => {'id': id},
                    );
                    _fetchProducts(biller['id'] as String, 'television');
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          cableBillers.firstWhere(
                                    (b) {
                                      final slug =
                                          b['attributes']?['slug'] as String?;
                                      return slug == selectedCableOperator ||
                                          b['id'] == selectedCableOperator;
                                    },
                                    orElse: () => {
                                      'attributes': {'name': 'N/A'},
                                    },
                                  )['attributes']['name']
                                  as String? ??
                              'Select operator',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 16),
        const Text(
          "Select Package",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        isFetchingCableSubscriptions
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : GestureDetector(
                onTap: () async {
                  if (cableSubscriptions.isEmpty) {
                    showSimpleDialog(
                      'This service is temporarily unavailable. Please check back later.',
                      Colors.orange,
                    );
                    return;
                  }
                  final id = await _showSelectionBottomSheet(
                    title: 'Select Package',
                    items: cableSubscriptions,
                    selectedId: selectedCablePackage,
                    idExtractor: (b) =>
                        (b['attributes']?['slug'] as String?) ?? '',
                    nameExtractor: (b) {
                      final name =
                          (b['attributes']?['name'] as String?) ?? 'N/A';
                      final price =
                          ((b['attributes']?['price']?['minimumAmount']
                                  as num?) ??
                              0) /
                          100;
                      return '$name - ₦${price.toStringAsFixed(0)}';
                    },
                  );
                  if (id != null) {
                    setState(() {
                      selectedCablePackage = id;
                      final selectedSub = cableSubscriptions.firstWhere(
                        (sub) => (sub['attributes']?['slug'] as String?) == id,
                        orElse: () => null as dynamic,
                      );
                      cableAmountController.text =
                          ((selectedSub['attributes']['price']['minimumAmount']
                                      as num) /
                                  100)
                              .toStringAsFixed(0);
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          cableSubscriptions.firstWhere(
                                    (s) =>
                                        (s['attributes']?['slug'] as String?) ==
                                        selectedCablePackage,
                                    orElse: () => {
                                      'attributes': {'name': 'N/A'},
                                    },
                                  )['attributes']['name']
                                  as String? ??
                              'Select package',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 16),
        const Text("Card Number"),
        const SizedBox(height: 4),
        TextFormField(
          controller: cardNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: "Enter card number",
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
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
        const SizedBox(height: 16),
        const Text("Amount"),
        const SizedBox(height: 4),
        TextFormField(
          controller: cableAmountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: "Enter amount",
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
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
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Operator',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      cableBillers.firstWhere(
                                (b) {
                                  final slug =
                                      b['attributes']?['slug'] as String?;
                                  return slug == selectedCableOperator ||
                                      b['id'] == selectedCableOperator;
                                },
                                orElse: () => {
                                  'attributes': {'name': 'N/A'},
                                },
                              )['attributes']['name']
                              as String? ??
                          'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Package',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      cableSubscriptions.firstWhere(
                                (s) =>
                                    s['attributes']['slug'] ==
                                    selectedCablePackage,
                                orElse: () => {
                                  'attributes': {'name': 'N/A'},
                                },
                              )['attributes']['name']
                              as String? ??
                          'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Card Number',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      cardNumberController.text.isEmpty
                          ? 'N/A'
                          : cardNumberController.text,
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      cableAmountController.text.isEmpty
                          ? 'N/A'
                          : '₦${cableAmountController.text}',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildCashbackUsageBox(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: isLoadingCable ? null : _buyCable,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: isLoadingCable
              ? CircularProgressIndicator(color: Colors.white)
              : const Text(
                  'Pay Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        SizedBox(height: 30),
      ],
    );
  }

  Widget _buildElectricityForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Buy Electricity",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          "Select Disco",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        isFetchingElectricityBillers
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : GestureDetector(
                onTap: () async {
                  final id = await _showSelectionBottomSheet(
                    title: 'Select Disco',
                    items: electricityBillers,
                    selectedId: selectedDisco,
                    idExtractor: (b) => b['id'] as String,
                    nameExtractor: (b) =>
                        (b['attributes']?['name'] as String?) ?? 'Unknown',
                  );
                  if (id != null) setState(() => selectedDisco = id);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          electricityBillers.firstWhere(
                                    (b) => b['id'] == selectedDisco,
                                    orElse: () => {
                                      'attributes': {'name': 'N/A'},
                                    },
                                  )['attributes']['name']
                                  as String? ??
                              'Select disco',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
        const SizedBox(height: 16),

        const SizedBox(height: 16),
        const Text(
          "Meter Number",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: meterNumberController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: "Enter meter number",
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
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
        const SizedBox(height: 16),
        const Text(
          "Amount",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: electricityAmountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 16, bottom: 16),
              child: Text(
                "₦",
                style: TextStyle(
                  color: Colors.grey[500],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            hintText: "Enter amount",
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
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
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Disco',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      electricityBillers.firstWhere(
                                (b) => b['id'] == selectedDisco,
                                orElse: () => {
                                  'attributes': {'name': 'N/A'},
                                },
                              )['attributes']['name']
                              as String? ??
                          'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Meter Number',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      meterNumberController.text.isEmpty
                          ? 'N/A'
                          : meterNumberController.text,
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      electricityAmountController.text.isEmpty
                          ? 'N/A'
                          : '₦${electricityAmountController.text}',
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildCashbackUsageBox(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: isLoadingElectricity ? null : _buyElectricity,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: isLoadingElectricity
              ? CircularProgressIndicator(color: Colors.white)
              : const Text(
                  'Pay Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCashbackUsageBox() {
    return Container(
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
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Use cashback for this payment',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black54,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          "Pay Bill",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Your Bills",
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 10),
            RadioListTile<String>(
              value: 'electricity',
              groupValue: selectedBill,
              onChanged: (value) => setState(() => selectedBill = value),
              title: const Text('Electricity'),
              secondary: const Icon(Icons.bolt_outlined, color: Colors.green),
              controlAffinity: ListTileControlAffinity.trailing,
              activeColor: Colors.blue,
            ),
            RadioListTile<String>(
              value: 'data_bundle',
              groupValue: selectedBill,
              onChanged: (value) => setState(() => selectedBill = value),
              title: const Text('Data Bundle'),
              secondary: const Icon(Icons.phone_android, color: Colors.purple),
              controlAffinity: ListTileControlAffinity.trailing,
              activeColor: Colors.blue,
            ),
            RadioListTile<String>(
              value: 'cable',
              groupValue: selectedBill,
              onChanged: (value) => setState(() => selectedBill = value),
              title: const Text('Cable'),
              secondary: const Icon(Icons.tv, color: Colors.pink),
              controlAffinity: ListTileControlAffinity.trailing,
              activeColor: Colors.blue,
            ),
            const SizedBox(height: 30),
            if (selectedBill == 'data_bundle') _buildDataBundleForm(),
            if (selectedBill == 'cable') _buildCableForm(),
            if (selectedBill == 'electricity') _buildElectricityForm(),
          ],
        ),
      ),
    );
  }

  String _getNetworkLogo(String identifier) {
    switch (identifier) {
      case 'mtn-data-ng':
        return 'https://upload.wikimedia.org/wikipedia/commons/2/2a/MTN_2022_logo.svg';
      case 'airtel-data-ng':
        return 'https://upload.wikimedia.org/wikipedia/commons/d/da/Airtel_Africa_logo.svg';
      case 'glo-data-ng':
        return 'https://upload.wikimedia.org/wikipedia/commons/8/86/Glo_button.png';
      case '9mobile-data-ng':
        return 'https://cdn.punchng.com/wp-content/uploads/2017/07/19170207/9Mobile-Telecom-Logo.jpg';
      case 'smile-data-ng':
        return 'https://upload.wikimedia.org/wikipedia/en/4/4f/Smile_Communications_Logo.png';
      case 'spectranet-data-ng':
        return 'https://upload.wikimedia.org/wikipedia/en/7/7a/Spectranet_Logo.png';
      default:
        return '';
    }
  }

  String _getCableLogo(String identifier) {
    switch (identifier) {
      case 'dstv-ng':
        return 'https://static.wikia.nocookie.net/logopedia/images/6/63/DStv_2010.png/revision/latest/scale-to-width-down/300';
      case 'gotv-ng':
        return 'https://upload.wikimedia.org/wikipedia/commons/9/98/GOtv_logo1.png';
      default:
        return '';
    }
  }

  /// Utility to return a widget representing a network/cable/airtime icon
  /// based on a given identifier string.  This mirrors the logic used in
  /// [_showSelectionBottomSheet] so that we can show the same image in the
  /// dropdowns themselves.
  Widget _iconForId(String id) {
    final netLogo = _getNetworkLogo(id);
    if (netLogo.isNotEmpty) {
      return Image.network(
        netLogo,
        width: 24,
        height: 24,
        cacheWidth: 48,
        cacheHeight: 48,
        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 24),
      );
    }
    final cableLogo = _getCableLogo(id);
    if (cableLogo.isNotEmpty) {
      return Image.network(
        cableLogo,
        width: 24,
        height: 24,
        cacheWidth: 48,
        cacheHeight: 48,
        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 24),
      );
    }
    // Fall back to local assets by checking the lowercase string.
    final lower = id.toLowerCase();
    if (lower.contains('mtn')) {
      return SvgPicture.asset(
        'assets/airtime_providers/mtn.svg',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('glo')) {
      return Image.asset(
        'assets/airtime_providers/glo.png',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('airtel')) {
      return Image.asset(
        'assets/airtime_providers/airtel.png',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('9mobile')) {
      return SvgPicture.asset(
        'assets/airtime_providers/9mobile.svg',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('dstv')) {
      return Image.asset(
        'assets/cable_providers/dstv.png',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('gotv')) {
      return Image.asset(
        'assets/cable_providers/gotv.png',
        width: 24,
        height: 24,
      );
    } else if (lower.contains('startimes')) {
      return Image.asset(
        'assets/cable_providers/startimes.png',
        width: 24,
        height: 24,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    mobileNumberController.dispose();
    cardNumberController.dispose();
    cableAmountController.dispose();
    meterNumberController.dispose();
    electricityAmountController.dispose();
    super.dispose();
  }
}
