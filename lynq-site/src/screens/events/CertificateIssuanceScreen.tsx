import React, { useState, useEffect, useMemo, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { 
  ArrowLeft, RefreshCw, Upload, Check, AlertTriangle, Play, Sparkles, 
  Loader, Image as ImageIcon, FolderArchive, FileText, CheckCircle2, 
  XCircle, ExternalLink, Award, ShieldCheck, Eye, X, CheckCircle, Search
} from 'lucide-react';
import JSZip from 'jszip';
import { supabase } from '../../core/supabase-client';
import { useAuth } from '../../core/auth-provider';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';
import { EventModel } from '../../models/types';

interface Attendee {
  user_id: string;
  name: string;
  email?: string;
  membership_id?: string;
  roll_no?: string;
}

interface UploadedCertFile {
  name: string;
  file?: File;
  data?: Uint8Array;
  type: string;
}

interface CertMatch {
  attendee: Attendee;
  matchedFile: UploadedCertFile | null;
  matchType: 'exact' | 'contains' | 'token' | 'manual' | 'none';
  matchScore: number;
}

interface ManualAttendanceRecord {
  key: string;
  rawName: string;
  rawEmail: string;
  rawMembershipId: string;
  rawPhone: string;
  rawRollNo: string;
  matchedUser: Attendee | null;
  matchType: 'exact_email' | 'exact_id' | 'exact_name' | 'fuzzy_name' | 'manual' | 'none';
  matchScore: number;
}

interface PublishResultItem {
  student: string;
  file: string;
  url?: string;
}

interface PublishFailItem {
  student: string;
  file: string;
  error: string;
}

interface VerifiedCertRow {
  id: string | number;
  user_id: string;
  student_name?: string;
  title?: string;
  file_url?: string;
  certificate_url?: string;
  storage_path?: string;
  issued_at?: string;
}

export const CertificateIssuanceScreen: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  
  const [event, setEvent] = useState<EventModel | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isProcessing, setIsProcessing] = useState(false);
  const [attendees, setAttendees] = useState<Attendee[]>([]);
  const [alreadyIssuedIds, setAlreadyIssuedIds] = useState<Set<string>>(new Set());
  const [verifiedCertificates, setVerifiedCertificates] = useState<VerifiedCertRow[]>([]);
  const [activeTabSection, setActiveTabSection] = useState<'workspace' | 'verified'>('workspace');
  const [verifiedSearchQuery, setVerifiedSearchQuery] = useState('');

  // Confirmation and Results Modals
  const [publishResultModal, setPublishResultModal] = useState<{
    isOpen: boolean;
    successItems: PublishResultItem[];
    failedItems: PublishFailItem[];
  } | null>(null);
  const [confirmModal, setConfirmModal] = useState<{
    isOpen: boolean;
    title: string;
    description: string;
    recipients: Array<{ student: string; file: string }>;
    onConfirm: () => void;
  } | null>(null);

  // Publish Mode: 'automated' (Google Slides) vs 'manual' (Google Drive / Files)
  const [publishMode, setPublishMode] = useState<'automated' | 'manual'>('automated');
  const [certificateName, setCertificateName] = useState('Certificate of Participation');
  const certificateNameRef = useRef(certificateName);
  useEffect(() => {
    certificateNameRef.current = certificateName;
  }, [certificateName]);

  // Automated Mode State
  const [slidesUrl, setSlidesUrl] = useState('');
  const [chairName, setChairName] = useState('');
  const [coordName, setCoordName] = useState('');
  const [isCompleted, setIsCompleted] = useState(false);

  // Automated Mode: Attendance Source & Manual Attendance List State
  const [automatedAttendanceSource, setAutomatedAttendanceSource] = useState<'app' | 'manual_sheet'>('app');
  const [uploadedAttendanceFileName, setUploadedAttendanceFileName] = useState<string | null>(null);
  const [manualAttendanceRecords, setManualAttendanceRecords] = useState<ManualAttendanceRecord[]>([]);
  const [manualAttendanceUserOverrides, setManualAttendanceUserOverrides] = useState<Record<string, string>>({}); // key -> userId
  const [attendanceListFilter, setAttendanceListFilter] = useState<'all' | 'matched' | 'unmatched' | 'pending'>('all');
  const [isParsingAttendanceFile, setIsParsingAttendanceFile] = useState(false);
  const [selectedRecordForAssign, setSelectedRecordForAssign] = useState<ManualAttendanceRecord | null>(null);
  const [userSearchQuery, setUserSearchQuery] = useState('');

  // Manual Mode State
  const [publishWithoutAttendance, setPublishWithoutAttendance] = useState(true);
  const [allMlynqUsers, setAllMlynqUsers] = useState<Attendee[]>([]);
  const [fileManualOverrides, setFileManualOverrides] = useState<Record<string, string>>({}); // fileName -> userId
  const [driveFolderUrl, setDriveFolderUrl] = useState('');
  const [uploadedFiles, setUploadedFiles] = useState<UploadedCertFile[]>([]);
  const [manualOverrides, setManualOverrides] = useState<Record<string, string>>({}); // userId -> fileName
  const [isExtractingZip, setIsExtractingZip] = useState(false);

  const [processedCount, setProcessedCount] = useState(0);
  const [progressMessage, setProgressMessage] = useState('');
  const [lastSuccessCount, setLastSuccessCount] = useState<number | null>(null);

  const attendeeCount = attendees.length;
  const issuedCount = alreadyIssuedIds.size;
  const pendingCount = attendeeCount - issuedCount;

  const loadStats = async () => {
    if (!id) return;
    setIsLoading(true);
    setLastSuccessCount(null);
    try {
      // 1. Fetch Event Template metadata
      const { data: eventRow, error: eErr } = await supabase
        .from('events')
        .select('*')
        .eq('id', parseInt(id))
        .maybeSingle();

      if (eErr) throw eErr;
      if (eventRow) {
        setEvent(eventRow as EventModel);
        if (eventRow.template_url) {
          setSlidesUrl(eventRow.template_url);
        } else if (eventRow.certificate_image_url) {
          setSlidesUrl(eventRow.certificate_image_url);
        }
        if (eventRow.chair_name) setChairName(eventRow.chair_name);
        if (eventRow.coordinator_name) setCoordName(eventRow.coordinator_name);
        setIsCompleted(eventRow.attendance_finalized || false);
      }

      // 2. Fetch Attendance and Registrations Rows
      const setAllUserIds = new Set<string>();

      try {
        const { data: attendanceRows } = await supabase
          .from('attendance')
          .select('user_id')
          .eq('event_id', parseInt(id));
        (attendanceRows || []).forEach(r => r.user_id && setAllUserIds.add(r.user_id));
      } catch (_) {}

      try {
        const { data: regRows } = await supabase
          .from('registrations')
          .select('user_id')
          .eq('event_id', parseInt(id));
        (regRows || []).forEach(r => r.user_id && setAllUserIds.add(r.user_id));
      } catch (_) {}

      const userIds = Array.from(setAllUserIds);
      let uniqueAttendees: Attendee[] = [];
      
      if (userIds.length > 0) {
        const { data: usersRows, error: uErr } = await supabase
          .from('profiles')
          .select('id, name, email, membership_id')
          .in('id', userIds);

        if (uErr) console.error(uErr);
        const usersMap = new Map((usersRows || []).map(u => [u.id, u]));
        uniqueAttendees = userIds.map(uid => {
          const profile = usersMap.get(uid);
          return {
            user_id: uid,
            name: profile?.name || 'Member',
            email: profile?.email || '',
            membership_id: profile?.membership_id || '',
          };
        });
      }
      setAttendees(uniqueAttendees);
      if (uniqueAttendees.length === 0) {
        setPublishWithoutAttendance(true);
      }

      // 4. Fetch already issued certificates
      const { data: issuedRows, error: cErr } = await supabase
        .from('certificates')
        .select('*')
        .eq('event_id', parseInt(id))
        .order('issued_at', { ascending: false });

      if (cErr) throw cErr;
      const issuedSet = new Set((issuedRows || []).map(r => r.user_id));
      setAlreadyIssuedIds(issuedSet);
      setVerifiedCertificates((issuedRows || []) as VerifiedCertRow[]);
      if (issuedRows && issuedRows.length > 0) {
        for (const r of issuedRows) {
          if (r.title) {
            const raw = r.title as string;
            const customPart = raw.includes(' — ') ? raw.split(' — ')[0] : (raw.includes(' - ') ? raw.split(' - ')[0] : raw);
            if (customPart.trim()) {
              setCertificateName(customPart.trim());
              break;
            }
          }
        }
      }

      // 5. Fetch all m-Lynq profiles for 'Publish without Attendance List' mode
      try {
        const { data: allProfRows } = await supabase
          .from('profiles')
          .select('id, name, email, iste_membership_id')
          .order('name');

        const mappedAll: Attendee[] = (allProfRows || []).map((p: any) => ({
          user_id: p.id,
          name: p.name || 'Member',
          email: p.email || '',
          membership_id: p.iste_membership_id || p.membership_id || '',
        }));
        setAllMlynqUsers(mappedAll);
      } catch (profErr) {
        console.error('Error loading all mlynq users:', profErr);
      }
    } catch (e) {
      console.error('Error loading event stats:', e);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, [id]);

  // Clean and normalize strings for multi-tier matching:
  // 100% case-insensitive, unconditionally strips .pdf and image extensions,
  // ignores prefixes/formatting/separators for exact and fuzzy comparisons.
  const normalizeText = (text?: string | null): string => {
    if (!text) return '';
    let s = text.trim();
    // 1. Strip file extension (.pdf, .png, .jpg, .jpeg) case-insensitively, including any trailing spaces
    s = s.replace(/\.(pdf|png|jpg|jpeg)\s*$/i, '');
    // Also remove standalone .pdf token if present
    s = s.replace(/\bpdf\b/gi, '');
    // 2. Convert to lowercase for 100% case-insensitive comparison
    s = s.toLowerCase();
    // 3. Remove common certificate prefixes (case-insensitive)
    s = s.replace(/^(certificate|cert|participation|appreciation|attendance|winner|completion)[_\-\s]+/i, '');
    // 4. Remove leading numbering/indexes e.g. "01.", "1 - ", "(1)"
    s = s.replace(/^(\d+[\.\-_)\s]+|\(\d+\)\s*)/, '');
    // 5. Replace separators (dots, underscores, hyphens, slashes) with space
    s = s.replace(/[_\-.\/\\|]+/g, ' ');
    // 6. Keep only alphanumeric and spaces
    s = s.replace(/[^a-z0-9\s]/g, '');
    // 7. Collapse spaces and trim
    return s.replace(/\s+/g, ' ').trim();
  };

  // Multi-tier matching for Non-Attendance List mode (File -> m-Lynq User)
  const fileMatches = useMemo(() => {
    return uploadedFiles.map(file => {
      // 0. Manual Override
      if (fileManualOverrides[file.name]) {
        const overrideUserId = fileManualOverrides[file.name];
        const matched = allMlynqUsers.find(u => u.user_id === overrideUserId) || null;
        return {
          file,
          matchedUser: matched,
          matchType: 'manual' as const,
          matchScore: 100,
        };
      }

      const cleanFile = normalizeText(file.name);
      const fileTokens = cleanFile.split(' ').filter(t => t.length >= 1);

      let bestUser: Attendee | null = null;
      let bestType: 'exact' | 'contains' | 'token' | 'none' = 'none';
      let bestScore = 0;

      for (const user of allMlynqUsers) {
        const cleanStudent = normalizeText(user.name);
        const studentTokens = cleanStudent.split(' ').filter(t => t.length >= 1);
        const cleanEmail = user.email ? normalizeText(user.email.split('@')[0]) : '';
        const cleanMemberId = user.membership_id ? normalizeText(user.membership_id) : '';

        // 1. Exact match
        if (cleanFile === cleanStudent && cleanFile.length > 0) {
          bestUser = user;
          bestType = 'exact';
          bestScore = 100;
          break;
        }

        // 2. Contains match
        if (cleanStudent.length >= 3 && cleanFile.includes(cleanStudent)) {
          if (bestScore < 90) {
            bestUser = user;
            bestType = 'contains';
            bestScore = 90;
          }
        } else if (cleanFile.length >= 3 && cleanStudent.includes(cleanFile)) {
          if (bestScore < 85) {
            bestUser = user;
            bestType = 'contains';
            bestScore = 85;
          }
        }

        // 3. Token match
        if (studentTokens.length > 0) {
          const matchedCount = studentTokens.filter(st => fileTokens.includes(st)).length;
          const ratio = matchedCount / studentTokens.length;
          if (ratio === 1.0 && bestScore < 88) {
            bestUser = user;
            bestType = 'token';
            bestScore = 88;
          } else if (ratio >= 0.6 && bestScore < 70) {
            const calculated = Math.round(ratio * 70);
            if (calculated > bestScore) {
              bestUser = user;
              bestType = 'token';
              bestScore = calculated;
            }
          }
        }

        // 4. Identifier match
        if (cleanEmail && cleanFile.includes(cleanEmail) && bestScore < 80) {
          bestUser = user;
          bestType = 'contains';
          bestScore = 80;
        }
        if (cleanMemberId && cleanFile.includes(cleanMemberId) && bestScore < 80) {
          bestUser = user;
          bestType = 'contains';
          bestScore = 80;
        }
      }

      return {
        file,
        matchedUser: bestScore >= 60 ? bestUser : null,
        matchType: bestScore >= 60 ? bestType : ('none' as const),
        matchScore: bestScore,
      };
    });
  }, [allMlynqUsers, uploadedFiles, fileManualOverrides]);

  // Multi-tier matching engine for manual certificates
  const matches: CertMatch[] = useMemo(() => {
    const fileList = [...uploadedFiles];
    const usedFileNames = new Set<string>();

    return attendees.map(attendee => {
      // Check manual override first
      if (manualOverrides[attendee.user_id]) {
        const overrideFileName = manualOverrides[attendee.user_id];
        const matched = fileList.find(f => f.name === overrideFileName) || null;
        if (matched) usedFileNames.add(matched.name);
        return {
          attendee,
          matchedFile: matched,
          matchType: 'manual',
          matchScore: 100,
        };
      }

      const cleanStudent = normalizeText(attendee.name);
      const studentTokens = cleanStudent.split(' ').filter(t => t.length >= 1);
      const cleanEmail = attendee.email ? normalizeText(attendee.email.split('@')[0]) : '';
      const cleanMemberId = attendee.membership_id ? normalizeText(attendee.membership_id) : '';

      let bestFile: UploadedCertFile | null = null;
      let bestType: 'exact' | 'contains' | 'token' | 'manual' | 'none' = 'none';
      let bestScore = 0;

      for (const f of fileList) {
        const cleanFile = normalizeText(f.name);
        const fileTokens = cleanFile.split(' ').filter(t => t.length >= 1);

        // 1. Exact match
        if (cleanFile === cleanStudent) {
          bestFile = f;
          bestType = 'exact';
          bestScore = 100;
          break;
        }

        // 2. Contains match (longer token)
        if (cleanStudent.length >= 3 && cleanFile.includes(cleanStudent)) {
          if (bestScore < 90) {
            bestFile = f;
            bestType = 'contains';
            bestScore = 90;
          }
        } else if (cleanFile.length >= 3 && cleanStudent.includes(cleanFile)) {
          if (bestScore < 85) {
            bestFile = f;
            bestType = 'contains';
            bestScore = 85;
          }
        }

        // 3. Token match: count matching words
        if (studentTokens.length > 0) {
          const matchedTokenCount = studentTokens.filter(st => fileTokens.includes(st)).length;
          const ratio = matchedTokenCount / studentTokens.length;
          if (ratio === 1.0 && bestScore < 88) {
            bestFile = f;
            bestType = 'token';
            bestScore = 88;
          } else if (ratio >= 0.6 && bestScore < 70) {
            bestFile = f;
            bestType = 'token';
            bestScore = Math.round(ratio * 70);
          }
        }

        // 4. Fallback identifier match: Email or Membership ID
        if (cleanEmail && cleanFile.includes(cleanEmail) && bestScore < 80) {
          bestFile = f;
          bestType = 'contains';
          bestScore = 80;
        }
        if (cleanMemberId && cleanFile.includes(cleanMemberId) && bestScore < 80) {
          bestFile = f;
          bestType = 'contains';
          bestScore = 80;
        }
      }

      if (bestFile) {
        usedFileNames.add(bestFile.name);
      }

      return {
        attendee,
        matchedFile: bestFile,
        matchType: bestType,
        matchScore: bestScore,
      };
    });
  }, [attendees, uploadedFiles, manualOverrides]);

  const matchedCount = matches.filter(m => m.matchedFile !== null).length;
  const pendingMatchedCount = matches.filter(m => m.matchedFile !== null && !alreadyIssuedIds.has(m.attendee.user_id)).length;
  const fileMatchedCount = fileMatches.filter(m => m.matchedUser !== null).length;
  const pendingFileMatchedCount = fileMatches.filter(m => m.matchedUser !== null && !alreadyIssuedIds.has(m.matchedUser.user_id)).length;

  const filteredVerifiedCertificates = useMemo(() => {
    if (!verifiedSearchQuery.trim()) return verifiedCertificates;
    const q = verifiedSearchQuery.toLowerCase();
    return verifiedCertificates.filter(c => 
      (c.student_name && c.student_name.toLowerCase().includes(q)) ||
      (c.title && c.title.toLowerCase().includes(q)) ||
      c.user_id.toLowerCase().includes(q)
    );
  }, [verifiedCertificates, verifiedSearchQuery]);

  // ── Manual Attendance List Matching Engine ──
  const calculatedManualAttendanceRecords = useMemo(() => {
    return manualAttendanceRecords.map(record => {
      // 0. Manual Override
      if (manualAttendanceUserOverrides[record.key]) {
        const overrideUserId = manualAttendanceUserOverrides[record.key];
        const matched = allMlynqUsers.find(u => u.user_id === overrideUserId) || null;
        return {
          ...record,
          matchedUser: matched,
          matchType: 'manual' as const,
          matchScore: 100,
        };
      }

      const cleanRecordName = normalizeText(record.rawName);
      const recordTokens = cleanRecordName.split(' ').filter(t => t.length >= 1);
      const cleanRecordEmail = record.rawEmail.trim().toLowerCase();
      const cleanRecordId = normalizeText(record.rawMembershipId);

      let bestUser: Attendee | null = null;
      let bestType: 'exact_email' | 'exact_id' | 'exact_name' | 'fuzzy_name' | 'none' = 'none';
      let bestScore = 0;

      for (const user of allMlynqUsers) {
        const userEmail = (user.email || '').trim().toLowerCase();
        const userId = normalizeText(user.membership_id || '');
        const cleanUserName = normalizeText(user.name);
        const userTokens = cleanUserName.split(' ').filter(t => t.length >= 1);

        // 1. Exact Email Match
        if (cleanRecordEmail && userEmail && cleanRecordEmail === userEmail) {
          bestUser = user;
          bestType = 'exact_email';
          bestScore = 100;
          break;
        }

        // 2. Exact Membership ID Match
        if (cleanRecordId && userId && cleanRecordId === userId) {
          bestUser = user;
          bestType = 'exact_id';
          bestScore = 100;
          break;
        }

        // 3. Exact Name Match
        if (cleanRecordName && cleanRecordName === cleanUserName) {
          if (bestScore < 95) {
            bestUser = user;
            bestType = 'exact_name';
            bestScore = 95;
          }
          continue;
        }

        // 4. Token Overlap Match
        if (userTokens.length > 0 && recordTokens.length > 0) {
          const matchedCount = recordTokens.filter(rt => userTokens.includes(rt)).length;
          const ratio = matchedCount / userTokens.length;
          if (ratio === 1.0 && bestScore < 90) {
            bestUser = user;
            bestType = 'fuzzy_name';
            bestScore = 90;
          } else if (ratio >= 0.6 && bestScore < 80) {
            const calculated = Math.round(ratio * 80);
            if (calculated > bestScore) {
              bestUser = user;
              bestType = 'fuzzy_name';
              bestScore = calculated;
            }
          }
        }

        // 5. Contains match
        if (cleanUserName.length >= 3 && cleanRecordName.includes(cleanUserName) && bestScore < 75) {
          bestUser = user;
          bestType = 'fuzzy_name';
          bestScore = 75;
        } else if (cleanRecordName.length >= 3 && cleanUserName.includes(cleanRecordName) && bestScore < 75) {
          bestUser = user;
          bestType = 'fuzzy_name';
          bestScore = 75;
        }
      }

      return {
        ...record,
        matchedUser: bestScore >= 60 ? bestUser : null,
        matchType: (bestScore >= 60 ? bestType : 'none') as any,
        matchScore: bestScore,
      };
    });
  }, [manualAttendanceRecords, manualAttendanceUserOverrides, allMlynqUsers]);

  const totalInManualList = calculatedManualAttendanceRecords.length;
  const matchedInManualList = calculatedManualAttendanceRecords.filter(r => r.matchedUser !== null).length;
  const unmatchedInManualList = calculatedManualAttendanceRecords.filter(r => r.matchedUser === null).length;
  const pendingToPublishInManualList = calculatedManualAttendanceRecords.filter(r => r.matchedUser !== null && !alreadyIssuedIds.has(r.matchedUser.user_id)).length;
  const manualMatchPercentage = totalInManualList > 0 ? ((matchedInManualList / totalInManualList) * 100).toFixed(1) : '0';

  const filteredManualRecords = useMemo(() => {
    return calculatedManualAttendanceRecords.filter(r => {
      if (attendanceListFilter === 'matched') return r.matchedUser !== null;
      if (attendanceListFilter === 'unmatched') return r.matchedUser === null;
      if (attendanceListFilter === 'pending') return r.matchedUser !== null && !alreadyIssuedIds.has(r.matchedUser.user_id);
      return true;
    });
  }, [calculatedManualAttendanceRecords, attendanceListFilter, alreadyIssuedIds]);

  const cleanHeader = (h: string) => h.toLowerCase().replace(/[^a-z0-9]/g, '');

  const extractColumnValue = (row: Record<string, string>, candidateKeys: string[]) => {
    for (const k of candidateKeys) {
      const normK = cleanHeader(k);
      for (const [key, val] of Object.entries(row)) {
        if (cleanHeader(key) === normK && val.trim()) return val.trim();
      }
    }
    for (const k of candidateKeys) {
      const normK = cleanHeader(k);
      for (const [key, val] of Object.entries(row)) {
        if (cleanHeader(key).includes(normK) && val.trim()) return val.trim();
      }
    }
    return '';
  };

  const parseCsvText = (text: string): Record<string, string>[] => {
    let content = text;
    if (content.charCodeAt(0) === 0xFEFF) {
      content = content.slice(1);
    }
    const lines = content.split(/\r?\n/).filter(l => l.trim().length > 0);
    if (lines.length < 2) return [];

    const parseLine = (line: string): string[] => {
      const tokens: string[] = [];
      let sb = '';
      let inQuotes = false;
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] === '"') {
            sb += '"';
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (c === ',' && !inQuotes) {
          tokens.push(sb.trim());
          sb = '';
        } else {
          sb += c;
        }
      }
      tokens.push(sb.trim());
      return tokens;
    };

    const headers = parseLine(lines[0]);
    const rows: Record<string, string>[] = [];

    for (let i = 1; i < lines.length; i++) {
      const tokens = parseLine(lines[i]);
      if (tokens.every(t => !t)) continue;
      const row: Record<string, string> = {};
      headers.forEach((h, idx) => {
        row[h] = tokens[idx] || '';
      });
      rows.push(row);
    }
    return rows;
  };

  const handleAttendanceFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsParsingAttendanceFile(true);
    try {
      const text = await file.text();
      const rows = parseCsvText(text);

      if (rows.length === 0) {
        throw new Error('No attendee data rows found in the uploaded file.');
      }

      const records: ManualAttendanceRecord[] = [];
      for (const r of rows) {
        const name = extractColumnValue(r, ['fullname', 'studentname', 'name', 'participantname', 'attendee', 'membername', 'student']);
        const email = extractColumnValue(r, ['emailaddress', 'email', 'mail', 'studentemail']);
        const memberId = extractColumnValue(r, ['membershipid', 'memberid', 'isteid', 'istemembershipid', 'membership', 'id']);
        const phone = extractColumnValue(r, ['phonenumber', 'phone', 'mobile', 'contact', 'whatsapp']);
        const rollNo = extractColumnValue(r, ['rollnumber', 'rollno', 'regno', 'registernumber', 'regid', 'admissionno']);

        if (name || email || memberId) {
          const key = `${name.toLowerCase().trim()}_${email.toLowerCase().trim()}_${memberId.toLowerCase().trim()}`;
          records.push({
            key,
            rawName: name,
            rawEmail: email,
            rawMembershipId: memberId,
            rawPhone: phone,
            rawRollNo: rollNo,
            matchedUser: null,
            matchType: 'none',
            matchScore: 0,
          });
        }
      }

      if (records.length === 0) {
        throw new Error('Could not extract any attendee records. Ensure column headers include Name or Email.');
      }

      setManualAttendanceRecords(records);
      setUploadedAttendanceFileName(file.name);
      setManualAttendanceUserOverrides({});
      setAttendanceListFilter('all');
    } catch (err: any) {
      alert('Error parsing attendance file: ' + err.message);
    } finally {
      setIsParsingAttendanceFile(false);
    }
  };

  const handlePublishManualAttendanceCertificates = () => {
    const matched = calculatedManualAttendanceRecords.filter(r => r.matchedUser !== null);
    if (matched.length === 0) {
      alert('No matched attendees found in the uploaded list.');
      return;
    }

    const toPublish = matched.filter(r => !alreadyIssuedIds.has(r.matchedUser!.user_id));
    if (toPublish.length === 0) {
      alert('All matched attendees already have certificates.');
      return;
    }

    setConfirmModal({
      isOpen: true,
      title: 'Publish Automated Certificates',
      description: `Ready to issue and send certificates from presentation template directly to ${toPublish.length} matched attendee(s)? Each student will receive their certificate in their m-Lynq account immediately. Attendance will also be marked automatically.`,
      recipients: toPublish.map(r => ({ student: r.matchedUser!.name || r.rawName, file: 'Presentation Template' })),
      onConfirm: () => {
        setConfirmModal(null);
        executePublishManualAttendanceCertificates(toPublish);
      }
    });
  };

  const executePublishManualAttendanceCertificates = async (toPublish: typeof calculatedManualAttendanceRecords) => {
    setIsProcessing(true);
    setProcessedCount(0);
    setLastSuccessCount(null);

    let successCount = 0;
    const total = toPublish.length;
    const successItems: PublishResultItem[] = [];
    const failedItems: PublishFailItem[] = [];

    try {
      for (let i = 0; i < toPublish.length; i++) {
        const item = toPublish[i];
        const sname = item.matchedUser!.name || item.rawName;
        const uid = item.matchedUser!.user_id;
        setProgressMessage(`Publishing for ${sname} (${i + 1}/${total})...`);

        const certCustomName = (certificateNameRef.current || certificateName).trim() || 'Certificate of Participation';
        const fileUrl = slidesUrl.trim() || event?.template_url || '';
        const { error } = await supabase.from('certificates').upsert({
          user_id: uid,
          event_id: parseInt(id!),
          student_name: sname,
          title: `${certCustomName} — ${event?.title}`,
          description: `Awarded ${certCustomName} for ${event?.title} on ${event?.date || ''}`,
          file_url: fileUrl,
          certificate_url: fileUrl,
          issued_by: currentUser?.id,
          issued_at: new Date().toISOString(),
        }, { onConflict: 'user_id,event_id' });

        if (!error) {
          try {
            await supabase.from('attendance').upsert({
              event_id: parseInt(id!),
              user_id: uid,
            }, { onConflict: 'event_id,user_id' });
          } catch (_) {}

          successCount++;
          setProcessedCount(i + 1);
          successItems.push({
            student: sname,
            file: 'Presentation Template',
            url: fileUrl,
          });
        } else {
          console.error(`Certificate DB record creation failed for ${sname}:`, error);
          failedItems.push({
            student: sname,
            file: 'Presentation Template',
            error: `Database save failed: ${error.message || 'Database error'}`,
          });
        }
      }
    } catch (err: any) {
      console.error('Manual attendance issuance error:', err);
    }

    await loadStats();
    setIsProcessing(false);
    setProgressMessage('');
    setLastSuccessCount(successCount);
    setPublishResultModal({
      isOpen: true,
      successItems,
      failedItems,
    });
  };

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = event.target.files;
    if (!files || files.length === 0) return;

    setIsExtractingZip(true);
    const newFiles: UploadedCertFile[] = [];

    try {
      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        if (file.name.toLowerCase().endsWith('.zip')) {
          const zip = new JSZip();
          const zipData = await zip.loadAsync(file);
          
          for (const [relativePath, zipEntry] of Object.entries(zipData.files)) {
            if (zipEntry.dir) continue;
            if (relativePath.includes('__MACOSX') || relativePath.startsWith('.')) continue;

            const lower = relativePath.toLowerCase();
            if (lower.endsWith('.pdf') || lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
              const fileData = await zipEntry.async('uint8array');
              const fileName = relativePath.split('/').pop() || relativePath;
              const mime = lower.endsWith('.pdf') ? 'application/pdf' : lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
              newFiles.push({
                name: fileName,
                data: fileData,
                type: mime,
              });
            }
          }
        } else {
          const lower = file.name.toLowerCase();
          if (lower.endsWith('.pdf') || lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
            newFiles.push({
              name: file.name,
              file: file,
              type: file.type || (lower.endsWith('.pdf') ? 'application/pdf' : 'image/png'),
            });
          }
        }
      }

      setUploadedFiles(prev => {
        const combined = [...prev];
        for (const nf of newFiles) {
          if (!combined.some(existing => existing.name === nf.name)) {
            combined.push(nf);
          }
        }
        return combined;
      });
    } catch (e: any) {
      alert('Error parsing uploaded files: ' + e.message);
    } finally {
      setIsExtractingZip(false);
    }
  };

  const handleSaveTemplateAndExecom = async () => {
    if (!id) return;
    setIsProcessing(true);
    setProgressMessage('Saving template & Execom details...');
    try {
      const { error } = await supabase
        .from('events')
        .update({
          template_url: slidesUrl.trim(),
          certificate_image_url: slidesUrl.trim(),
          certificate_template_type: 'slides',
          chair_name: chairName.trim() || null,
          coordinator_name: coordName.trim() || null,
        })
        .eq('id', parseInt(id));

      if (error) throw error;
      alert('Template URL and Execom names updated successfully!');
    } catch (e: any) {
      console.error(e);
      alert('Save failed: ' + e.message);
    } finally {
      setIsProcessing(false);
      setProgressMessage('');
      loadStats();
    }
  };

  const handleFinalizeEvent = async () => {
    if (!id) return;
    setIsProcessing(true);
    setProgressMessage('Finalizing event...');
    try {
      const { error } = await supabase
        .from('events')
        .update({ attendance_finalized: true })
        .eq('id', parseInt(id));

      if (error) throw error;
      setIsCompleted(true);
      alert('Event marked as Completed successfully!');
    } catch (e: any) {
      alert('Failed to finalize event: ' + e.message);
    } finally {
      setIsProcessing(false);
      setProgressMessage('');
      loadStats();
    }
  };

  // Automated Google Slides Issuance
  const handlePublishAutomatedCertificates = () => {
    if (attendees.length === 0) {
      alert('No attendees found for this event.');
      return;
    }

    const eligible = attendees.filter(a => !alreadyIssuedIds.has(a.user_id));
    if (eligible.length === 0) {
      alert('All attendees already have certificates.');
      return;
    }

    setConfirmModal({
      isOpen: true,
      title: 'Publish Automated Certificates',
      description: `Ready to generate and publish certificates from presentation template for ${eligible.length} attendee(s) of "${event?.title}"? Each student will receive their certificate in their m-Lynq account immediately.`,
      recipients: eligible.map(a => ({ student: a.name, file: 'Google Slides Template' })),
      onConfirm: () => {
        setConfirmModal(null);
        executePublishAutomatedCertificates(eligible);
      }
    });
  };

  const executePublishAutomatedCertificates = async (eligible: typeof attendees) => {
    setIsProcessing(true);
    setProcessedCount(0);
    setLastSuccessCount(null);

    let successCount = 0;
    const total = eligible.length;
    const successItems: PublishResultItem[] = [];
    const failedItems: PublishFailItem[] = [];

    try {
      if (slidesUrl.trim() || chairName.trim() || coordName.trim()) {
        await supabase
          .from('events')
          .update({
            ...(slidesUrl.trim() ? { template_url: slidesUrl.trim(), certificate_image_url: slidesUrl.trim(), certificate_template_type: 'slides' } : {}),
            chair_name: chairName.trim() || null,
            coordinator_name: coordName.trim() || null,
          })
          .eq('id', parseInt(id!));
      }

      const { data: funcData, error: funcErr } = await supabase.functions.invoke('generate-certificates', {
        body: {
          eventId: parseInt(id!),
          templateUrl: slidesUrl.trim(),
          chairName: chairName.trim(),
          coordinatorName: coordName.trim(),
          forceRegenerate: true,
        },
      });

      if (!funcErr && funcData && typeof funcData.generated === 'number') {
        successCount = funcData.generated;
        eligible.forEach(a => {
          successItems.push({
            student: a.name,
            file: 'Generated Slide PDF',
            url: slidesUrl.trim() || event?.template_url || '',
          });
        });
      } else {
        for (let i = 0; i < eligible.length; i++) {
          const attendee = eligible[i];
          setProgressMessage(`Publishing for ${attendee.name} (${i + 1}/${total})...`);

          const certCustomName = (certificateNameRef.current || certificateName).trim() || 'Certificate of Participation';
          const fileUrl = slidesUrl.trim() || event?.template_url || '';
          const { error } = await supabase.from('certificates').upsert({
            user_id: attendee.user_id,
            event_id: parseInt(id!),
            student_name: attendee.name,
            title: `${certCustomName} — ${event?.title}`,
            description: `Awarded ${certCustomName} for ${event?.title} on ${event?.date || ''}`,
            file_url: fileUrl,
            certificate_url: fileUrl,
            issued_by: currentUser?.id,
            issued_at: new Date().toISOString()
          }, { onConflict: 'user_id,event_id' });

          if (!error) {
            successCount++;
            setProcessedCount(i + 1);
            successItems.push({
              student: attendee.name,
              file: 'Google Slides Template',
              url: fileUrl,
            });
          } else {
            console.error(`Certificate DB record creation failed for ${attendee.name}:`, error);
            failedItems.push({
              student: attendee.name,
              file: 'Google Slides Template',
              error: `Database save failed: ${error.message || 'Database error'}`,
            });
          }
        }
      }
    } catch (err: any) {
      console.error(`Error issuing certificates:`, err);
    }

    await loadStats();
    setIsProcessing(false);
    setProgressMessage('');
    setLastSuccessCount(successCount);
    setPublishResultModal({
      isOpen: true,
      successItems,
      failedItems,
    });
  };

  // Manual Distribution Issuance Pipeline
  const promptPublishManualCertificates = () => {
    const toPublish = matches.filter(m => m.matchedFile !== null && !alreadyIssuedIds.has(m.attendee.user_id));
    if (toPublish.length === 0) {
      if (uploadedFiles.length === 0) {
        alert('Please upload certificate files or a .ZIP archive first.');
      } else {
        alert('No pending matched certificates to publish. Attendees may have already received certificates, or no files matched.');
      }
      return;
    }

    setConfirmModal({
      isOpen: true,
      title: 'Publish Manual Certificates',
      description: `Ready to upload and publish certificates for ${toPublish.length} matched event attendee(s)?`,
      recipients: toPublish.map(m => ({ student: m.attendee.name, file: m.matchedFile!.name })),
      onConfirm: () => {
        setConfirmModal(null);
        executePublishManualCertificates(toPublish);
      }
    });
  };

  const executePublishManualCertificates = async (toPublish: typeof matches) => {
    setIsProcessing(true);
    setProcessedCount(0);
    setLastSuccessCount(null);

    let successCount = 0;
    const total = toPublish.length;
    const successItems: PublishResultItem[] = [];
    const failedItems: PublishFailItem[] = [];

    try {
      for (let i = 0; i < toPublish.length; i++) {
        const item = toPublish[i];
        const { attendee, matchedFile } = item;
        if (!matchedFile) continue;

        setProgressMessage(`Uploading certificate for ${attendee.name} (${i + 1}/${total})...`);

        const ext = matchedFile.name.split('.').pop() || 'pdf';
        const storagePath = `${id}/${attendee.user_id}.${ext}`;
        
        let filePayload: any = matchedFile.file;
        if (!filePayload && matchedFile.data) {
          filePayload = new Blob([matchedFile.data as any], { type: matchedFile.type || 'application/pdf' });
        }

        // Upload to Supabase Storage 'certificates' bucket
        const { error: uploadError } = await supabase.storage
          .from('certificates')
          .upload(storagePath, filePayload, {
            contentType: matchedFile.type || 'application/pdf',
            upsert: true,
          });

        if (uploadError) {
          console.error(`Upload failed for ${attendee.name}:`, uploadError);
          failedItems.push({
            student: attendee.name,
            file: matchedFile.name,
            error: `Storage upload failed: ${uploadError.message || 'Permission or storage error'}`,
          });
          continue;
        }

        const { data: pubData } = supabase.storage
          .from('certificates')
          .getPublicUrl(storagePath);

        const fileUrl = pubData?.publicUrl || '';

        const certCustomName = (certificateNameRef.current || certificateName).trim() || 'Certificate of Participation';
        const { error: certError } = await supabase.from('certificates').upsert({
          user_id: attendee.user_id,
          event_id: parseInt(id!),
          student_name: attendee.name,
          title: `${certCustomName} — ${event?.title}`,
          description: `Awarded ${certCustomName} for ${event?.title} on ${event?.date || ''}`,
          file_url: fileUrl,
          certificate_url: fileUrl,
          storage_path: storagePath,
          issued_by: currentUser?.id,
          issued_at: new Date().toISOString(),
        }, { onConflict: 'event_id,user_id' });

        if (!certError) {
          successCount++;
          setProcessedCount(i + 1);
          successItems.push({
            student: attendee.name,
            file: matchedFile.name,
            url: fileUrl,
          });
        } else {
          console.error(`Certificate DB record creation failed for ${attendee.name}:`, certError);
          failedItems.push({
            student: attendee.name,
            file: matchedFile.name,
            error: `Database save failed: ${certError.message || 'Database error'}`,
          });
        }
      }
    } catch (err: any) {
      console.error('Error during manual certificate publication:', err);
    }

    await loadStats();
    setIsProcessing(false);
    setProgressMessage('');
    setLastSuccessCount(successCount);
    setPublishResultModal({
      isOpen: true,
      successItems,
      failedItems,
    });
  };

  // Publish without Attendance List Issuance Pipeline (Match against all m-Lynq users)
  const promptPublishWithoutAttendance = () => {
    const toPublish = fileMatches.filter(m => m.matchedUser !== null && !alreadyIssuedIds.has(m.matchedUser.user_id));
    if (toPublish.length === 0) {
      if (uploadedFiles.length === 0) {
        alert('Please upload your certificate files or a .ZIP archive first.');
      } else {
        alert('No pending matched certificates to publish. Make sure student names match, or manually assign users from the table.');
      }
      return;
    }

    setConfirmModal({
      isOpen: true,
      title: 'Publish Certificates to m-Lynq',
      description: `Ready to issue and send certificates directly to ${toPublish.length} matched m-Lynq user(s)? Each student will receive their certificate in their app account immediately.`,
      recipients: toPublish.map(m => ({ student: m.matchedUser!.name, file: m.file.name })),
      onConfirm: () => {
        setConfirmModal(null);
        executePublishWithoutAttendance(toPublish);
      }
    });
  };

  const executePublishWithoutAttendance = async (toPublish: typeof fileMatches) => {
    setIsProcessing(true);
    setProcessedCount(0);
    setLastSuccessCount(null);

    let successCount = 0;
    const total = toPublish.length;
    const successItems: PublishResultItem[] = [];
    const failedItems: PublishFailItem[] = [];

    try {
      for (let i = 0; i < toPublish.length; i++) {
        const item = toPublish[i];
        const { matchedUser, file } = item;
        if (!matchedUser) continue;

        setProgressMessage(`Publishing for ${matchedUser.name} (${i + 1}/${total})...`);

        const ext = file.name.split('.').pop() || 'pdf';
        const storagePath = `${id}/${matchedUser.user_id}.${ext}`;
        
        let filePayload: any = file.file;
        if (!filePayload && file.data) {
          filePayload = new Blob([file.data as any], { type: file.type || 'application/pdf' });
        }

        const { error: uploadError } = await supabase.storage
          .from('certificates')
          .upload(storagePath, filePayload, {
            contentType: file.type || 'application/pdf',
            upsert: true,
          });

        if (uploadError) {
          console.error(`Upload failed for ${matchedUser.name}:`, uploadError);
          failedItems.push({
            student: matchedUser.name,
            file: file.name,
            error: `Storage upload failed: ${uploadError.message || 'Permission or storage error'}`,
          });
          continue;
        }

        const { data: pubData } = supabase.storage
          .from('certificates')
          .getPublicUrl(storagePath);

        const fileUrl = pubData?.publicUrl || '';

        const certCustomName = (certificateNameRef.current || certificateName).trim() || 'Certificate of Participation';
        const { error: certError } = await supabase.from('certificates').upsert({
          user_id: matchedUser.user_id,
          event_id: parseInt(id!),
          student_name: matchedUser.name,
          title: `${certCustomName} — ${event?.title}`,
          description: `Awarded ${certCustomName} for ${event?.title} on ${event?.date || ''}`,
          file_url: fileUrl,
          certificate_url: fileUrl,
          storage_path: storagePath,
          issued_by: currentUser?.id,
          issued_at: new Date().toISOString(),
        }, { onConflict: 'event_id,user_id' });

        try {
          await supabase.from('attendance').upsert({
            event_id: parseInt(id!),
            user_id: matchedUser.user_id,
          }, { onConflict: 'event_id,user_id' });
        } catch (_) {}

        if (!certError) {
          successCount++;
          setProcessedCount(i + 1);
          successItems.push({
            student: matchedUser.name,
            file: file.name,
            url: fileUrl,
          });
        } else {
          console.error(`Certificate DB record creation failed for ${matchedUser.name}:`, certError);
          failedItems.push({
            student: matchedUser.name,
            file: file.name,
            error: `Database save failed: ${certError.message || 'Database error'}`,
          });
        }
      }
    } catch (err: any) {
      console.error('Error during non-attendance certificate publication:', err);
    }

    await loadStats();
    setIsProcessing(false);
    setProgressMessage('');
    setLastSuccessCount(successCount);
    setPublishResultModal({
      isOpen: true,
      successItems,
      failedItems,
    });
  };

  if (!currentUser) return null;

  return (
    <div className="publish-certs-container" style={{ padding: '16px 20px', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <header className="page-header" style={{ display: 'flex', alignItems: 'center', height: '60px', marginBottom: '20px' }}>
        <button onClick={() => navigate('/events')} className="back-button" style={{ background: 'none', border: 'none', color: 'var(--text-primary)', cursor: 'pointer', marginRight: '16px' }}>
          <ArrowLeft size={20} />
        </button>
        <h2 className="page-title" style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 800, fontSize: '20px', margin: 0 }}>
          Publish Certificates
        </h2>
        <div style={{ marginLeft: 'auto' }}>
          {!isLoading && !isProcessing && (
            <button onClick={loadStats} className="role-filter-chip" style={{ display: 'flex', alignItems: 'center', gap: '6px', background: 'none', border: '1px solid var(--border-light)', cursor: 'pointer' }}>
              <RefreshCw size={14} /> Refresh
            </button>
          )}
        </div>
      </header>

      {isLoading ? (
        <div className="flex-center" style={{ height: '300px', flexDirection: 'column', gap: '12px' }}>
          <Loader size={32} className="spinner" />
          <span>Loading stats...</span>
        </div>
      ) : (
        <div className="publish-content" style={{ display: 'flex', flexDirection: 'column', gap: '20px', marginBottom: '80px' }}>
          {/* Event info card */}
          <GlassCard padding="20px">
            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '18px', margin: '0 0 8px 0' }}>
              {event?.title}
            </h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px', margin: 0 }}>
              Date: {event?.date} | Location: {event?.location || 'N/A'}
            </p>
          </GlassCard>

          {/* Optional Attendance Finalization Informational Card (Non-blocking) */}
          {!isCompleted ? (
            <div style={{ padding: '14px 18px', borderRadius: '12px', border: '1px solid rgba(245, 158, 11, 0.3)', background: 'rgba(245, 158, 11, 0.06)', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <AlertTriangle size={20} style={{ color: '#f59e0b', flexShrink: 0 }} />
              <div style={{ flex: 1 }}>
                <h4 style={{ margin: '0 0 2px 0', fontSize: '14px', color: 'white', fontWeight: 600 }}>Attendance Not Yet Finalized</h4>
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-secondary)' }}>You can still publish certificates anytime. Click finalize when you want to lock attendance.</p>
              </div>
              <button 
                onClick={handleFinalizeEvent} 
                disabled={isProcessing}
                className="role-filter-chip" 
                style={{ cursor: 'pointer', background: '#f59e0b', border: 'none', color: '#000', fontWeight: 700, padding: '7px 14px', borderRadius: '8px', fontSize: '12px' }}
              >
                Mark Finalized
              </button>
            </div>
          ) : (
            <div style={{ padding: '14px 18px', borderRadius: '12px', border: '1px solid rgba(22, 192, 122, 0.4)', background: 'rgba(22, 192, 122, 0.05)', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Check size={20} style={{ color: 'rgb(22, 192, 122)', flexShrink: 0 }} />
              <div>
                <h4 style={{ margin: '0 0 2px 0', fontSize: '14px', color: 'white', fontWeight: 600 }}>Attendance Finalized</h4>
                <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-secondary)' }}>Event marked as completed. All attendee records are locked.</p>
              </div>
            </div>
          )}

          {/* Stats grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '12px' }}>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-primary)' }}>{attendeeCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Total Attendees</div>
            </GlassCard>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: 'rgb(22, 192, 122)' }}>{issuedCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Already Issued</div>
            </GlassCard>
            <GlassCard padding="16px" style={{ textAlign: 'center' }}>
              <div style={{ fontSize: '24px', fontWeight: 800, color: '#f59e0b' }}>{pendingCount}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Pending</div>
            </GlassCard>
          </div>

          {/* Certificate Name / Type Card */}
          <GlassCard padding="18px">
            <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '15px', margin: '0 0 6px 0', display: 'flex', alignItems: 'center', gap: '8px', color: '#f59e0b' }}>
              <Award size={18} /> Certificate Name / Type
            </h3>
            <p style={{ margin: '0 0 12px 0', fontSize: '12px', color: 'var(--text-secondary)' }}>
              Customize the certificate name shown to participants in m-Lynq (e.g. Certificate of Participation, Certificate of Appreciation, Winner, 1st Prize, etc.).
            </p>
            <input
              type="text"
              value={certificateName}
              onChange={(e) => setCertificateName(e.target.value)}
              placeholder="e.g. Certificate of Participation"
              style={{ width: '100%', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '12px', color: 'var(--text-primary)', padding: '12px', outline: 'none', fontSize: '14px', fontWeight: 600 }}
            />
          </GlassCard>

          {/* Main Navigation Switch: Workspace vs Verified Database */}
          <div style={{ display: 'flex', gap: '10px' }}>
            <button
              onClick={() => setActiveTabSection('workspace')}
              style={{
                flex: 1,
                padding: '12px 16px',
                borderRadius: '12px',
                border: activeTabSection === 'workspace' ? '1px solid rgb(22, 192, 122)' : '1px solid var(--border-light)',
                background: activeTabSection === 'workspace' ? 'rgba(22, 192, 122, 0.12)' : 'rgba(255, 255, 255, 0.03)',
                color: activeTabSection === 'workspace' ? 'rgb(22, 192, 122)' : 'var(--text-secondary)',
                fontWeight: 700,
                fontSize: '14px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: '0.2s'
              }}
            >
              <Upload size={16} /> Certificate Upload & Issuance
            </button>
            <button
              onClick={() => {
                setActiveTabSection('verified');
                loadStats();
              }}
              style={{
                flex: 1,
                padding: '12px 16px',
                borderRadius: '12px',
                border: activeTabSection === 'verified' ? '1px solid #3b82f6' : '1px solid var(--border-light)',
                background: activeTabSection === 'verified' ? 'rgba(59, 130, 246, 0.12)' : 'rgba(255, 255, 255, 0.03)',
                color: activeTabSection === 'verified' ? '#3b82f6' : 'var(--text-secondary)',
                fontWeight: 700,
                fontSize: '14px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: '0.2s'
              }}
            >
              <ShieldCheck size={16} /> Verified Database Records ({verifiedCertificates.length})
            </button>
          </div>

          {activeTabSection === 'verified' ? (
            <GlassCard padding="20px">
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '14px', flexWrap: 'wrap', gap: '10px' }}>
                <div>
                  <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: '0 0 4px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <ShieldCheck size={18} style={{ color: 'rgb(22, 192, 122)' }} /> Verified Live Certificates
                  </h3>
                  <p style={{ margin: 0, fontSize: '12px', color: 'var(--text-secondary)' }}>
                    Accurate, live records fetched directly from the Supabase database. These certificates are active in students' m-Lynq apps.
                  </p>
                </div>
                <button
                  onClick={loadStats}
                  style={{
                    display: 'flex', alignItems: 'center', gap: '6px',
                    padding: '8px 14px', borderRadius: '10px',
                    background: 'rgba(255, 255, 255, 0.05)', border: '1px solid var(--border-light)',
                    color: 'var(--text-primary)', fontSize: '12px', fontWeight: 600, cursor: 'pointer'
                  }}
                >
                  <RefreshCw size={13} /> Re-verify Database
                </button>
              </div>

              <div style={{ marginBottom: '14px' }}>
                <input
                  type="text"
                  placeholder="Search by student name or certificate title..."
                  value={verifiedSearchQuery}
                  onChange={(e) => setVerifiedSearchQuery(e.target.value)}
                  style={{
                    width: '100%', padding: '10px 14px',
                    background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)',
                    borderRadius: '10px', color: 'var(--text-primary)', fontSize: '13px', outline: 'none'
                  }}
                />
              </div>

              {filteredVerifiedCertificates.length === 0 ? (
                <div style={{ padding: '32px', textAlign: 'center', borderRadius: '12px', border: '1px dashed var(--border-light)', background: 'rgba(255,255,255,0.01)' }}>
                  <ShieldCheck size={32} style={{ color: 'var(--text-muted)', margin: '0 auto 10px auto', display: 'block' }} />
                  <div style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)', marginBottom: '4px' }}>
                    {verifiedCertificates.length === 0 ? 'No certificates issued yet' : 'No matching certificates found'}
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {verifiedCertificates.length === 0 
                      ? 'Upload certificates or run automated generation to publish certificates.'
                      : 'Try a different search query.'}
                  </div>
                </div>
              ) : (
                <div style={{ maxHeight: '420px', overflowY: 'auto', borderRadius: '12px', border: '1px solid var(--border-light)' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px' }}>
                    <thead>
                      <tr style={{ background: 'rgba(255, 255, 255, 0.05)', textAlign: 'left', borderBottom: '1px solid var(--border-light)' }}>
                        <th style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>#</th>
                        <th style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>Student Name</th>
                        <th style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>Certificate Title</th>
                        <th style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>Issued Date</th>
                        <th style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>Verification</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filteredVerifiedCertificates.map((cert, idx) => (
                        <tr key={cert.id || cert.user_id} style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
                          <td style={{ padding: '10px 14px', color: 'var(--text-muted)' }}>{idx + 1}</td>
                          <td style={{ padding: '10px 14px', fontWeight: 600, color: 'var(--text-primary)' }}>
                            {cert.student_name || 'Student'}
                          </td>
                          <td style={{ padding: '10px 14px', color: 'var(--text-secondary)' }}>
                            {cert.title || 'Certificate'}
                          </td>
                          <td style={{ padding: '10px 14px', color: 'var(--text-muted)', fontSize: '11px' }}>
                            {cert.issued_at ? new Date(cert.issued_at).toLocaleString() : 'Recently'}
                          </td>
                          <td style={{ padding: '10px 14px' }}>
                            {(cert.file_url || cert.certificate_url) ? (
                              <a
                                href={cert.file_url || cert.certificate_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                style={{
                                  display: 'inline-flex', alignItems: 'center', gap: '4px',
                                  padding: '4px 8px', borderRadius: '6px',
                                  background: 'rgba(59, 130, 246, 0.1)', color: '#3b82f6',
                                  textDecoration: 'none', fontSize: '11px', fontWeight: 600
                                }}
                              >
                                <ExternalLink size={12} /> View PDF
                              </a>
                            ) : (
                              <span style={{ color: 'rgb(22, 192, 122)', fontSize: '11px', fontWeight: 600 }}>
                                <CheckCircle size={12} /> Active in DB
                              </span>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </GlassCard>
          ) : (
            <>
              {/* Mode Selector Segmented Tabs */}
              <div style={{ display: 'flex', background: 'rgba(255, 255, 255, 0.05)', padding: '4px', borderRadius: '14px', border: '1px solid var(--border-light)' }}>
            <button
              onClick={() => setPublishMode('automated')}
              style={{
                flex: 1,
                padding: '12px',
                borderRadius: '10px',
                border: 'none',
                background: publishMode === 'automated' ? 'var(--color-primary, #3b82f6)' : 'transparent',
                color: publishMode === 'automated' ? '#fff' : 'var(--text-secondary)',
                fontWeight: 700,
                fontSize: '14px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: 'all 0.2s',
              }}
            >
              <Sparkles size={16} /> ⚡ Automated (Google Slides)
            </button>
            <button
              onClick={() => setPublishMode('manual')}
              style={{
                flex: 1,
                padding: '12px',
                borderRadius: '10px',
                border: 'none',
                background: publishMode === 'manual' ? 'var(--color-primary, #3b82f6)' : 'transparent',
                color: publishMode === 'manual' ? '#fff' : 'var(--text-secondary)',
                fontWeight: 700,
                fontSize: '14px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
                transition: 'all 0.2s',
              }}
            >
              <FolderArchive size={16} /> 📁 Manual (Google Drive / Files)
            </button>
          </div>

          {/* Mode 1: Automated (Google Slides) */}
          {publishMode === 'automated' && (
            <>
            <GlassCard padding="20px">
              <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: '0 0 12px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <ImageIcon size={18} style={{ color: '#3b82f6' }} /> Google Slides Certificate Template
              </h3>
              
              <div style={{ marginBottom: '16px' }}>
                <label className="form-input-label" style={{ display: 'block', fontSize: '13px', marginBottom: '6px', color: 'var(--text-secondary)' }}>
                  Presentation Template URL
                </label>
                <input
                  type="text"
                  value={slidesUrl}
                  onChange={(e) => setSlidesUrl(e.target.value)}
                  placeholder="https://docs.google.com/presentation/d/..."
                  style={{ width: '100%', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '12px', color: 'var(--text-primary)', padding: '12px', outline: 'none', fontSize: '13px' }}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '16px' }}>
                <div>
                  <label className="form-input-label" style={{ display: 'block', fontSize: '12px', marginBottom: '4px', color: 'var(--text-muted)' }}>
                    Chairperson Name {`({{chair_name}})`}
                  </label>
                  <input
                    type="text"
                    value={chairName}
                    onChange={(e) => setChairName(e.target.value)}
                    placeholder="e.g. Chair Name"
                    style={{ width: '100%', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '10px', color: 'var(--text-primary)', padding: '10px', outline: 'none', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label className="form-input-label" style={{ display: 'block', fontSize: '12px', marginBottom: '4px', color: 'var(--text-muted)' }}>
                    Coordinator Name {`({{coord_name}})`}
                  </label>
                  <input
                    type="text"
                    value={coordName}
                    onChange={(e) => setCoordName(e.target.value)}
                    placeholder="e.g. Coordinator Name"
                    style={{ width: '100%', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '10px', color: 'var(--text-primary)', padding: '10px', outline: 'none', fontSize: '13px' }}
                  />
                </div>
              </div>

              <button
                onClick={handleSaveTemplateAndExecom}
                className="role-filter-chip active"
                style={{ cursor: 'pointer', background: 'rgb(22, 192, 122)', border: 'none', color: 'white', padding: '10px 18px', fontWeight: 600 }}
              >
                Save Template & Execom Details
              </button>
            </GlassCard>

            <GlassCard padding="20px">
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <FileText size={18} style={{ color: 'rgb(22, 192, 122)' }} /> Attendance Source & Participant Matching
                </h3>
                {isParsingAttendanceFile && <Loader size={16} className="animate-spin" style={{ color: 'rgb(22, 192, 122)' }} />}
              </div>
              <p style={{ margin: '0 0 16px 0', fontSize: '12px', color: 'var(--text-secondary)' }}>
                Choose participants from event registrations or upload an external attendance sheet (CSV) to auto-match with m-Lynq student profiles.
              </p>

              {/* Toggle Source */}
              <div style={{ display: 'flex', background: 'rgba(255, 255, 255, 0.04)', padding: '4px', borderRadius: '10px', border: '1px solid var(--border-light)', marginBottom: '16px' }}>
                <button
                  onClick={() => setAutomatedAttendanceSource('app')}
                  style={{
                    flex: 1,
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: 'none',
                    background: automatedAttendanceSource === 'app' ? 'rgba(22, 192, 122, 0.2)' : 'transparent',
                    color: automatedAttendanceSource === 'app' ? 'white' : 'var(--text-secondary)',
                    fontWeight: automatedAttendanceSource === 'app' ? 700 : 500,
                    fontSize: '13px',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px'
                  }}
                >
                  App / QR ({attendees.length})
                </button>
                <button
                  onClick={() => setAutomatedAttendanceSource('manual_sheet')}
                  style={{
                    flex: 1,
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: 'none',
                    background: automatedAttendanceSource === 'manual_sheet' ? 'rgba(22, 192, 122, 0.2)' : 'transparent',
                    color: automatedAttendanceSource === 'manual_sheet' ? 'white' : 'var(--text-secondary)',
                    fontWeight: automatedAttendanceSource === 'manual_sheet' ? 700 : 500,
                    fontSize: '13px',
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '6px'
                  }}
                >
                  <Upload size={14} /> {totalInManualList > 0 ? `Manual List (${totalInManualList})` : 'Upload Manual List'}
                </button>
              </div>

              {automatedAttendanceSource === 'app' ? (
                <div style={{ padding: '12px 14px', borderRadius: '10px', background: 'rgba(255, 255, 255, 0.02)', border: '1px solid var(--border-light)', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  Targeting {attendeeCount} participant(s) registered or scanned via QR. {pendingCount} pending issuance.
                </div>
              ) : (
                <div>
                  {/* File Upload Box */}
                  <label
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      alignItems: 'center',
                      justifyContent: 'center',
                      padding: '24px',
                      borderRadius: '12px',
                      border: '1.5px dashed rgba(22, 192, 122, 0.4)',
                      background: 'rgba(22, 192, 122, 0.02)',
                      cursor: 'pointer',
                      marginBottom: '16px'
                    }}
                  >
                    <input
                      type="file"
                      accept=".csv,.txt"
                      onChange={handleAttendanceFileUpload}
                      style={{ display: 'none' }}
                    />
                    <Upload size={28} style={{ color: 'rgb(22, 192, 122)', marginBottom: '8px' }} />
                    <span style={{ fontSize: '13px', fontWeight: 600, color: 'white' }}>
                      {uploadedAttendanceFileName ? `Selected: ${uploadedAttendanceFileName}` : 'Select Attendance Sheet (.csv, .txt)'}
                    </span>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                      Auto-detects Name, Email, and ID columns & matches against all registered m-Lynq users
                    </span>
                  </label>

                  {/* Match Stats Overview Card */}
                  {totalInManualList > 0 && (
                    <>
                      <div style={{ padding: '14px', borderRadius: '12px', background: 'rgba(22, 192, 122, 0.08)', border: '1px solid rgba(22, 192, 122, 0.3)', marginBottom: '16px' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                          <span style={{ fontSize: '13px', fontWeight: 700, color: 'white' }}>Attendance Matches Overview</span>
                          <span style={{ fontSize: '11px', fontWeight: 700, padding: '2px 8px', borderRadius: '6px', background: 'rgba(22, 192, 122, 0.2)', color: 'rgb(22, 192, 122)' }}>
                            {manualMatchPercentage}% Matched
                          </span>
                        </div>
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '8px', textAlign: 'center' }}>
                          <div style={{ padding: '8px', background: 'rgba(255, 255, 255, 0.04)', borderRadius: '8px' }}>
                            <div style={{ fontSize: '16px', fontWeight: 800, color: 'white' }}>{totalInManualList}</div>
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>Total In Sheet</div>
                          </div>
                          <div style={{ padding: '8px', background: 'rgba(255, 255, 255, 0.04)', borderRadius: '8px' }}>
                            <div style={{ fontSize: '16px', fontWeight: 800, color: 'rgb(22, 192, 122)' }}>{matchedInManualList}</div>
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>Matched</div>
                          </div>
                          <div style={{ padding: '8px', background: 'rgba(255, 255, 255, 0.04)', borderRadius: '8px' }}>
                            <div style={{ fontSize: '16px', fontWeight: 800, color: unmatchedInManualList > 0 ? '#ef4444' : 'var(--text-muted)' }}>{unmatchedInManualList}</div>
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>Unmatched</div>
                          </div>
                          <div style={{ padding: '8px', background: 'rgba(255, 255, 255, 0.04)', borderRadius: '8px' }}>
                            <div style={{ fontSize: '16px', fontWeight: 800, color: '#3b82f6' }}>{pendingToPublishInManualList}</div>
                            <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>Pending Issue</div>
                          </div>
                        </div>
                      </div>

                      {/* Filter chips */}
                      <div style={{ display: 'flex', gap: '6px', marginBottom: '12px', flexWrap: 'wrap' }}>
                        {(['all', 'matched', 'unmatched', 'pending'] as const).map(f => (
                          <button
                            key={f}
                            onClick={() => setAttendanceListFilter(f)}
                            style={{
                              padding: '5px 10px',
                              borderRadius: '6px',
                              border: 'none',
                              fontSize: '11px',
                              fontWeight: attendanceListFilter === f ? 700 : 500,
                              background: attendanceListFilter === f ? 'rgb(22, 192, 122)' : 'rgba(255,255,255,0.05)',
                              color: attendanceListFilter === f ? '#000' : 'var(--text-secondary)',
                              cursor: 'pointer'
                            }}
                          >
                            {f.toUpperCase()} ({
                              f === 'all' ? totalInManualList :
                              f === 'matched' ? matchedInManualList :
                              f === 'unmatched' ? unmatchedInManualList : pendingToPublishInManualList
                            })
                          </button>
                        ))}
                      </div>

                      {/* Review List */}
                      <div style={{ maxHeight: '280px', overflowY: 'auto', border: '1px solid var(--border-light)', borderRadius: '10px', background: 'rgba(0,0,0,0.2)' }}>
                        {filteredManualRecords.length === 0 ? (
                          <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '12px' }}>
                            No attendees in this filter.
                          </div>
                        ) : (
                          filteredManualRecords.map(r => {
                            const isIssued = r.matchedUser && alreadyIssuedIds.has(r.matchedUser.user_id);
                            return (
                              <div
                                key={r.key}
                                style={{
                                  padding: '10px 14px',
                                  borderBottom: '1px solid rgba(255,255,255,0.05)',
                                  display: 'flex',
                                  alignItems: 'center',
                                  justifyContent: 'space-between',
                                  gap: '12px'
                                }}
                              >
                                <div style={{ flex: 1, minWidth: 0 }}>
                                  <div style={{ fontSize: '13px', fontWeight: 600, color: 'white' }}>{r.rawName || 'Unknown Name'}</div>
                                  <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                                    {r.rawEmail && <span>{r.rawEmail} </span>}
                                    {r.rawMembershipId && <span>• ID: {r.rawMembershipId}</span>}
                                  </div>
                                  {r.matchedUser ? (
                                    <div style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '2px' }}>
                                      👤 Matched: {r.matchedUser.name} ({r.matchedUser.email})
                                    </div>
                                  ) : (
                                    <div style={{ fontSize: '11px', color: '#f59e0b', marginTop: '2px' }}>
                                      ⚠️ Not found in m-Lynq. Tap edit to assign manually.
                                    </div>
                                  )}
                                </div>
                                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                  {isIssued ? (
                                    <span style={{ fontSize: '11px', color: 'rgb(22, 192, 122)', fontWeight: 700 }}>Issued</span>
                                  ) : r.matchedUser ? (
                                    <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(59, 130, 246, 0.2)', color: '#60a5fa', fontWeight: 700 }}>
                                      {r.matchType.replace('_', ' ').toUpperCase()}
                                    </span>
                                  ) : (
                                    <span style={{ fontSize: '10px', padding: '2px 6px', borderRadius: '4px', background: 'rgba(239, 68, 68, 0.2)', color: '#f87171', fontWeight: 700 }}>
                                      UNMATCHED
                                    </span>
                                  )}
                                  <button
                                    onClick={() => {
                                      setSelectedRecordForAssign(r);
                                      setUserSearchQuery('');
                                    }}
                                    style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', padding: '4px' }}
                                    title="Assign / Reassign User"
                                  >
                                    <ExternalLink size={16} />
                                  </button>
                                </div>
                              </div>
                            );
                          })
                        )}
                      </div>
                    </>
                  )}
                </div>
              )}
            </GlassCard>
          </>
        )}

          {/* Mode 2: Manual (Google Drive Link / Files) */}
          {publishMode === 'manual' && (
            <GlassCard padding="20px">
              <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: '0 0 12px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <FolderArchive size={18} style={{ color: '#f59e0b' }} /> Google Drive & Direct File Distribution
              </h3>

              {/* Option: Publish without Attendance List Toggle Card */}
              <div style={{ padding: '14px 16px', borderRadius: '12px', background: publishWithoutAttendance ? 'rgba(22, 192, 122, 0.12)' : 'rgba(255, 255, 255, 0.03)', border: `1px solid ${publishWithoutAttendance ? 'rgba(22, 192, 122, 0.4)' : 'var(--border-light)'}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '18px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <Sparkles size={20} style={{ color: publishWithoutAttendance ? 'rgb(22, 192, 122)' : 'var(--text-secondary)' }} />
                  <div>
                    <div style={{ fontSize: '14px', fontWeight: 700, color: 'var(--text-primary)' }}>Publish without Attendance List</div>
                    <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
                      {publishWithoutAttendance
                        ? `Active: Matching files against all ${allMlynqUsers.length} registered m-Lynq students`
                        : `Inactive: Matching only against ${attendees.length} event attendees`}
                    </div>
                  </div>
                </div>
                <label style={{ position: 'relative', display: 'inline-block', width: '44px', height: '24px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={publishWithoutAttendance}
                    onChange={(e) => setPublishWithoutAttendance(e.target.checked)}
                    style={{ opacity: 0, width: 0, height: 0 }}
                  />
                  <span style={{
                    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
                    background: publishWithoutAttendance ? 'rgb(22, 192, 122)' : 'rgba(150,150,150,0.3)',
                    borderRadius: '24px', transition: '0.2s',
                  }}>
                    <span style={{
                      position: 'absolute', content: '""', height: '18px', width: '18px',
                      left: publishWithoutAttendance ? '22px' : '3px', bottom: '3px',
                      background: 'white', borderRadius: '50%', transition: '0.2s',
                    }} />
                  </span>
                </label>
              </div>

              {/* Google Drive Link input */}
              <div style={{ marginBottom: '18px' }}>
                <label className="form-input-label" style={{ display: 'block', fontSize: '13px', marginBottom: '6px', color: 'var(--text-secondary)' }}>
                  Google Drive Folder Link
                </label>
                <div style={{ display: 'flex', gap: '10px' }}>
                  <input
                    type="text"
                    value={driveFolderUrl}
                    onChange={(e) => setDriveFolderUrl(e.target.value)}
                    placeholder="https://drive.google.com/drive/folders/..."
                    style={{ flex: 1, background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', borderRadius: '12px', color: 'var(--text-primary)', padding: '12px', outline: 'none', fontSize: '13px' }}
                  />
                  {driveFolderUrl.trim() && (
                    <a
                      href={driveFolderUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="role-filter-chip"
                      style={{ display: 'flex', alignItems: 'center', gap: '6px', padding: '10px 14px', borderRadius: '10px', border: '1px solid var(--border-light)', textDecoration: 'none', color: 'var(--text-primary)', fontSize: '13px' }}
                    >
                      <ExternalLink size={14} /> Open
                    </a>
                  )}
                </div>
                <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px', display: 'block' }}>
                  Provide folder link for records, and upload certificate PDFs or a .ZIP archive below for 100% offline & CORS resilience.
                </span>
              </div>

              {/* File / ZIP Upload Zone */}
              <div style={{ marginBottom: '20px' }}>
                <label className="form-input-label" style={{ display: 'block', fontSize: '13px', marginBottom: '8px', color: 'var(--text-secondary)' }}>
                  Upload Certificate Files or ZIP Archive
                </label>
                <label
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '10px',
                    padding: '24px',
                    borderRadius: '14px',
                    border: '2px dashed rgba(255, 255, 255, 0.2)',
                    background: 'rgba(255, 255, 255, 0.02)',
                    cursor: 'pointer',
                  }}
                >
                  <input
                    type="file"
                    multiple
                    accept=".pdf,.png,.jpg,.jpeg,.zip"
                    onChange={handleFileUpload}
                    style={{ display: 'none' }}
                  />
                  {isExtractingZip ? (
                    <>
                      <Loader size={24} className="spinner" style={{ color: '#3b82f6' }} />
                      <span style={{ fontSize: '13px', color: 'var(--text-primary)' }}>Extracting and analyzing certificate files...</span>
                    </>
                  ) : (
                    <>
                      <Upload size={24} style={{ color: '#f59e0b' }} />
                      <span style={{ fontSize: '14px', fontWeight: 600, color: 'var(--text-primary)' }}>Click to select files or drag & drop</span>
                      <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                        {publishWithoutAttendance
                          ? 'Loads certificate files and matches student names with all m-Lynq user accounts'
                          : 'Supports multiple PDFs, images, or a single .ZIP folder'}
                      </span>
                    </>
                  )}
                </label>
              </div>

              {/* Match Summary */}
              {uploadedFiles.length > 0 && (
                <div style={{ padding: '14px', borderRadius: '12px', background: 'rgba(255, 255, 255, 0.04)', border: '1px solid var(--border-light)', marginBottom: '16px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                    <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-primary)' }}>
                      📁 {uploadedFiles.length} Certificate Files Loaded
                    </span>
                    <span style={{ fontSize: '12px', color: 'rgb(22, 192, 122)', fontWeight: 600 }}>
                      {publishWithoutAttendance
                        ? `Matched with m-Lynq: ${fileMatchedCount} / ${uploadedFiles.length}`
                        : `Matched with Attendees: ${matchedCount} / ${attendeeCount}`}
                    </span>
                  </div>
                  <div style={{ width: '100%', height: '6px', borderRadius: '3px', background: 'rgba(255,255,255,0.1)', overflow: 'hidden' }}>
                    <div style={{ height: '100%', background: 'rgb(22, 192, 122)', width: `${(publishWithoutAttendance ? (fileMatchedCount / (uploadedFiles.length || 1)) : (matchedCount / (attendeeCount || 1))) * 100}%` }}></div>
                  </div>
                </div>
              )}

              {/* Mapping Table */}
              {uploadedFiles.length > 0 && (
                <div style={{ marginTop: '16px' }}>
                  <h4 style={{ fontSize: '14px', fontWeight: 700, color: 'var(--text-primary)', marginBottom: '10px' }}>
                    {publishWithoutAttendance ? 'm-Lynq User Matching Preview' : 'Attendee Name Mapping Preview'}
                  </h4>
                  <div style={{ maxHeight: '320px', overflowY: 'auto', borderRadius: '12px', border: '1px solid var(--border-light)' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px' }}>
                      <thead>
                        <tr style={{ background: 'rgba(255, 255, 255, 0.05)', textAlign: 'left', borderBottom: '1px solid var(--border-light)' }}>
                          <th style={{ padding: '10px 12px', color: 'var(--text-secondary)' }}>Certificate File</th>
                          <th style={{ padding: '10px 12px', color: 'var(--text-secondary)' }}>Matched m-Lynq User</th>
                          <th style={{ padding: '10px 12px', color: 'var(--text-secondary)' }}>Status</th>
                          <th style={{ padding: '10px 12px', color: 'var(--text-secondary)' }}>Assign User</th>
                        </tr>
                      </thead>
                      <tbody>
                        {publishWithoutAttendance ? (
                          fileMatches.map(m => {
                            const isIssued = m.matchedUser ? alreadyIssuedIds.has(m.matchedUser.user_id) : false;
                            return (
                              <tr key={m.file.name} style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
                                <td style={{ padding: '8px 12px', fontWeight: 600, color: 'var(--text-primary)' }}>
                                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', maxWidth: '220px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                    <FileText size={12} style={{ color: '#3b82f6' }} /> {m.file.name}
                                  </span>
                                </td>
                                <td style={{ padding: '8px 12px', color: m.matchedUser ? 'var(--text-primary)' : 'var(--text-muted)' }}>
                                  {m.matchedUser ? (
                                    <span>{m.matchedUser.name} <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>({m.matchedUser.email})</span></span>
                                  ) : (
                                    <span style={{ color: '#ef4444' }}>No m-Lynq user matched</span>
                                  )}
                                </td>
                                <td style={{ padding: '8px 12px' }}>
                                  {isIssued ? (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: 'rgb(22, 192, 122)', fontSize: '11px', fontWeight: 600 }}>
                                      <CheckCircle2 size={12} /> Issued
                                    </span>
                                  ) : m.matchedUser ? (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#3b82f6', fontSize: '11px', fontWeight: 600 }}>
                                      <CheckCircle2 size={12} /> Matched ({m.matchType})
                                    </span>
                                  ) : (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#f59e0b', fontSize: '11px', fontWeight: 600 }}>
                                      <XCircle size={12} /> Unmatched
                                    </span>
                                  )}
                                </td>
                                <td style={{ padding: '8px 12px' }}>
                                  <select
                                    value={m.matchedUser?.user_id || ''}
                                    onChange={(e) => {
                                      const val = e.target.value;
                                      setFileManualOverrides(prev => ({
                                        ...prev,
                                        [m.file.name]: val,
                                      }));
                                    }}
                                    style={{ background: 'var(--bg-card)', border: '1px solid var(--border-light)', borderRadius: '6px', color: 'var(--text-primary)', padding: '4px 8px', fontSize: '11px', maxWidth: '180px' }}
                                  >
                                    <option value="">Select m-Lynq User...</option>
                                    {allMlynqUsers.map(u => (
                                      <option key={u.user_id} value={u.user_id}>
                                        {u.name} ({u.email || u.membership_id || 'Student'})
                                      </option>
                                    ))}
                                  </select>
                                </td>
                              </tr>
                            );
                          })
                        ) : (
                          matches.map(m => {
                            const isIssued = alreadyIssuedIds.has(m.attendee.user_id);
                            return (
                              <tr key={m.attendee.user_id} style={{ borderBottom: '1px solid rgba(255,255,255,0.04)' }}>
                                <td style={{ padding: '8px 12px', fontWeight: 600, color: 'var(--text-primary)' }}>
                                  {m.attendee.name}
                                </td>
                                <td style={{ padding: '8px 12px', color: m.matchedFile ? 'var(--text-primary)' : 'var(--text-muted)' }}>
                                  {m.matchedFile ? (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', maxWidth: '200px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                      <FileText size={12} style={{ color: '#3b82f6' }} /> {m.matchedFile.name}
                                    </span>
                                  ) : (
                                    <span style={{ color: '#ef4444' }}>No file matched</span>
                                  )}
                                </td>
                                <td style={{ padding: '8px 12px' }}>
                                  {isIssued ? (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: 'rgb(22, 192, 122)', fontSize: '11px', fontWeight: 600 }}>
                                      <CheckCircle2 size={12} /> Issued
                                    </span>
                                  ) : m.matchedFile ? (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#3b82f6', fontSize: '11px', fontWeight: 600 }}>
                                      <CheckCircle2 size={12} /> Matched ({m.matchType})
                                    </span>
                                  ) : (
                                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#f59e0b', fontSize: '11px', fontWeight: 600 }}>
                                      <XCircle size={12} /> Unmatched
                                    </span>
                                  )}
                                </td>
                                <td style={{ padding: '8px 12px' }}>
                                  <select
                                    value={m.matchedFile?.name || ''}
                                    onChange={(e) => {
                                      const val = e.target.value;
                                      setManualOverrides(prev => ({
                                        ...prev,
                                        [m.attendee.user_id]: val,
                                      }));
                                    }}
                                    style={{ background: 'rgba(255,255,255,0.06)', border: '1px solid var(--border-light)', borderRadius: '6px', color: 'white', padding: '4px 8px', fontSize: '11px', maxWidth: '160px' }}
                                  >
                                    <option value="">Select File...</option>
                                    {uploadedFiles.map(f => (
                                      <option key={f.name} value={f.name} style={{ background: '#1e1e1e', color: 'white' }}>
                                        {f.name}
                                      </option>
                                    ))}
                                  </select>
                                </td>
                              </tr>
                            );
                          })
                        )}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </GlassCard>
          )}

          {/* Progress Bar & Messaging */}
          {isProcessing && (
            <div style={{ padding: '16px', borderRadius: '12px', background: 'rgba(255,255,255,0.03)', border: '1px solid var(--border-light)', display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Loader size={16} className="spinner" />
                <span style={{ fontSize: '14px', color: 'white', fontWeight: 600 }}>{progressMessage}</span>
              </div>
              {isProcessing && (
                <div style={{ width: '100%', height: '6px', borderRadius: '3px', background: 'rgba(255,255,255,0.1)', overflow: 'hidden' }}>
                  <div style={{ height: '100%', background: 'rgb(22, 192, 122)', width: `${(processedCount / ((publishMode === 'automated' ? (automatedAttendanceSource === 'manual_sheet' ? pendingToPublishInManualList : pendingCount) : (publishWithoutAttendance ? fileMatches.length : pendingCount)) || 1)) * 100}%` }}></div>
                </div>
              )}
            </div>
          )}

          {lastSuccessCount !== null && (
            <div style={{ padding: '16px', borderRadius: '12px', background: 'rgba(22, 192, 122, 0.05)', border: '1px solid rgba(22, 192, 122, 0.3)', display: 'flex', alignItems: 'center', gap: '10px' }}>
              <Sparkles size={18} style={{ color: 'rgb(22, 192, 122)' }} />
              <span style={{ fontSize: '14px', color: 'white' }}>Published {lastSuccessCount} certificate(s) successfully!</span>
            </div>
          )}

          {/* Publish Action Button */}
          <div style={{ marginTop: '12px' }}>
            {publishMode === 'automated' ? (
              automatedAttendanceSource === 'manual_sheet' ? (
                <button
                  onClick={handlePublishManualAttendanceCertificates}
                  disabled={pendingToPublishInManualList === 0 || isProcessing}
                  style={{
                    width: '100%',
                    padding: '16px',
                    borderRadius: '14px',
                    background: (pendingToPublishInManualList > 0 && !isProcessing) ? 'rgb(22, 192, 122)' : 'rgba(255,255,255,0.05)',
                    color: (pendingToPublishInManualList > 0 && !isProcessing) ? '#000' : 'var(--text-muted)',
                    fontFamily: 'var(--font-space-grotesk)',
                    fontWeight: 700,
                    fontSize: '15px',
                    border: 'none',
                    cursor: (pendingToPublishInManualList > 0 && !isProcessing) ? 'pointer' : 'not-allowed',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '8px'
                  }}
                >
                  <Play size={18} /> Publish {pendingToPublishInManualList} Matched Certificates (Automated)
                </button>
              ) : (
                <button
                  onClick={handlePublishAutomatedCertificates}
                  disabled={pendingCount === 0 || isProcessing}
                  style={{
                    width: '100%',
                    padding: '16px',
                    borderRadius: '14px',
                    background: (pendingCount > 0 && !isProcessing) ? '#f59e0b' : 'rgba(255,255,255,0.05)',
                    color: (pendingCount > 0 && !isProcessing) ? '#000' : 'var(--text-muted)',
                    fontFamily: 'var(--font-space-grotesk)',
                    fontWeight: 700,
                    fontSize: '15px',
                    border: 'none',
                    cursor: (pendingCount > 0 && !isProcessing) ? 'pointer' : 'not-allowed',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: '8px'
                  }}
                >
                  <Play size={18} /> Publish {pendingCount} Pending Certificates (Slides Engine)
                </button>
              )
            ) : publishWithoutAttendance ? (
              <button
                onClick={promptPublishWithoutAttendance}
                disabled={pendingFileMatchedCount === 0 || isProcessing}
                style={{
                  width: '100%',
                  padding: '16px',
                  borderRadius: '14px',
                  background: (pendingFileMatchedCount > 0 && !isProcessing) ? 'rgb(22, 192, 122)' : 'rgba(255,255,255,0.05)',
                  color: (pendingFileMatchedCount > 0 && !isProcessing) ? '#000' : 'var(--text-muted)',
                  fontFamily: 'var(--font-space-grotesk)',
                  fontWeight: 700,
                  fontSize: '15px',
                  border: 'none',
                  cursor: (pendingFileMatchedCount > 0 && !isProcessing) ? 'pointer' : 'not-allowed',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px'
                }}
              >
                <Play size={18} /> Publish {pendingFileMatchedCount} Matched Certificates to m-Lynq Users
              </button>
            ) : (
              <button
                onClick={promptPublishManualCertificates}
                disabled={pendingMatchedCount === 0 || isProcessing}
                style={{
                  width: '100%',
                  padding: '16px',
                  borderRadius: '14px',
                  background: (pendingMatchedCount > 0 && !isProcessing) ? 'rgb(22, 192, 122)' : 'rgba(255,255,255,0.05)',
                  color: (pendingMatchedCount > 0 && !isProcessing) ? '#000' : 'var(--text-muted)',
                  fontFamily: 'var(--font-space-grotesk)',
                  fontWeight: 700,
                  fontSize: '15px',
                  border: 'none',
                  cursor: (pendingMatchedCount > 0 && !isProcessing) ? 'pointer' : 'not-allowed',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px'
                }}
              >
                <Play size={18} /> Publish {pendingMatchedCount} Matched Certificates (Manual Distribution)
              </button>
            )}
          </div>
            </>
          )}
        </div>
      )}

      {/* Confirmation Modal */}
      {confirmModal && confirmModal.isOpen && (
        <div style={{
          position: 'fixed', inset: 0, zIndex: 9999,
          background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px'
        }}>
          <div style={{
            background: 'var(--bg-card)', border: '1px solid var(--border-light)',
            borderRadius: '16px', maxWidth: '520px', width: '100%', padding: '24px',
            boxShadow: '0 20px 40px rgba(0,0,0,0.5)', display: 'flex', flexDirection: 'column', gap: '16px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 700, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Sparkles size={20} style={{ color: 'rgb(22, 192, 122)' }} /> {confirmModal.title}
              </h3>
              <button onClick={() => setConfirmModal(null)} style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer' }}>
                <X size={20} />
              </button>
            </div>

            <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
              {confirmModal.description}
            </p>

            {/* Editable Certificate Name with Quick Chips */}
            <div style={{
              padding: '12px 14px', borderRadius: '12px',
              background: 'rgba(255, 255, 255, 0.03)',
              border: '1px solid var(--border-light)',
              display: 'flex', flexDirection: 'column', gap: '8px'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <label style={{ fontSize: '12px', fontWeight: 700, color: '#f59e0b', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <Award size={15} /> Certificate Name / Type
                </label>
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Shown in m-Lynq</span>
              </div>
              <input
                type="text"
                value={certificateName}
                onChange={(e) => setCertificateName(e.target.value)}
                placeholder="e.g. Certificate of Participation, Winner, 1st Prize..."
                style={{
                  width: '100%',
                  background: 'rgba(255, 255, 255, 0.06)',
                  border: '1px solid var(--border-light)',
                  borderRadius: '8px',
                  color: 'var(--text-primary)',
                  padding: '9px 12px',
                  fontSize: '13px',
                  fontWeight: 600,
                  outline: 'none'
                }}
              />
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginTop: '2px' }}>
                {[
                  'Certificate of Participation',
                  'Certificate of Appreciation',
                  'Certificate of Excellence',
                  'Winner',
                  '1st Prize',
                  'Runner Up',
                  'Volunteer Certificate'
                ].map((preset) => {
                  const isSelected = certificateName.trim() === preset;
                  return (
                    <button
                      key={preset}
                      type="button"
                      onClick={() => setCertificateName(preset)}
                      style={{
                        padding: '4px 8px',
                        borderRadius: '6px',
                        border: isSelected ? '1px solid rgb(22, 192, 122)' : '1px solid var(--border-light)',
                        background: isSelected ? 'rgba(22, 192, 122, 0.2)' : 'rgba(255,255,255,0.03)',
                        color: isSelected ? 'rgb(22, 192, 122)' : 'var(--text-secondary)',
                        fontSize: '11px',
                        fontWeight: 600,
                        cursor: 'pointer',
                        transition: 'all 0.15s ease'
                      }}
                    >
                      {preset}
                    </button>
                  );
                })}
              </div>
            </div>

            <div style={{ maxHeight: '180px', overflowY: 'auto', borderRadius: '10px', border: '1px solid var(--border-light)', padding: '8px 12px', background: 'rgba(255,255,255,0.02)' }}>
              <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: '6px' }}>
                Target Recipients ({confirmModal.recipients.length}):
              </div>
              {confirmModal.recipients.map((r, idx) => (
                <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0', borderBottom: idx < confirmModal.recipients.length - 1 ? '1px solid var(--border-light)' : 'none', fontSize: '12px' }}>
                  <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{r.student}</span>
                  <span style={{ color: 'var(--text-muted)' }}>{r.file}</span>
                </div>
              ))}
            </div>

            <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
              <button
                onClick={() => setConfirmModal(null)}
                style={{ flex: 1, padding: '12px', borderRadius: '10px', border: '1px solid var(--border-light)', background: 'transparent', color: 'var(--text-primary)', fontWeight: 600, cursor: 'pointer' }}
              >
                Cancel
              </button>
              <button
                onClick={confirmModal.onConfirm}
                style={{ flex: 1, padding: '12px', borderRadius: '10px', border: 'none', background: 'rgb(22, 192, 122)', color: '#000', fontWeight: 700, cursor: 'pointer' }}
              >
                Confirm & Publish
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Results & Verification Modal */}
      {publishResultModal && publishResultModal.isOpen && (
        <div style={{
          position: 'fixed', inset: 0, zIndex: 9999,
          background: 'rgba(0,0,0,0.8)', backdropFilter: 'blur(6px)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '16px'
        }}>
          <div style={{
            background: 'var(--bg-card)', border: '1px solid var(--border-light)',
            borderRadius: '18px', maxWidth: '560px', width: '100%', padding: '24px',
            boxShadow: '0 25px 50px rgba(0,0,0,0.6)', display: 'flex', flexDirection: 'column', gap: '16px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 700, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: '8px' }}>
                {publishResultModal.failedItems.length === 0 ? (
                  <CheckCircle size={22} style={{ color: 'rgb(22, 192, 122)' }} />
                ) : publishResultModal.successItems.length > 0 ? (
                  <AlertTriangle size={22} style={{ color: '#f59e0b' }} />
                ) : (
                  <XCircle size={22} style={{ color: '#ef4444' }} />
                )}
                Certificate Issuance Report
              </h3>
              <button onClick={() => setPublishResultModal(null)} style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer' }}>
                <X size={20} />
              </button>
            </div>

            {/* Summary Banner */}
            <div style={{
              padding: '14px', borderRadius: '12px',
              background: publishResultModal.failedItems.length === 0 ? 'rgba(22, 192, 122, 0.12)' : publishResultModal.successItems.length > 0 ? 'rgba(245, 158, 11, 0.12)' : 'rgba(239, 68, 68, 0.12)',
              border: `1px solid ${publishResultModal.failedItems.length === 0 ? 'rgba(22, 192, 122, 0.4)' : publishResultModal.successItems.length > 0 ? 'rgba(245, 158, 11, 0.4)' : 'rgba(239, 68, 68, 0.4)'}`
            }}>
              <div style={{ fontSize: '14px', fontWeight: 700, color: 'var(--text-primary)', marginBottom: '4px' }}>
                {publishResultModal.failedItems.length === 0 
                  ? `✅ Confirmed: All ${publishResultModal.successItems.length} Certificates Published Successfully!`
                  : `${publishResultModal.successItems.length} Succeeded, ${publishResultModal.failedItems.length} Failed`}
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                Certificates are uploaded to Supabase Storage and registered directly in the student database.
              </div>
            </div>

            {/* Success List */}
            {publishResultModal.successItems.length > 0 && (
              <div>
                <div style={{ fontSize: '12px', fontWeight: 700, color: 'rgb(22, 192, 122)', marginBottom: '6px' }}>
                  Verified Active in Database ({publishResultModal.successItems.length}):
                </div>
                <div style={{ maxHeight: '160px', overflowY: 'auto', borderRadius: '10px', border: '1px solid var(--border-light)', padding: '6px 12px', background: 'rgba(255,255,255,0.02)' }}>
                  {publishResultModal.successItems.map((item, idx) => (
                    <div key={idx} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px 0', borderBottom: idx < publishResultModal.successItems.length - 1 ? '1px solid var(--border-light)' : 'none', fontSize: '12px' }}>
                      <div>
                        <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{item.student}</span>
                        <span style={{ color: 'var(--text-muted)', fontSize: '11px', marginLeft: '6px' }}>({item.file})</span>
                      </div>
                      {item.url && (
                        <a href={item.url} target="_blank" rel="noopener noreferrer" style={{ display: 'flex', alignItems: 'center', gap: '4px', color: '#3b82f6', textDecoration: 'none', fontSize: '11px', fontWeight: 600 }}>
                          <ExternalLink size={12} /> View PDF
                        </a>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Failed List */}
            {publishResultModal.failedItems.length > 0 && (
              <div>
                <div style={{ fontSize: '12px', fontWeight: 700, color: '#ef4444', marginBottom: '6px' }}>
                  Failed Uploads ({publishResultModal.failedItems.length}):
                </div>
                <div style={{ maxHeight: '140px', overflowY: 'auto', borderRadius: '10px', border: '1px solid rgba(239, 68, 68, 0.3)', padding: '6px 12px', background: 'rgba(239, 68, 68, 0.05)' }}>
                  {publishResultModal.failedItems.map((item, idx) => (
                    <div key={idx} style={{ padding: '6px 0', borderBottom: idx < publishResultModal.failedItems.length - 1 ? '1px solid rgba(239, 68, 68, 0.2)' : 'none', fontSize: '12px' }}>
                      <div style={{ fontWeight: 600, color: '#ef4444' }}>{item.student} ({item.file})</div>
                      <div style={{ color: 'var(--text-muted)', fontSize: '11px', marginTop: '2px' }}>{item.error}</div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div style={{ display: 'flex', gap: '12px', marginTop: '8px' }}>
              <button
                onClick={() => {
                  setPublishResultModal(null);
                  setActiveTabSection('verified');
                }}
                style={{ flex: 1, padding: '12px', borderRadius: '10px', border: '1px solid #3b82f6', background: 'rgba(59, 130, 246, 0.1)', color: '#3b82f6', fontWeight: 600, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}
              >
                <ShieldCheck size={16} /> View Verified Database Records
              </button>
              <button
                onClick={() => setPublishResultModal(null)}
                style={{ padding: '12px 24px', borderRadius: '10px', border: 'none', background: 'var(--text-primary)', color: 'var(--bg-card)', fontWeight: 700, cursor: 'pointer' }}
              >
                Done
              </button>
            </div>
          </div>
        </div>
      )}

      {selectedRecordForAssign && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)', zIndex: 1000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px' }}>
          <div style={{ background: '#1e1e1e', borderRadius: '16px', border: '1px solid var(--border-light)', width: '100%', maxWidth: '480px', padding: '20px', maxHeight: '80vh', display: 'flex', flexDirection: 'column' }}>
            <h3 style={{ fontSize: '16px', fontWeight: 700, margin: '0 0 6px 0', color: 'white' }}>Assign m-Lynq User</h3>
            <p style={{ margin: '0 0 12px 0', fontSize: '12px', color: 'var(--text-secondary)' }}>
              Attendee: <strong>{selectedRecordForAssign.rawName}</strong> ({selectedRecordForAssign.rawEmail || selectedRecordForAssign.rawMembershipId || 'No email'})
            </p>
            <input
              type="text"
              placeholder="Search by student name or email..."
              value={userSearchQuery}
              onChange={(e) => setUserSearchQuery(e.target.value)}
              style={{ width: '100%', padding: '10px 12px', background: 'rgba(255,255,255,0.05)', border: '1px solid var(--border-light)', borderRadius: '8px', color: 'white', marginBottom: '12px', fontSize: '13px', outline: 'none' }}
            />
            <div style={{ flex: 1, overflowY: 'auto', border: '1px solid var(--border-light)', borderRadius: '8px', marginBottom: '14px' }}>
              {allMlynqUsers
                .filter(u => u.name.toLowerCase().includes(userSearchQuery.toLowerCase()) || (u.email || '').toLowerCase().includes(userSearchQuery.toLowerCase()))
                .map(u => (
                  <div
                    key={u.user_id}
                    onClick={() => {
                      setManualAttendanceUserOverrides(prev => ({ ...prev, [selectedRecordForAssign.key]: u.user_id }));
                      setSelectedRecordForAssign(null);
                    }}
                    style={{ padding: '10px 12px', borderBottom: '1px solid rgba(255,255,255,0.05)', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}
                  >
                    <div>
                      <div style={{ fontSize: '13px', fontWeight: 600, color: 'white' }}>{u.name}</div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{u.email}</div>
                    </div>
                    {selectedRecordForAssign.matchedUser?.user_id === u.user_id && (
                      <Check size={16} style={{ color: 'rgb(22, 192, 122)' }} />
                    )}
                  </div>
                ))}
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <button
                onClick={() => {
                  setManualAttendanceUserOverrides(prev => {
                    const copy = { ...prev };
                    delete copy[selectedRecordForAssign.key];
                    return copy;
                  });
                  setSelectedRecordForAssign(null);
                }}
                style={{ background: 'none', border: 'none', color: '#ef4444', fontSize: '13px', cursor: 'pointer' }}
              >
                Clear Assignment
              </button>
              <button
                onClick={() => setSelectedRecordForAssign(null)}
                style={{ padding: '8px 16px', borderRadius: '8px', border: 'none', background: 'rgba(255,255,255,0.1)', color: 'white', fontSize: '13px', cursor: 'pointer' }}
              >
                Done
              </button>
            </div>
          </div>
        </div>
      )}

      <NavBar />
      
      <style>{`
        .spinner {
          animation: spin 1s linear infinite;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
