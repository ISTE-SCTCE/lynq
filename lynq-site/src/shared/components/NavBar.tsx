import React from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { LayoutGrid, Calendar, Wallet, MessageSquare, User } from 'lucide-react';
import { useAuth } from '../../core/auth-provider';

export const NavBar: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { permissions } = useAuth();

  if (!permissions) return null;

  const currentPath = location.pathname;
  
  // Decide which items to display
  const isAtLeastTier2 = permissions.isAtLeastTier2;
  const isBudgetPage = currentPath.startsWith('/budget');
  const isEventsPage = currentPath.startsWith('/events');

  // Find active tab index
  let activeIndex = 0;
  if (isBudgetPage || isEventsPage) {
    activeIndex = 1;
  } else if (currentPath.startsWith('/chat')) {
    activeIndex = 2;
  } else if (currentPath.startsWith('/settings') || currentPath.startsWith('/more')) {
    activeIndex = 3;
  }

  const handleSelectTab = (index: number) => {
    switch (index) {
      case 0:
        navigate('/home');
        break;
      case 1:
        navigate(isAtLeastTier2 ? '/budget' : '/events');
        break;
      case 2:
        navigate('/chat');
        break;
      case 3:
        navigate('/settings');
        break;
    }
  };

  const navItems = [
    { icon: LayoutGrid, label: 'Home', index: 0 },
    { 
      icon: isAtLeastTier2 ? Wallet : Calendar, 
      label: isAtLeastTier2 ? 'Budget' : 'Events', 
      index: 1 
    },
    { icon: MessageSquare, label: 'Chat', index: 2 },
    { icon: User, label: 'Profile', index: 3 },
  ];

  return (
    <>
      {/* Floating glass navigation bar */}
      <nav className="liquid-glass-nav-bar">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = activeIndex === item.index;
          return (
            <button
              key={item.index}
              onClick={() => handleSelectTab(item.index)}
              className={`nav-item ${isActive ? 'active' : ''}`}
            >
              <div className="nav-icon-container">
                <Icon size={20} className="nav-icon" />
                {isActive && <div className="nav-active-bubble"></div>}
              </div>
              <span className="nav-label">{item.label}</span>
            </button>
          );
        })}
      </nav>

      <style>{`
        .liquid-glass-nav-bar {
          position: fixed;
          bottom: 20px;
          left: 50%;
          transform: translateX(-50%);
          width: calc(100% - 32px);
          max-width: 440px;
          height: 72px;
          background: var(--bg-glass);
          backdrop-filter: blur(25px);
          -webkit-backdrop-filter: blur(25px);
          border: 1px solid var(--border-glass);
          box-shadow: var(--shadow-premium), 0 10px 40px rgba(0,0,0,0.1);
          border-radius: 24px;
          display: flex;
          align-items: center;
          justify-content: space-around;
          padding: 0 8px;
          z-index: 1000;
          transition: all 0.3s ease;
        }

        .nav-item {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          height: 100%;
          width: 70px;
          background: none;
          border: none;
          color: var(--text-muted);
          position: relative;
          transition: color 0.3s ease;
        }

        .nav-item.active {
          color: rgb(var(--secondary-neon));
        }

        .nav-icon-container {
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          width: 38px;
          height: 38px;
          border-radius: 50%;
          margin-bottom: 3px;
        }

        .nav-icon {
          position: relative;
          z-index: 2;
          transition: transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        }

        .nav-item.active .nav-icon {
          transform: translateY(-2px) scale(1.1);
        }

        .nav-active-bubble {
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(var(--secondary-neon), 0.12);
          border-radius: 50%;
          z-index: 1;
          animation: popBubble 0.35s cubic-bezier(0.175, 0.885, 0.32, 1.275);
        }

        .nav-label {
          font-family: var(--font-space-grotesk);
          font-size: 11px;
          font-weight: 700;
          letter-spacing: 0.5px;
          transition: transform 0.2s ease, opacity 0.2s ease;
        }

        @keyframes popBubble {
          0% { transform: scale(0); opacity: 0; }
          100% { transform: scale(1); opacity: 1; }
        }

        /* Dynamic Desktop responsiveness adjustments */
        @media (min-width: 1024px) {
          .liquid-glass-nav-bar {
            bottom: auto;
            top: 50%;
            left: 30px;
            transform: translateY(-50%);
            width: 80px;
            height: 380px;
            flex-direction: column;
            padding: 20px 0;
            border-radius: 30px;
          }
          
          .nav-item {
            width: 100%;
            height: 70px;
          }
        }
      `}</style>
    </>
  );
};
