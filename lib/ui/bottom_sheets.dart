import 'dart:math' as math;

import 'package:card_app/account_statement/account_statement.dart';
import 'package:card_app/card_channels/card_channels.dart';
import 'package:card_app/card_channels/card_merchants.dart';
import 'package:card_app/card_channels/subscriptions_page.dart';
import 'package:card_app/card_channels/nfc_pos_sheet.dart';
import 'package:card_app/card_details/card_details.dart';
import 'package:card_app/change_pin/change_pin.dart';
import 'package:card_app/top_up/fund_card.dart';
import 'package:card_app/transfer/choose_transfer_type_page.dart';
import 'package:card_app/ui/keypad.dart';
import 'package:card_app/ui/receipt_page.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:card_app/cards/card_design.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class CardDetailsBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  final int initialIndex;
  String selectedCurrency;

  CardDetailsBottomSheet({
    super.key,
    required this.cards,
    required this.selectedCurrency,
    required this.initialIndex,
  });

  @override
  State<CardDetailsBottomSheet> createState() => _CardDetailsBottomSheetState();
}

class _CardDetailsBottomSheetState extends State<CardDetailsBottomSheet> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<String, List<dynamic>> _transactionsMap = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: 0.9,
    );
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final duration = const Duration(milliseconds: 200);
      _pageController
          .animateTo(
            _currentIndex + 0.2,
            duration: duration,
            curve: Curves.easeOut,
          )
          .then((_) {
            _pageController.animateTo(
              _currentIndex.toDouble(),
              duration: duration,
              curve: Curves.easeIn,
            );
          });
    });
    _fetchTransactions(widget.cards[widget.initialIndex]['card_id']);
  }

  String _getCardCurrency(Map<String, dynamic> card) {
    final raw = card['selectedCurrency']?.toString() ?? '';
    final match = RegExp(r'\(([A-Z]{3})\)').firstMatch(raw.toUpperCase());
    if (match != null) return match.group(1)!;
    if (raw.toUpperCase().contains('USD')) return 'USD';
    return 'NGN';
  }

  Future<void> _fetchTransactions(String? cardId) async {
    if (cardId == null) return;
    if (_transactionsMap.containsKey(cardId)) return;
    final card = widget.cards.firstWhere(
      (c) => c['card_id'] == cardId,
      orElse: () => {},
    );
    final currency = _getCardCurrency(card);
    try {
      if (currency == 'USD') {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'bridgecardGetCardTransactions',
        );
        final response = await callable.call({'card_id': cardId});
        if (response.data['status'] == 'success') {
          setState(() {
            _transactionsMap[cardId] = List.from(
              response.data['data']['transactions'] ?? [],
            );
          });
        } else {
          setState(() => _transactionsMap[cardId] = []);
        }
      } else {
        // NGN: read from Firestore users/{uid}/transactions (same source as transaction history)
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          setState(() => _transactionsMap[cardId] = []);
          return;
        }
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .where('cardId', isEqualTo: cardId)
            .orderBy('timestamp', descending: true)
            .limit(20)
            .get();
        final list = snap.docs.map((d) => d.data()).toList();
        // Prepend a synthetic 'Card Created' entry so it always appears in activity
        final cardCreatedAt = card['createdAt'];
        String createdAtStr = '';
        if (cardCreatedAt is Timestamp) {
          createdAtStr = cardCreatedAt.toDate().toIso8601String();
        }
        final syntheticEntry = <String, dynamic>{
          'type': 'CREDIT',
          'description': 'Card Created',
          'amount': 0,
          'currency': 'NGN',
          'createdAt': createdAtStr,
        };
        setState(() {
          _transactionsMap[cardId] = [...list, syntheticEntry];
        });
      }
    } catch (e) {
      print('Error fetching transactions for $cardId: $e');
      setState(() => _transactionsMap[cardId] = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double viewportWidth = MediaQuery.of(context).size.width;
    const double cardAspectRatio = 1.6;
    final double pageHeight = (viewportWidth * 0.9) / cardAspectRatio;
    final String? currentCardId =
        widget.cards[_currentIndex]['card_id']?.toString();
    final List<dynamic> transactions =
        currentCardId != null ? (_transactionsMap[currentCardId] ?? []) : [];
    final bool isLoading = currentCardId != null &&
        !_transactionsMap.containsKey(currentCardId);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: pageHeight,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.cards.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                        _fetchTransactions(widget.cards[index]['card_id']);
                      },
                      itemBuilder: (context, index) {
                        var card = widget.cards[index];
                        var details = card['details'] ?? {};

                        // Resolve design template
                        final String brandStr =
                            (details['brand'] ?? card['scheme'] ?? 'Visa')
                                .toString()
                                .toLowerCase();
                        final String brandLabel = brandStr.contains('master')
                            ? 'MasterCard'
                            : brandStr.contains('verve')
                                ? 'Verve'
                                : brandStr.contains('afrigo')
                                    ? 'AfriGo'
                                    : 'Visa';
                        final String currencyCode = _getCardCurrency(card);
                        final String designId = card['design']?.toString() ?? '';
                        CardTemplate cardTemplate =
                            getTemplateById(designId) ??
                            getTemplatesForCard(brandLabel, currencyCode).first;

                        final String cardFormFactor =
                            card['type']?.toString() ?? 'Virtual';
                        final String formFactorLabel =
                            cardFormFactor[0].toUpperCase() +
                            cardFormFactor.substring(1).toLowerCase();

                        // Card number / masked pan
                        final String maskedPan =
                            details['masked_pan']?.toString() ?? '';
                        final String last4 =
                            details['last_4']?.toString() ??
                            (maskedPan.length >= 4
                                ? maskedPan.substring(maskedPan.length - 4)
                                : '••••');
                        String formattedNumber;
                        if (maskedPan.isNotEmpty) {
                          formattedNumber = '•••• •••• •••• $last4';
                        } else {
                          final rawNumber =
                              details['card_number']?.toString() ??
                              '0000000000000000';
                          formattedNumber = rawNumber
                              .replaceAllMapped(
                                RegExp(r'.{4}'),
                                (match) => '${match.group(0)} ',
                              )
                              .trim();
                        }

                        String cardName =
                            details['card_name']?.toString() ??
                            details['customer_name']?.toString() ??
                            card['nameOnCard']?.toString() ??
                            'CARD HOLDER';
                        // Show branded holder name for anonymous cards in card UI
                        final cardType = (card['type']?.toString() ?? '').toLowerCase();
                        if (cardType == 'anonymous') {
                          cardName = 'PadiPay';
                        }

                        String expiryMonth =
                            (details['expiry_month']?.toString() ?? 'MM')
                                .padLeft(2, '0');
                        String expiryYear =
                            details['expiry_year']?.toString() ?? 'YY';
                        String expiry = expiryYear.length >= 2
                            ? '$expiryMonth/${expiryYear.substring(expiryYear.length - 2)}'
                            : '$expiryMonth/$expiryYear';

                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            double value = 1.0;
                            if (_pageController.position.haveDimensions) {
                              value = (_pageController.page! - index).abs();
                              value = (1 - (value * 0.1)).clamp(0.9, 1.0);
                            }
                            return Transform.scale(scale: value, child: child);
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PadiCardWidget(
                                template: cardTemplate,
                                brand: brandLabel,
                                currency: currencyCode,
                                cardHolder: cardName,
                                cardNumber: formattedNumber,
                                expiry: expiry,
                                cardType: formFactorLabel,
                              ),
                              // Eye icon — PIN/biometric-gated secure card detail reveal
                              Positioned(
                                bottom: (pageHeight * 0.63) * 0.38,
                                right: MediaQuery.of(context).size.width * 0.09,
                                child: GestureDetector(
                                  onTap: () async {
                                    final cId = widget.cards[index]['card_id']?.toString();
                                    if (cId == null) return;
                                    final cardPin = widget.cards[index]['pin']?.toString();
                                    final cardDetails = widget.cards[index]['details'] as Map<String, dynamic>? ?? {};
                                    final expM = (cardDetails['expiry_month'] ?? widget.cards[index]['expiry_month'])?.toString();
                                    final expY = (cardDetails['expiry_year'] ?? widget.cards[index]['expiry_year'])?.toString();
                                    final result = await showModalBottomSheet<String?>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const EnterPasscodeSheetForTransaction(),
                                    );
                                    if (result == null) return;
                                    if (result == 'BIOMETRIC_SUCCESS' || result == cardPin) {
                                      if (!context.mounted) return;
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        enableDrag: false,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => SudoSecureCardSheet(
                                          cardId: cId,
                                          expiryMonth: expM,
                                          expiryYear: expY,
                                          cardPin: widget.cards[index]['pin']?.toString(),
                                        ),
                                      );
                                    } else {
                                      showSimpleDialog('Incorrect PIN', Colors.red);
                                    }
                                  },
                                  child: const Icon(
                                    Icons.visibility,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: widget.cards.asMap().entries.map((e) {
                      return Container(
                        height: e.key == _currentIndex ? 25 : 18,
                        width: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: e.key == _currentIndex
                              ? Colors.white
                              : Colors.grey[500],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        navigateTo(context, SendFundsPage());
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          top: 7,
                          bottom: 7,
                          left: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(55),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              padding: EdgeInsets.only(left: 0, right: 5),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  FontAwesomeIcons.paperPlane,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Withdraw",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        final currentCard = widget.cards[_currentIndex];
                        navigateTo(
                          context,
                          FundCard(
                            card: currentCard,
                            currency: widget.selectedCurrency,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          top: 7,
                          bottom: 7,
                          left: 8,
                        ),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(55),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Image.asset(
                                  "assets/deposit_card.png",
                                  width: 25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Deposit",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (context) => MoreActionsBottomSheet(card: widget.cards[_currentIndex]),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Icon(Icons.more_vert, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey.withAlpha(50),
                            ),
                          ),
                          child: isLoading
                              ? Center(child: CircularProgressIndicator())
                              : transactions.isEmpty
                              ? Center(child: Text('No recent activity'))
                              : ListView.builder(
                                  itemCount: transactions.length,
                                  itemBuilder: (context, idx) {
                                    final trans =
                                        transactions[idx] as Map? ?? {};
                                    // Support both Bridgecard (USD) and Firestore Sudo (NGN) shapes
                                    final String type =
                                        trans['card_transaction_type']?.toString() ??
                                        trans['type']?.toString() ??
                                        'DEBIT';
                                    final String typeStr = type.toLowerCase();
                                    final bool isDeclinedTx = typeStr == 'card_declined';
                                    final bool isRefundTx = typeStr == 'card_refund';
                                    final bool isCredit = typeStr == 'credit' || typeStr == 'deposit' || isRefundTx;
                                    final String sign = (isCredit && !isDeclinedTx) ? '+' : '-';
                                    // Amount: Bridgecard sends kobo string, Firestore Sudo docs store naira number
                                    double amt = 0;
                                    final rawAmt = trans['amount'];
                                    if (rawAmt is num) {
                                      amt = rawAmt.toDouble();
                                      // Bridgecard USD transactions have 'card_transaction_type'; Firestore docs don't
                                      if (trans['card_transaction_type'] != null) {
                                        amt /= 100; // Bridgecard is in kobo
                                      }
                                    } else if (rawAmt != null) {
                                      amt = double.tryParse(rawAmt.toString()) ?? 0.0;
                                      amt /= 100;
                                    }
                                    final String currencySym =
                                        (trans['currency']?.toString() ?? '') == 'USD'
                                            ? '\$'
                                            : '₦';
                                    final formatter = NumberFormat('#,###.00', 'en_US');
                                    final String amountStr =
                                        isDeclinedTx ? '$currencySym${formatter.format(amt)}'
                                        : '$sign$currencySym${formatter.format(amt)}';
                                    final Color color = isDeclinedTx
                                        ? Colors.red
                                        : isRefundTx || isCredit
                                            ? Colors.green
                                            : const Color(0xFFE65100);
                                    final String statusLabel = isDeclinedTx
                                        ? 'Declined'
                                        : isRefundTx
                                            ? 'Refunded'
                                            : 'Successful';
                                    final Color statusColor = color;
                                    // Title: Firestore docs use 'merchant', Bridgecard uses 'description'/'narration'
                                    final String title =
                                        trans['merchant']?.toString() ??
                                        trans['description']?.toString() ??
                                        trans['narration']?.toString() ??
                                        trans['type']?.toString() ??
                                        'Transaction';
                                    // Date: Firestore docs use Timestamp, Bridgecard uses string fields
                                    String formattedDate = '';
                                    final rawTs = trans['timestamp'];
                                    if (rawTs is Timestamp) {
                                      formattedDate = DateFormat('HH:mm • MMMM d, yyyy').format(rawTs.toDate());
                                    } else {
                                      final String dateStr =
                                          trans['transaction_date']?.toString() ??
                                          trans['createdAt']?.toString() ??
                                          trans['updatedAt']?.toString() ??
                                          '';
                                      final DateTime? dtUtc =
                                          DateTime.tryParse(dateStr)?.toUtc() ??
                                          _parseUtcDate(dateStr);
                                      formattedDate = dtUtc != null
                                          ? DateFormat('HH:mm • MMMM d, yyyy').format(dtUtc.toLocal())
                                          : dateStr;
                                    }
                                    return _buildTransactionRow(
                                      amountStr,
                                      title.toString(),
                                      formattedDate,
                                      color,
                                      statusLabel: statusLabel,
                                      statusColor: statusColor,
                                      onTap: () {
                                        final reference =
                                            trans['reference']?.toString() ??
                                            trans['transactionId']?.toString() ??
                                            '';
                                        navigateTo(
                                          context,
                                          ReceiptPage(
                                            reference: reference,
                                            cardData: typeStr == 'card_debit' || typeStr == 'card_declined' || typeStr == 'card_refund'
                                                ? Map<String, dynamic>.from(trans)
                                                : null,
                                          ),
                                          type: NavigationType.push,
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _parseUtcDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final parts = dateStr.split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;
      return DateTime.utc(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (e) {
      print('Error parsing date: $e');
      return null;
    }
  }

  Widget _buildTransactionRow(
    String amount,
    String title,
    String date,
    Color amountColor, {
    VoidCallback? onTap,
    String? statusLabel,
    Color? statusColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.grey),
                      Text(
                        date,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: amountColor,
                  ),
                ),
                if (statusLabel != null) ...[  
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor ?? amountColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class MoreActionsBottomSheet extends StatefulWidget {
  final Map<String, dynamic> card;
  const MoreActionsBottomSheet({super.key, required this.card});

  @override
  State<MoreActionsBottomSheet> createState() => _MoreActionsBottomSheetState();
}

class _MoreActionsBottomSheetState extends State<MoreActionsBottomSheet> {
  bool _isFrozen = false;
  bool _freezeLoading = false;
  bool _terminateLoading = false;

  bool get _isPhysicalCard =>
      (widget.card['type']?.toString().toLowerCase() ?? '') == 'physical';

  Map<String, dynamic> get _physicalTracking {
    final raw = widget.card['physicalCardTracking'] ?? widget.card['tracking'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  bool get _isDelivered {
    final status = _physicalTracking['status']?.toString().toLowerCase() ?? '';
    return widget.card['physicalCardDelivered'] == true || status == 'delivered';
  }

  bool get _isActivated => widget.card['physicalCardActivated'] == true;

  @override
  void initState() {
    super.initState();
    _isFrozen = widget.card['frozen'] == true;
  }

  Future<void> _toggleFreeze(bool val) async {
    final cardId = widget.card['card_id']?.toString();
    final firestoreDocId = (widget.card['firestoreDocId'] ?? widget.card['id'])?.toString();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (cardId == null || userId == null) {
      showSimpleDialog('Card ID not found', Colors.red);
      return;
    }

    setState(() => _freezeLoading = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('sudoUpdateCard').call({
        'cardId': cardId,
        'status': val ? 'inactive' : 'active',
      });

      // Persist frozen flag to Firestore card doc
      if (firestoreDocId != null && firestoreDocId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('cards')
            .doc(firestoreDocId)
            .update({'frozen': val});
      }

      // Update in-memory card map so the next bottom sheet open reflects the new state
      widget.card['frozen'] = val;

      if (mounted) setState(() => _isFrozen = val);
    } catch (e) {
      if (mounted) showSimpleDialog('Failed to ${val ? 'freeze' : 'unfreeze'} card: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _freezeLoading = false);
    }
  }

  Future<void> _terminateCard() async {
    final cardId = widget.card['card_id']?.toString();
    final firestoreDocId = (widget.card['firestoreDocId'] ?? widget.card['id'])?.toString();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (cardId == null || userId == null) {
      showSimpleDialog('Card ID not found', Colors.red);
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminate Card'),
        content: const Text(
          'Are you sure you want to terminate this card?\n\nThis action is permanent and cannot be undone. The card will be deactivated immediately and all future transactions will be declined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _terminateLoading = true);
    try {
      // Tell Sudo to terminate the card
      await FirebaseFunctions.instance.httpsCallable('sudoUpdateCard').call({
        'cardId': cardId,
        'status': 'terminated',
      });

      // Mark as deleted in Firestore so it won't show in the cards page
      if (firestoreDocId != null && firestoreDocId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('cards')
            .doc(firestoreDocId)
            .update({'deleted': true, 'terminatedAt': FieldValue.serverTimestamp()});
      }

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        showSimpleDialog('Your card has been terminated.', Colors.green);
      }
    } catch (e) {
      if (mounted) showSimpleDialog('Failed to terminate card: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _terminateLoading = false);
    }
  }

  void _showTrackPhysicalCard() {
    final tracking = _physicalTracking;
    final status = tracking['status']?.toString() ?? 'pending';
    final courier = tracking['courier']?.toString() ?? 'Not set';
    final trackingNumber = tracking['trackingNumber']?.toString() ?? 'Not set';
    final etaDate = tracking['etaDate']?.toString() ?? 'Not set';
    final note = tracking['note']?.toString() ?? 'No update yet';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Track Physical Card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${status.toUpperCase()}'),
            const SizedBox(height: 8),
            Text('Courier: $courier'),
            const SizedBox(height: 6),
            Text('Tracking No: $trackingNumber'),
            const SizedBox(height: 6),
            Text('ETA: $etaDate'),
            const SizedBox(height: 10),
            Text('Note: $note'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _activatePhysicalCardHandler() {
    // TODO: Implement physical card activation call when backend handler is ready.
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.black54,
                    size: 25,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16),
                const Text(
                  'More Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 40),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Account Statement'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                navigateTo(context, AccountStatementPage(card: widget.card));
              },
            ),
            ListTile(
              leading: const Icon(Icons.contactless_outlined),
              title: const Text('Pay at POS (Tap to Pay)'),
              subtitle: const Text('Use your phone at contactless payment terminals',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                final cardId = widget.card['card_id']?.toString();
                if (cardId == null || cardId.isEmpty) {
                  showSimpleDialog('Card is not yet active', Colors.red);
                  return;
                }
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => NfcPosSheet(
                    cardId: cardId,
                    cardholderName: widget.card['nameOnCard']?.toString() ??
                        widget.card['cardHolderName']?.toString(),
                    lastFour: widget.card['last4']?.toString() ??
                        widget.card['lastFour']?.toString(),
                    expiryDate: widget.card['expiryMonth'] != null &&
                            widget.card['expiryYear'] != null
                        ? '${widget.card['expiryMonth']}/${widget.card['expiryYear']}'
                        : widget.card['expiryDate']?.toString(),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(FontAwesomeIcons.snowflake, size: 20),
                      SizedBox(width: 12),
                      Text('Freeze Card', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                  FlutterSwitch(
                    width: 50,
                    height: 25,
                    toggleSize: 20,
                    borderRadius: 20,
                    padding: 3,
                    value: _isFrozen,
                    activeColor: primaryColor,
                    inactiveColor: Colors.grey.shade300,
                    onToggle: _freezeLoading ? (_) {} : _toggleFreeze,
                  ),
                  if (_freezeLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Change Card Channels'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                navigateTo(context, ChangeCardChannelsPage(card: widget.card));
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Manage Merchants'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                navigateTo(context, ManageMerchantsPage(card: widget.card));
              },
            ),
            ListTile(
              leading: const Icon(Icons.subscriptions_outlined),
              title: const Text('Subscriptions'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                navigateTo(context, SubscriptionsPage(card: widget.card));
              },
            ),
            if (_isPhysicalCard)
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('Track Physical Card'),
                subtitle: Text(
                  'Status: ${( _physicalTracking['status']?.toString() ?? 'pending').toUpperCase()}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 20),
                onTap: _showTrackPhysicalCard,
              ),
            if (_isPhysicalCard)
              ListTile(
                leading: Icon(
                  _isActivated ? Icons.check_circle : Icons.power_settings_new,
                  color: _isActivated ? Colors.green : Colors.black87,
                ),
                title: Text(_isActivated ? 'Physical Card Activated' : 'Activate Physical Card'),
                subtitle: Text(
                  _isDelivered
                      ? 'Tap to activate this delivered card'
                      : 'Activation becomes available when delivery is marked completed',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 20),
                onTap: _isDelivered && !_isActivated
                    ? _activatePhysicalCardHandler
                    : null,
              ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Change PIN'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: () {
                final cardId = widget.card['card_id']?.toString();
                final currentPin = widget.card['pin']?.toString();
                if (cardId == null) {
                  showSimpleDialog('Card ID not found', Colors.red);
                  return;
                }
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => ChangeSudoCardPinSheet(
                    cardId: cardId,
                    currentPin: currentPin ?? '',
                  ),
                );
              },
            ),
            ListTile(
              leading: _terminateLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                    )
                  : const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Terminate Card',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 20),
              onTap: _terminateLoading ? null : _terminateCard,
            ),
          ],
        ),
      ),
    );
  }
}

class EnterPasscodeSheet extends StatefulWidget {
  const EnterPasscodeSheet({super.key});
  @override
  _EnterPasscodeSheetState createState() => _EnterPasscodeSheetState();
}

class _EnterPasscodeSheetState extends State<EnterPasscodeSheet> {
  String pin = '';
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Enter Account Passcode',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Enter your 4-digit passcode to view card details',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isCurrent = index == pin.length;
                  bool isEntered = index < pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isEntered
                          ? Text(
                              pin[index],
                              style: const TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (pin.isNotEmpty) {
                        pin = pin.substring(0, pin.length - 1);
                      }
                    } else if (pin.length < 4) {
                      pin += val;
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: pin.length == 4
                      ? () {
                          Navigator.pop(context, pin);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pin.length == 4 ? Colors.blue : Colors.grey,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CreatePasscodeSheet extends StatefulWidget {
  Map<String, dynamic> card = {};
  CreatePasscodeSheet({super.key, required this.card});
  @override
  _CreatePasscodeSheetState createState() => _CreatePasscodeSheetState();
}

class _CreatePasscodeSheetState extends State<CreatePasscodeSheet> {
  String pin = '';
  String confirmPin = '';
  bool isConfirming = false;

  void _showConfirmScreen() {
    setState(() {
      isConfirming = true;
      confirmPin = '';
    });
  }

  Future<void> _savePasscode() async {
    if (pin == confirmPin) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({"passcode": pin}, SetOptions(merge: true));
          showSimpleDialog("Passcode set successfully", Colors.green);
          Navigator.pop(context, true);
        }
      } catch (e) {
        print('Error saving passcode: $e');
        showSimpleDialog('Error saving passcode', Colors.red);
      }
    } else {
      showSimpleDialog('Passcodes do not match. Please try again.', Colors.red);
      setState(() {
        isConfirming = false;
        pin = '';
        confirmPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = isConfirming ? confirmPin : pin;
    final title = isConfirming ? 'Confirm Passcode' : 'Create Account Passcode';
    final subtitle = isConfirming
        ? 'Re-enter your 4-digit passcode'
        : 'Enter a 4-digit passcode to secure your account';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      if (isConfirming) {
                        setState(() {
                          isConfirming = false;
                          confirmPin = '';
                        });
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool isCurrent = index == currentPin.length;
                  bool isEntered = index < currentPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? Colors.blue : Colors.grey,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isEntered
                          ? Text(
                              currentPin[index],
                              style: const TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Keypad(
                onPressed: (val) {
                  setState(() {
                    if (val == null) {
                      if (currentPin.isNotEmpty) {
                        if (isConfirming) {
                          confirmPin = confirmPin.substring(0, confirmPin.length - 1);
                        } else {
                          pin = pin.substring(0, pin.length - 1);
                        }
                      }
                    } else if (currentPin.length < 4) {
                      if (isConfirming) {
                        confirmPin += val;
                      } else {
                        pin += val;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: currentPin.length == 4
                      ? () {
                          if (isConfirming) {
                            _savePasscode();
                          } else {
                            _showConfirmScreen();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentPin.length == 4 ? Colors.blue : Colors.grey,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: Text(
                    isConfirming ? 'Confirm' : 'Next',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardTypeBottomSheet extends StatefulWidget {
  const CardTypeBottomSheet({super.key});
  @override
  State<CardTypeBottomSheet> createState() => _CardTypeBottomSheetState();
}

class _CardTypeBottomSheetState extends State<CardTypeBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Text(
                      'Choose Your Card Type',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Image.asset("assets/cards.png"),
                const SizedBox(height: 20),
                const Text(
                  textAlign: TextAlign.center,
                  'Select the type of card that works\nbest for you',
                  style: TextStyle(color: Colors.black38),
                ),
                const SizedBox(height: 20),
                _buildOption(
                  icon: "assets/physical_card_icon.png",
                  title: 'Get a Physical Card',
                  subtitle: 'Have your card shipped right to your door!',
                  value: 'Physical',
                ),
                _buildOption(
                  icon: "assets/virtual_card_icon.png",
                  title: 'Create a Virtual Card',
                  subtitle: 'A digital card for online use',
                  value: 'Virtual',
                ),
                _buildOption(
                  icon: "assets/anon_card_icon.png",
                  title: 'Create Anonymous Card',
                  subtitle: 'No personal details shown, ideal for privacy',
                  value: 'Anonymous',
                ),
                // _buildOption(
                //   icon: "assets/map_physical_card.png",
                //   title: 'Map a Physical Card',
                //   subtitle: 'Have a physical card? Link it!',
                //   value: 'Map',
                // ),
                // _buildOption(
                //   icon: "assets/credit_card_icon.png",
                //   title: 'Request a Credit Card',
                //   subtitle: 'Flexible Credit Experience',
                //   value: 'Credit',
                // ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required String icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context, value);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(icon, width: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w200,
                      fontSize: 12,
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

class BasicDetailsBottomSheet extends StatefulWidget {
  final String cardType;
  const BasicDetailsBottomSheet({super.key, required this.cardType});
  @override
  State<BasicDetailsBottomSheet> createState() =>
      _BasicDetailsBottomSheetState();
}

class _BasicDetailsBottomSheetState extends State<BasicDetailsBottomSheet> {
  String _selectedScheme = '';
  String? _selectedState;
  String? _selectedCity;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _address2Controller = TextEditingController();
  final TextEditingController _bvnController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  String selectedCurrency = 'USD';
  bool agreeWithTerms = false;
  bool _bvnMissing = false;
  bool _dobMissing = false;
  double? _usdNgnRate;
  bool _rateLoading = false;
  final TextEditingController _fundAmountController = TextEditingController();

  static const Map<String, List<String>> _stateCities = {
    'Abia': ['Aba', 'Umuahia', 'Ohafia', 'Arochukwu', 'Bende', 'Isuikwuato', 'Ikwuano', 'Isiala Ngwa', 'Obingwa', 'Osisioma'],
    'Adamawa': ['Yola', 'Mubi', 'Numan', 'Ganye', 'Gombi', 'Guyuk', 'Hong', 'Jada', 'Lamurde', 'Madagali'],
    'Akwa Ibom': ['Uyo', 'Eket', 'Ikot Abasi', 'Oron', 'Abak', 'Ikot Ekpene', 'Etinan', 'Essien Udim', 'Ini', 'Itu'],
    'Anambra': ['Awka', 'Onitsha', 'Nnewi', 'Ekwulobia', 'Aguata', 'Ayamelum', 'Dunukofia', 'Idemili', 'Ogbaru', 'Orumba'],
    'Bauchi': ['Bauchi', 'Azare', 'Misau', 'Ningi', 'Alkaleri', 'Bogoro', 'Darazo', 'Dass', 'Gamawa', 'Giade'],
    'Bayelsa': ['Yenagoa', 'Ogbia', 'Brass', 'Nembe', 'Ekeremor', 'Kolokuma', 'Sagbama', 'Southern Ijaw'],
    'Benue': ['Makurdi', 'Gboko', 'Katsina-Ala', 'Otukpo', 'Adoka', 'Ado', 'Agatu', 'Apa', 'Logo', 'Obi'],
    'Borno': ['Maiduguri', 'Biu', 'Konduga', 'Damboa', 'Askira', 'Bama', 'Chibok', 'Dikwa', 'Gwoza', 'Hawul'],
    'Cross River': ['Calabar', 'Ogoja', 'Ikom', 'Obudu', 'Akamkpa', 'Akpabuyo', 'Bekwarra', 'Biase', 'Boki', 'Etung'],
    'Delta': ['Asaba', 'Warri', 'Sapele', 'Ughelli', 'Agbor', 'Isoko', 'Ndokwa', 'Okpe', 'Oshimili', 'Patani'],
    'Ebonyi': ['Abakaliki', 'Afikpo', 'Onueke', 'Ikwo', 'Ezza', 'Ishielu', 'Ivo', 'Izzi', 'Ohaozara', 'Ohaukwu'],
    'Edo': ['Benin City', 'Auchi', 'Ekpoma', 'Uromi', 'Akoko-Edo', 'Egor', 'Etsako', 'Igueben', 'Ikpoba-Okha', 'Orhionmwon'],
    'Ekiti': ['Ado-Ekiti', 'Ikere-Ekiti', 'Ijero-Ekiti', 'Emure', 'Gbonyin', 'Ido-Osi', 'Ilejemeje', 'Ikole', 'Moba', 'Oye'],
    'Enugu': ['Enugu', 'Nsukka', 'Agbani', 'Awgu', 'Ezeagu', 'Igbo-Etiti', 'Igboeze', 'Isi-Uzo', 'Nkanu', 'Oji River'],
    'FCT (Abuja)': ['Abuja', 'Gwagwalada', 'Kuje', 'Bwari', 'Kwali', 'Abaji'],
    'Gombe': ['Gombe', 'Kaltungo', 'Billiri', 'Balanga', 'Dukku', 'Funakaye', 'Kwami', 'Nafada', 'Shongom', 'Yamaltu'],
    'Imo': ['Owerri', 'Orlu', 'Okigwe', 'Ahiazu', 'Ehime-Mbano', 'Ezinihitte', 'Ideato', 'Ihitte-Uboma', 'Ikeduru', 'Isiala Mbano'],
    'Jigawa': ['Dutse', 'Hadejia', 'Gumel', 'Birnin Kudu', 'Auyo', 'Babura', 'Buji', 'Birniwa', 'Guri', 'Gwaram'],
    'Kaduna': ['Kaduna', 'Zaria', 'Kafanchan', 'Chikun', 'Birnin Gwari', 'Giwa', 'Igabi', 'Ikara', 'Jaba', 'Kaura'],
    'Kano': ['Kano', 'Wudil', 'Gaya', 'Bichi', 'Ajingi', 'Albasu', 'Bagwai', 'Bebeji', 'Danbatta', 'Gwarzo'],
    'Katsina': ['Katsina', 'Daura', 'Funtua', 'Malumfashi', 'Bakori', 'Batagarawa', 'Batsari', 'Bindawa', 'Charanchi', 'Dan Musa'],
    'Kebbi': ['Birnin Kebbi', 'Argungu', 'Koko', 'Jega', 'Aleiro', 'Arewa', 'Augie', 'Bagudo', 'Bunza', 'Dandi'],
    'Kogi': ['Lokoja', 'Kabba', 'Ankpa', 'Idah', 'Adavi', 'Ajaokuta', 'Bassa', 'Dekina', 'Ibaji', 'Igalamela'],
    'Kwara': ['Ilorin', 'Offa', 'Omu-Aran', 'Kaiama', 'Asa', 'Baruten', 'Edu', 'Ifelodun', 'Irepodun', 'Moro'],
    'Lagos': ['Lagos Island', 'Ikeja', 'Victoria Island', 'Lekki', 'Surulere', 'Alimosho', 'Apapa', 'Badagry', 'Epe', 'Eti-Osa'],
    'Nasarawa': ['Lafia', 'Keffi', 'Akwanga', 'Nasarawa', 'Awe', 'Doma', 'Keana', 'Kokona', 'Nasarawa Egon', 'Obi'],
    'Niger': ['Minna', 'Suleja', 'Bida', 'Kontagora', 'Agaie', 'Agwara', 'Borgu', 'Bosso', 'Chanchaga', 'Edati'],
    'Ogun': ['Abeokuta', 'Sagamu', 'Ijebu-Ode', 'Ilaro', 'Ado-Odo', 'Ewekoro', 'Ifo', 'Ijebu East', 'Imeko Afon', 'Ipokia'],
    'Ondo': ['Akure', 'Ondo Town', 'Owo', 'Ikare', 'Ese-Odo', 'Idanre', 'Ifedore', 'Ilaje', 'Ile-Oluji', 'Odigbo'],
    'Osun': ['Osogbo', 'Ilesha', 'Ife', 'Ede', 'Aiyedaade', 'Aiyedire', 'Boluwaduro', 'Boripe', 'Ejigbo', 'Ife North'],
    'Oyo': ['Ibadan', 'Ogbomoso', 'Oyo', 'Iseyin', 'Akinyele', 'Afijio', 'Atiba', 'Atisbo', 'Egbeda', 'Ibadan North'],
    'Plateau': ['Jos', 'Bukuru', 'Shendam', 'Pankshin', 'Barkin Ladi', 'Bassa', 'Bokkos', 'Jos East', 'Jos North', 'Jos South'],
    'Rivers': ['Port Harcourt', 'Obio-Akpor', 'Bonny', 'Eleme', 'Abua-Odual', 'Ahoada', 'Akuku-Toru', 'Andoni', 'Asari-Toru', 'Degema'],
    'Sokoto': ['Sokoto', 'Wamako', 'Binji', 'Bodinga', 'Dange Shuni', 'Gada', 'Goronyo', 'Gudu', 'Gwadabawa', 'Illela'],
    'Taraba': ['Jalingo', 'Wukari', 'Bali', 'Donga', 'Gashaka', 'Gassol', 'Ibi', 'Karim Lamido', 'Kurmi', 'Lau'],
    'Yobe': ['Damaturu', 'Nguru', 'Potiskum', 'Gashua', 'Bade', 'Bursari', 'Fika', 'Fune', 'Geidam', 'Gulani'],
    'Zamfara': ['Gusau', 'Kaura Namoda', 'Talata Mafara', 'Anka', 'Bakura', 'Birnin Magaji', 'Bukkuyum', 'Bungudu', 'Gummi', 'Maru'],
  };
  @override
  void initState() {
    super.initState();
    if (widget.cardType == 'Physical') {
      selectedCurrency = 'NGN';
    }
    _fetchUserData();
    _loadUsdNgnRate();
  }

  Future<void> _loadUsdNgnRate() async {
    try {
      setState(() => _rateLoading = true);

      double? rate;
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
        if (parsed != null && parsed > 0) rate = parsed;
      }

      if (rate == null) {
        final fxCallable = FirebaseFunctions.instance.httpsCallable(
          'bridgecardGetFxRate',
        );
        final fxResponse = await fxCallable.call();
        if (fxResponse.data is Map && fxResponse.data['status'] == 'success') {
          final dynamic ngnUsd = fxResponse.data['data']?['NGN-USD'];
          if (ngnUsd is num) {
            rate = ngnUsd.toDouble() / 100;
          }
        }
      }

      if (mounted) {
        setState(() => _usdNgnRate = rate);
      }
    } catch (e) {
      print('Failed to load USD/NGN rate: $e');
    } finally {
      if (mounted) {
        setState(() => _rateLoading = false);
      }
    }
  }

  double? _computeNgnEquivalent(int usdAmount) {
    final rate = _usdNgnRate;
    if (rate == null || rate <= 0) return null;
    return usdAmount * rate;
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      final userState = address?['state']?.toString();
      final userCity = address?['city']?.toString();
      final resolvedState =
          (_stateCities.containsKey(userState)) ? userState : null;
      final resolvedCity = (resolvedState != null &&
              (_stateCities[resolvedState]?.contains(userCity) ?? false))
          ? userCity
          : null;
      setState(() {
        _nameController.text = widget.cardType == 'Anonymous'
              ? ''
            : '${data['firstName']} ${data['lastName']}';
        _address1Controller.text = address?['street']?.toString() ?? '';
        if (resolvedState != null) _selectedState = resolvedState;
        if (resolvedCity != null) _selectedCity = resolvedCity;
        final bvn = data['bvn']?.toString() ?? '';
        final dob = data['dateOfBirth']?.toString() ?? '';
        _bvnMissing = bvn.isEmpty;
        _dobMissing = dob.isEmpty;
        if (bvn.isNotEmpty) _bvnController.text = bvn;
        if (dob.isNotEmpty) _dobController.text = dob;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 40),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: Icon(
                    Icons.arrow_back_ios,
                    size: 20,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 30),
                const Text(
                  'Basic Details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Set up your card details',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Text('Step 1 of 3'),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: 1 / 3,
                  backgroundColor: Colors.grey.shade300,
                  color: primaryColor,
                ),
                const SizedBox(height: 20),
                const Text('Scheme'),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (selectedCurrency.contains("USD")) ...[
                          _buildSchemeOption(
                            'assets/visa.png',
                            "Visa",
                            primaryColor,
                          ),
                          const SizedBox(width: 10),
                          _buildSchemeOption(
                            'assets/mastercard.png',
                            "MasterCard",
                            Colors.orange,
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (selectedCurrency.contains("NGN")) ...[
                          _buildSchemeOption(
                            'assets/verve.png',
                            "Verve",
                            Colors.green,
                          ),
                          const SizedBox(width: 10),
                          _buildSchemeOption(
                            'assets/afrigo.png',
                            "AfriGo",
                            Colors.green,
                          ),
                        ],

                        const SizedBox(width: 10),

                        // const SizedBox(width: 10),
                        // _buildSchemeOption(
                        // 'Coral',
                        // Colors.pink,
                        // comingSoon: true,
                        // ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.cardType != 'Anonymous') ...[
                  const Text('Name on Card'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    readOnly: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'John Doe',
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                const Text('Select Currency'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    hintText: 'Select currency',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 15,
                    ),
                  ),
                  initialValue: selectedCurrency,
                  dropdownColor:
                      Colors.white, // sets dropdown item background color
                  items: (widget.cardType == 'Physical'
                        ? ['NGN']
                        : ['USD', 'NGN'])
                      .map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedCurrency = value!;
                      _selectedScheme = '';
                    });
                  },
                ),
                if (selectedCurrency.contains('USD')) ...[
                  const SizedBox(height: 20),
                  Text('Funding Amount (USD)'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _fundAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                    decoration: InputDecoration(
                      prefixText: selectedCurrency.contains('USD') ? '\$ ' : '₦ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: selectedCurrency.contains('USD') ? 'e.g. 20' : 'e.g. 5000',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final parsedUsd = int.tryParse(_fundAmountController.text.trim());
                      final equivalent =
                          parsedUsd == null ? null : _computeNgnEquivalent(parsedUsd);
                      final rate = _usdNgnRate;

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _rateLoading
                                  ? 'Loading USD/NGN rate...'
                                  : rate == null
                                      ? 'USD/NGN rate unavailable. Please try again shortly.'
                                      : 'Rate: 1 USD = ₦${NumberFormat('#,##0.##').format(rate)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            if (equivalent != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Estimated debit equivalent: ₦${NumberFormat('#,##0.##').format(equivalent)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (widget.cardType != 'Anonymous' && (_bvnMissing || _dobMissing)) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'USD cards require identity verification. Please provide your BVN.',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_bvnMissing) ...[
                      const SizedBox(height: 16),
                      const Text('BVN (Bank Verification Number)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bvnController,
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          hintText: '11-digit BVN',
                          counterText: '',
                        ),
                      ),
                    ],
                    if (_dobMissing) ...[  
                      const SizedBox(height: 16),
                      const Text('Date of Birth'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _dobController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [DateInputFormatter()],
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          hintText: 'DD/MM/YYYY',
                        ),
                      ),
                    ],
                  ],
                ],
                SizedBox(height: 20),
                Transform.translate(
                  offset: Offset(-15, 0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: agreeWithTerms,
                        onChanged: (value) {
                          setState(() {
                            agreeWithTerms = value!;
                          });
                        },
                        shape: const CircleBorder(),
                        activeColor: Colors.blue, // optional
                      ),
                      Expanded(
                        child: Wrap(
                          children: [
                            const Text('Agree with '),
                            GestureDetector(
                              onTap: () {
                                // Navigate or show dialog
                                print('Terms and Conditions tapped');
                              },
                              child: Text(
                                'Terms and Conditions',
                                style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.cardType == 'Physical') ...[
                  const SizedBox(height: 20),
                  const Text('Shipping Address'),
                  const SizedBox(height: 20),
                  const Text('Address Line 1'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address1Controller,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'eg. 456 Main Land',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Address Line 2'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address2Controller,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      hintText: 'eg. 456 Main Land',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('State'),
                  const SizedBox(height: 10),
                  _buildSearchablePicker(
                    hint: 'Select State',
                    value: _selectedState,
                    onTap: _openStateSelector,
                  ),
                  const SizedBox(height: 20),
                  const Text('City'),
                  const SizedBox(height: 10),
                  _buildSearchablePicker(
                    hint: _selectedState == null ? 'Select a state first' : 'Select City',
                    value: _selectedCity,
                    onTap: _selectedState == null ? null : _openCitySelector,
                  ),
                ],
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    if (_selectedScheme == "") {
                      showSimpleDialog("Select a card scheme", Colors.red);
                      return;
                    }
                    if (selectedCurrency.contains('USD')) {
                      final parsed = int.tryParse(_fundAmountController.text.trim());
                      if (parsed == null || parsed < 3) {
                        showSimpleDialog('Enter a valid funding amount (minimum \$3)', Colors.red);
                        return;
                      }
                      final rate = _usdNgnRate;
                      if (rate == null || rate <= 0) {
                        showSimpleDialog('USD/NGN rate is unavailable. Please try again.', Colors.red);
                        return;
                      }
                      // BVN/DOB only needed for individual (non-anonymous) USD cards
                      if (widget.cardType != 'Anonymous' && (_bvnMissing || _dobMissing)) {
                        final bvn = _bvnController.text.trim();
                        final dob = _dobController.text.trim();
                        if (_bvnMissing && (bvn.isEmpty || bvn.length != 11)) {
                          showSimpleDialog('Enter a valid 11-digit BVN', Colors.red);
                          return;
                        }
                        if (_dobMissing && (dob.isEmpty || dob.length < 8)) {
                          showSimpleDialog('Enter your date of birth (DD/MM/YYYY)', Colors.red);
                          return;
                        }
                        // Save to Firestore in background
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          final updates = <String, dynamic>{};
                          if (_bvnMissing) updates['bvn'] = bvn;
                          if (_dobMissing) updates['dateOfBirth'] = dob;
                          FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .update(updates);
                        }
                      }
                    }
                    if (!agreeWithTerms) {
                      showSimpleDialog("Agree with terms and conditions", Colors.red);
                      return;
                    }

                    if (_selectedScheme.isEmpty ||
                        (widget.cardType != 'Anonymous' && _nameController.text.isEmpty)) {
                      showSimpleDialog("Please fill in all details", Colors.red);
                      return;
                    }
                    if (widget.cardType == 'Physical' &&
                        (_address1Controller.text.isEmpty ||
                            _selectedCity == null ||
                            _selectedState == null)) {
                      showSimpleDialog('Please fill in shipping details', Colors.red);
                      return;
                    }
                    Map<String, dynamic> data = {
                      'scheme': _selectedScheme,
                      'nameOnCard': _nameController.text,
                      'selectedCurrency': selectedCurrency,
                      'selectedScheme': _selectedScheme,
                      if (selectedCurrency.contains('USD'))
                        'fundAmount': int.parse(_fundAmountController.text.trim()),
                      if (selectedCurrency.contains('USD') && _usdNgnRate != null)
                        'usdNgnRate': _usdNgnRate,
                      if (selectedCurrency.contains('USD'))
                        'fundAmountNgnEquivalent': _computeNgnEquivalent(
                          int.parse(_fundAmountController.text.trim()),
                        ),
                    };
                    if (widget.cardType == 'Physical') {
                      data['shippingAddress'] = {
                        'address1': _address1Controller.text,
                        'address2': _address2Controller.text,
                        'city': _selectedCity ?? '',
                        'state': _selectedState ?? '',
                      };
                    }
                    Navigator.pop(context, data);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchablePicker({
    required String hint,
    required String? value,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
          color: onTap == null ? Colors.grey.shade100 : Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value ?? hint,
              style: TextStyle(
                color: value != null ? Colors.black87 : Colors.grey.shade500,
                fontSize: 16,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Future<void> _openStateSelector() async {
    final selected = await _showSearchableSheet(
      title: 'Select State',
      items: (_stateCities.keys.toList()..sort()),
      selectedValue: _selectedState,
    );
    if (selected == null || selected == _selectedState) return;
    setState(() {
      _selectedState = selected;
      _selectedCity = null;
    });
  }

  Future<void> _openCitySelector() async {
    final selected = await _showSearchableSheet(
      title: 'Select City',
      items: _stateCities[_selectedState] ?? [],
      selectedValue: _selectedCity,
    );
    if (selected == null) return;
    setState(() => _selectedCity = selected);
  }

  Future<String?> _showSearchableSheet({
    required String title,
    required List<String> items,
    String? selectedValue,
  }) {
    String searchQuery = '';
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        bottom: true,
        child: StatefulBuilder(
          builder: (ctx, setModal) {
            final filtered = items
                .where((i) => i.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setModal(() => searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text('No results found',
                                style: TextStyle(color: Colors.grey.shade500)))
                        : ListView.builder(
                            itemCount: filtered.length,
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final isSelected = selectedValue == item;
                              return GestureDetector(
                                onTap: () => Navigator.pop(ctx, item),
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
                                      Expanded(
                                        child: Text(
                                          item,
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
                                        Icon(Icons.check_circle,
                                            color: primaryColor, size: 20),
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
      ),
    );
  }

  Widget _buildSchemeOption(
    String icon,
    String label,
    Color color,
  ) {
    final isSelected = _selectedScheme == label;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedScheme = label;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(icon, width: 50),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: primaryColor, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class CustomizeCardBottomSheet extends StatefulWidget {
  final String scheme;   // 'Visa', 'MasterCard', 'Verve', 'AfriGo'
  final String currency; // 'NGN', 'USD'
  final String cardType; // 'Virtual', 'Anonymous', 'Physical'
  final String nameOnCard;

  const CustomizeCardBottomSheet({
    super.key,
    required this.scheme,
    required this.currency,
    required this.cardType,
    required this.nameOnCard,
  });
  @override
  State<CustomizeCardBottomSheet> createState() =>
      _CustomizeCardBottomSheetState();
}

class _CustomizeCardBottomSheetState extends State<CustomizeCardBottomSheet>
    with SingleTickerProviderStateMixin {
  late List<CardTemplate> _templates;
  late CardTemplate _selectedTemplate;
  Color? _colorOverride;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _templates = getTemplatesForCard(widget.scheme, widget.currency);
    _selectedTemplate = _templates.first;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Clear color override when switching back to templates tab
      if (_tabController.index == 0 && _colorOverride != null) {
        setState(() => _colorOverride = null);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Text(
                'Customize Your Card',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set up your card preference',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text('Step 2 of 3'),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: 2 / 3,
                backgroundColor: Colors.grey.shade300,
              ),
              const SizedBox(height: 20),
              // Live preview
              Center(
                child: PadiCardWidget(
                  template: _selectedTemplate,
                  brand: widget.scheme,
                  currency: widget.currency,
                  cardHolder: widget.cardType == 'Anonymous' ? 'PadiPay' : widget.nameOnCard,
                  cardType: widget.cardType,
                  colorOverride: _colorOverride,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _colorOverride != null
                      ? 'Custom Color'
                      : _selectedTemplate.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Tabs
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: primaryColor,
                  unselectedLabelColor: Colors.grey,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Designs'),
                    Tab(text: 'Custom Color'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ── Designs tab ──
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _templates.map((t) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _buildTemplateOption(t),
                          );
                        }).toList(),
                      ),
                    ),
                    // ── Custom Color tab ──
                    _buildColorPicker(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'templateId': _selectedTemplate.id,
                    'colorOverride': _colorOverride?.value,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'I want this Card',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    // A row of preset swatches + a "pick" button
    const presets = [
      Color(0xFFE53935), Color(0xFFE91E63), Color(0xFF9C27B0),
      Color(0xFF3F51B5), Color(0xFF2196F3), Color(0xFF00BCD4),
      Color(0xFF4CAF50), Color(0xFFFF9800), Color(0xFF795548),
      Color(0xFF607D8B), Color(0xFF212121), Color(0xFFF5F5F5),
    ];
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((c) {
                final isSelected = _colorOverride?.value == c.value;
                return GestureDetector(
                  onTap: () => setState(() => _colorOverride = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: primaryColor, width: 3)
                          : Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: c == const Color(0xFFF5F5F5)
                                ? Colors.black54
                                : Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _openFullColorPicker,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                  Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
              ),
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  void _openFullColorPicker() {
    Color pickerColor = _colorOverride ?? const Color(0xFF2196F3);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: () {
              setState(() => _colorOverride = pickerColor);
              Navigator.pop(ctx);
            },
            child: const Text('Apply', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateOption(CardTemplate template) {
    final isSelected = _selectedTemplate.id == template.id && _colorOverride == null;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedTemplate = template;
        _colorOverride = null;
      }),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: primaryColor, width: 2.5)
              : Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: template.gradientColors.length >= 2
                    ? [template.gradientColors.first, template.gradientColors.last]
                    : [template.gradientColors.first, template.gradientColors.first],
              ),
            ),
            child: isSelected
                ? const Icon(FontAwesomeIcons.check, color: Colors.white, size: 16)
                : null,
          ),
        ),
      ),
    );
  }
}

class ReviewConfirmBottomSheet extends StatelessWidget {
  final String cardType;
  final Map<String, dynamic> basicData;
  final String selectedDesign; // Now a template ID
  final String selectedCurrency;
  final String selectedScheme;
  final int? colorOverride;
  const ReviewConfirmBottomSheet({
    super.key,
    required this.cardType,
    required this.basicData,
    required this.selectedDesign,
    required this.selectedCurrency,
    required this.selectedScheme,
    this.colorOverride,
  });
  @override
  Widget build(BuildContext context) {
    final template = getTemplateById(selectedDesign);
    final fallbackTemplates = getTemplatesForCard(selectedScheme, selectedCurrency);
    final displayTemplate = template ?? fallbackTemplates.first;
    final displayColor = colorOverride != null ? Color(colorOverride!) : null;
    final designName = colorOverride != null ? 'Custom Color' : displayTemplate.name;
    final usdRate = basicData['usdNgnRate'] is num
      ? (basicData['usdNgnRate'] as num).toDouble()
      : double.tryParse(basicData['usdNgnRate']?.toString() ?? '');
    final usdAmount = basicData['fundAmount'] is num
      ? (basicData['fundAmount'] as num).toDouble()
      : double.tryParse(basicData['fundAmount']?.toString() ?? '');
    final ngnEquivalent = basicData['fundAmountNgnEquivalent'] is num
      ? (basicData['fundAmountNgnEquivalent'] as num).toDouble()
      : (usdAmount != null && usdRate != null ? usdAmount * usdRate : null);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 15),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const Text(
                  'Review & Confirm',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Double-check your card details before creating',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                const Text('Step 3 of 3'),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: 1.0),
                const SizedBox(height: 20),
                const Text(
                  'Your New Card',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Transform.rotate(
                    angle: -0.1,
                    child: PadiCardWidget(
                      template: displayTemplate,
                      brand: selectedScheme,
                      currency: selectedCurrency,
                      cardHolder: cardType == 'Anonymous' ? 'PadiPay' : (basicData['nameOnCard'] ?? 'CARD HOLDER'),
                      cardType: cardType,
                      colorOverride: displayColor,
                      width: MediaQuery.of(context).size.width * 0.85,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.shade100, // inner border color
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    margin: EdgeInsets.all(6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.02),
                      border: Border.all(
                        color: Colors.grey.shade100, // inner border color
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Summary',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            selectedCurrency.contains("USD")
                                ? Text(
                                    "\$3 Fee",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : SizedBox.shrink(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildSummaryRow(
                          'Scheme',
                          selectedScheme.toUpperCase(),
                        ),
                        _buildSummaryRow('CARD TYPE', cardType),
                        if (cardType != 'Anonymous')
                          _buildSummaryRow(
                            'CARDHOLDER NAME',
                            basicData['nameOnCard'],
                          ),
                        _buildSummaryRow('DESIGN', designName),
                        _buildSummaryRow('Currency', selectedCurrency),
                        if (selectedCurrency.toUpperCase().contains('USD') &&
                            usdRate != null)
                          _buildSummaryRow(
                            'USD/NGN RATE',
                            '1 USD = ₦${NumberFormat('#,##0.##').format(usdRate)}',
                          ),
                        if (selectedCurrency.toUpperCase().contains('USD') &&
                            usdAmount != null)
                          _buildSummaryRow(
                            'Funding Amount',
                            '\$${NumberFormat('#,##0.##').format(usdAmount)}',
                          ),
                        if (selectedCurrency.toUpperCase().contains('USD') &&
                            ngnEquivalent != null)
                          _buildSummaryRow(
                            'Estimated NGN Equivalent',
                            '₦${NumberFormat('#,##0.##').format(ngnEquivalent)}',
                          ),
                        _buildSummaryRow(
                          'DELIVERY',
                          cardType == 'Physical'
                          ? 'Up to 2 Weeks'
                              : 'Instant',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Secure & Protected",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(width: 30),
                          Expanded(
                            child: Text(
                              'YOUR CARD WILL BE SECURED WITH INDUSTRY-STANDARD ENCRYPTION AND FRAUD PROTECTION.',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'I want this Card',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PCI-DSS compliant card detail viewer using Sudo's SecureProxy SDK.
// Sensitive data (PAN, CVV2, PIN) is rendered in iframes served by Sudo's
// SecureProxy servers and displayed directly to the user.
// The data never passes through our Firebase backend.
// ---------------------------------------------------------------------------
class SudoSecureCardSheet extends StatefulWidget {
  final String cardId;
  final String? expiryMonth;
  final String? expiryYear;
  final String? cardPin;

  const SudoSecureCardSheet({
    super.key,
    required this.cardId,
    this.expiryMonth,
    this.expiryYear,
    this.cardPin,
  });

  @override
  State<SudoSecureCardSheet> createState() => _SudoSecureCardSheetState();
}

class _SudoSecureCardSheetState extends State<SudoSecureCardSheet> {
  WebViewController? _webController;
  bool _loading = true;
  String? _error;

  // Sandbox vault ID — swap to 'vdl2xefo5' when moving to production
  static const String _vaultId = 'we0dsa28s';

  @override
  void initState() {
    super.initState();
    _initSecureView();
  }

  Future<void> _initSecureView() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Start both fetches in parallel for speed
      final tokenFuture = FirebaseFunctions.instance
          .httpsCallable('sudoGenerateCardToken')
          .call({'cardId': widget.cardId});

      Future<DocumentSnapshot<Map<String, dynamic>>?> userFuture;
      if (uid != null) {
        userFuture =
            FirebaseFirestore.instance.collection('users').doc(uid).get();
      } else {
        userFuture = Future.value(null);
      }

      final tokenResult = await tokenFuture;
      final token = tokenResult.data['token'] as String?;
      if (token == null) throw Exception('No card token returned');

      // Build billing address — prefer Sudo customer's billingAddress (tied to
      // the card), fall back to the user profile address field.
      String billingAddress = '';
      try {
        final userSnap = await userFuture;
        if (userSnap != null && userSnap.exists) {
          final userData = userSnap.data();
          print('[SecureCard] userData keys: ${userData?.keys.toList()}');

          // Path: sudoCustomer -> data -> billingAddress
          // Use dynamic throughout to avoid Map<String, dynamic>.from() cast errors.
          dynamic billing;
          final sc = userData?['sudoCustomer'];
          print('[SecureCard] sudoCustomer type: ${sc?.runtimeType}, value: $sc');
          if (sc is Map) {
            final d = sc['data'];
            print('[SecureCard] sudoCustomer[data] type: ${d?.runtimeType}, value: $d');
            if (d is Map) {
              billing = d['billingAddress'];
              print('[SecureCard] billingAddress from data: type=${billing?.runtimeType}, value=$billing');
            }
          }

          if (billing is Map) {
            final parts = <String>[];
            for (final key in ['line1', 'city', 'state', 'country', 'postalCode']) {
              final v = billing[key];
              if (v != null) {
                final s = v.toString();
                if (s.isNotEmpty) parts.add(s);
              }
            }
            billingAddress = parts.join(', ');
            print('[SecureCard] resolved billingAddress (sudo): $billingAddress');
          } else {
            print('[SecureCard] billing is not a Map (${billing?.runtimeType}), trying profile address fallback');
          }

          // Fall back to user profile address
          if (billingAddress.isEmpty) {
            final address = userData?['address'];
            print('[SecureCard] profile address: type=${address?.runtimeType}, value=$address');
            if (address is Map) {
              final parts = <String>[];
              for (final key in ['street', 'city', 'state', 'country']) {
                final v = address[key];
                if (v != null) {
                  final s = v.toString();
                  if (s.isNotEmpty) parts.add(s);
                }
              }
              billingAddress = parts.join(', ');
              print('[SecureCard] resolved billingAddress (profile fallback): $billingAddress');
            }
          }
        } else {
          print('[SecureCard] userSnap is null or does not exist');
        }
      } catch (e, st) {
        print('[SecureCard] billing address error: $e\n$st');
      }

      // Build expiry string from params
      final expM = (widget.expiryMonth ?? '').padLeft(2, '0');
      final expY = widget.expiryYear ?? '';
      final expiry = expY.length >= 2
          ? '$expM/${expY.substring(expY.length - 2)}'
          : (expM.isNotEmpty || expY.isNotEmpty ? '$expM/$expY' : '--');

      print('[SecureCard] final billingAddress before HTML build: "$billingAddress"');

      final billingFields = <String, String>{};
      if (billingAddress.isNotEmpty) {
        // Re-read structured fields from Firestore data for proper display
        try {
          final userData = (await userFuture)?.data();
          final sc = userData?['sudoCustomer'];
          if (sc is Map) {
            final d = sc['data'];
            if (d is Map) {
              final b = d['billingAddress'];
              if (b is Map) {
                for (final key in ['line1', 'city', 'state', 'postalCode', 'country']) {
                  final v = b[key]?.toString() ?? '';
                  if (v.isNotEmpty) billingFields[key] = v;
                }
              }
            }
          }
          // Fallback: split back from joined string for profile address
          if (billingFields.isEmpty) {
            billingFields['address'] = billingAddress;
          }
        } catch (_) {
          billingFields['address'] = billingAddress;
        }
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'NativeCopy',
          onMessageReceived: (msg) async {
            await Clipboard.setData(ClipboardData(text: msg.message));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
        )
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (mounted) setState(() => _error = e.description);
          },
        ))
        ..loadHtmlString(
            _buildHtml(widget.cardId, token, expiry, billingFields, cardPin: widget.cardPin));

      if (mounted) setState(() => _webController = controller);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _buildHtml(
      String cardId, String token, String expiry, Map<String, String> billingFields, {String? cardPin}) {
    final safeExpJS = expiry.replaceAll("'", "\\'");
    final safePinJS = (cardPin ?? '').replaceAll("'", "\\'");

    String billingHtml = '';
    if (billingFields.isNotEmpty) {
      String safeCopy(String v) => v.replaceAll("'", "\\'").replaceAll('"', '\\"');

      // Street address spans full width; city+state are side by side; zip+country side by side
      final line1 = billingFields['line1'];
      final city = billingFields['city'];
      final state = billingFields['state'];
      final zip = billingFields['postalCode'];
      final country = billingFields['country'];
      final fallback = billingFields['address'];

      final copyIcon = '''<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>''';

      String fieldHtml(String label, String value, String btnId) => '''
  <div class="field">
    <div class="field-header">
      <span class="label">$label</span>
      <button class="copy-btn" id="$btnId" title="Copy" onclick="copyStatic('${safeCopy(value)}','${btnId}')">$copyIcon</button>
    </div>
    <div class="billing-text">$value</div>
  </div>''';

      if (fallback != null) {
        billingHtml = fieldHtml('Billing Address', fallback, 'billCopyBtn');
      } else {
        final buf = StringBuffer();
        if (line1 != null) buf.write(fieldHtml('Street Address', line1, 'billLine1Btn'));
        if (city != null && state != null) {
          buf.write('''
  <div class="half-row">
    <div class="field">
      <div class="field-header"><span class="label">City</span><button class="copy-btn" id="billCityBtn" title="Copy" onclick="copyStatic('${safeCopy(city)}','billCityBtn')">$copyIcon</button></div>
      <div class="billing-text">$city</div>
    </div>
    <div class="field">
      <div class="field-header"><span class="label">State</span><button class="copy-btn" id="billStateBtn" title="Copy" onclick="copyStatic('${safeCopy(state)}','billStateBtn')">$copyIcon</button></div>
      <div class="billing-text">$state</div>
    </div>
  </div>''');
        } else {
          if (city != null) buf.write(fieldHtml('City', city, 'billCityBtn'));
          if (state != null) buf.write(fieldHtml('State', state, 'billStateBtn'));
        }
        if (zip != null && country != null) {
          buf.write('''
  <div class="half-row">
    <div class="field">
      <div class="field-header"><span class="label">Postal Code</span><button class="copy-btn" id="billZipBtn" title="Copy" onclick="copyStatic('${safeCopy(zip)}','billZipBtn')">$copyIcon</button></div>
      <div class="billing-text">$zip</div>
    </div>
    <div class="field">
      <div class="field-header"><span class="label">Country</span><button class="copy-btn" id="billCountryBtn" title="Copy" onclick="copyStatic('${safeCopy(country)}','billCountryBtn')">$copyIcon</button></div>
      <div class="billing-text">$country</div>
    </div>
  </div>''');
        } else {
          if (zip != null) buf.write(fieldHtml('Postal Code', zip, 'billZipBtn'));
          if (country != null) buf.write(fieldHtml('Country', country, 'billCountryBtn'));
        }
        billingHtml = buf.toString();
      }
    }

    return '''<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap" rel="stylesheet">
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#f5f5f5;padding:18px 14px}
    .label{color:#888;font-size:10px;text-transform:uppercase;letter-spacing:1.5px;margin-bottom:6px;font-family:Arial,sans-serif;font-weight:600}
    .field{background:#fff;border-radius:12px;padding:12px 14px;margin-bottom:12px;border:1px solid #e0e0e0;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
    .field-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}
    .field-value{font-family:'Share Tech Mono','Courier New',monospace;font-size:16px;color:#111;letter-spacing:2px;line-height:28px}
    iframe{border:none;width:calc(100% - 28px);height:28px;display:block}
    .copy-btn{background:none;border:none;cursor:pointer;padding:4px;display:flex;align-items:center;border-radius:6px;color:#ccc;transition:all .15s;flex-shrink:0}
    .copy-btn:hover{background:#f0f0f0;color:#555}
    .copy-btn.copied svg{stroke:#4caf50}
    .half-row{display:flex;gap:10px}
    .half-row .field{flex:1;min-width:0}
    .billing-text{font-family:Arial,sans-serif;font-size:13px;color:#444;line-height:1.5;padding:2px 0}
  </style>
</head>
<body>

  <div class="field">
    <div class="field-header">
      <span class="label">Card Number</span>
      <button class="copy-btn" id="numCopyBtn" title="Copy">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>
      </button>
    </div>
    <div id="num"></div>
  </div>

  <div class="half-row">
    <div class="field">
      <div class="field-header">
        <span class="label">CVV</span>
        <button class="copy-btn" id="cvvCopyBtn" title="Copy">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>
        </button>
      </div>
      <div id="cvv"></div>
    </div>
    <div class="field">
      <div class="field-header">
        <span class="label">Expires</span>
        <button class="copy-btn" id="expCopyBtn" title="Copy" onclick="copyStatic('$safeExpJS','expCopyBtn')">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>
        </button>
      </div>
      <div class="field-value">$expiry</div>
    </div>
  </div>

  <div class="field">
    <div class="field-header">
      <span class="label">PIN</span>
      <div style="display:flex;gap:2px;align-items:center">
        <button class="copy-btn" id="pinCopyBtn" title="Copy" style="display:none">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>
        </button>
        <button class="copy-btn" id="pinEyeBtn" title="Reveal PIN" onclick="togglePin()">
          <span id="pinEyeShow"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg></span>
          <span id="pinEyeHide" style="display:none"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg></span>
        </button>
      </div>
    </div>
    <div style="position:relative;min-height:28px">
      <div id="pin" class="field-value" style="display:none">${cardPin ?? ''}</div>
      <div id="pin-mask" style="position:absolute;top:0;left:0;right:0;bottom:0;background:white;display:flex;align-items:center;pointer-events:none">
        <span style="font-family:'Share Tech Mono','Courier New',monospace;font-size:18px;letter-spacing:8px;color:#bbb">• • • •</span>
      </div>
    </div>
  </div>

  $billingHtml

  <script src="https://js.securepro.xyz/sudo-show/1.1/ACiWvWF9tYAez4M498DHs.min.js"></script>
  <script>
    var vaultId = "$_vaultId";
    var cardToken = "$token";
    var cardId = "$cardId";

    function flashCopied(id) {
      var b = document.getElementById(id);
      if (!b) return;
      b.classList.add('copied');
      setTimeout(function(){ b.classList.remove('copied'); }, 1500);
    }

    function copyStatic(val, id) {
      try { NativeCopy.postMessage(val); } catch(e){}
      flashCopied(id);
    }

    var numP = SecureProxy.create(vaultId);
    var numReq = numP.request({
      name:"pan", method:"GET",
      path:"/cards/"+cardId+"/secure-data/number",
      headers:{"Authorization":"Bearer "+cardToken},
      htmlWrapper:"text", jsonPathSelector:"data.number",
      serializers:[numP.SERIALIZERS.replace("(\\\\d{4})(\\\\d{4})(\\\\d{4})(\\\\d{4})","\$1 \$2 \$3 \$4")]
    });
    numReq.render("#num");
    document.getElementById('numCopyBtn').onclick = function(){
      if (typeof numReq.copy==='function') numReq.copy();
      flashCopied('numCopyBtn');
    };

    var cvvP = SecureProxy.create(vaultId);
    var cvvReq = cvvP.request({
      name:"cvv", method:"GET",
      path:"/cards/"+cardId+"/secure-data/cvv2",
      headers:{"Authorization":"Bearer "+cardToken},
      htmlWrapper:"text", jsonPathSelector:"data.cvv2", serializers:[]
    });
    cvvReq.render("#cvv");
    document.getElementById('cvvCopyBtn').onclick = function(){
      if (typeof cvvReq.copy==='function') cvvReq.copy();
      flashCopied('cvvCopyBtn');
    };

    var pinRevealed = false;
    function togglePin() {
      pinRevealed = !pinRevealed;
      document.getElementById('pin-mask').style.display = pinRevealed ? 'none' : 'flex';
      document.getElementById('pin').style.display = pinRevealed ? 'block' : 'none';
      document.getElementById('pinCopyBtn').style.display = pinRevealed ? 'flex' : 'none';
      document.getElementById('pinEyeShow').style.display = pinRevealed ? 'none' : 'inline';
      document.getElementById('pinEyeHide').style.display = pinRevealed ? 'inline' : 'none';
    }

    document.getElementById('pinCopyBtn').onclick = function(){
      copyStatic('$safePinJS', 'pinCopyBtn');
    };
  </script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.93,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Secure Card Details',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.lock, color: Colors.green.shade600, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'PCI-DSS Compliant',
                            style: TextStyle(
                              color: Colors.green.shade600,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, color: Colors.grey.shade700, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Body — loader / error / WebView
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade300, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load secure card view:\n$_error',
                              style: TextStyle(
                                color: Colors.red.shade400,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : _webController == null || _loading
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: primaryColor,
                                strokeWidth: 2,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Loading card details...',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : WebViewWidget(controller: _webController!),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 12),
                  const SizedBox(width: 4),
                
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class ChangeSudoCardPinSheet extends StatefulWidget {
  final String cardId;
  final String currentPin;

  const ChangeSudoCardPinSheet({
    super.key,
    required this.cardId,
    required this.currentPin,
  });

  @override
  State<ChangeSudoCardPinSheet> createState() => _ChangeSudoCardPinSheetState();
}

class _ChangeSudoCardPinSheetState extends State<ChangeSudoCardPinSheet> {
  // step 0 = enter current PIN, step 1 = enter new PIN, step 2 = confirm new PIN
  int _step = 0;
  String _enteredOld = '';
  String _enteredNew = '';
  String _enteredConfirm = '';
  bool _loading = false;

  String get _currentInput {
    if (_step == 0) return _enteredOld;
    if (_step == 1) return _enteredNew;
    return _enteredConfirm;
  }

  void _onKeyPress(String? digit) {
    setState(() {
      if (digit == null) {
        // backspace
        if (_step == 0 && _enteredOld.isNotEmpty) _enteredOld = _enteredOld.substring(0, _enteredOld.length - 1);
        if (_step == 1 && _enteredNew.isNotEmpty) _enteredNew = _enteredNew.substring(0, _enteredNew.length - 1);
        if (_step == 2 && _enteredConfirm.isNotEmpty) _enteredConfirm = _enteredConfirm.substring(0, _enteredConfirm.length - 1);
      } else {
        if (_step == 0 && _enteredOld.length < 4) _enteredOld += digit;
        if (_step == 1 && _enteredNew.length < 4) _enteredNew += digit;
        if (_step == 2 && _enteredConfirm.length < 4) _enteredConfirm += digit;
      }
    });
    _checkAdvance();
  }

  void _checkAdvance() {
    if (_step == 0 && _enteredOld.length == 4) {
      if (_enteredOld != widget.currentPin) {
        setState(() { _enteredOld = ''; });
        showSimpleDialog('Incorrect current PIN', Colors.red);
        return;
      }
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() { _step = 1; });
      });
    } else if (_step == 1 && _enteredNew.length == 4) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() { _step = 2; });
      });
    } else if (_step == 2 && _enteredConfirm.length == 4) {
      if (_enteredNew != _enteredConfirm) {
        setState(() { _enteredConfirm = ''; _step = 1; _enteredNew = ''; });
        showSimpleDialog("PINs don't match. Try again.", Colors.red);
        return;
      }
      _changePin();
    }
  }

  Future<void> _changePin() async {
    setState(() => _loading = true);
    debugPrint('[ChangeSudoCardPinSheet] Calling sudoChangeCardPin for cardId: ${widget.cardId}');
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('sudoChangeCardPin')
          .call({'cardId': widget.cardId, 'oldPin': _enteredOld, 'newPin': _enteredNew});
      debugPrint('[ChangeSudoCardPinSheet] Response: ${result.data}');
      final data = result.data;
      final succeeded = data['success'] == true ||
          data['statusCode'] == 200 ||
          (data['message'] as String? ?? '').toLowerCase().contains('updated successfully');
      if (succeeded) {
        debugPrint('[ChangeSudoCardPinSheet] PIN changed successfully for cardId: ${widget.cardId}');
        if (mounted) {
          Navigator.pop(context);
          showSimpleDialog('PIN changed successfully!', Colors.green);
        }
      } else {
        throw Exception('PIN change failed: unexpected response $data');
      }
    } catch (e) {
      debugPrint('[ChangeSudoCardPinSheet] Error changing PIN: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _step = 0;
          _enteredOld = '';
          _enteredNew = '';
          _enteredConfirm = '';
        });
        showSimpleDialog('Failed to change PIN: ${e.toString()}', Colors.red);
      }
    }
  }

  String get _stepTitle {
    if (_step == 0) return 'Enter Current PIN';
    if (_step == 1) return 'Enter New PIN';
    return 'Confirm New PIN';
  }

  @override
  Widget build(BuildContext context) {
    final dots = _currentInput.length;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16, bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('Change Card PIN', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_stepTitle, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < dots ? Colors.black : Colors.grey.shade300,
              ),
            )),
          ),
          const SizedBox(height: 32),
          if (_loading)
            const CircularProgressIndicator()
          else
            Keypad(onPressed: _onKeyPress),
        ],
      ),
    );
  }
}

class ConfirmTransactionBottomSheet extends StatelessWidget {
  const ConfirmTransactionBottomSheet({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 15),
              const Text(
                'Confirm Transaction',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Review and confirm to complete your transaction.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade100),
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Summary',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'AMOUNT:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          '₦20,000',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MERCHANT/POS:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'Zenith Bank POS - Lekki Branch',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CARD:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          'Virtual Card (••• 4821)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close loading
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => const SuccessBottomSheet(
                      actionText: 'Done',
                      title: 'Payment Successful!',
                      description: 'Your payment was processed successfully.',
                    ),
                    isScrollControlled: true,
                  ).then((_) {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
