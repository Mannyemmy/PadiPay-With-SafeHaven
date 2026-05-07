import 'dart:math';

import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LoanPage extends StatefulWidget {
  const LoanPage({super.key});

  @override
  State<LoanPage> createState() => _LoanPageState();
}

class _LoanPageState extends State<LoanPage> {
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
        title: Text(
          "Loan",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.3)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Current Loan Balance",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "₦",
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 24),
                      ),
                    ],
                  ),
                  Text(
                    "₦3,299.00",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Of ₦5000 total",
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    "50% repaid",
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Next Payment",
                        style: GoogleFonts.inter(
                          color: Colors.black38,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      Text(
                        "₦300",
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        "Due on Oct 15, 2025",
                        style: GoogleFonts.inter(
                          color: Colors.black38,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.credit_card, color: primaryColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Quick Actions",
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => const SuccessBottomSheet(
                          actionText: "Done",
                          title: "Payment Successful",
                          description:
                              "Your loan payment has been made successfully.",
                        ),
                        isScrollControlled: true,
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            child: Image.asset(
                              "assets/mynaui_send.png",
                              width: 26,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Make Payment",
                            style: GoogleFonts.inter(
                              color: Colors.black45,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ApplyLoanPage(),
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            child: Image.asset(
                              "assets/proicons_document.png",
                              width: 26,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "New Loan",
                            style: GoogleFonts.inter(
                              color: Colors.black45,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ApplyLoanPage extends StatefulWidget {
  const ApplyLoanPage({super.key});

  @override
  State<ApplyLoanPage> createState() => _ApplyLoanPageState();
}

class _ApplyLoanPageState extends State<ApplyLoanPage> {
  double loanAmount = 14500.0;
  int repaymentDuration = 12;
  final double interestRate = 8.5;

  double get monthlyInterestRate => interestRate / 100 / 12;

  double get monthlyPayment {
    if (monthlyInterestRate == 0) return loanAmount / repaymentDuration;
    num temp = pow(1 + monthlyInterestRate, repaymentDuration);
    return loanAmount * monthlyInterestRate * temp / (temp - 1);
  }

  double get totalRepayment => monthlyPayment * repaymentDuration;

  double get totalInterest => totalRepayment - loanAmount;

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
        title: Text(
          "Apply for a Loan",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loan Amount',
                    style: GoogleFonts.inter(
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '₦${loanAmount.toStringAsFixed(0)}.00',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Slider(
              value: loanAmount,
              min: 1000.0,
              max: 17480.0,
              activeColor: primaryColor,
              onChanged: (value) {
                setState(() {
                  loanAmount = value;
                });
              },
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('1.000.00'), Text('17.480.00')],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Repayment Duration',
                        style: GoogleFonts.inter(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 5),
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 2, horizontal: 10),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        DropdownButton<int>(
                          icon: Icon(Icons.abc,color: Colors.transparent,),
                          value: repaymentDuration,
                          underline: const SizedBox(),
                          items: [3, 6, 9, 12, 18, 24]
                              .map(
                                (int value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value months',style: GoogleFonts.inter(color: Colors.grey),),
                                ),
                              )
                              .toList(),
                          onChanged: (int? newValue) {
                            setState(() {
                              repaymentDuration = newValue!;
                            });
                          },
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
               border: Border.all(color: Colors.grey.shade200)
              ),
              child:  Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Interest Rate', style: GoogleFonts.inter(color: Colors.grey)),
                  Text('8.5%',style: GoogleFonts.inter(color: Colors.black45,fontWeight: FontWeight.bold,fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repayment Summary',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold,fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Monthly Payment',style: GoogleFonts.inter(color: Colors.black45,fontWeight: FontWeight.w500),),
                      Text('₦${monthlyPayment.toStringAsFixed(2)}',style: GoogleFonts.inter(color: Colors.black54,fontWeight: FontWeight.w700,fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Interest',style: GoogleFonts.inter(color: Colors.black45,fontWeight: FontWeight.w500)),
                      Text('₦${totalInterest.toStringAsFixed(2)}',style: GoogleFonts.inter(color: Colors.black54,fontWeight: FontWeight.w700,fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Repayment',style: GoogleFonts.inter(color: Colors.black45,fontWeight: FontWeight.w500)),
                      Text('₦${totalRepayment.toStringAsFixed(2)}',style: GoogleFonts.inter(color: Colors.black54,fontWeight: FontWeight.w700,fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => const SuccessBottomSheet(
                    actionText: "Done",
                    title: "Application Submitted",
                    description:
                        "Your loan application has been submitted successfully.",
                  ),
                  isScrollControlled: true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Apply Now',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,fontSize: 15
                ),
              ),
            ),
            const SizedBox(height: 20),
             Center(
              child: Text(
                'By applying, you agree to our terms and conditions. Your application will be reviewed within 24 hours.',
                style: GoogleFonts.inter(color: Colors.grey, fontSize: 12,fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
