import React from 'react';
import { motion } from 'framer-motion';

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
    <motion.div
      className={`glass-card ${className}`}
      onClick={onClick}
      style={cardStyle}
      whileHover={onClick ? { scale: 1.015, y: -2, filter: 'brightness(1.08)' } : undefined}
      whileTap={onClick ? { scale: 0.985 } : undefined}
      transition={{ type: 'spring', stiffness: 450, damping: 25 }}
    >
      {children}
    </motion.div>
  );
};
