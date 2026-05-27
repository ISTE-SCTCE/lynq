import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';

class MembershipCardScreen extends ConsumerWidget {
  const MembershipCardScreen({super.key});

  static const _terracotta = Color(0xFFD97D55);
  static const _cream = Color(0xFFF4E9D7);
  static const _sage = Color(0xFFB8C4A9);
  static const _teal = Color(0xFF6FA4AF);
  static const _bg = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile ?? {};

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Membership Card',
            style: GoogleFonts.spaceGrotesk(color: _cream, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildCard(auth, profile),
            const SizedBox(height: 32),
            _buildMemberDetails(profile),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(MemberAuthState auth, Map<String, dynamic> profile) {
    final validityEnd = auth.validityEnd;
    final isValid = auth.isMembershipValid;

    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
        ),
        border: Border.all(
          color: isValid
              ? _sage.withValues(alpha: 0.4)
              : Colors.red.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _terracotta.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned(
            right: -40, top: -40,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _terracotta.withValues(alpha: 0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            left: -30, bottom: -30,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _teal.withValues(alpha: 0.06),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _terracotta.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school_rounded,
                          size: 20, color: _terracotta),
                    ),
                    const SizedBox(width: 10),
                    Text('ISTE Student Chapter',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: _cream.withValues(alpha: 0.7))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isValid ? _sage : Colors.red).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: (isValid ? _sage : Colors.red).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        isValid ? 'ACTIVE' : 'EXPIRED',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isValid ? _sage : Colors.redAccent),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Member name
                Text(
                  auth.name.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.bold, color: _cream,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  profile['roll_number'] as String? ?? '',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white38),
                ),
                const SizedBox(height: 12),
                // ID and validity
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MEMBER ID', style: GoogleFonts.inter(fontSize: 8, color: Colors.white24)),
                        Text(auth.membershipId,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 14, fontWeight: FontWeight.bold,
                                color: _terracotta)),
                      ],
                    ),
                    const Spacer(),
                    if (validityEnd != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('VALID UNTIL', style: GoogleFonts.inter(fontSize: 8, color: Colors.white24)),
                          Text(
                            '${validityEnd.month.toString().padLeft(2, '0')}/${validityEnd.year}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 14, fontWeight: FontWeight.bold, color: _cream),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberDetails(Map<String, dynamic> profile) {
    final fields = [
      ['Full Name', profile['name'] as String? ?? '—'],
      ['Email', profile['email'] as String? ?? '—'],
      ['Roll Number', profile['roll_number'] as String? ?? '—'],
      ['Branch', profile['branch'] as String? ?? '—'],
      ['Year', profile['year'] as String? ?? '—'],
      ['Phone', profile['phone'] as String? ?? '—'],
      ['Membership Type', profile['membership_type'] as String? ?? '—'],
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Member Details',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 16, fontWeight: FontWeight.bold, color: _cream)),
          const SizedBox(height: 16),
          ...fields.map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(f[0],
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(f[1],
                      style: GoogleFonts.inter(
                          fontSize: 13, color: _cream, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
