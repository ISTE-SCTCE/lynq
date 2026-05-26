import React, { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';

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
}) => {
  const [showPassword, setShowPassword] = useState(false);

  const handleTogglePassword = () => {
    setShowPassword(!showPassword);
  };

  const isTextArea = maxLines > 1;
  const inputType = isPassword ? (showPassword ? 'text' : 'password') : type;

  return (
    <div className={`custom-field-container ${className}`}>
      <label className="custom-field-label">{label}</label>
      <div className="custom-input-wrapper">
        {PrefixIcon && <PrefixIcon className="input-prefix-icon" size={18} />}
        
        {isTextArea ? (
          <textarea
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder || `Enter ${label.toLowerCase()}`}
            rows={maxLines}
            className={`custom-input-field ${PrefixIcon ? 'has-prefix' : ''}`}
          />
        ) : (
          <input
            type={inputType}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder || `Enter ${label.toLowerCase()}`}
            className={`custom-input-field ${PrefixIcon ? 'has-prefix' : ''} ${isPassword ? 'has-suffix' : ''}`}
          />
        )}

        {isPassword && (
          <button type="button" onClick={handleTogglePassword} className="input-suffix-button">
            {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
          </button>
        )}
      </div>

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
          color: var(--text-primary);
          outline: none;
          transition: all 0.2s ease;
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
          box-shadow: 0 0 10px rgba(var(--secondary-neon), 0.15);
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
    </div>
  );
};
