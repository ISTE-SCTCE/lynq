import codecs
with codecs.open('lynq/lib/screens/splash_screen.dart', 'r', 'utf-8') as f:
    content = f.read()

content = content.replace("\\'", "'")

with codecs.open('lynq/lib/screens/splash_screen.dart', 'w', 'utf-8') as f:
    f.write(content)
