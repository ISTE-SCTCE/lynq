import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/auth_provider.dart';
import 'edit_profile_screen.dart';

class MembershipCardScreen extends ConsumerWidget {
  const MembershipCardScreen({super.key});

  static const _cream    = Color(0xFFF4E9D7);
  static const _teal     = Color(0xFF6FA4AF);
  static const _bg       = Color(0xFF141414);
  static const _surface  = Color(0xFF1E1E1E);

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
            _buildMemberDetails(profile, context),
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
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2B2B), Color(0xFF141414)],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle glow in the top-left
          Positioned(
            left: -40, top: -40,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Colors.white.withValues(alpha: 0.05),
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
                // Header row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E2D26), // subtle brown/terracotta tint
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.school_rounded,
                              size: 20, color: Color(0xFFD97D55)),
                        ),
                        const SizedBox(width: 12),
                        Text('ISTE Student Chapter',
                            style: GoogleFonts.inter(
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isValid ? Colors.transparent : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isValid ? const Color(0xFF4CAF50).withValues(alpha: 0.5) : const Color(0xFFE53935).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        isValid ? 'ACTIVE' : 'EXPIRED',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isValid ? const Color(0xFF81C784) : const Color(0xFFE57373)),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Member Name
                Text(
                  auth.name.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 26, fontWeight: FontWeight.bold, color: const Color(0xFFF4E9D7),
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 24),
                // Member ID
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MEMBER ID', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white38, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(auth.membershipId,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: const Color(0xFFD97D55), letterSpacing: 1.2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberDetails(Map<String, dynamic> profile, BuildContext context) {
    final fields = [
      ['Full Name', profile['name'] as String? ?? '—'],
      ['Email', profile['email'] as String? ?? '—'],
      ['Roll Number', profile['roll_number'] as String? ?? '—'],
      ['Branch', profile['branch'] ?? profile['department'] as String? ?? '—'],
      ['Year', profile['year'] as String? ?? '—'],
      ['Phone', profile['phone'] as String? ?? '—'],
      ['Membership Type', profile['membership_type'] ?? profile['plan'] as String? ?? '—'],
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Member Details',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18, fontWeight: FontWeight.w700, color: _cream)),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: _teal, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                  );
                },
              ),
            ],
          ),
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
