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
  final _memberPriceCtrl = TextEditingController(text: '0');
  final _nonMemberPriceCtrl = TextEditingController(text: '0');
  final _locationCtrl = TextEditingController();
  final List<String> _allowedRoles = ['member', 'restricted', 'panel', 'forum_execcom', 'core_execcom', 'vice_chairman', 'chairman'];
  List<String> _selectedRoles = ['member', 'restricted', 'panel', 'forum_execcom', 'core_execcom', 'vice_chairman', 'chairman'];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isPaid = false;
  File? _posterFile;
  String? _posterUrl;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) {
      setState(() => _posterFile = File(pickedFile.path));
    }
  }

  Future<String?> _uploadPoster() async {
    if (_posterFile == null) return null;
    try {
      final bytes = await FlutterImageCompress.compressWithFile(
        _posterFile!.absolute.path,
        quality: 70,
      );
      if (bytes == null) return null;

      final ext = _posterFile!.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$ext';
      final path = 'posters/$fileName';
      
      await Supabase.instance.client.storage
          .from('event_posters')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
          
      final url = Supabase.instance.client.storage
          .from('event_posters')
          .getPublicUrl(path);
          
      return url;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      String? uploadedPosterUrl;
      if (_posterFile != null) {
        uploadedPosterUrl = await _uploadPoster();
      }

      await Supabase.instance.client.from('events').insert({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'date': _selectedDate.toIso8601String().split('T').first,
        'folder_id': widget.folderId,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
        'member_price': int.tryParse(_memberPriceCtrl.text.trim()) ?? 0,
        'non_member_price': int.tryParse(_nonMemberPriceCtrl.text.trim()) ?? 0,
        'is_paid': _isPaid,
        'location': _locationCtrl.text.trim(),
        'allowed_roles': _selectedRoles,
        'poster_url': uploadedPosterUrl,
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
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    image: _posterFile != null 
                        ? DecorationImage(image: FileImage(_posterFile!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _posterFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            Text('Add Event Poster', style: GoogleFonts.inter(color: Colors.grey)),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              CustomTextField(label: 'Event Title', controller: _titleCtrl, prefixIcon: Icons.event),
              const SizedBox(height: 16),
              CustomTextField(label: 'Description', controller: _descCtrl, prefixIcon: Icons.description_outlined, maxLines: 4),
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
