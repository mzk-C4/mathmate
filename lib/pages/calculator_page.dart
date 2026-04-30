import 'package:flutter/material.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  String _display = '0';
  double _num1 = 0;
  double _num2 = 0;
  String _operator = '';
  bool _operatorPressed = false;
  bool _decimalAdded = false;

  void _buttonPressed(String text) {
    setState(() {
      if (text == 'C') {
        _display = '0';
        _num1 = 0;
        _num2 = 0;
        _operator = '';
        _operatorPressed = false;
        _decimalAdded = false;
      } else if (text == '⌫') {
        if (_display.length > 1) {
          _display = _display.substring(0, _display.length - 1);
        } else {
          _display = '0';
        }
      } else if (text == '+/-') {
        if (_display != '0') {
          _display = _display.startsWith('-')
              ? _display.substring(1)
              : '-$_display';
        }
      } else if (text == '%') {
        final double value = double.parse(_display) / 100;
        _display = _formatResult(value);
      } else if (text == '.') {
        if (!_decimalAdded) {
          _display = '$_display.';
          _decimalAdded = true;
        }
      } else if (text == '÷' || text == '×' || text == '-' || text == '+') {
        _num1 = double.parse(_display);
        _operator = text;
        _operatorPressed = true;
        _decimalAdded = false;
      } else if (text == '=') {
        _num2 = double.parse(_display);
        double result;
        switch (_operator) {
          case '+':
            result = _num1 + _num2;
          case '-':
            result = _num1 - _num2;
          case '×':
            result = _num1 * _num2;
          case '÷':
            result = _num2 != 0 ? _num1 / _num2 : double.nan;
          default:
            result = double.parse(_display);
        }
        _display = _formatResult(result);
        _num1 = 0;
        _num2 = 0;
        _operator = '';
        _operatorPressed = false;
        _decimalAdded = _display.contains('.');
      } else {
        if (_operatorPressed) {
          _display = text;
          _operatorPressed = false;
        } else {
          _display = _display == '0' ? text : '$_display$text';
        }
      }
    });
  }

  String _formatResult(double value) {
    if (value.isNaN) return 'Error';
    if (value.isInfinite) return 'Error';
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(10);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  Widget _buildButton(String text, {Color? color, Color? textColor}) {
    final Color bg = color ?? Colors.grey.shade200;
    final Color fg = textColor ?? Colors.black87;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _buttonPressed(text),
            child: Container(
              alignment: Alignment.center,
              height: 56,
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('计算器'),
        backgroundColor: Colors.blue.withValues(alpha: 0.1),
      ),
      body: Column(
        children: <Widget>[
          // Display
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            color: Colors.white,
            child: Text(
              _display,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w300,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          // Keypad
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  // Row 1
                  Row(
                    children: <Widget>[
                      _buildButton('C', color: Colors.red.shade100, textColor: Colors.red),
                      _buildButton('⌫'),
                      _buildButton('%'),
                      _buildButton('÷', color: Colors.blue.shade100, textColor: Colors.blue.shade800),
                    ],
                  ),
                  // Row 2
                  Row(
                    children: <Widget>[
                      _buildButton('7'),
                      _buildButton('8'),
                      _buildButton('9'),
                      _buildButton('×', color: Colors.blue.shade100, textColor: Colors.blue.shade800),
                    ],
                  ),
                  // Row 3
                  Row(
                    children: <Widget>[
                      _buildButton('4'),
                      _buildButton('5'),
                      _buildButton('6'),
                      _buildButton('-', color: Colors.blue.shade100, textColor: Colors.blue.shade800),
                    ],
                  ),
                  // Row 4
                  Row(
                    children: <Widget>[
                      _buildButton('1'),
                      _buildButton('2'),
                      _buildButton('3'),
                      _buildButton('+', color: Colors.blue.shade100, textColor: Colors.blue.shade800),
                    ],
                  ),
                  // Row 5
                  Row(
                    children: <Widget>[
                      _buildButton('+/-'),
                      _buildButton('0'),
                      _buildButton('.'),
                      _buildButton('=', color: Colors.blue, textColor: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
