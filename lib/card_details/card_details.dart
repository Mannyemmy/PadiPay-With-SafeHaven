import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:card_app/utils/screen_security.dart';
import 'package:google_fonts/google_fonts.dart';

class CardDetailsPage extends StatefulWidget {
  const CardDetailsPage({super.key});

  @override
  State<CardDetailsPage> createState() => _CardDetailsPageState();
}

class _CardDetailsPageState extends State<CardDetailsPage> {
  @override
  void initState() {
    super.initState();
    ScreenSecurity.secureOn();
  }

  @override
  void dispose() {
    ScreenSecurity.secureOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: navyBlue,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(height: 60),
                Text(
                  'Card Details',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Name on Card'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'Name',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Card PAN'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '6924464649477974924794479',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Card Exp Date'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '09/36',
                  ),
                ),
                const SizedBox(height: 16),
                Text('CVV'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '787',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Default PIN'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: '6924',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Address'),
                const SizedBox(height: 8),
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'address example',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
