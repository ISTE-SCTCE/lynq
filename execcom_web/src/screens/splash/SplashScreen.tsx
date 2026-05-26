import React, { useEffect } from 'react';
import { useAuth } from '../../core/auth-provider';

export const SplashScreen: React.FC = () => {
  const { isLoading, hideSplash } = useAuth();

  useEffect(() => {
    if (!isLoading) {
      const timer = setTimeout(() => {
        hideSplash();
      }, 300); // 300ms delay for a snappy, premium visual transition
      return () => clearTimeout(timer);
    }
  }, [isLoading, hideSplash]);

  return (
    <div className="splash-screen-container">
      <div className="splash-content">
        <div className="logo-container float-animation">
          <img src="/logo.png" className="logo-img" alt="LYNQ Logo" />
        </div>
        <h1 className="splash-title">LYNQ</h1>
        <p className="splash-tagline">Connect. Coordinate. Lead.</p>
        
        <div className="spinner-container">
          <div className="splash-spinner"></div>
        </div>
      </div>

      <style>{`
        .splash-screen-container {
          position: fixed;
          top: 0;
          left: 0;
          width: 100vw;
          height: 100vh;
          background: linear-gradient(135deg, #261610 0%, #141414 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 9999;
          color: #ffffff;
        }

        .splash-content {
          text-align: center;
          display: flex;
          flex-direction: column;
          align-items: center;
        }

        .logo-container {
          width: 110px;
          height: 110px;
          border-radius: 30px;
          background: rgba(255, 255, 255, 0.08);
          border: 1px solid rgba(255, 255, 255, 0.15);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: 24px;
          box-shadow: 0 15px 35px rgba(0, 0, 0, 0.2);
        }

        .logo-img {
          width: 80px;
          height: 80px;
          object-fit: contain;
          filter: drop-shadow(0 4px 15px rgba(var(--secondary-neon), 0.4));
        }

        .splash-title {
          font-size: 40px;
          font-weight: 900;
          letter-spacing: 5px;
          margin-bottom: 12px;
          animation: fadeSlideUp 0.8s ease-out;
        }

        .splash-tagline {
          font-size: 15px;
          color: rgba(255, 255, 255, 0.6);
          letter-spacing: 1px;
          margin-bottom: 50px;
          animation: fadeIn 1.2s ease-in;
        }

        .spinner-container {
          height: 40px;
          display: flex;
          align-items: center;
        }

        .splash-spinner {
          width: 28px;
          height: 28px;
          border: 3px solid rgba(255, 255, 255, 0.1);
          border-radius: 50%;
          border-top-color: rgb(var(--secondary-neon));
          animation: spin 0.8s linear infinite;
        }

        @keyframes fadeSlideUp {
          from { transform: translateY(20px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }

        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
};
