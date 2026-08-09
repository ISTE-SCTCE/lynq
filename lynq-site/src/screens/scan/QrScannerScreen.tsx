import React, { useState, useEffect, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, AlertTriangle, RefreshCw, Sparkles, ShieldCheck, Play, Power, HelpCircle } from 'lucide-react';
import { Html5Qrcode } from 'html5-qrcode';
import { useAuth } from '../../core/auth-provider';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';

interface ScanResult {
  success: boolean;
  message: string;
  userName?: string;
  rollNumber?: string;
  branch?: string;
}

export const QrScannerScreen: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const eventIdStr = searchParams.get('eventId');
  const eventId = eventIdStr ? parseInt(eventIdStr) : null;
  const { currentUser } = useAuth();

  const [isProcessing, setIsProcessing] = useState(false);
  const [lastResult, setLastResult] = useState<ScanResult | null>(null);
  const [isCameraActive, setIsCameraActive] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);

  const qrRef = useRef<Html5Qrcode | null>(null);

  useEffect(() => {
    // Initialise and start scanner
    const startScanner = async () => {
      try {
        const html5QrCode = new Html5Qrcode("reader");
        qrRef.current = html5QrCode;

        await html5QrCode.start(
          { facingMode: "environment" },
          {
            fps: 10,
            qrbox: (width, height) => {
              const minSide = Math.min(width, height);
              const qrboxSize = Math.floor(minSide * 0.65);
              return { width: qrboxSize, height: qrboxSize };
            }
          },
          (decodedText) => {
            handleProcessQr(decodedText);
          },
          () => {
            // Silence silent scan failure messages
          }
        );
        setIsCameraActive(true);
      } catch (err: any) {
        console.error("Scanner failed to start:", err);
        setCameraError(err.message || "Failed to access browser camera. Please grand permissions.");
      }
    };

    startScanner();

    return () => {
      if (qrRef.current && qrRef.current.isScanning) {
        qrRef.current.stop()
          .then(() => console.log("Scanner stopped"))
          .catch(err => console.error("Error stopping scanner", err));
      }
    };
  }, []);

  const handleProcessQr = async (code: string) => {
    if (isProcessing) return;
    setIsProcessing(true);

    try {
      // 1. JSON decoding
      let payload: any;
      try {
        payload = JSON.parse(code);
      } catch (_) {
        setLastResult({ success: false, message: 'Invalid QR code signature format.' });
        setIsProcessing(false);
        return;
      }

      const uid = payload.uid;
      const token = payload.token;
      const ts = payload.ts;

      if (!uid || !token || !ts) {
        setLastResult({ success: false, message: 'Malformed attendance credentials.' });
        setIsProcessing(false);
        return;
      }

      // 2. Validate token is not older than 30s
      const ageInSeconds = (Date.now() - ts) / 1000;
      if (ageInSeconds > 30) {
        setLastResult({ success: false, message: 'QR code expired. Please refresh mobile app.' });
        setIsProcessing(false);
        return;
      }

      // 3. Query token in DB
      const { data: tokenRows, error: tokenErr } = await supabase
        .from('qr_tokens')
        .select()
        .eq('user_id', uid)
        .eq('token_hash', token)
        .eq('is_used', false)
        .gt('expires_at', new Date().toISOString())
        .limit(1);

      if (tokenErr || !tokenRows || tokenRows.length === 0) {
        setLastResult({ success: false, message: 'Invalid token signature or already marked.' });
        setIsProcessing(false);
        return;
      }

      const tokenRow = tokenRows[0];
      const tokenId = tokenRow.id;

      // 4. Duplicate attendance checks
      if (eventId !== null) {
        const { data: existingData } = await supabase
          .from('attendance')
          .select('id')
          .eq('event_id', eventId)
          .eq('user_id', uid)
          .limit(1);

        if (existingData && existingData.length > 0) {
          const { data: userRow } = await supabase
            .from('profiles')
            .select('name')
            .eq('id', uid)
            .single();

          setLastResult({
            success: false,
            message: `Already marked: ${userRow?.name || 'User'}`
          });
          setIsProcessing(false);
          return;
        }
      }

      // 5. Fetch user profile detail
      const { data: userRow } = await supabase
        .from('profiles')
        .select('name, roll_number, branch')
        .eq('id', uid)
        .single();

      // 6. Log attendance row
      if (eventId !== null && currentUser) {
        const { error: attError } = await supabase.from('attendance').insert({
          event_id: eventId,
          user_id: uid,
          scanned_by: currentUser.id,
          qr_token_id: tokenId,
        });

        if (attError) throw attError;
      }

      // 7. Set token as used
      await supabase
        .from('qr_tokens')
        .update({ is_used: true })
        .eq('id', tokenId);

      setLastResult({
        success: true,
        message: 'Attendance logged successfully!',
        userName: userRow?.name,
        rollNumber: userRow?.roll_number,
        branch: userRow?.branch
      });
    } catch (e: any) {
      console.error('Scan process failed:', e);
      setLastResult({ success: false, message: e.message || 'Error processing attendance scan.' });
    } finally {
      setIsProcessing(false);
      // Reset scanning window in 3.5 seconds
      setTimeout(() => {
        setLastResult(null);
      }, 3500);
    }
  };

  return (
    <div className="scanner-container">
      {/* Absolute top bar overlay */}
      <header className="scanner-header flex-center">
        <button onClick={() => navigate(-1)} className="back-button">
          <ArrowLeft size={20} />
        </button>
        <span className="scanner-title">
          {eventId ? `Scanning for Event #${eventId}` : 'Secure Attendance Scanner'}
        </span>
        <div style={{ width: '20px' }}></div>
      </header>

      {/* Reader box container */}
      <div className="camera-view-port">
        <div id="reader" style={{ width: '100%', height: '100%', objectFit: 'cover' }}></div>
        
        {/* Customized overlay scanner visual frames */}
        {isCameraActive && (
          <div className="scanner-overlay-canvas flex-center">
            <div 
              className={`target-focus-box ${lastResult ? (lastResult.success ? 'success' : 'failure') : 'pulse'}`}
            >
              <div className="corner top-left"></div>
              <div className="corner top-right"></div>
              <div className="corner bottom-left"></div>
              <div className="corner bottom-right"></div>
              
              {!lastResult && <div className="scanning-bar"></div>}
            </div>
          </div>
        )}
      </div>

      {/* Camera error displays */}
      {cameraError && (
        <div className="scanner-error flex-center" style={{ flexDirection: 'column', padding: '40px 24px', flex: 1 }}>
          <AlertTriangle size={48} style={{ color: 'var(--accent-gold)', marginBottom: '16px' }} />
          <h3 style={{ fontFamily: 'var(--font-space-grotesk)' }}>Camera Access Blocked</h3>
          <p style={{ fontSize: '13px', color: 'var(--text-muted)', textAlign: 'center', marginTop: '8px', lineHeight: '1.45' }}>
            {cameraError}
          </p>
        </div>
      )}

      {/* Result feedback panels */}
      {lastResult && (
        <div className="result-card-overlay">
          <GlassCard 
            className={`result-card ${lastResult.success ? 'success' : 'failure'}`}
            padding="16px"
            style={{ 
              borderColor: lastResult.success ? 'rgba(22, 192, 122, 0.4)' : 'rgba(239, 68, 68, 0.4)',
              backgroundColor: lastResult.success ? 'rgba(22, 192, 122, 0.08)' : 'rgba(239, 68, 68, 0.08)'
            }}
          >
            <div className="flex-row-between" style={{ justifyContent: 'flex-start' }}>
              <div 
                className="status-icon-holder flex-center"
                style={{ 
                  backgroundColor: lastResult.success ? 'rgba(22, 192, 122, 0.15)' : 'rgba(239, 68, 68, 0.15)',
                  color: lastResult.success ? 'rgb(22, 192, 122)' : '#ef4444'
                }}
              >
                {lastResult.success ? <CheckCircle2 size={24} /> : <AlertTriangle size={24} />}
              </div>

              <div className="result-text-meta" style={{ marginLeft: '14px', flex: 1, textAlign: 'left' }}>
                {lastResult.userName && <span className="result-name-lbl">{lastResult.userName}</span>}
                <p 
                  className="result-msg-lbl"
                  style={{ color: lastResult.success ? 'var(--text-primary)' : '#ef4444' }}
                >
                  {lastResult.message}
                </p>
                {lastResult.rollNumber && (
                  <span className="result-roll-lbl">
                    {lastResult.rollNumber} {lastResult.branch ? `· ${lastResult.branch}` : ''}
                  </span>
                )}
              </div>
            </div>
          </GlassCard>
        </div>
      )}

      <style>{`
        .scanner-container {
          display: flex;
          flex-direction: column;
          height: 100vh;
          background: #000;
          position: relative;
          color: #fff;
        }

        .scanner-header {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 60px;
          padding: 0 16px;
          background: rgba(0, 0, 0, 0.5);
          backdrop-filter: blur(10px);
          z-index: 100;
          justify-content: space-between;
          border-bottom: 1px solid rgba(255,255,255,0.06);
        }

        .back-button {
          color: #fff;
        }

        .scanner-title {
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 13.5px;
          letter-spacing: 0.5px;
        }

        .camera-view-port {
          flex: 1;
          position: relative;
          overflow: hidden;
          background: #000;
        }

        /* Scan Box Focus Frame Overlay */
        .scanner-overlay-canvas {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          pointer-events: none;
          background: rgba(0,0,0,0.3);
        }

        .target-focus-box {
          position: relative;
          width: 240px;
          height: 240px;
          border-radius: 20px;
          transition: all 0.3s ease;
        }

        .target-focus-box.pulse {
          box-shadow: 0 0 0 1000px rgba(0, 0, 0, 0.6);
        }
        .target-focus-box.success {
          box-shadow: 0 0 0 1000px rgba(22, 192, 122, 0.25);
        }
        .target-focus-box.failure {
          box-shadow: 0 0 0 1000px rgba(239, 68, 68, 0.25);
        }

        /* Bracket corners */
        .corner {
          position: absolute;
          width: 20px;
          height: 20px;
          border: 3.5px solid rgb(22, 192, 122);
          transition: border-color 0.3s ease;
        }
        
        .target-focus-box.failure .corner {
          border-color: #ef4444;
        }

        .top-left { top: 0; left: 0; border-right: none; border-bottom: none; border-radius: 12px 0 0 0; }
        .top-right { top: 0; right: 0; border-left: none; border-bottom: none; border-radius: 0 12px 0 0; }
        .bottom-left { bottom: 0; left: 0; border-right: none; border-top: none; border-radius: 0 0 0 12px; }
        .bottom-right { bottom: 0; right: 0; border-left: none; border-top: none; border-radius: 0 0 12px 0; }

        /* Scanning sliding bar */
        .scanning-bar {
          position: absolute;
          top: 10px;
          left: 10px;
          right: 10px;
          height: 2px;
          background: linear-gradient(90deg, transparent, rgb(22, 192, 122), transparent);
          animation: scanBarMove 2.5s linear infinite;
        }

        @keyframes scanBarMove {
          0% { top: 10px; }
          50% { top: 230px; }
          100% { top: 10px; }
        }

        /* Result card drawer at bottom */
        .result-card-overlay {
          position: absolute;
          bottom: 40px;
          left: 16px;
          right: 16px;
          z-index: 100;
          animation: slideUp 0.3s ease-out;
        }

        @keyframes slideUp {
          from { transform: translateY(50px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }

        .result-card {
          width: 100%;
        }

        .status-icon-holder {
          width: 44px;
          height: 44px;
          border-radius: 50%;
          flex-shrink: 0;
        }

        .result-name-lbl {
          font-family: var(--font-space-grotesk);
          font-weight: 800;
          font-size: 16px;
          color: #fff;
          display: block;
        }

        .result-msg-lbl {
          font-size: 12.5px;
          margin: 0;
          font-weight: 600;
        }

        .result-roll-lbl {
          font-size: 11px;
          color: rgba(255,255,255,0.4);
          margin-top: 2px;
          display: block;
        }
      `}</style>
    </div>
  );
};
