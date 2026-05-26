import React from 'react';

interface GlassCardProps {
  children: React.ReactNode;
  className?: string;
  onClick?: (e: React.MouseEvent<HTMLDivElement>) => void;
  style?: React.CSSProperties;
  padding?: string;
  borderRadius?: string;
}

export const GlassCard: React.FC<GlassCardProps> = ({
  children,
  className = '',
  onClick,
  style,
  padding,
  borderRadius,
}) => {
  const cardStyle: React.CSSProperties = {
    ...style,
    padding: padding !== undefined ? padding : '20px',
    borderRadius: borderRadius !== undefined ? borderRadius : '20px',
    cursor: onClick ? 'pointer' : 'default',
  };

  return (
    <div
      className={`glass-card ${className}`}
      onClick={onClick}
      style={cardStyle}
    >
      {children}
    </div>
  );
};
