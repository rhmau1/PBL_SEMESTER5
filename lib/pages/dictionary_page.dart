import 'package:flutter/material.dart';

import '../screens/sign_guide_screen.dart';

class DictionaryPage extends StatelessWidget {
  const DictionaryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SafeArea(child: SignGuideScreen());
}
