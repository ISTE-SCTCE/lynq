import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:m_lynq/screens/auth/login_screen.dart';

void main() {
  setUpAll(() {
    // Avoid font loading issues in tests
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Auth Workflow UI Logic & Transition Tests', () {
    testWidgets('Initial entry shows Email field and Continue button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Verify email text field is present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);

      // Verify the Continue button is displayed
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Entering invalid email displays error message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Input invalid email
      await tester.enterText(find.byType(TextField), 'invalidemail');
      
      // Tap continue
      await tester.tap(find.text('Continue'));
      await tester.pump();

      // Verify error message
      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('Entering empty email displays error message', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      
      // Tap continue without entering text
      await tester.tap(find.text('Continue'));
      await tester.pump();

      // Verify error message
      expect(find.text('Please enter your email address'), findsOneWidget);
    });
  });
}
