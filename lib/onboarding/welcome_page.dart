import 'package:card_app/auth/sign-in.dart';
import 'package:card_app/onboarding/onboarding_1.dart';
import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 15, top: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset('assets/welcome_graphic.png', width: screenWidth),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 35,
                    color: Colors.black,
                  ),
                  children: [
                    TextSpan(text: "Next-Gen Spending\nStarts "),
                    TextSpan(
                      text: "Here!",
                      style: TextStyle(color: Color(0xFF007AFF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Manage physical, virtual, and anonymous cards — "
                "fund your wallet, pay with NFC, and stay in control of your finances.",
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: Colors.black,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 30),

              // Get Started button
              InkWell(
                onTap: () {
                  navigateTo(context, Onboarding1());
                },
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(right: 15),
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Get Started",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(Icons.arrow_forward, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Login prompt
              InkWell(
                onTap: () {
                  navigateTo(context, SignIn());
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  margin: EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      vertical: BorderSide(
                        color: const Color(0xFF007AFF),
                        width: 2,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white,
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Already have an account?",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Login",
                          style: TextStyle(
                            color: Color(0xFF007AFF),
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
