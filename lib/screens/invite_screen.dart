import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/powersync_service.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late String _token;
  bool _initialized = false;

  Map<String, dynamic>? _invite;
  bool _loading = true;
  String? _error;
  bool _joining = false;
  bool _joined = false;
  bool _isAuthenticated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is String) {
        _token = args;
      } else if (args is Map) {
        _token = args['token'] as String;
        if (args['authenticated'] == true) _isAuthenticated = true;
      }
      _initialized = true;
      _loadInvite();
      if (!_isAuthenticated) _checkAuth();
    }
  }

  Future<void> _checkAuth() async {
    final auth = await AuthService.isAuthenticated();
    if (!mounted) return;
    setState(() => _isAuthenticated = auth);
  }

  Future<void> _loadInvite() async {
    try {
      final data = await ApiService.getInvite(_token);
      if (!mounted) return;
      setState(() {
        _invite = data;
        _loading = false;
        if (data['is_subscribed'] == true) _joined = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load invite. Check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    setState(() => _joining = true);
    try {
      await ApiService.acceptInvite(_token);

      try {
        final subscriptions = await ApiService.getSubscriptions();
        await PowerSyncService.seedSessions(subscriptions);
      } catch (e) {
        if (kDebugMode) debugPrint('[Invite] local_sessions re-seed failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _joined = true;
        _joining = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _joining = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not join session. Try again.';
        _joining = false;
      });
    }
  }

  void _goHome() {
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const CircularProgressIndicator(color: AppColors.accent);
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _goHome,
            child: const Text('Go Home'),
          ),
        ],
      );
    }

    if (_joined) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: AppColors.accent),
          const SizedBox(height: 16),
          Text(
            "You've joined",
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            _invite?['session_name'] ?? '',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _goHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Open FieldLog', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );
    }

    final name = _invite?['session_name'] ?? '';
    final description = _invite?['session_description'] ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.sensors_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: 20),
        Text(
          "You've been invited to join",
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          textAlign: TextAlign.center,
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isAuthenticated
                ? (_joining ? null : _accept)
                : () => Navigator.pushNamed(context, '/login', arguments: _token),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _joining
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _isAuthenticated ? 'Join Session' : 'Log in to join',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _goHome,
          child: Text('Not now', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textTertiary)),
        ),
      ],
    );
  }
}
