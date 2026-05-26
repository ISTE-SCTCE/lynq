import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

export interface CalendarEvent {
  title: string;
  time: string;
}

export interface EventsData {
  [key: string]: any[];
}

interface DateItem {
  day: number;
  fullDate: string;
  month: number;
  year: number;
  dateObj: Date;
  dayOfWeek: number;
  dayName: string;
}

export interface CalendarWidgetProps {
  events: EventsData;
  selectedDate: string;
  onDateSelect: (date: string) => void;
}

const daysOfWeek: string[] = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

export const CalendarWidget: React.FC<CalendarWidgetProps> = ({
  events,
  selectedDate,
  onDateSelect,
}) => {
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const isDragging = useRef<boolean>(false);
  const startX = useRef<number>(0);
  const scrollLeftStart = useRef<number>(0);

  // Generate dynamic 90-day range: 30 days in the past, to 60 days in the future
  const dates: DateItem[] = Array.from({ length: 90 }, (_, i) => {
    const date = new Date();
    date.setDate(date.getDate() - 30 + i);
    return {
      day: date.getDate(),
      fullDate: date.toISOString().split('T')[0],
      month: date.getMonth(),
      year: date.getFullYear(),
      dateObj: date,
      dayOfWeek: date.getDay(),
      dayName: daysOfWeek[date.getDay()],
    };
  });

  // Calculate Month & Year string dynamically based on selected date
  const selectedDateObj = new Date(selectedDate);
  const currentMonthYear = selectedDateObj.toLocaleDateString('en-US', {
    month: 'long',
    year: 'numeric',
  });

  // Smooth desktop mouse-drag scrolling
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    const onMouseDown = (e: MouseEvent) => {
      isDragging.current = true;
      startX.current = e.pageX - el.offsetLeft;
      scrollLeftStart.current = el.scrollLeft;
      el.style.cursor = 'grabbing';
    };

    const onMouseLeave = () => {
      isDragging.current = false;
      el.style.cursor = 'grab';
    };

    const onMouseUp = () => {
      isDragging.current = false;
      el.style.cursor = 'grab';
    };

    const onMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      e.preventDefault();
      const x = e.pageX - el.offsetLeft;
      const walk = (x - startX.current) * 1.5; // Drag speed modifier
      el.scrollLeft = scrollLeftStart.current - walk;
    };

    el.style.cursor = 'grab';
    el.addEventListener('mousedown', onMouseDown);
    el.addEventListener('mouseleave', onMouseLeave);
    el.addEventListener('mouseup', onMouseUp);
    el.addEventListener('mousemove', onMouseMove);

    // Initial center on the selected date
    const selectedIndex = dates.findIndex((d) => d.fullDate === selectedDate);
    if (selectedIndex !== -1 && el) {
      setTimeout(() => {
        const itemWidth = 56; // estimated column width (40px + 16px gap)
        const containerWidth = el.clientWidth;
        const scrollPosition = selectedIndex * itemWidth - containerWidth / 2 + itemWidth / 2;
        el.scrollTo({ left: scrollPosition, behavior: 'smooth' });
      }, 100);
    }

    return () => {
      el.removeEventListener('mousedown', onMouseDown);
      el.removeEventListener('mouseleave', onMouseLeave);
      el.removeEventListener('mouseup', onMouseUp);
      el.removeEventListener('mousemove', onMouseMove);
    };
  }, []);

  return (
    <div className="calendar-widget-container glass-card">
      <div className="calendar-widget-header">
        <motion.div
          key={currentMonthYear}
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          className="calendar-month-title"
        >
          {currentMonthYear}
        </motion.div>
      </div>

      <div className="calendar-scroller-relative">
        <div ref={scrollRef} className="calendar-dates-scroller scrollbar-hide">
          {dates.map((date) => {
            const isSelected = selectedDate === date.fullDate;
            const hasEvent = events[date.fullDate]?.length > 0;

            return (
              <div key={date.fullDate} className="calendar-date-column">
                <span className={`calendar-day-name ${isSelected ? 'selected' : ''}`}>
                  {date.dayName}
                </span>

                <motion.div
                  className="calendar-day-bubble-wrapper"
                  whileTap={{ scale: 0.9 }}
                  onClick={() => onDateSelect(date.fullDate)}
                >
                  <div className="calendar-day-bubble-inner">
                    {isSelected && (
                      <motion.div
                        layoutId="selected-date-glow"
                        transition={{
                          type: 'spring',
                          stiffness: 200,
                          damping: 20,
                        }}
                        className="calendar-selected-bg"
                      />
                    )}
                    <span className={`calendar-day-number ${isSelected ? 'selected' : ''}`}>
                      {date.day}
                    </span>
                  </div>

                  <AnimatePresence mode="popLayout" initial={false}>
                    {hasEvent && !isSelected && (
                      <motion.span
                        initial={{ opacity: 0, scale: 0 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0 }}
                        transition={{ duration: 0.2 }}
                        className="calendar-event-dot"
                      />
                    )}
                  </AnimatePresence>
                </motion.div>
              </div>
            );
          })}
        </div>
      </div>

      <style>{`
        .calendar-widget-container {
          width: 100%;
          border-radius: 24px;
          padding: 16px;
          margin-bottom: 20px;
          user-select: none;
          -webkit-user-select: none;
          box-shadow: var(--shadow-premium);
        }

        .calendar-widget-header {
          display: flex;
          align-items: center;
          margin-bottom: 12px;
          padding-left: 8px;
        }

        .calendar-month-title {
          font-family: var(--font-space-grotesk);
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
        }

        .calendar-scroller-relative {
          position: relative;
          width: 100%;
          overflow: hidden;
        }

        .calendar-dates-scroller {
          display: flex;
          gap: 12px;
          overflow-x: auto;
          padding: 4px 8px 8px 8px;
          scroll-behavior: smooth;
          scrollbar-width: none; /* Firefox */
          -ms-overflow-style: none; /* IE 10+ */
        }

        .calendar-dates-scroller::-webkit-scrollbar {
          display: none; /* Chrome, Safari, Opera */
        }

        .calendar-date-column {
          display: flex;
          flex-direction: column;
          align-items: center;
          min-width: 42px;
          flex-shrink: 0;
        }

        .calendar-day-name {
          font-size: 11px;
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
          margin-bottom: 6px;
          transition: color 0.2s ease;
        }

        .calendar-day-name.selected {
          color: rgb(22, 192, 122);
        }

        .calendar-day-bubble-wrapper {
          position: relative;
          display: flex;
          flex-direction: column;
          align-items: center;
          cursor: pointer;
          width: 40px;
        }

        .calendar-day-bubble-inner {
          position: relative;
          width: 40px;
          height: 40px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 50%;
        }

        .calendar-selected-bg {
          position: absolute;
          inset: 0;
          border-radius: 50%;
          background: rgb(22, 192, 122);
          box-shadow: 0 4px 12px rgba(22, 192, 122, 0.35);
        }

        .calendar-day-number {
          position: relative;
          z-index: 2;
          font-family: var(--font-space-grotesk);
          font-size: 14px;
          font-weight: 700;
          color: var(--text-primary);
          transition: color 0.2s ease;
        }

        .calendar-day-number.selected {
          color: #ffffff !important;
        }

        .calendar-event-dot {
          display: block;
          width: 5px;
          height: 5px;
          background-color: rgb(22, 192, 122);
          border-radius: 50%;
          margin-top: 4px;
          will-change: transform;
        }
      `}</style>
    </div>
  );
};
