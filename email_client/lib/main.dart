import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/email_client_state.dart';
import 'ui/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmailClientApp());
}

class EmailClientApp extends StatelessWidget {
  final EmailClientState? state;

  const EmailClientApp({super.key, this.state});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => state ?? EmailClientState(),
      child: MaterialApp(
        title: 'IMAP Spam Triage',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1), // Indigo
            brightness: Brightness.dark,
            surface: const Color(0xFF131722),
            surfaceContainer: const Color(0xFF1E2230),
            surfaceContainerHighest: const Color(0xFF282D3F),
            surfaceContainerLowest: const Color(0xFF0C0E14),
          ),
          scaffoldBackgroundColor: const Color(0xFF0C0E14),
          fontFamily: 'sans-serif',
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4F46E5),
            brightness: Brightness.light,
          ),
        ),
        home: const MainScreen(),
      ),
    );
  }
}
