import codecs

with codecs.open('lynq/lib/screens/budget/budget_overview_screen.dart', 'r', 'utf-8') as f:
    content = f.read()

content = content.replace('_NewTransactionSheet(', 'NewTransactionSheet(')
lines = content.split('\n')
new_lines = lines[:1407]
new_lines.insert(8, "import 'new_transaction_sheet.dart';")
new_lines.insert(9, "import 'forum_ledger_screen.dart';")

with codecs.open('lynq/lib/screens/budget/budget_overview_screen.dart', 'w', 'utf-8') as f:
    f.write('\n'.join(new_lines))
