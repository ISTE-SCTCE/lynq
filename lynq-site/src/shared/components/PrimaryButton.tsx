import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';

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
    <motion.button
      type={type}
      onClick={onClick}
      disabled={disabled || isLoading}
      style={style}
      className={`primary-button flex-center ${className}`}
      whileHover={!(disabled || isLoading) ? { scale: 1.02, y: -2, filter: 'brightness(1.1)' } : undefined}
      whileTap={!(disabled || isLoading) ? { scale: 0.98, y: 0 } : undefined}
      transition={{ type: 'spring', stiffness: 500, damping: 25 }}
    >
      <AnimatePresence mode="wait">
        {isLoading ? (
          <motion.span 
            key="spinner"
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.8 }}
            transition={{ duration: 0.15 }}
            className="btn-spinner"
          />
        ) : (
          <motion.span 
            key="content"
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -5 }}
            transition={{ duration: 0.15 }}
            className="btn-content flex-center"
          >
            {children ? children : (
              <>
                {Icon && <Icon className="btn-icon" size={18} style={{ marginRight: '8px' }} />}
                {text}
              </>
            )}
          </motion.span>
        )}
      </AnimatePresence>

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
          border: none;
          outline: none;
          cursor: pointer;
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
    </motion.button>
  );
};
