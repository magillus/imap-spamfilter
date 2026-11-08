import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account_config.dart';
import '../state/email_client_state.dart';

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key});

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  bool _isManual = false;
  final _hostController = TextEditingController(text: 'mail.perlak.com');
  final _portController = TextEditingController(text: '993');
  final _userController = TextEditingController(text: 'mateusz@perlak.com');
  final _passController = TextEditingController();
  final _folderController = TextEditingController(text: 'AI-Spam');

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmailClientState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.manage_accounts),
          SizedBox(width: 10),
          Text('IMAP Accounts & Settings'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accounts detected from ~/.config/imap-spam-filter/accounts/:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              if (state.accounts.isEmpty)
                const Text('No accounts configured yet.')
              else
                ...state.accounts.map((acct) {
                  final isActive = state.activeAccount?.name == acct.name;
                  return Card(
                    color: isActive
                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isActive ? colorScheme.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        isActive ? Icons.check_circle : Icons.account_circle_outlined,
                        color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        acct.name,
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${acct.user} • ${acct.host}:${acct.port} • Spam: ${acct.spamFolder}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isActive
                          ? const Chip(
                              label: Text('Active', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            )
                          : TextButton(
                              child: const Text('Switch'),
                              onPressed: () {
                                state.selectAccount(acct);
                                Navigator.of(context).pop();
                              },
                            ),
                    ),
                  );
                }),

              const Divider(height: 24),

              InkWell(
                onTap: () => setState(() => _isManual = !_isManual),
                child: Row(
                  children: [
                    Icon(_isManual ? Icons.expand_less : Icons.expand_more),
                    const SizedBox(width: 8),
                    const Text('Custom Manual Connection Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              if (_isManual) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostController,
                        decoration: const InputDecoration(labelText: 'IMAP Host', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(labelText: 'Port', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: 'Username / Email', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (leave blank if stored in creds)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _folderController,
                  decoration: const InputDecoration(labelText: 'AI-Spam Folder Name', isDense: true),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Connect to this server'),
                  onPressed: () {
                    final custom = AccountConfig(
                      name: 'Custom',
                      host: _hostController.text.trim(),
                      port: int.tryParse(_portController.text.trim()) ?? 993,
                      user: _userController.text.trim(),
                      password: _passController.text.isNotEmpty ? _passController.text : null,
                      spamFolder: _folderController.text.trim(),
                      dataDir: state.activeAccount?.dataDir ?? '${state.accounts.firstOrNull?.dataDir}',
                    );
                    state.selectAccount(custom);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

