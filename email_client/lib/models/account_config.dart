import 'dart:convert';
import 'dart:io';

class AccountConfig {
  final String name;
  final String host;
  final int port;
  final String user;
  final String? password;
  final String? credPath;
  final String spamFolder;
  final String classifyArgs;
  final String learnArgs;
  final String dataDir;

  AccountConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.user,
    this.password,
    this.credPath,
    this.spamFolder = 'AI-Spam',
    this.classifyArgs = '',
    this.learnArgs = '',
    required this.dataDir,
  });

  /// Decrypts or gets the plain password.
  String? getDecryptedPassword() {
    if (password != null && password!.isNotEmpty) {
      return password;
    }
    if (credPath != null && File(credPath!).existsSync()) {
      try {
        final result = Process.runSync(
          'systemd-creds',
          ['decrypt', '--user', '--name=imap-password', credPath!, '-'],
        );
        if (result.exitCode == 0) {
          return (result.stdout as String).replaceAll('\r', '').replaceAll('\n', '').trim();
        }
      } catch (e) {
        stderr.writeln('Error decrypting systemd-creds for $name: $e');
      }
    }
    // Fallback: check IMAP_PASSWORD env var
    return Platform.environment['IMAP_PASSWORD'];
  }

  /// Load all accounts from ~/.config/imap-spam-filter/accounts/
  static List<AccountConfig> loadDiscoveredAccounts() {
    final list = <AccountConfig>[];
    final home = Platform.environment['HOME'] ?? '';
    final acctDir = Directory('$home/.config/imap-spam-filter/accounts');
    final credDir = Directory('$home/.config/imap-spam-filter/creds');
    final stateBase = '$home/.local/state/imap-spam-filter';

    if (acctDir.existsSync()) {
      for (final entity in acctDir.listSync()) {
        if (entity is File && entity.path.endsWith('.conf')) {
          final acctName = entity.uri.pathSegments.last.replaceAll('.conf', '');
          final content = entity.readAsStringSync();
          final lines = const LineSplitter().convert(content);

          String host = 'imap.gmail.com';
          int port = 993;
          String user = '';
          String spamFolder = 'AI-Spam';
          String classifyArgs = '';
          String learnArgs = '';

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;
            final key = trimmed.substring(0, trimmed.indexOf('=')).trim();
            var val = trimmed.substring(trimmed.indexOf('=') + 1).trim();
            if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
              val = val.substring(1, val.length - 1);
            }

            if (key == 'IMAP_HOST') host = val;
            if (key == 'IMAP_PORT') port = int.tryParse(val) ?? 993;
            if (key == 'IMAP_USER') user = val;
            if (key == 'SPAM_FOLDER') spamFolder = val;
            if (key == 'CLASSIFY_ARGS') classifyArgs = val;
            if (key == 'LEARN_ARGS') learnArgs = val;
          }

          final credFile = File('${credDir.path}/$acctName.cred');
          final acctStateDir = Directory('$stateBase/$acctName');

          list.add(
            AccountConfig(
              name: acctName,
              host: host,
              port: port,
              user: user,
              credPath: credFile.existsSync() ? credFile.path : null,
              spamFolder: spamFolder,
              classifyArgs: classifyArgs,
              learnArgs: learnArgs,
              dataDir: acctStateDir.path,
            ),
          );
        }
      }
    }

    // If no accounts found in ~/.config, create a default local one pointing to workspace root
    if (list.isEmpty) {
      list.add(
        AccountConfig(
          name: 'Manual / Default',
          host: Platform.environment['IMAP_HOST'] ?? 'mail.perlak.com',
          port: int.tryParse(Platform.environment['IMAP_PORT'] ?? '993') ?? 993,
          user: Platform.environment['IMAP_USER'] ?? '',
          password: Platform.environment['IMAP_PASSWORD'],
          spamFolder: Platform.environment['SPAM_FOLDER'] ?? 'AI-Spam',
          dataDir: '$home/Work/imap-spam-filter',
        ),
      );
    }

    return list;
  }
}

