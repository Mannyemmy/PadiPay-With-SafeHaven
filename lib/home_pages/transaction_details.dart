import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class TransactionDetailsPage extends StatefulWidget {
  final String transactionId;
  const TransactionDetailsPage({super.key, required this.transactionId});

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  Map<String, dynamic>? transactionData;
  Map<String, dynamic>? senderData;
  Map<String, dynamic>? receiverData;
  DateTime? transactionDate;
  String? amount;
  String? status;
  bool isLoading = true;
  String? errorMessage;

  String getFormattedTransactionDateTime() {
    if (transactionDate == null) return '';
    final formattedDate = DateFormat("MMMM d, y - h:mm a").format(transactionDate!);
    return formattedDate;
  }

  @override
  void initState() {
    super.initState();
    fetchTransactionDetails();
  }

  Future<void> fetchTransactionDetails() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      DocumentSnapshot transDoc = await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .get();
      if (!transDoc.exists) {
        setState(() {
          isLoading = false;
          errorMessage = 'Transaction not found';
        });
        return;
      }

      transactionData = transDoc.data() as Map<String, dynamic>;
      amount = transactionData!['amount'].toString();
      status = transactionData!['status'] is String
          ? transactionData!['status']
          : transactionData!['status'] == true
              ? 'Successful'
              : 'Failed';
      transactionDate = (transactionData!['timestamp'] as Timestamp?)?.toDate() ??
          (transactionData!['createdAtFirestore'] as Timestamp).toDate();

      DocumentSnapshot senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(transactionData!['senderId'])
          .get();
      if (senderDoc.exists) {
        senderData = senderDoc.data() as Map<String, dynamic>;
      }

      DocumentSnapshot receiverDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(transactionData!['receiverId'])
          .get();
      if (receiverDoc.exists) {
        receiverData = receiverDoc.data() as Map<String, dynamic>;
      }

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Error fetching transaction details: $e';
      });
    }
  }

  String get senderName =>
      senderData != null ? "${senderData!['firstName']} ${senderData!['lastName']}" : "Unknown";
  String get recipientName =>
      receiverData != null ? "${receiverData!['firstName']} ${receiverData!['lastName']}" : "Unknown";

  Future<void> _shareImage() async {
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/receipt.png').writeAsBytes(pngBytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing image: $e')),
      );
    }
  }

  pw.Widget _buildCheckIcon(double iconSize) {
    return pw.CustomPaint(
      size: PdfPoint(iconSize, iconSize),
      painter: (PdfGraphics canvas, PdfPoint size) {
        canvas.setStrokeColor(PdfColor.fromHex('00A86B'));
        canvas.setLineWidth(2);
        canvas.drawEllipse(0, 0, size.x, size.y);
        canvas.strokePath();
        canvas.moveTo(size.x * 0.2, size.y * 0.55);
        canvas.lineTo(size.x * 0.45, size.y * 0.75);
        canvas.lineTo(size.x * 0.8, size.y * 0.35);
        canvas.strokePath();
      },
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
              size: PdfPoint(context.page.pageFormat.width - 64, context.page.pageFormat.height - 64),
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
                        color: PdfColor(0.0, 0.6588, 0.4196, 0.1),
                        shape: pw.BoxShape.circle,
                      ),
                      child: _buildCheckIcon(30),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      "NGN $amount",
                      style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        _buildCheckIcon(16),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          status ?? 'Successful',
                          style: pw.TextStyle(
                            color: status == 'Successful' ? PdfColor.fromHex('00A86B') : PdfColors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      getFormattedTransactionDateTime(),
                      style: pw.TextStyle(fontSize: 14, color: PdfColors.grey500, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 5),
                  pw.Text("Recipient Details", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Recipient Name", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text(recipientName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Bank Name", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Access Bank", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Account Number", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text("012****789", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  pw.Text("Sender Details", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Sender Name", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text(senderName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Bank Name", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text("PadiPay", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Account Number", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text("785****345", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 10),
                  pw.Text("Transaction Information", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 20),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Transaction No.", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text(widget.transactionId, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Session ID", style: pw.TextStyle(color: PdfColors.grey, fontWeight: pw.FontWeight.bold)),
                      pw.Text("SES-4F3A2B1C", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text(errorMessage!, style: TextStyle(color: Colors.red))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: Row(
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
      body: Container(
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
              data: MediaQuery.of(context).copyWith(platformBrightness: Brightness.light),
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  color: Colors.white,
                  child: CustomPaint(
                    painter: WatermarkPainter(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 10),
                        Container(
                          padding: EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Color(0xFF00A86B).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            size: 30,
                            color: Color(0xFF00A86B),
                          ),
                        ),
                        Text(
                          "₦$amount",
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
                              Icons.check_circle_outline_rounded,
                              size: 16,
                              color: status == 'Successful' ? Color(0xFF00A86B) : Colors.red,
                            ),
                            SizedBox(width: 5),
                            Text(
                              status ?? 'Successful',
                              style: TextStyle(
                                color: status == 'Successful' ? Color(0xFF00A86B) : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.access_time,
                              color: Colors.grey,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              DateFormat('HH:mm').format(transactionDate!),
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                            Text(
                              DateFormat('MMMM d, yyyy').format(transactionDate!),
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Divider(color: Colors.grey.shade300),
                        SizedBox(height: 5),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "Recipient Details",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Recipient Name",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    recipientName,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Bank Name",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    "Access Bank",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Account Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    "012****789",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Divider(color: Colors.grey.shade300),
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    "Sender Details",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Sender Name",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    senderName,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Bank Name",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    "PadiPay",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Account Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    "785****345",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Divider(color: Colors.grey.shade300),
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    "Transaction Information",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Transaction No.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    widget.transactionId,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Session ID",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    "SES-4F3A2B1C",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
                ),
              ),
            ),
          ),
        ),
      ),
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