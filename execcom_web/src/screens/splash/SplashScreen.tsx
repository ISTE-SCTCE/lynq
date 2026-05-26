import React, { useEffect, useState, useRef, useCallback } from 'react';
import { useAuth } from '../../core/auth-provider';

const FULL_WORD = 'lynq';
const CHAR_DELAY_MS = 110;
const POST_TYPE_HOLD_MS = 400;
// Hard cutoff — splash never shows longer than this
const MAX_SPLASH_MS = 3500;

export const SplashScreen: React.FC = () => {
  const { isLoading, hideSplash } = useAuth();
  const [displayText, setDisplayText] = useState('');
  const [cursorBlinking, setCursorBlinking] = useState(false);
  const typingDone = useRef(false);
  const dismissed = useRef(false);
  // Always use latest hideSplash via ref to avoid stale closures
  const hideSplashRef = useRef(hideSplash);
  useEffect(() => { hideSplashRef.current = hideSplash; }, [hideSplash]);

  const dismiss = useCallback(() => {
    if (dismissed.current) return;
    dismissed.current = true;
    hideSplashRef.current();
  }, []);

  // Hard cutoff safety net — always dismiss after MAX_SPLASH_MS
  useEffect(() => {
    const t = setTimeout(dismiss, MAX_SPLASH_MS);
    return () => clearTimeout(t);
  }, [dismiss]);

  // Typewriter effect
  useEffect(() => {
    let idx = 0;
    let timeout: ReturnType<typeof setTimeout>;

    const typeNext = () => {
      if (idx < FULL_WORD.length) {
        idx++;
        setDisplayText(FULL_WORD.slice(0, idx));
        timeout = setTimeout(typeNext, CHAR_DELAY_MS);
      } else {
        typingDone.current = true;
        setCursorBlinking(true);
      }
    };

    timeout = setTimeout(typeNext, 200);
    return () => clearTimeout(timeout);
  }, []);

  // Dismiss once both auth AND typing are done
  useEffect(() => {
    if (!isLoading && typingDone.current) {
      setTimeout(dismiss, POST_TYPE_HOLD_MS);
    }
  }, [isLoading]);

  // Also poll: in case isLoading already false before typing finishes
  useEffect(() => {
    if (isLoading) return;
    const interval = setInterval(() => {
      if (typingDone.current) {
        clearInterval(interval);
        setTimeout(dismiss, POST_TYPE_HOLD_MS);
      }
    }, 80);
    return () => clearInterval(interval);
  }, [isLoading]);

  return (
    <div className="spl-root">
      <div className="spl-content">
        {/* Logo */}
        <div className="spl-logo-wrap spl-float">
          <img src="/logo.png" className="spl-logo-img" alt="LYNQ" />
        </div>

        {/* Typewriter title */}
        <div className="spl-title-row">
          <span className="spl-title-text">{displayText}</span>
          <span className={`spl-cursor ${cursorBlinking ? 'spl-cursor--blink' : ''}`} />
        </div>

        <p className="spl-tagline">Connect. Coordinate. Lead.</p>

        {/* Spinner */}
        <div className="spl-spinner-wrap">
          <div className="spl-spinner" />
        </div>
      </div>

      <style>{`
        .spl-root {
          position: fixed;
          inset: 0;
          background: linear-gradient(145deg, #1a0f08 0%, #0e0e0e 55%, #0a1412 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9999;
          overflow: hidden;
        }
        .spl-root::before {
          content: '';
          position: absolute;
          width: 600px; height: 600px;
          border-radius: 50%;
          background: radial-gradient(circle, rgba(217,125,85,0.12) 0%, transparent 70%);
          top: -200px; left: -200px;
          pointer-events: none;
        }
        .spl-root::after {
          content: '';
          position: absolute;
          width: 500px; height: 500px;
          border-radius: 50%;
          background: radial-gradient(circle, rgba(111,164,175,0.10) 0%, transparent 70%);
          bottom: -180px; right: -150px;
          pointer-events: none;
        }
        .spl-content {
          position: relative;
          z-index: 2;
          display: flex;
          flex-direction: column;
          align-items: center;
          animation: splFadeIn 0.5s cubic-bezier(0.16,1,0.3,1) both;
        }
        @keyframes splFadeIn {
          from { opacity: 0; transform: translateY(12px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        .spl-logo-wrap {
          width: 104px; height: 104px;
          border-radius: 28px;
          background: rgba(255,255,255,0.06);
          border: 1px solid rgba(255,255,255,0.12);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 28px;
          box-shadow: 0 20px 50px rgba(0,0,0,0.35), 0 0 0 1px rgba(217,125,85,0.08);
        }
        .spl-logo-img {
          width: 72px; height: 72px;
          object-fit: contain;
          filter: drop-shadow(0 4px 18px rgba(217,125,85,0.3));
        }
        @keyframes splFloat {
          0%,100% { transform: translateY(0px); }
          50%      { transform: translateY(-7px); }
        }
        .spl-float { animation: splFloat 5s ease-in-out infinite; }
        .spl-title-row {
          display: flex;
          align-items: center;
          height: 60px;
          margin-bottom: 14px;
        }
        .spl-title-text {
          font-family: 'Qurova', sans-serif;
          font-weight: normal;
          font-size: 50px;
          color: #ffffff;
          letter-spacing: 3px;
          line-height: 1;
          will-change: contents;
        }
        .spl-cursor {
          display: inline-block;
          width: 3px; height: 44px;
          background: rgb(22,192,122);
          border-radius: 2px;
          margin-left: 3px;
          flex-shrink: 0;
          opacity: 1;
        }
        .spl-cursor--blink {
          animation: splCursorBlink 0.65s step-end 4 forwards;
        }
        @keyframes splCursorBlink {
          0%,100% { opacity: 1; }
          50%      { opacity: 0; }
        }
        .spl-tagline {
          font-size: 14px;
          color: rgba(255,255,255,0.45);
          letter-spacing: 1.5px;
          margin-bottom: 52px;
          animation: splFadeIn 0.8s 0.3s ease both;
          font-family: 'Space Grotesk', sans-serif;
          text-transform: uppercase;
        }
        .spl-spinner-wrap {
          display: flex;
          align-items: center;
          justify-content: center;
          height: 36px;
        }
        .spl-spinner {
          width: 26px; height: 26px;
          border: 2.5px solid rgba(255,255,255,0.08);
          border-top-color: rgb(22,192,122);
          border-radius: 50%;
          animation: splSpin 0.75s linear infinite;
        }
        @keyframes splSpin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
