import 'package:flutter/material.dart';

class Keypad extends StatelessWidget {
  final Function(String?) onPressed;
  final Widget? rightChild;
  const Keypad({super.key, required this.onPressed, this.rightChild});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['1', '2', '3'].map((n) => _buildButton(n)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['4', '5', '6'].map((n) => _buildButton(n)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['7', '8', '9'].map((n) => _buildButton(n)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Backspace on the left, red
            SizedBox(
              width: 80,
              height: 56,
              child: TextButton(
                onPressed: () => onPressed(null),
                child: const Icon(Icons.backspace_outlined, size: 28, color: Colors.red),
              ),
            ),
            _buildButton('0'),
            // Right slot: tick or empty placeholder
            SizedBox(
              width: 80,
              height: 56,
              child: rightChild ?? const SizedBox(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildButton(String? text) {
    return SizedBox(
      width: 80,
      height: 56,
      child: TextButton(
        onPressed: () => onPressed(text),
        child: Text(
          text!,
          style: const TextStyle(fontSize: 32, color: Colors.black),
        ),
      ),
    );
  }
}
