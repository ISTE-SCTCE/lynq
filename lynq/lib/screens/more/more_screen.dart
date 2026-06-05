import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/liquid_glass_nav_bar.dart';
import '../../core/permission_engine.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perms = context.read<AuthProvider>().permissions;
    if (perms == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: Text('More', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMoreItem(
            context,
            icon: Icons.people_outline,
            title: 'Members',
            subtitle: 'View and manage team members',
            onTap: () => context.push('/members'),
          ),
          _buildMoreItem(
            context,
            icon: Icons.groups_outlined,
            title: 'Teams',
            subtitle: 'Manage folder-based teams',
            onTap: () => context.push('/folders'),
          ),
          _buildMoreItem(
            context,
            icon: Icons.receipt_long_outlined,
            title: 'Reports',
            subtitle: perms.canReadReports ? 'View uploaded reports' : 'Upload activity reports',
            onTap: () {
              if (perms.canReadReports) {
                context.push('/reports');
              } else {
                context.push('/reports/upload');
              }
            },
          ),
          if (perms.canAccessScopedBudget || perms.canViewTotalBudget)
            _buildMoreItem(
              context,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Budget',
              subtitle: 'Financial overview and requests',
              onTap: () => context.push('/budget'),
            ),
          if (perms.canManagePermissions)
            _buildMoreItem(
              context,
              icon: Icons.admin_panel_settings_outlined,
              title: 'Permission Manager',
              subtitle: 'Control system access levels',
              onTap: () => context.push('/settings/permissions'), // Need to implement this path
            ),
          const SizedBox(height: 20),
          _buildMoreItem(
            context,
            icon: Icons.logout,
            title: 'Sign Out',
            subtitle: 'Log out of your account',
            color: Colors.redAccent,
            onTap: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        selectedIndex: 3,
        onItemSelected: (i) {
          if (i == 3) return;
          switch (i) {
            case 0: context.go('/home'); break;
            case 1: 
              if (perms.isAtLeastTier2) {
                context.push('/budget');
              } else {
                context.push('/events');
              }
              break;
            case 2: context.push('/chat'); break;
          }
        },
        items: [
          LiquidNavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: 'Home'),
          LiquidNavItem(
            icon: perms.isAtLeastTier2 ? Icons.account_balance_wallet_outlined : Icons.calendar_today_outlined,
            selectedIcon: perms.isAtLeastTier2 ? Icons.account_balance_wallet_rounded : Icons.calendar_today_rounded,
            label: perms.isAtLeastTier2 ? 'Budget' : 'Events',
          ),
          LiquidNavItem(icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'Chat'),
          LiquidNavItem(icon: Icons.more_horiz_outlined, selectedIcon: Icons.more_horiz_rounded, label: 'More'),
        ],
      ),
      extendBody: true,
    );
  }

  Widget _buildMoreItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (color ?? AppTheme.secondary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color ?? AppTheme.darkGreen, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
