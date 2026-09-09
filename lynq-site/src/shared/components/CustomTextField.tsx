import React, { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';
import { motion } from 'framer-motion';

interface CustomTextFieldProps {
  label: string;
  value: string;
  onChange: (val: string) => void;
  prefixIcon?: React.ComponentType<any>;
  isPassword?: boolean;
  type?: string;
  maxLines?: number;
  className?: string;
  placeholder?: string;
  error?: string;
}

export const CustomTextField: React.FC<CustomTextFieldProps> = ({
  label,
  value,
  onChange,
  prefixIcon: PrefixIcon,
  isPassword = false,
  type = 'text',
  maxLines = 1,
  className = '',
  placeholder = '',
  error = '',
}) => {
  const [showPassword, setShowPassword] = useState(false);

  const handleTogglePassword = () => {
    setShowPassword(!showPassword);
  };

  const isTextArea = maxLines > 1;
  const inputType = isPassword ? (showPassword ? 'text' : 'password') : type;

  return (
    <motion.div 
      className={`custom-field-container ${className}`}
      animate={error ? { x: [-8, 8, -6, 6, -3, 3, 0] } : {}}
      transition={{ type: 'spring', stiffness: 600, damping: 20 }}
    >
      <label className={`custom-field-label ${error ? 'has-error' : ''}`}>{label}</label>
      <div className="custom-input-wrapper">
        {PrefixIcon && <PrefixIcon className="input-prefix-icon" size={18} />}
        
        {isTextArea ? (
          <textarea
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder || `Enter ${label.toLowerCase()}`}
            rows={maxLines}
            className={`custom-input-field ${PrefixIcon ? 'has-prefix' : ''} ${error ? 'error-border' : ''}`}
          />
        ) : (
          <input
            type={inputType}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder || `Enter ${label.toLowerCase()}`}
            className={`custom-input-field ${PrefixIcon ? 'has-prefix' : ''} ${isPassword ? 'has-suffix' : ''} ${error ? 'error-border' : ''}`}
          />
        )}

        {isPassword && (
          <button type="button" onClick={handleTogglePassword} className="input-suffix-button">
            {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
          </button>
        )}
      </div>

      {error && (
        <motion.span 
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          className="custom-field-error-text"
        >
          {error}
        </motion.span>
      )}

      <style>{`
        .custom-field-container {
          display: flex;
          flex-direction: column;
          margin-bottom: 16px;
          width: 100%;
        }

        .custom-field-label {
          font-family: var(--font-space-grotesk);
          font-size: 13px;
          font-weight: 600;
          color: var(--text-secondary);
          margin-bottom: 6px;
          letter-spacing: 0.5px;
          transition: color 0.2s ease;
        }

        .custom-field-label.has-error {
          color: #ff4d4d;
        }

        .custom-input-wrapper {
          position: relative;
          display: flex;
          align-items: center;
          width: 100%;
        }

        .input-prefix-icon {
          position: absolute;
          left: 14px;
          color: var(--text-muted);
          pointer-events: none;
        }

        .custom-input-field {
          width: 100%;
          padding: 14px 16px;
          background: rgba(255, 255, 255, 0.04);
          border: 1px solid var(--border-light);
          border-radius: 14px;
          font-size: 14px;
          font-family: var(--font-inter);
          color: #ffffff;
          -webkit-text-fill-color: #ffffff;
          outline: none;
          transition: all 0.2s cubic-bezier(0.25, 0.8, 0.25, 1);
          caret-color: #ffffff;
        }

        /* Override browser autofill background (Chromium/Safari) */
        .custom-input-field:-webkit-autofill,
        .custom-input-field:-webkit-autofill:hover,
        .custom-input-field:-webkit-autofill:focus,
        .custom-input-field:-webkit-autofill:active {
          -webkit-box-shadow: 0 0 0 1000px rgba(22, 28, 42, 0.95) inset !important;
          -webkit-text-fill-color: #ffffff !important;
          caret-color: #ffffff;
          border-color: var(--border-light);
          transition: background-color 9999s ease-in-out 0s;
        }

        .custom-input-field.has-prefix {
          padding-left: 44px;
        }

        .custom-input-field.has-suffix {
          padding-right: 44px;
        }

        .custom-input-field:focus {
          border-color: rgb(var(--secondary-neon));
          background: rgba(255, 255, 255, 0.08);
          box-shadow: 0 0 0 3px rgba(var(--secondary-neon), 0.15);
        }

        .custom-input-field.error-border {
          border-color: #ff4d4d;
        }

        .custom-input-field.error-border:focus {
          box-shadow: 0 0 0 3px rgba(255, 77, 77, 0.15);
        }

        .custom-field-error-text {
          font-size: 12px;
          color: #ff4d4d;
          margin-top: 4px;
          font-family: var(--font-inter);
        }

        .input-suffix-button {
          position: absolute;
          right: 14px;
          color: var(--text-muted);
          background: none;
          border: none;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 0;
          cursor: pointer;
        }

        .input-suffix-button:hover {
          color: var(--text-secondary);
        }

        textarea.custom-input-field {
          resize: none;
        }
      `}</style>
    </motion.div>
  );
};
