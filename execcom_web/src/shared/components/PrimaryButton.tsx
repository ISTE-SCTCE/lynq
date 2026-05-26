import React from 'react';

interface PrimaryButtonProps {
  text?: string;
  onClick?: () => void | Promise<void>;
  isLoading?: boolean;
  disabled?: boolean;
  style?: React.CSSProperties;
  className?: string;
  icon?: React.ComponentType<any>;
  children?: React.ReactNode;
  type?: 'button' | 'submit' | 'reset';
}

export const PrimaryButton: React.FC<PrimaryButtonProps> = ({
  text,
  onClick,
  isLoading = false,
  disabled = false,
  style,
  className = '',
  icon: Icon,
  children,
  type = 'button',
}) => {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled || isLoading}
      style={style}
      className={`primary-button flex-center ${className}`}
    >
      {isLoading ? (
        <span className="btn-spinner"></span>
      ) : (
        <span className="btn-content flex-center">
          {children ? children : (
            <>
              {Icon && <Icon className="btn-icon" size={18} style={{ marginRight: '8px' }} />}
              {text}
            </>
          )}
        </span>
      )}

      <style>{`
        .primary-button {
          width: 100%;
          padding: 16px;
          border-radius: 14px;
          font-family: var(--font-space-grotesk);
          font-weight: 700;
          font-size: 16px;
          letter-spacing: 0.5px;
          background: linear-gradient(135deg, rgb(15, 117, 73) 0%, rgb(22, 192, 122) 100%);
          color: #ffffff;
          box-shadow: 0 4px 15px rgba(22, 192, 122, 0.2);
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
          border: none;
          outline: none;
        }

        .primary-button:hover:not(:disabled) {
          transform: translateY(-2px);
          box-shadow: 0 6px 20px rgba(22, 192, 122, 0.35);
          filter: brightness(1.1);
        }

        .primary-button:active:not(:disabled) {
          transform: translateY(1px);
        }

        .primary-button:disabled {
          opacity: 0.6;
          cursor: not-allowed;
          box-shadow: none;
        }

        .btn-spinner {
          width: 20px;
          height: 20px;
          border: 3px solid rgba(255, 255, 255, 0.3);
          border-radius: 50%;
          border-top-color: #ffffff;
          animation: spin 1s ease-in-out infinite;
        }

        .btn-icon {
          display: inline-block;
          vertical-align: middle;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }
      `}</style>
    </button>
  );
};
