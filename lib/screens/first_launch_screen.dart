import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/data_providers.dart';
import '../services/default_data_directory.dart';

/// Shown once, the first time the app runs (before any data directory has
/// been configured). Lets the user pick where their Headcount data should
/// live on disk, or fall back to an app-local default if they'd rather
/// decide later.
class FirstLaunchScreen extends ConsumerStatefulWidget {
  const FirstLaunchScreen({super.key});

  @override
  ConsumerState<FirstLaunchScreen> createState() => _FirstLaunchScreenState();
}

class _FirstLaunchScreenState extends ConsumerState<FirstLaunchScreen> {
  bool _isWorking = false;
  String? _errorMessage;

  Future<void> _pickDirectory() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      final selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose a folder for your Headcount data',
      );

      if (selectedPath == null) {
        // User cancelled the picker — not an error, just no-op back to
        // the same screen so they can try again or use the fallback.
        setState(() => _isWorking = false);
        return;
      }

      await ref.read(dataDirectoryProvider.notifier).setPath(selectedPath);
      // No navigation call needed: main.dart watches dataDirectoryProvider
      // and swaps to the home screen automatically once it's non-null.
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not use that folder: $e';
        _isWorking = false;
      });
    }
  }

  Future<void> _useDefaultLocation() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      final fallbackPath = await defaultDataDirectoryPath();
      await ref.read(dataDirectoryProvider.notifier).setPath(fallbackPath);
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not set up the default folder: $e';
        _isWorking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.groups_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Headcount',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Headcount stores everything as plain text files on '
                    'your device — no account, no cloud. Choose a folder '
                    'where you\'d like to keep this data. If you plan to '
                    'track it with Git, pick (or create) a folder you '
                    'control, like one inside your home directory.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _isWorking ? null : _pickDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose a folder'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isWorking ? null : _useDefaultLocation,
                    child: const Text('Decide later, use the default'),
                  ),
                  if (_isWorking) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
