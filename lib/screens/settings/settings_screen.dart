import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_provider.dart';
import '../../core/theme_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showChangePasswordDialog(BuildContext context) {
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Change Password', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                label: 'New Password',
                controller: newPasswordCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_outline,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Confirm Password',
                controller: confirmPasswordCtrl,
                isPassword: true,
                prefixIcon: Icons.lock_reset,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
            ),
            SizedBox(
              width: 100,
              child: PrimaryButton(
                text: 'Update',
                isLoading: isLoading,
                onPressed: () async {
                  if (newPasswordCtrl.text.isEmpty) return;
                  if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  setState(() => isLoading = true);
                  try {
                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(password: newPasswordCtrl.text.trim()),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password updated successfully'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    setState(() => isLoading = false);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final role = AppRole.fromString(user?.role);

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            GlassCard(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppTheme.secondary.withValues(alpha: 0.2),
                    child: Text(
                      (user?.name ?? '?').isNotEmpty ? user!.name[0].toUpperCase() : '?',
                      style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.name ?? '', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (user?.post != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(user!.post!, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 4),
                  Text(role.label, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(user?.email ?? '', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Text('Appearance', 
              style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 12),
            _buildThemeToggle(context),
            const SizedBox(height: 24),

            Text('Account & Security', 
              style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 12),
            _settingsTile(Icons.lock_person_outlined, 'Change Password', () => _showChangePasswordDialog(context)),
            _settingsTile(Icons.refresh, 'Refresh Data', () async {
              await auth.refreshUserData();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data refreshed')));
              }
            }),

            const SizedBox(height: 24),
            Text('System', 
              style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 12),
            _settingsTile(Icons.info_outline, 'About', () {
              showAboutDialog(
                context: context,
                applicationName: 'ISTE Execcom',
                applicationVersion: '1.0.0',
                children: [
                  Text('Execcom Management System', style: GoogleFonts.inter()),
                ],
              );
            }),
            if (auth.permissions?.canManagePermissions ?? false)
              _settingsTile(Icons.admin_panel_settings_outlined, 'Permission Manager', () {
                context.push('/settings/permissions');
              }),
            const SizedBox(height: 12),
            _settingsTile(Icons.logout, 'Sign Out', () async {
              await auth.signOut();
            }, isDestructive: true),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon, color: isDestructive ? Colors.red : AppColors.primary),
          title: Text(title, style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: isDestructive ? Colors.red : null,
          )),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.themeMode == ThemeMode.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary),
          title: Text('Dark Mode', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          value: isDark,
          activeColor: AppColors.primary,
          onChanged: (value) {
            context.read<ThemeProvider>().toggleTheme(value);
          },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
