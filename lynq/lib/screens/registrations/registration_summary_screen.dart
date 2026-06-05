import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../models/task_models.dart';
import '../../shared/widgets/glass_card.dart';
import '../../core/app_cache.dart';
import 'registration_service.dart';

class RegistrationSummaryScreen extends StatefulWidget {
  const RegistrationSummaryScreen({super.key});

  @override
  State<RegistrationSummaryScreen> createState() => _RegistrationSummaryScreenState();
}

class _RegistrationSummaryScreenState extends State<RegistrationSummaryScreen> {
  bool _isLoading = true;
  int _totalMembers = 0;
  Map<String, List<RegistrationQueueModel>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final cache = AppCache();
    if (cache.registrationData != null) {
      setState(() {
        _totalMembers = cache.registrationData!['totalMembers'] as int;
        _grouped = cache.registrationData!['grouped'] as Map<String, List<RegistrationQueueModel>>;
        _isLoading = false;
      });
      // Return early if cache is fresh
      if (!cache.isRegistrationStale) return;
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final result = await RegistrationService.fetchRegistrationData(Supabase.instance.client);
      cache.updateRegistrationData(result);
      if (mounted) {
        setState(() {
          _totalMembers = result['totalMembers'] as int;
          _grouped = result['grouped'] as Map<String, List<RegistrationQueueModel>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalRegistrations = 0;
    _grouped.forEach((key, list) {
      totalRegistrations += list.length;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Registration Overview', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Action Required', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    _SummaryCard(
                      title: 'Waiting for Approval',
                      count: _grouped['Pending']?.length ?? 0,
                      icon: Icons.hourglass_empty_rounded,
                      color: Colors.orange,
                      onTap: () => _navigateToQueue(0),
                    ),
                    const SizedBox(height: 24),
                    Text('Overview', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _StatusCard(
                          title: 'Payment Pending',
                          count: _grouped['Payment']?.length ?? 0,
                          icon: Icons.payment_rounded,
                          color: AppTheme.secondary,
                          onTap: () => _navigateToQueue(1),
                        ),
                        _StatusCard(
                          title: 'Approved',
                          count: _grouped['Approved']?.length ?? 0,
                          icon: Icons.check_circle_outline_rounded,
                          color: AppTheme.darkGreen,
                          onTap: () => _navigateToQueue(2),
                        ),
                        _StatusCard(
                          title: 'Rejected',
                          count: _grouped['Rejected']?.length ?? 0,
                          icon: Icons.cancel_outlined,
                          color: Colors.red,
                          onTap: () => _navigateToQueue(3),
                        ),
                        _StatusCard(
                          title: 'Excel Intake',
                          count: _grouped['Excel Intake']?.length ?? 0,
                          icon: Icons.table_chart_rounded,
                          color: Colors.blueAccent,
                          onTap: () => _navigateToQueue(4),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Total Members', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    _SummaryCard(
                      title: 'Total Active Members',
                      count: _totalMembers,
                      icon: Icons.people_alt_rounded,
                      color: AppTheme.primary,
                      onTap: () {}, // Do nothing
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  void _navigateToQueue(int index) {
    context.push('/registrations/queue', extra: {
      'initialIndex': index,
      'groupedData': _grouped,
      'totalMembers': _totalMembers,
    });
  }
}

class _SummaryCard extends StatefulWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SummaryCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: GoogleFonts.inter(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('${widget.count}', style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatefulWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StatusCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 24),
                  ),
                  Text('${widget.count}', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
