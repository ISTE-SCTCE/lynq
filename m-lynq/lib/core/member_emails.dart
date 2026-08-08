// Complete list of registered ISTE Member emails from official registration list
final Set<String> kIsteMemberEmails = {
  'aadithyanrs9e@gmail.com', 'aardhraramesh@gmail.com', 'aasiyas252006@gmail.com', 
  'abinanth@gmail.com', 'aabhinavbr@gmail.com', 'abhiramnair6772@gmail.com', 
  'abhirammanoj13@gmail.com', 'abhiraminair0406@gmail.com', 'abhiramism25@gmail.com', 
  'abhishekas808scetian@gmail.com', 'abhisheksshenoy@gmail.com', 'adarshjj507@gmail.com', 
  'adarshcr4@gmail.com', 'adimanju35@gmail.com', 'adityenh@gmail.com', 
  'adithyans1369@gmail.com', 'imadityamurali@gmail.com', 'adwaithgalr@gmail.com', 
  'ajaykrishnas2208@gmail.com', 'ajinsoorya2005@gmail.com', 'ajmalms141@gmail.com', 
  'akshay.sm4096@gmail.com', 'aldenrenjitrosh@gmail.com', 'alhajshaikha122@gmail.com', 
  'amantejas05@gmail.com', 'anaghamp07@gmail.com', 'anakhapj2005@gmail.com', 
  'ananthakrishnanar2020@gmail.com', 'evbanjali@gmail.com', 'anjanapradeep512@gmail.com', 
  'annamariyapaulose@gmail.com', 'aparnasreenivas27@gmail.com', 'archasunil777@gmail.com', 
  'archars810@gmail.com', 'ardraspillai01@gmail.com', 'arjuns8267@gmail.com', 
  'aromalye@gmail.com', 'arunraj.priyam@gmail.com', 'aryashibu73@gmail.com', 
  'ashwinnairshiji@gmail.com', 'aswina9a@gmail.com', 'aiyshaansar@gmail.com', 
  'bazithms2006.dsc@gmail.com', 'nichuneelu1022@gmail.com', 'chinmayi@gmail.com', 
  'dev.nanda018@gmail.com', 'devikhavr@gmail.com', 'diyaramesh112@gmail.com', 
  'farhanafirosh07@gmail.com', 'fidhafathima494@gmail.com', 'ars.suru786@gmail.com', 
  'ganeshgopal3106@gmail.com', 'gsnmega6@gmail.com', 'asgayathri48@gmail.com', 
  'tgoutham96@gmail.com', 'gowri.l.nair06@gmail.com', 'hkalladi45@gmail.com', 
  'hareeshms6665@gmail.com', 'jeslynbabu@gmail.com', 'jonethjillsff@gmail.com', 
  'krish2krishnaveni@gmail.com', 'lamiyashifa45@gmail.com', 'libishma2007@gmail.com', 
  'unnikrishnan44013au@gmail.com', 'mahadevanalsctcollege@gmail.com', 'malavikathampy572@gmail.com', 
  'manupriyaa7prasad@gmail.com', 'farhanmohammed2706@gmail.com', 'navaneethsnair13732@gmail.com', 
  'naveed0506@gmail.com', 'nandanayanam@gmail.com', 'neerajasheejarajesh5@gmail.com', 
  'nehasanjeevkrishna@gmail.com', 'nihithasheebaranjith@gmail.com', 'nissyelsajacob18@gmail.com', 
  'nithingopinathofficial2006@gmail.com', 'niyahfath499@gmail.com', 'niyathasuresh48@gmail.com', 
  'sabareesh20042005@gmail.com', 'parthasarathy03062005@gmail.com', 'prajod2005@gmail.com', 
  'riniissac2407@gmail.com', 'ryanshanu227@gmail.com', 'aishwaryask104@gmail.com', 
  'sadhikasunilb@gmail.com', 'sandramariyamr@gmail.com', 'kssanjay1111@gmail.com', 
  'sarveshbm07@gmail.com', 'siyavarghese29@gmail.com', 'sradha.manoj@gmail.com', 
  'gangaskanthp69@gmail.com', 'sreelekshmi2487@gmail.com', 'sreenidhikannan23@gmail.com', 
  'sreeramps1609@gmail.com', 'stefinmathew0@gmail.com', 'swathyssunil2006@gmail.com', 
  'thanusreenubi@gmail.com', 'thejask9495@gmail.com', 'udayutthara1213@gmail.com', 
  'varshavr742@gmail.com', 'reachvishaljai@gmail.com', 'viswajithss18@gmail.com'
};

bool isIsteMemberEmail(String email) {
  final trimmed = email.trim().toLowerCase();
  if (trimmed.isEmpty) return false;
  return kIsteMemberEmails.contains(trimmed);
}
