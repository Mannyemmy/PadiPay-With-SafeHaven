import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      elevation: 1,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: 80,
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(child: _buildNavItem(0, FontAwesomeIcons.house, "Home")),
            Expanded(
              child: _buildNavItem(1, FontAwesomeIcons.creditCard, "Cards"),
            ),

            Expanded(
              child: _buildNavItem(
                2,
                FontAwesomeIcons.fileContract,
                "Transactions",
              ),
            ),
            Expanded(child: _buildNavItem(3, FontAwesomeIcons.user, "Profile")),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = index == currentIndex;
    return InkWell(
      onTap: () => onTap(index),
      child: Stack(
        children: [
          Align(
            alignment: AlignmentGeometry.center,

            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? primaryColor : Colors.grey,
                    size: 20,
                  ),
                  SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? primaryColor : Colors.grey,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (label == "Cards")
            Positioned(
              child: Align(
                alignment: Alignment.topRight,
                child: Transform.translate(
                  offset: Offset(-4, 0),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.lightGreen,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      "Hot",
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
