import codecs

with codecs.open('lynq/lib/screens/budget/budget_overview_screen.dart', 'r', 'utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines[1407:1906]:
    line = line.replace('_NewTransactionSheet', 'NewTransactionSheet')
    if 'const NewTransactionSheet({required this.isIncomeInitial, required this.myFolderIds});' in line:
        line = '  final int? preselectedFolderId;\n  const NewTransactionSheet({super.key, required this.isIncomeInitial, required this.myFolderIds, this.preselectedFolderId});\n'
    if 'widget.myFolderIds.isNotEmpty ? widget.myFolderIds.first : null' in line:
        line = line.replace('widget.myFolderIds.isNotEmpty ? widget.myFolderIds.first : null', 'widget.preselectedFolderId ?? (widget.myFolderIds.isNotEmpty ? widget.myFolderIds.first : null)')
    new_lines.append(line)

with codecs.open('lynq/lib/screens/budget/new_transaction_sheet.dart', 'w', 'utf-8') as f2:
    f2.write("import 'dart:io' as io;\n")
    f2.write("import 'package:flutter/material.dart';\n")
    f2.write("import 'package:google_fonts/google_fonts.dart';\n")
    f2.write("import 'package:supabase_flutter/supabase_flutter.dart';\n")
    f2.write("import 'package:file_picker/file_picker.dart';\n")
    f2.write("import '../../core/theme.dart';\n")
    f2.write("import '../../models/app_models.dart';\n\n")
    f2.write("".join(new_lines))
