import { useState, useEffect } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { supabase } from '../lib/supabase';
import DashboardLayout from '../components/DashboardLayout';
import { Download, Share2, Award } from 'lucide-react';
import jsPDF from 'jspdf';

function CertCard({ cert }) {
  const title = cert.title || (cert.events?.title ? `Certificate of Participation – ${cert.events.title}` : 'Certificate');
  const description = cert.description || (cert.events?.title ? `Awarded for attending ${cert.events.title}` : '');
  const issuedAt = cert.issued_at ? new Date(cert.issued_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' }) : '';

  const handleDownload = () => {
    if (cert.file_url) {
      window.open(cert.file_url, '_blank');
    } else {
      // Generate a basic PDF if no URL
      const doc = new jsPDF({ orientation: 'landscape', unit: 'pt', format: 'a4' });
      const W = doc.internal.pageSize.getWidth();
      const H = doc.internal.pageSize.getHeight();

      // Background
      doc.setFillColor(20, 20, 20);
      doc.rect(0, 0, W, H, 'F');

      // Gold border
      doc.setDrawColor(245, 200, 66);
      doc.setLineWidth(3);
      doc.rect(24, 24, W - 48, H - 48, 'D');

      // Title
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(245, 200, 66);
      doc.setFontSize(14);
      doc.text('ISTE STUDENT CHAPTER', W / 2, 80, { align: 'center' });

      doc.setFontSize(32);
      doc.setTextColor(255, 255, 255);
      doc.text('Certificate of Participation', W / 2, 140, { align: 'center' });

      doc.setFontSize(13);
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(180, 180, 180);
      doc.text('This is to certify that', W / 2, 185, { align: 'center' });

      doc.setFont('helvetica', 'bold');
      doc.setFontSize(28);
      doc.setTextColor(245, 200, 66);
      // Name from cert
      const recipientName = cert.recipient_name || cert.profiles?.name || 'Member';
      doc.text(recipientName, W / 2, 230, { align: 'center' });

      doc.setFont('helvetica', 'normal');
      doc.setFontSize(13);
      doc.setTextColor(180, 180, 180);
      doc.text(description || title, W / 2, 270, { align: 'center', maxWidth: W - 120 });

      if (issuedAt) {
        doc.setFontSize(11);
        doc.text(`Issued on: ${issuedAt}`, W / 2, H - 60, { align: 'center' });
      }

      doc.save(`${title.replace(/\s+/g, '_')}.pdf`);
    }
  };

  const handleShare = () => {
    if (navigator.share && cert.file_url) {
      navigator.share({ title, text: `My certificate from ISTE: ${cert.file_url}`, url: cert.file_url }).catch(() => {});
    } else if (cert.file_url) {
      navigator.clipboard.writeText(cert.file_url).then(() => alert('Certificate link copied!')).catch(() => {});
    }
  };

  return (
    <div style={{ background: '#1A1A1A', borderRadius: 20, padding: '24px', border: '1.5px solid rgba(245,200,66,0.3)', position: 'relative', overflow: 'hidden' }}>
      {/* Gold shimmer border */}
      <div style={{ position: 'absolute', inset: 0, borderRadius: 20, background: 'linear-gradient(135deg, rgba(245,200,66,0.08) 0%, transparent 60%)', pointerEvents: 'none' }} />

      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        {/* Gold seal */}
        <div style={{ width: 56, height: 56, borderRadius: '50%', background: 'linear-gradient(135deg, #F5C842, #D4A00A)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: '0 4px 16px rgba(245,200,66,0.3)' }}>
          <Award size={28} color="#fff" />
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          <h3 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 16, fontWeight: 700, color: '#fff', marginBottom: 6, lineHeight: 1.3 }}>{title}</h3>
          <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 13, color: 'rgba(255,255,255,0.5)', marginBottom: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{description}</p>
          {issuedAt && <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 11, color: 'rgba(255,255,255,0.3)', fontWeight: 500 }}>Issued: {issuedAt}</p>}
        </div>

        {/* Action buttons */}
        <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
          <button onClick={handleDownload} title="Download" style={{ width: 38, height: 38, borderRadius: 10, background: 'rgba(245,200,66,0.15)', border: '1px solid rgba(245,200,66,0.3)', color: '#F5C842', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Download size={16} />
          </button>
          {cert.file_url && (
            <button onClick={handleShare} title="Share" style={{ width: 38, height: 38, borderRadius: 10, background: 'rgba(58,175,169,0.15)', border: '1px solid rgba(58,175,169,0.3)', color: '#3AAFA9', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Share2 size={16} />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

export default function CertificatesPage() {
  const { user } = useAuth();
  const [certs, setCerts] = useState([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setIsLoading(true);
      const { data } = await supabase.from('certificates').select('*, events(title, date)').eq('user_id', user.id).order('issued_at', { ascending: false });
      setCerts(data || []);
      setIsLoading(false);
    };
    load();
  }, [user]);

  return (
    <DashboardLayout>
      <div style={{ maxWidth: 780, margin: '0 auto', padding: '32px 24px', minHeight: '100vh', background: '#141414' }}>
        <h1 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 26, fontWeight: 700, color: '#fff', marginBottom: 6 }}>My Certificates</h1>
        <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: 'rgba(255,255,255,0.4)', marginBottom: 32 }}>Your earned certificates from ISTE events</p>

        {isLoading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 80 }}>
            <div style={{ width: 36, height: 36, border: '4px solid rgba(245,200,66,0.2)', borderTopColor: '#F5C842', borderRadius: '50%', animation: 'spin 1s linear infinite' }} />
          </div>
        ) : certs.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '80px 24px' }}>
            <Award size={72} color="rgba(255,255,255,0.1)" style={{ marginBottom: 20 }} />
            <h2 style={{ fontFamily: "'Space Grotesk',sans-serif", fontSize: 20, fontWeight: 700, color: 'rgba(255,255,255,0.3)', marginBottom: 10 }}>No certificates yet</h2>
            <p style={{ fontFamily: "'Inter',sans-serif", fontSize: 14, color: 'rgba(255,255,255,0.2)' }}>Attend events to earn certificates</p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }} className="fade-in">
            {certs.map(cert => <CertCard key={cert.id} cert={cert} />)}
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
