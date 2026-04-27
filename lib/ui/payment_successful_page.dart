import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/ui/receipt_page.dart';
import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentSuccessfulPage extends StatefulWidget {
  final String actionText;
  final String title;
  final String description;
  final String amount;
  final String recipientName;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String reference;

  const PaymentSuccessfulPage({
    super.key,
    required this.bankName,
    required this.actionText,
    required this.title,
    required this.description,
    required this.amount,
    required this.recipientName,
    required this.bankCode,
    required this.accountNumber,
    required this.reference,
  });

  @override
  State<PaymentSuccessfulPage> createState() => _PaymentSuccessfulPageState();
}

class _PaymentSuccessfulPageState extends State<PaymentSuccessfulPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _circleAnimation;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _circleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String formatNumber(String numberString) {
    final number = int.tryParse(numberString.replaceAll(',', '')) ?? 0;
    return NumberFormat('#,###').format(number);
  }

  @override
  Widget build(BuildContext context) {
    const double size = 200;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        navigateTo(context, HomePage(), type: NavigationType.clearStack);
      },
      child: Scaffold(
        body: SafeArea(bottom: true,
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Container(
              color: primaryColor,
              child: SafeArea(bottom: true,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          InkWell(
                            onTap: () {
                              navigateTo(context, HomePage());
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                "Done",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),Spacer(),
                      Center(
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _circleAnimation,
                                builder: (context, child) {
                                  return SizedBox(
                                    width: size,
                                    height: size,
                                    child: CircularProgressIndicator(
                                      value: _circleAnimation.value,
                                      strokeWidth: 8,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                      backgroundColor: Colors.white24,
                                    ),
                                  );
                                },
                              ),
                              ScaleTransition(
                                scale: _checkScale,
                                child: const Icon(
                                  Icons.verified,
                                  color: Colors.white,
                                  size: 120,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      widget.amount == "0"
                          ? Text(
                              "₦${formatNumber(widget.amount)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 30,
                                color: Colors.white,
                              ),
                            )
                          : SizedBox.shrink(),
                      SizedBox(height: 15),
                      Text(
                        widget.description,
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),
                      ElevatedButton(
                        onPressed: () {
                          navigateTo(
                            context,
                            ReceiptPage(reference: widget.reference),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: primaryColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share, color: primaryColor, size: 22),
                            SizedBox(width: 15),
                            Text(
                              "Share Receipt",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Spacer(),
                    ],
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
