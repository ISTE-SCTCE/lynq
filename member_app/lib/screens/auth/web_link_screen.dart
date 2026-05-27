import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';

class WebLinkScreen extends StatefulWidget {
  const WebLinkScreen({super.key});

  @override
  State<WebLinkScreen> createState() => _WebLinkScreenState();
}

class _WebLinkScreenState extends State<WebLinkScreen> {
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isScanning = false;

  Future<void> _verifyCode(String code) async {
    setState(() => _isLoading = true);
    try {
      // Find the web user by the 6-digit linking code
      final response = await Supabase.instance.client
          .from('web_linking_codes')
          .select('web_user_id, status')
          .eq('code', code)
          .eq('status', 'pending')
          .maybeSingle();

      if (response == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid or expired code'), backgroundColor: Colors.red));
      } else {
        final webUserId = response['web_user_id'];
        
        // Link the current mobile user to the web user id
        await Supabase.instance.client.from('member_profiles').update({
          'linked_web_account': webUserId,
        }).eq('id', Supabase.instance.client.auth.currentUser?.id ?? '');

        // Mark code as used
        await Supabase.instance.client.from('web_linking_codes').update({
          'status': 'used'
        }).eq('code', code);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accounts linked successfully!'), backgroundColor: Colors.green));
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _isScanning = false),
          ),
        ),
        body: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null && barcode.rawValue!.length == 6) {
                setState(() => _isScanning = false);
                _verifyCode(barcode.rawValue!);
                break;
              }
            }
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Link Website Account', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code or scan the QR code from the member portal website to link your profile.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeCtrl,
              style: GoogleFonts.spaceGrotesk(fontSize: 24, letterSpacing: 8, color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLength: 6,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                hintText: 'XXXXXX',
                hintStyle: TextStyle(color: Colors.white24),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _verifyCode(_codeCtrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                : Text('Verify Code', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() => _isScanning = true),
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: Text('Scan QR Code', style: GoogleFonts.inter(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.white30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
