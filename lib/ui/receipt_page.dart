import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  String transactionNo = '';
  String senderName = '';
  String senderAccountNumber = '';
  String senderBankName = '';
  String amount = '';
  String status = '';
  String transactionDateTime = '';
  String transactionType = '';
  bool isLoadingDetails = true;
  List<Map<String, String>> recipientDetails = []; 
  List<Map<String, String>> senderDetails = [];
  List<Map<String, String>> transactionInfo = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactionDetails();
    _generateTransactionIds();
  }

  Future<void> _fetchTransactionDetails() async {
    setState(() => isLoadingDetails = true);
    if (widget.cardData != null) {
      _populateFromCardData(widget.cardData!);
      return;
    }
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final transactionDoc = await FirebaseFirestore.instance
          .collection('transactions')
          .where('reference', isEqualTo: widget.reference)
          .get();

      if (transactionDoc.docs.isNotEmpty) {
        final data = transactionDoc.docs.first.data();
        final userId = data['userId'] as String?;
        final actualSender = data['actualSender'] as String?;
        String transactionType = data['type'] as String? ?? '';
        
        // Check if this is an anonymous transfer and current user is the recipient
        final isAnonymousTransfer = 
            transactionType.toLowerCase() == 'ghost_transfer' ||
            transactionType.toLowerCase() == 'anonymous_transfer';
        final isSent = userId == currentUserId || actualSender == currentUserId;
        final isReceivedAnonymously = isAnonymousTransfer && !isSent;
        
        final userIdForLookup = (actualSender != null && actualSender.isNotEmpty) ? actualSender : userId;
        final rawTs = data['createdAtFirestore'] ?? data['timestamp'];

        // Fetch sender details only if NOT a received anonymous transfer
        String fetchedSenderName = '';
        String fetchedSenderAccountNumber = '';
        String fetchedSenderBankName = '';
        if (!isReceivedAnonymously && userIdForLookup != null && userIdForLookup.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userIdForLookup)
                .get();

            if (userDoc.exists) {
              final userData = userDoc.data()!;
              fetchedSenderName = "${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}".trim();
              if (fetchedSenderName.isEmpty) {
                fetchedSenderName = userData['userName'] ?? '';
              }

              final safehavenData = userData['safehavenData'] as Map<String, dynamic>?;
              if (safehavenData != null) {
                final virtualAccount = safehavenData['virtualAccount'] as Map<String, dynamic>?;
                if (virtualAccount != null) {
                  fetchedSenderAccountNumber = virtualAccount['data']['attributes']['accountNumber']?.toString() ?? '';
                  fetchedSenderBankName = virtualAccount['data']['attributes']['bank']?['name']?.toString() ?? '';
                }
              }
            }
          } catch (e) {
            debugPrint('Error fetching sender user doc: $e');
          }
        } else if (isReceivedAnonymously) {
          // For received anonymous transfers, fetch company details
          try {
            final companyDoc = await FirebaseFirestore.instance
                .collection('company')
                .doc('account_details')
                .get();

            if (companyDoc.exists) {
              final companyData = companyDoc.data()!;
              fetchedSenderName = companyData['accountName']?.toString() ?? 'PadiPay';
              fetchedSenderAccountNumber = companyData['accountNumber']?.toString() ?? '';
              fetchedSenderBankName = companyData['bankName']?.toString() ?? '';
            }
          } catch (e) {
            debugPrint('Error fetching company details: $e');
            // Fallback to generic company name
            fetchedSenderName = 'PadiPay';
            fetchedSenderAccountNumber = '';
            fetchedSenderBankName = '';
          }
        }

        // Safely format timestamp
        DateTime? parsedTs;
        if (rawTs is Timestamp) {
          parsedTs = rawTs.toDate();
        } else if (rawTs is DateTime) {
          parsedTs = rawTs;
        } else if (rawTs is int) {
          parsedTs = DateTime.fromMillisecondsSinceEpoch(rawTs);
        } else if (rawTs is String) {
          try {
            parsedTs = DateTime.parse(rawTs);
          } catch (_) {
            parsedTs = null;
          }
        }

        setState(() {
          transactionType = data['type'] ?? '';
          amount = (data['amount'] ?? 0).toString();
          status = data['status'] ?? (data['api_response']?['data']?['attributes']?['status'] ?? '');
          transactionDateTime = parsedTs != null
              ? DateFormat("MMMM d, yyyy 'at' h:mm:ss a 'UTC+1'").format(parsedTs)
              : '';

          if (transactionType == 'transfer'||transactionType == 'ghost_transfer') {
            recipientDetails = [
              {'label': 'Recipient Name', 'value': data['recipientName'] ?? ''},
              {'label': 'Bank Name', 'value': data['bankName'] ?? ''},
              {'label': 'Account Number', 'value': data['account_number'] ?? ''},
            ];
          } else if (transactionType == 'airtime') {
            recipientDetails = [
              {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
              {'label': 'Network', 'value': data['network'] ?? ''},
            ];
          } else if (transactionType == 'data') {
            recipientDetails = [
              {'label': 'Phone Number', 'value': data['phoneNumber'] ?? ''},
              {'label': 'Network', 'value': data['network'] ?? ''},
              {'label': 'Bundle', 'value': data['bundle'] ?? ''},
            ];
          } else if (transactionType == 'cable') {
            recipientDetails = [
              {'label': 'Smartcard Number', 'value': data['fullData']?['customerDetail']?['smartcardNumber'] ?? ''},
              {'label': 'Provider', 'value': data['network'] ?? ''},
              {'label': 'Plan', 'value': data['plan'] ?? ''},
            ];
          } else if (transactionType == 'electricity') {
            recipientDetails = [
              {'label': 'Meter Number', 'value': data['meterNumber'] ?? ''},
              {'label': 'Disco', 'value': data['disco'] ?? ''},
              {'label': 'Token', 'value': data['token'] ?? ''},
              {'label': 'Units', 'value': data['units'] ?? ''},
            ];
          }

          senderName = fetchedSenderName;
          senderAccountNumber = fetchedSenderAccountNumber;
          senderBankName = fetchedSenderBankName;

          senderDetails = [
            {'label': 'Sender Name', 'value': senderName},
            if (senderBankName.isNotEmpty) {'label': 'Bank Name', 'value': senderBankName},
            if (senderAccountNumber.isNotEmpty) {'label': 'Account Number', 'value': _maskAccountNumber(senderAccountNumber)},
          ];

          transactionInfo = [
            {'label': 'Transaction No.', 'value': transactionNo},
            {'label': 'Reference', 'value': widget.reference},
          ];
        });
      }
    } catch (e) {
      // Handle error if needed
    } finally {
      if (mounted) setState(() => isLoadingDetails = false);
    }
  }

  void _generateTransactionIds() {
    setState(() {
      transactionNo = widget.reference;
    });
  }

  String getFormattedAmount() {
    final number = double.parse(amount.isEmpty ? '0' : amount);
    final formatter = NumberFormat('#,###');
    return formatter.format(number);
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length < 7) return accountNumber;
    return '${accountNumber.substring(0, 3)}****${accountNumber.substring(accountNumber.length - 3)}';
  }

  void _populateFromCardData(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final parsedTs = ts?.toDate();
    setState(() {
      transactionType = type;
      amount = (data['amount'] ?? 0).toString();
      if (type == 'card_declined') {
        status = 'Declined';
      } else if (type == 'card_refund') {
        status = 'Refunded';
      } else {
        status = 'Successful';
      }
      transactionDateTime = parsedTs != null
          ? DateFormat("MMMM d, yyyy 'at' h:mm:ss a 'UTC+1'").format(parsedTs)
          : '';
      String? declineReasonText;
      if (type == 'card_declined') {
        // authorization.declined events store a raw 'reason' string from Sudo
        if (data['reason'] != null && data['reason'].toString().isNotEmpty) {
          declineReasonText = data['reason'].toString();
        }
        // authorization.request declines store a structured 'declineReason' code
        if (data['declineReason'] != null) {
          final code = data['declineReason'].toString();
          if (code == 'insufficient_funds') {
            declineReasonText = 'Insufficient wallet balance';
          } else if (code == 'card_frozen') {
            declineReasonText = 'Card is frozen';
          } else if (code == 'channel_blocked') {
            final ch = (data['declineChannelLabel']?.toString() ?? '').toLowerCase();
            final label = ch == 'pos' ? 'POS (in-store)' : ch == 'atm' ? 'ATM' : 'Online (Web)';
            declineReasonText = '$label transactions are disabled on this card.\nTo enable: Cards → tap card → ••• menu → Card Channels → turn on $label.';
          } else {
            declineReasonText = code;
          }
        }
      }
      recipientDetails = [
        {'label': 'Merchant', 'value': data['merchant']?.toString() ?? ''},
        if ((data['channel'] ?? '').toString().isNotEmpty)
          {'label': 'Channel', 'value': (data['channel']?.toString() ?? '').toUpperCase()},
        {'label': 'Currency', 'value': data['currency']?.toString() ?? 'NGN'},
        if (type == 'card_declined' && declineReasonText != null)
          {'label': 'Decline Reason', 'value': declineReasonText},
      ];
      senderDetails = [];
      transactionInfo = [
        {'label': 'Transaction No.', 'value': transactionNo},
        if (widget.reference.isNotEmpty) {'label': 'Reference', 'value': widget.reference},
      ];
      isLoadingDetails = false;
    });
  }

  Color _getStatusColor() {
    switch (status.toUpperCase()) {
      case 'SUCCESSFUL':
        return Color(0xFF00A86B); // Green
      case 'FAILED':
      case 'DECLINED':
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
    switch (status.toUpperCase()) {
      case 'SUCCESSFUL':
        return PdfColor.fromHex('00A86B');
      case 'FAILED':
      case 'DECLINED':
        return PdfColors.red;
      case 'PENDING':
        return PdfColors.orange;
      case 'REFUNDED':
        return PdfColors.blue;
      default:
        return PdfColors.grey;
    }
  }

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
      // Handle error if needed
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
        if (status.toUpperCase() == 'SUCCESSFUL') {
          canvas.moveTo(size.x * 0.2, size.y * 0.55);
          canvas.lineTo(size.x * 0.45, size.y * 0.75);
          canvas.lineTo(size.x * 0.8, size.y * 0.35);
          canvas.strokePath();
        } else if (status.toUpperCase() == 'FAILED' || status.toUpperCase() == 'DECLINED') {
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

  pw.Widget _buildDetailsSection(String title, List<Map<String, String>> details) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        ...details.map((item) => pw.Column(
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
        )),
      ],
    );
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();
    final font = PdfFont.helvetica(pdf.document);

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
                          status,
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
                  pw.SizedBox(height: 10),
                  _buildDetailsSection("Transaction Information", transactionInfo),
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
      // Handle error if needed
    }
  }

  Future<void> refresh() async {
    navigateTo(context, ReceiptPage(reference: widget.reference, cardData: widget.cardData), type: NavigationType.replace);
  }

  Widget _buildDetailsSectionUI(String title, List<Map<String, String>> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.black,fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 10),
        ...details.map((item) => Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,fontSize: 12
                  ),
                ),
                Text(
                  item['value'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: SafeArea(bottom:true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _shareImage,
              child: Container(
                margin: EdgeInsets.only(left: 20, top: 15, bottom: 25),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20, color: Colors.grey.shade700),
                    SizedBox(width: 10),
                    Text(
                      "Share Image",
                      style: TextStyle(
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
                margin: EdgeInsets.only(right: 20, top: 15, bottom: 25),
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article, size: 20, color: Colors.grey.shade700),
                    SizedBox(width: 10),
                    Text(
                      "Share PDF",
                      style: TextStyle(
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
          onTap: () {
            Navigator.of(context).pop();
          },
          child: Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
        ),
        title: Text(
          "Share Receipt",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: primaryColor,
        backgroundColor: Colors.white,
        onRefresh: () => refresh(),
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.grey.shade100, offset: Offset(1, 1.5)),
            ],
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Theme(
              data: Theme.of(context).copyWith(brightness: Brightness.light),
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
                      child: isLoadingDetails ? _buildShimmerSkeleton() : Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 10),
                          Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _getStatusColor().withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              status.toUpperCase() == 'SUCCESSFUL'
                                  ? Icons.check_circle_outline_rounded
                                  : (status.toUpperCase() == 'FAILED' || status.toUpperCase() == 'DECLINED')
                                  ? Icons.cancel_outlined
                                  : Icons.hourglass_empty_rounded,
                              size: 30,
                              color: _getStatusColor(),
                            ),
                          ),
                          Text(
                            "₦${getFormattedAmount()}",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                status.toUpperCase() == 'SUCCESSFUL'
                                    ? Icons.check_circle_outline_rounded
                                    : (status.toUpperCase() == 'FAILED' || status.toUpperCase() == 'DECLINED')
                                    ? Icons.cancel_outlined
                                    : Icons.hourglass_empty_rounded,
                                size: 16,
                                color: _getStatusColor(),
                              ),
                              SizedBox(width: 5),
                              Text(
                                status,
                                style: TextStyle(color: _getStatusColor()),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Text(
                            transactionDateTime,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 10),
                          Divider(color: Colors.grey.shade300),
                          SizedBox(height: 5),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(
                              children: [
                                _buildDetailsSectionUI("Recipient Details", recipientDetails),
                                Divider(color: Colors.grey.shade300),
                                SizedBox(height: 10),
                                _buildDetailsSectionUI("Sender Details", senderDetails),
                                SizedBox(height: 10),
                                Divider(color: Colors.grey.shade300),
                                SizedBox(height: 10),
                                _buildDetailsSectionUI("Transaction Information", transactionInfo),
                                const SizedBox(height: 20),
                                Container(
                                  padding: EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    textAlign: TextAlign.center,
                                    "Enjoy a better life with PadiPay. Get free transfers, instant loans, and cashback rewards.",
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

  Widget _buildShimmerSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 10),
          Center(child: _Shimmer(width: 60, height: 60, borderRadius: 60)),
          SizedBox(height: 10),
          Center(child: _Shimmer(width: 200, height: 28, borderRadius: 8)),
          SizedBox(height: 6),
          Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Shimmer(width: 16, height: 16, borderRadius: 8),
            SizedBox(width: 6),
            _Shimmer(width: 80, height: 12, borderRadius: 6),
          ])),
          SizedBox(height: 10),
          Divider(color: Colors.grey.shade300),
          SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 14, borderRadius: 6),
          SizedBox(height: 10),
          _Shimmer(width: double.infinity, height: 12),
          SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 12),
          SizedBox(height: 16),
          _Shimmer(width: double.infinity, height: 14, borderRadius: 6),
          SizedBox(height: 10),
          _Shimmer(width: double.infinity, height: 12),
          SizedBox(height: 8),
          _Shimmer(width: double.infinity, height: 12),
          SizedBox(height: 16),
          _Shimmer(width: double.infinity, height: 80, borderRadius: 12),
        ],
      ),
    );
  }

  class _Shimmer extends StatefulWidget {
    final double width;
    final double height;
    final double borderRadius;
    const _Shimmer({this.width = double.infinity, this.height = 12, this.borderRadius = 8});

    @override
    State<_Shimmer> createState() => _ShimmerState();
  }

  class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
    late final AnimationController _controller;

    @override
    void initState() {
      super.initState();
      _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
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
        builder: (context, _) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              gradient: LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade100, Colors.grey.shade300],
                stops: [(_controller.value - 0.3).clamp(0.0, 1.0), _controller.value, (_controller.value + 0.3).clamp(0.0, 1.0)],
                begin: Alignment(-1, -0.3),
                end: Alignment(1, 0.3),
              ),
            ),
          );
        },
      );
    }
  }

class WatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.srcOver);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'PadiPay',
        style: TextStyle(
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