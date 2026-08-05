import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/primary_button.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class EventFormScreen extends StatefulWidget {
  final int? folderId;
  const EventFormScreen({super.key, this.folderId});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  final _perkCtrl = TextEditingController();
  List<String> _perks = [];
  final _memberPriceCtrl = TextEditingController(text: '0');
  final _nonMemberPriceCtrl = TextEditingController(text: '0');
  final _locationCtrl = TextEditingController();
  final List<String> _allowedRoles = ['member', 'restricted', 'panel', 'forum_execcom', 'core_execcom', 'vice_chairman', 'chairman'];
  List<String> _selectedRoles = ['member', 'restricted', 'panel', 'forum_execcom', 'core_execcom', 'vice_chairman', 'chairman'];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isPaid = false;
  List<File> _posterFiles = [];
  int _numDays = 1;

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(imageQuality: 85);
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _posterFiles.addAll(pickedFiles.map((f) => File(f.path)));
      });
    }
  }

  Future<List<String>> _uploadPosters() async {
    List<String> urls = [];
    for (var file in _posterFiles) {
      try {
        final bytes = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          quality: 70,
        );
        if (bytes == null) continue;

        final ext = file.path.split('.').last;
        final fileName = '${const Uuid().v4()}.$ext';
        final path = 'posters/$fileName';
        
        await Supabase.instance.client.storage
            .from('event_posters')
            .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
            
        final url = Supabase.instance.client.storage
            .from('event_posters')
            .getPublicUrl(path);
        urls.add(url);
      } catch (e) {
        debugPrint('Upload error: $e');
      }
    }
    return urls;
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      List<String> uploadedPosterUrls = await _uploadPosters();

      await Supabase.instance.client.from('events').insert({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'details': _detailsCtrl.text.trim(),
        'date': _selectedDate.toIso8601String().split('T').first,
        'execom_id': widget.folderId,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
        'member_price': int.tryParse(_memberPriceCtrl.text.trim()) ?? 0,
        'non_member_price': int.tryParse(_nonMemberPriceCtrl.text.trim()) ?? 0,
        'is_paid': _isPaid,
        'location': _locationCtrl.text.trim(),
        'allowed_roles': _selectedRoles,
        'poster_url': uploadedPosterUrls.isNotEmpty ? uploadedPosterUrls.first : null,
        'posters': uploadedPosterUrls,
        'perks': _perks,
        'num_days': _numDays,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event created'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Event', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_posterFiles.isEmpty)
                GestureDetector(
                  onTap: _pickImages,
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('Add Event Posters', style: GoogleFonts.inter(color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 140,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _posterFiles.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _posterFiles.length) {
                            return GestureDetector(
                              onTap: _pickImages,
                              child: Container(
                                width: 100,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: const Icon(Icons.add, color: Colors.grey),
                              ),
                            );
                          }
                          return Container(
                            width: 140,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              image: DecorationImage(image: FileImage(_posterFiles[index]), fit: BoxFit.cover),
                            ),
                            child: Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () {
                                  setState(() => _posterFiles.removeAt(index));
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              CustomTextField(label: 'Event Title', controller: _titleCtrl, prefixIcon: Icons.event),
              const SizedBox(height: 16),
              CustomTextField(label: 'Short Description', controller: _descCtrl, prefixIcon: Icons.description_outlined, maxLines: 2),
              const SizedBox(height: 16),
              CustomTextField(label: 'Full Details', controller: _detailsCtrl, prefixIcon: Icons.notes_outlined, maxLines: 5),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'Add Perk',
                      controller: _perkCtrl,
                      prefixIcon: Icons.star_border,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.green),
                    onPressed: () {
                      if (_perkCtrl.text.isNotEmpty) {
                        setState(() {
                          _perks.add(_perkCtrl.text.trim());
                          _perkCtrl.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
              if (_perks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Wrap(
                    spacing: 8,
                    children: _perks.map((p) => Chip(
                      label: Text(p, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => setState(() => _perks.remove(p)),
                    )).toList(),
                  ),
                ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                  if (d != null) setState(() => _selectedDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 12),
                      Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}', style: GoogleFonts.inter()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CustomTextField(label: 'Location', controller: _locationCtrl, prefixIcon: Icons.location_on_outlined),
              const SizedBox(height: 16),
              // ── Number of Days ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_outlined, size: 18, color: Colors.grey),
                    const SizedBox(width: 12),
                    Text('Number of Days', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                      onPressed: () => setState(() { if (_numDays > 1) _numDays--; }),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$_numDays',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 22),
                      onPressed: () => setState(() { if (_numDays < 30) _numDays++; }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Allowed Roles', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allowedRoles.map((role) {
                  final isSelected = _selectedRoles.contains(role);
                  return FilterChip(
                    label: Text(role.replaceAll('_', ' ')),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedRoles.add(role);
                        } else {
                          _selectedRoles.remove(role);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text('Is Paid Event?', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                value: _isPaid,
                onChanged: (val) => setState(() => _isPaid = val),
                activeColor: Theme.of(context).colorScheme.primary,
                contentPadding: EdgeInsets.zero,
              ),
              if (_isPaid) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        label: 'Member Price (₹)',
                        controller: _memberPriceCtrl,
                        prefixIcon: Icons.currency_rupee,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomTextField(
                        label: 'Non-Member Price (₹)',
                        controller: _nonMemberPriceCtrl,
                        prefixIcon: Icons.currency_rupee,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(text: 'Create Event', onPressed: _submit, isLoading: _isLoading),
            ],
          ),
        ),
      ),
    );
  }
}
