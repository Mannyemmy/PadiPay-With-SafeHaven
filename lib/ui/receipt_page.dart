import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:card_app/utils.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReceiptPage extends StatefulWidget {
  final String reference;
  final Map<String, dynamic>? cardData;

  const ReceiptPage({super.key, required this.reference, this.cardData});

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  late ConfettiController _confettiController;

  // Receipt data state
  bool isLoadingDetails = true;
  String transactionNo = '';
  String senderName = '';
  String senderAccountNumber = '';
  String senderBankName = '';
  String amount = '';
  String principalAmount = '';
  double? _fees;
  double? _vat;
  double? _stampDuty;
  double? _totalAmount;
  String status = '';
  String transactionDateTime = '';
  String transactionType = '';
  List<Map<String, String>> recipientDetails = [];
  List<Map<String, String>> senderDetails = [];
  List<Map<String, String>> transactionInfo = [];

  // For stream subscription and timeout
  Stream<DocumentSnapshot?>? _transactionStream;
  bool _hasTimedOut = false;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 5),
    );
    _confettiController.play();

    _generateTransactionIds();

    if (widget.cardData != null) {
      // Card transactions are synchronous – no need for stream
      _populateFromCardData(widget.cardData!);
      setState(() => isLoadingDetails = false);
    } else {
      // Real‑time listener for webhook‑saved transaction
      _listenForTransaction();
      // Timeout after 10 seconds
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && isLoadingDetails && !_hasTimedOut) {
          setState(() {
            _hasTimedOut = true;
            isLoadingDetails = false;
          });
        }
      });
    }
  }

  void _listenForTransaction() {
    _pollForTransaction();
  }

  Future<void> _pollForTransaction() async {
    const maxAttempts = 20;
    int attempts = 0;

    print("🔍 ReceiptPage: Starting poll for reference: ${widget.reference}");

    while (attempts < maxAttempts && mounted) {
      print("🔄 Attempt ${attempts + 1}/$maxAttempts");

      // Try 1: reference
      QuerySnapshot refQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .where('reference', isEqualTo: widget.reference)
          .limit(1)
          .get();
      if (refQuery.docs.isNotEmpty) {
        print("✅ Found by 'reference' field: ${refQuery.docs.first.id}");
        await _populateFromTransactionDoc(refQuery.docs.first);
        if (mounted) setState(() => isLoadingDetails = false);
        return;
      } else {
        print("❌ No match for 'reference' = ${widget.reference}");
      }

      // Try 2: paymentReference
      QuerySnapshot paymentQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .where('paymentReference', isEqualTo: widget.reference)
          .limit(1)
          .get();
      if (paymentQuery.docs.isNotEmpty) {
        print(
          "✅ Found by 'paymentReference' field: ${paymentQuery.docs.first.id}",
        );
        await _populateFromTransactionDoc(paymentQuery.docs.first);
        if (mounted) setState(() => isLoadingDetails = false);
        return;
      } else {
        print("❌ No match for 'paymentReference' = ${widget.reference}");
      }

      // Try 3: sessionId
      QuerySnapshot sessionQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .where('sessionId', isEqualTo: widget.reference)
          .limit(1)
          .get();
      if (sessionQuery.docs.isNotEmpty) {
        print("✅ Found by 'sessionId' field: ${sessionQuery.docs.first.id}");
        await _populateFromTransactionDoc(sessionQuery.docs.first);
        if (mounted) setState(() => isLoadingDetails = false);
        return;
      } else {
        print("❌ No match for 'sessionId' = ${widget.reference}");
      }

      // Try 4: safehavenId
      QuerySnapshot safehavenQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .where('safehavenId', isEqualTo: widget.reference)
          .limit(1)
          .get();
      if (safehavenQuery.docs.isNotEmpty) {
        print(
          "✅ Found by 'safehavenId' field: ${safehavenQuery.docs.first.id}",
        );
        await _populateFromTransactionDoc(safehavenQuery.docs.first);
        if (mounted) setState(() => isLoadingDetails = false);
        return;
      } else {
        print("❌ No match for 'safehavenId' = ${widget.reference}");
      }

      attempts++;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print("⏰ ReceiptPage: Polling timed out after $maxAttempts attempts");
    if (mounted) {
      setState(() {
        _hasTimedOut = true;
        isLoadingDetails = false;
      });
    }
  } // ----------------------------------------------------------------------

  Future<void> _populateFromTransactionDoc(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final userId = data['userId'] as String?;
    final actualSender = data['actualSender'] as String?;
    final txType = (data['type'] as String? ?? '').toLowerCase();

    final principal = (data['amount'] as num?)?.toDouble() ?? 0.0;
    principalAmount = principal.toString();
    _fees = (data['fees'] as num?)?.toDouble() ?? 0.0;
    _vat = (data['vat'] as num?)?.toDouble() ?? 0.0;
    _stampDuty = (data['stampDuty'] as num?)?.toDouble() ?? 0.0;

    if (data['totalAmount'] != null) {
      _totalAmount = (data['totalAmount'] as num).toDouble();
    } else {
      _totalAmount = principal + _fees! + _vat! + _stampDuty!;
    }

    final isAnonymousTransfer =
        txType == 'ghost_transfer' || txType == 'anonymous_transfer';
    final isSent = userId == currentUserId || actualSender == currentUserId;
    final isReceivedAnonymously = isAnonymousTransfer && !isSent;

    final userIdForLookup = (actualSender != null && actualSender.isNotEmpty)
        ? actualSender
        : userId;

    final rawTs = data['createdAtFirestore'] ?? data['timestamp'];
    DateTime? parsedTs;
    if (rawTs is Timestamp)
      parsedTs = rawTs.toDate();
    else if (rawTs is DateTime)
      parsedTs = rawTs;
    else if (rawTs is int)
      parsedTs = DateTime.fromMillisecondsSinceEpoch(rawTs);
    else if (rawTs is String)
      try {
        parsedTs = DateTime.parse(rawTs);
      } catch (_) {}

    // Helper to get current user details
    String currentUserName = '';
    String currentUserAccountNumber = '';
    String currentUserBankName = '';
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();
        if (currentUserDoc.exists) {
          final cuData = currentUserDoc.data()!;
          currentUserName =
              '${cuData['firstName'] ?? ''} ${cuData['lastName'] ?? ''}'.trim();
          if (currentUserName.isEmpty)
            currentUserName = cuData['userName'] ?? cuData['email'] ?? '';
          final safehavenData =
              cuData['safehavenData'] as Map<String, dynamic>?;
          final virtualAccount =
              safehavenData?['virtualAccount'] as Map<String, dynamic>?;
          currentUserAccountNumber =
              virtualAccount?['data']?['attributes']?['accountNumber']
                  ?.toString() ??
              '';
          currentUserBankName =
              virtualAccount?['data']?['attributes']?['bank']?['name']
                  ?.toString() ??
              '';
        }
      } catch (e) {
        debugPrint('Error fetching current user: $e');
      }
    }

    // Sender details (different for received anonymous)
    String fetchedSenderName = _firstNonEmpty([
      data['senderName'],
      data['debitAccountName'],
      data['originatorAccountName'],
      data['counterParty']?['accountName'],
      data['api_response']?['data']?['attributes']?['senderName'],
    ]);
    String fetchedSenderAccountNumber = _firstNonEmpty([
      data['senderAccountNumber'],
      data['debitAccountNumber'],
      data['originatorAccountNumber'],
      data['counterParty']?['accountNumber'],
    ]);
    String fetchedSenderBankName = _firstNonEmpty([
      data['senderBankName'],
      data['debitBankName'],
      data['originatorBankName'],
      data['bankName'],
    ]);

    final shouldLookupSenderByUid =
        !isReceivedAnonymously &&
        fetchedSenderName.isEmpty &&
        userIdForLookup != null &&
        userIdForLookup.isNotEmpty &&
        (txType == 'transfer' || txType == 'ghost_transfer');

    if (shouldLookupSenderByUid) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userIdForLookup)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          fetchedSenderName =
              '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                  .trim();
          if (fetchedSenderName.isEmpty)
            fetchedSenderName = userData['userName'] ?? '';
          final safehavenData =
              userData['safehavenData'] as Map<String, dynamic>?;
          if (safehavenData != null) {
            final virtualAccount =
                safehavenData['virtualAccount'] as Map<String, dynamic>?;
            if (virtualAccount != null) {
              fetchedSenderAccountNumber =
                  virtualAccount['data']['attributes']['accountNumber']
                      ?.toString() ??
                  '';
              fetchedSenderBankName =
                  virtualAccount['data']['attributes']['bank']?['name']
                      ?.toString() ??
                  '';
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching sender user doc: $e');
      }
    } else if (isReceivedAnonymously) {
      try {
        final companyDoc = await FirebaseFirestore.instance
            .collection('company')
            .doc('account_details')
            .get();
        if (companyDoc.exists) {
          final companyData = companyDoc.data()!;
          fetchedSenderName =
              companyData['accountName']?.toString() ?? 'PadiPay';
          fetchedSenderAccountNumber =
              companyData['accountNumber']?.toString() ?? '';
          fetchedSenderBankName = companyData['bankName']?.toString() ?? '';
        }
      } catch (e) {
        debugPrint('Error fetching company details: $e');
      }
    }

    final isCreditLike =
        txType == 'deposit' || txType == 'add_money' || txType == 'fund';
    // Inside _populateFromTransactionDoc, replace the recipient variables:

    final recipientName = _firstNonEmpty([
      data['recipientName'], // added – this is what webhook saves
      data['creditAccountName'],
      data['beneficiaryAccountName'],
      currentUserName,
    ]);

    final recipientAccountNumber = _firstNonEmpty([
      data['recipientAccount'], // added – webhook saves recipientAccount
      data['creditAccountNumber'],
      data['beneficiaryAccountNumber'],
      data['account_number'],
      data['accountNumber'],
      currentUserAccountNumber,
    ]);

    final recipientBank = _firstNonEmpty([
      data['recipientBankName'], // if webhook saves this, add it
      data['creditBankName'],
      data['beneficiaryBankName'],
      data['bankName'],
      currentUserBankName,
    ]);

    setState(() {
      transactionType = data['type'] ?? '';
      amount = principalAmount;
      status =
          data['status'] ??
          data['api_response']?['data']?['attributes']?['status'] ??
          '';
      transactionDateTime = parsedTs != null
          ? DateFormat("MMMM d, yyyy 'at' h:mm:ss a 'UTC+1'").format(parsedTs)
          : '';

      // Build recipient details based on transaction type
      if (txType == 'transfer' || txType == 'ghost_transfer' || isCreditLike) {
        recipientDetails = [
          {'label': 'Recipient Name', 'value': recipientName},
          {'label': 'Bank Name', 'value': recipientBank},
          {
            'label': 'Account Number',
            'value': recipientAccountNumber.isNotEmpty
                ? recipientAccountNumber
                : '',
          },
        ];
      } else if (txType == 'airtime') {
        recipientDetails = [
          {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
          {'label': 'Network', 'value': data['network'] ?? ''},
        ];
      } else if (txType == 'data') {
        recipientDetails = [
          {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
          {'label': 'Network', 'value': data['network'] ?? ''},
          {'label': 'Bundle', 'value': data['bundle'] ?? ''},
        ];
      } else if (txType == 'cable') {
        recipientDetails = [
          {
            'label': 'Smartcard Number',
            'value':
                data['fullData']?['customerDetail']?['smartcardNumber'] ?? '',
          },
          {'label': 'Provider', 'value': data['network'] ?? ''},
          {'label': 'Plan', 'value': data['plan'] ?? ''},
        ];
      } else if (txType == 'electricity') {
        recipientDetails = [
          {'label': 'Meter Number', 'value': data['meterNumber'] ?? ''},
          {'label': 'Disco', 'value': data['disco'] ?? ''},
          {'label': 'Token', 'value': data['token'] ?? ''},
          {'label': 'Units', 'value': data['units'] ?? ''},
        ];
      } else {
        recipientDetails = [
          {'label': 'Recipient Name', 'value': recipientName},
          {'label': 'Bank Name', 'value': recipientBank},
        ];
        if (recipientAccountNumber.isNotEmpty) {
          recipientDetails.add({
            'label': 'Account Number',
            'value': _maskAccountNumber(recipientAccountNumber),
          });
        }
      }

      senderName = fetchedSenderName.isNotEmpty
          ? fetchedSenderName
          : (isSent ? currentUserName : 'Unknown');
      senderAccountNumber = fetchedSenderAccountNumber;
      senderBankName = fetchedSenderBankName;

      senderDetails = [
        {'label': 'Sender Name', 'value': senderName},
        if (senderBankName.isNotEmpty)
          {'label': 'Bank Name', 'value': senderBankName},
        if (senderAccountNumber.isNotEmpty)
          {
            'label': 'Account Number',
            'value': _maskAccountNumber(senderAccountNumber),
          },
      ];

      transactionInfo = [
        {'label': 'Transaction No.', 'value': transactionNo},
        {'label': 'Reference', 'value': widget.reference},
      ];
    });
  }

  // ----------------------------------------------------------------------
  //  Card data (synchronous, no webhook)
  // ----------------------------------------------------------------------
  void _populateFromCardData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final parsedTs = ts?.toDate();
    setState(() {
      transactionType = type;
      amount = (data['amount'] ?? 0).toString();
      if (type == 'card_declined')
        status = 'Declined';
      else if (type == 'card_refund')
        status = 'Refunded';
      else
        status = 'Successful';

      transactionDateTime = parsedTs != null
          ? DateFormat("MMMM d, yyyy 'at' h:mm:ss a 'UTC+1'").format(parsedTs)
          : '';

      String? declineReasonText;
      if (type == 'card_declined') {
        if (data['reason'] != null && data['reason'].toString().isNotEmpty) {
          declineReasonText = data['reason'].toString();
        }
        if (data['declineReason'] != null) {
          final code = data['declineReason'].toString();
          if (code == 'insufficient_funds')
            declineReasonText = 'Insufficient wallet balance';
          else if (code == 'card_frozen')
            declineReasonText = 'Card is frozen';
          else if (code == 'channel_blocked') {
            final ch = (data['declineChannelLabel']?.toString() ?? '')
                .toLowerCase();
            final label = ch == 'pos'
                ? 'POS (in-store)'
                : ch == 'atm'
                ? 'ATM'
                : 'Online (Web)';
            declineReasonText =
                '$label transactions are disabled on this card.\nTo enable: Cards → tap card → ••• menu → Card Channels → turn on $label.';
          } else
            declineReasonText = code;
        }
      }

      recipientDetails = [
        {'label': 'Merchant', 'value': data['merchant']?.toString() ?? ''},
        if ((data['channel'] ?? '').toString().isNotEmpty)
          {
            'label': 'Channel',
            'value': (data['channel']?.toString() ?? '').toUpperCase(),
          },
        {'label': 'Currency', 'value': data['currency']?.toString() ?? 'NGN'},
        if (type == 'card_declined' && declineReasonText != null)
          {'label': 'Decline Reason', 'value': declineReasonText},
      ];
      senderDetails = [];
      transactionInfo = [
        {'label': 'Transaction No.', 'value': transactionNo},
        if (widget.reference.isNotEmpty)
          {'label': 'Reference', 'value': widget.reference},
      ];
    });
  }

  void _generateTransactionIds() {
    setState(() => transactionNo = widget.reference);
  }

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  String getFormattedAmount() {
    final number = double.parse(amount.isEmpty ? '0' : amount);
    return NumberFormat('#,###').format(number);
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length < 7) return accountNumber;
    return '${accountNumber.substring(0, 3)}****${accountNumber.substring(accountNumber.length - 3)}';
  }

  String _normalizedStatus() {
    final raw = status.trim().toUpperCase();
    if (raw == 'SUCCESSFUL' ||
        raw == 'SUCCESS' ||
        raw == 'COMPLETED' ||
        raw == 'APPROVED')
      return 'SUCCESSFUL';
    if (raw == 'FAILED' ||
        raw == 'FAIL' ||
        raw == 'DECLINED' ||
        raw == 'UNSUCCESSFUL')
      return 'FAILED';
    if (raw == 'PENDING' || raw == 'PROCESSING' || raw == 'IN_PROGRESS')
      return 'PENDING';
    if (raw == 'REFUNDED') return 'REFUNDED';
    return raw.isEmpty ? 'PENDING' : raw;
  }

  String _statusDisplayLabel() {
    switch (_normalizedStatus()) {
      case 'SUCCESSFUL':
        return 'Successful';
      case 'FAILED':
        return 'Failed';
      case 'PENDING':
        return 'Pending';
      case 'REFUNDED':
        return 'Refunded';
      default:
        final s = status.trim();
        return s.isEmpty
            ? 'Pending'
            : s[0].toUpperCase() + s.substring(1).toLowerCase();
    }
  }

  Color _getStatusColor() {
    switch (_normalizedStatus()) {
      case 'SUCCESSFUL':
        return const Color(0xFF00A86B);
      case 'FAILED':
        return Colors.red;
      case 'PENDING':
        return Colors.orange;
      case 'REFUNDED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  PdfColor _getPdfStatusColor() {
    switch (_normalizedStatus()) {
      case 'SUCCESSFUL':
        return PdfColor.fromHex('00A86B');
      case 'FAILED':
        return PdfColors.red;
      case 'PENDING':
        return PdfColors.orange;
      case 'REFUNDED':
        return PdfColors.blue;
      default:
        return PdfColors.grey;
    }
  }

  List<Map<String, String>> _getFeeBreakdown() {
    final breakdown = <Map<String, String>>[];
    final principalVal = double.tryParse(principalAmount) ?? 0.0;
    final totalVal = _totalAmount ?? principalVal;

    if ((_fees ?? 0) > 0 || (_vat ?? 0) > 0 || (_stampDuty ?? 0) > 0) {
      if (principalVal > 0)
        breakdown.add({
          'label': 'Transfer Amount',
          'value': '₦${NumberFormat('#,##0.00').format(principalVal)}',
        });
      if ((_fees ?? 0) > 0)
        breakdown.add({
          'label': 'Transaction Fee',
          'value': '₦${NumberFormat('#,##0.00').format(_fees!)}',
        });
      if ((_vat ?? 0) > 0)
        breakdown.add({
          'label': 'VAT',
          'value': '₦${NumberFormat('#,##0.00').format(_vat!)}',
        });
      if ((_stampDuty ?? 0) > 0)
        breakdown.add({
          'label': 'Stamp Duty',
          'value': '₦${NumberFormat('#,##0.00').format(_stampDuty!)}',
        });
      if (totalVal != principalVal)
        breakdown.add({
          'label': 'Total Charged',
          'value': '₦${NumberFormat('#,##0.00').format(totalVal)}',
        });
    }
    return breakdown;
  }

  // ----------------------------------------------------------------------
  //  Share / PDF helpers (unchanged)
  // ----------------------------------------------------------------------
  Future<void> _shareImage() async {
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/receipt.png').writeAsBytes(pngBytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      debugPrint('Share image error: $e');
    }
  }

  pw.Widget _buildStatusIcon(double iconSize) {
    return pw.CustomPaint(
      size: PdfPoint(iconSize, iconSize),
      painter: (PdfGraphics canvas, PdfPoint size) {
        canvas.setStrokeColor(_getPdfStatusColor());
        canvas.setLineWidth(2);
        canvas.drawEllipse(0, 0, size.x, size.y);
        canvas.strokePath();
        if (_normalizedStatus() == 'SUCCESSFUL') {
          canvas.moveTo(size.x * 0.2, size.y * 0.55);
          canvas.lineTo(size.x * 0.45, size.y * 0.75);
          canvas.lineTo(size.x * 0.8, size.y * 0.35);
          canvas.strokePath();
        } else if (_normalizedStatus() == 'FAILED') {
          canvas.moveTo(size.x * 0.3, size.y * 0.3);
          canvas.lineTo(size.x * 0.7, size.y * 0.7);
          canvas.moveTo(size.x * 0.7, size.y * 0.3);
          canvas.lineTo(size.x * 0.3, size.y * 0.7);
          canvas.strokePath();
        } else {
          canvas.moveTo(size.x * 0.5, size.y * 0.2);
          canvas.lineTo(size.x * 0.5, size.y * 0.8);
          canvas.strokePath();
        }
      },
    );
  }

  pw.Widget _buildDetailsSection(
    String title,
    List<Map<String, String>> details,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        ...details.map(
          (item) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    item['label'] ?? '',
                    style: pw.TextStyle(
                      color: PdfColors.grey,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    item['value'] ?? '',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();
    final font = PdfFont.helvetica(pdf.document);
    final feeBreakdown = _getFeeBreakdown();

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Stack(
          children: [
            pw.CustomPaint(
              size: PdfPoint(
                context.page.pageFormat.width - 64,
                context.page.pageFormat.height - 64,
              ),
              painter: (PdfGraphics canvas, PdfPoint size) {
                canvas.saveContext();
                final currentTransform = canvas.getTransform();
                final rotation = vm.Matrix4.rotationZ(45 * math.pi / 180);
                canvas.setTransform(rotation.multiplied(currentTransform));
                canvas.setFillColor(PdfColor(0.5, 0.5, 0.5, 0.07));
                const spacing = 100.0;
                for (double x = -size.x * 2; x < size.x * 2; x += spacing) {
                  for (double y = -size.y * 2; y < size.y * 2; y += spacing) {
                    canvas.drawString(font, 25, 'PadiPay', x, y / 4);
                  }
                }
                canvas.restoreContext();
              },
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        color: _getPdfStatusColor(),
                        shape: pw.BoxShape.circle,
                      ),
                      child: _buildStatusIcon(30),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      "NGN ${getFormattedAmount()}",
                      style: pw.TextStyle(
                        fontSize: 30,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _buildStatusIcon(16),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          _statusDisplayLabel(),
                          style: pw.TextStyle(color: _getPdfStatusColor()),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      transactionDateTime,
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey500,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 5),
                  _buildDetailsSection("Recipient Details", recipientDetails),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  _buildDetailsSection("Sender Details", senderDetails),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  if (feeBreakdown.isNotEmpty) ...[
                    pw.SizedBox(height: 10),
                    _buildDetailsSection("Fees & Charges", feeBreakdown),
                    pw.SizedBox(height: 10),
                    pw.Divider(color: PdfColors.grey300),
                  ],
                  pw.SizedBox(height: 10),
                  _buildDetailsSection(
                    "Transaction Information",
                    transactionInfo,
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(20),
                    ),
                    child: pw.Text(
                      "Enjoy a better life with PadiPay. Get free transfers, instant loans, and cashback rewards.",
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(color: PdfColors.grey500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> _sharePdf() async {
    try {
      final bytes = await _generatePdf();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/receipt.pdf').writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      debugPrint('Share PDF error: $e');
    }
  }

  Future<void> refresh() async {
    navigateTo(
      context,
      ReceiptPage(reference: widget.reference, cardData: widget.cardData),
      type: NavigationType.replace,
    );
  }

  Widget _buildDetailsSectionUI(
    String title,
    List<Map<String, String>> details,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        ...details.map(
          (item) => Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      item['label'] ?? '',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Text(
                      item['value'] ?? '',
                      textAlign: TextAlign.right,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(
        bottom: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _shareImage,
              child: Container(
                margin: const EdgeInsets.only(left: 20, top: 15, bottom: 25),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Text(
                      "Share Image",
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: _sharePdf,
              child: Container(
                margin: const EdgeInsets.only(right: 20, top: 15, bottom: 25),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article, size: 20, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Text(
                      "Share PDF",
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
        title: Text(
          "Share Receipt",
          style: GoogleFonts.inter(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          RefreshIndicator(
            color: primaryColor,
            backgroundColor: Colors.white,
            onRefresh: refresh,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade100,
                    offset: const Offset(1, 1.5),
                  ),
                ],
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(brightness: Brightness.light),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(platformBrightness: Brightness.light),
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: Container(
                        color: Colors.white,
                        child: CustomPaint(
                          painter: WatermarkPainter(),
                          child: _buildBody(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [
                    Colors.green,
                    Colors.blue,
                    Colors.pink,
                    Colors.orange,
                    Colors.purple,
                  ],
                  numberOfParticles: 30,
                  gravity: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.cardData != null) {
      // cardData flow is synchronous, already populated
      return _buildReceiptContent();
    }

    if (_hasTimedOut) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              "Receipt not ready yet",
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "The transaction record is still being processed.\nPlease try again in a few seconds.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasTimedOut = false;
                  isLoadingDetails = true;
                  _listenForTransaction();
                  Future.delayed(const Duration(seconds: 10), () {
                    if (mounted && isLoadingDetails && !_hasTimedOut)
                      setState(() => _hasTimedOut = true);
                  });
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: Text(
                "Retry",
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (isLoadingDetails) {
      return _buildShimmerSkeleton();
    }

    return _buildReceiptContent();
  }

  Widget _buildReceiptContent() {
    final feeBreakdown = _getFeeBreakdown();
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _getStatusColor().withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _normalizedStatus() == 'SUCCESSFUL'
                ? Icons.check_circle_rounded
                : (_normalizedStatus() == 'FAILED'
                      ? Icons.cancel_outlined
                      : Icons.hourglass_empty_rounded),
            size: 30,
            color: _getStatusColor(),
          ),
        ),
        Text(
          "₦${getFormattedAmount()}",
          style: GoogleFonts.inter(
            color: Colors.black,
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _normalizedStatus() == 'SUCCESSFUL'
                  ? Icons.check_circle_rounded
                  : (_normalizedStatus() == 'FAILED'
                        ? Icons.cancel_outlined
                        : Icons.hourglass_empty_rounded),
              size: 16,
              color: _getStatusColor(),
            ),
            const SizedBox(width: 5),
            Text(
              _statusDisplayLabel(),
              style: GoogleFonts.inter(color: _getStatusColor()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          transactionDateTime,
          style: GoogleFonts.inter(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: Colors.grey.shade300),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              _buildDetailsSectionUI("Recipient Details", recipientDetails),
              Divider(color: Colors.grey.shade300),
              const SizedBox(height: 10),
              _buildDetailsSectionUI("Sender Details", senderDetails),
              const SizedBox(height: 10),
              Divider(color: Colors.grey.shade300),
              if (feeBreakdown.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildDetailsSectionUI("Fees & Charges", feeBreakdown),
                const SizedBox(height: 10),
                Divider(color: Colors.grey.shade300),
              ],
              const SizedBox(height: 10),
              _buildDetailsSectionUI(
                "Transaction Information",
                transactionInfo,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Enjoy a better life with PadiPay. Get free transfers, instant loans, and cashback rewards.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(child: _Shimmer(width: 60, height: 60, borderRadius: 60)),
          const SizedBox(height: 10),
          Center(child: _Shimmer(width: 200, height: 28, borderRadius: 8)),
          const SizedBox(height: 6),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Shimmer(width: 16, height: 16, borderRadius: 8),
                const SizedBox(width: 6),
                _Shimmer(width: 80, height: 12, borderRadius: 6),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 14, borderRadius: 6),
          const SizedBox(height: 10),
          _Shimmer(width: double.infinity, height: 12),
          const SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 12),
          const SizedBox(height: 16),
          _Shimmer(width: double.infinity, height: 14, borderRadius: 6),
          const SizedBox(height: 10),
          _Shimmer(width: double.infinity, height: 12),
          const SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 12),
          const SizedBox(height: 16),
          _Shimmer(width: double.infinity, height: 80, borderRadius: 12),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
//  Shimmer widget (unchanged)
// ----------------------------------------------------------------------
class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const _Shimmer({
    this.width = double.infinity,
    this.height = 12,
    this.borderRadius = 8,
  });

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade300,
              Colors.grey.shade100,
              Colors.grey.shade300,
            ],
            stops: [
              (_controller.value - 0.3).clamp(0.0, 1.0),
              _controller.value,
              (_controller.value + 0.3).clamp(0.0, 1.0),
            ],
            begin: Alignment(-1, -0.3),
            end: Alignment(1, 0.3),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
//  Watermark painter (unchanged)
// ----------------------------------------------------------------------
class WatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'PadiPay',
        style: GoogleFonts.inter(
          fontSize: 25,
          color: Colors.grey.withValues(alpha: 0.07),
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    canvas.save();
    canvas.rotate(45 * math.pi / 180);
    const spacing = 100.0;
    for (double x = -size.width * 2; x < size.width * 2; x += spacing) {
      for (double y = -size.height * 2; y < size.height * 2; y += spacing) {
        textPainter.paint(canvas, Offset(x, y / 4));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
