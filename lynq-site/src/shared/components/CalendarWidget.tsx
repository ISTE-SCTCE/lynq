import React, { useState, useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { ChevronLeft, ChevronRight, RotateCcw } from 'lucide-react';

export interface CalendarEvent {
  title: string;
  time?: string;
  [key: string]: any;
}

export interface EventsData {
  [key: string]: any[];
}

export interface CalendarWidgetProps {
  events: EventsData;
  selectedDate: string;
  onDateSelect: (date: string) => void;
  onClearDateFilter?: () => void;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

function formatDateKey(d: Date): string {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export const CalendarWidget: React.FC<CalendarWidgetProps> = ({
  events,
  selectedDate,
  onDateSelect,
}) => {
  const initialDate = useMemo(() => {
    if (selectedDate) {
      const parts = selectedDate.split('-');
      if (parts.length === 3) {
        return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
      }
    }
    return new Date();
  }, [selectedDate]);

  const [viewDate, setViewDate] = useState<Date>(initialDate);
  const [slideDirection, setSlideDirection] = useState<number>(0);

  const todayStr = useMemo(() => formatDateKey(new Date()), []);

  const year = viewDate.getFullYear();
  const month = viewDate.getMonth();

  const handlePrevMonth = () => {
    setSlideDirection(-1);
    setViewDate(new Date(year, month - 1, 1));
  };

  const handleNextMonth = () => {
    setSlideDirection(1);
    setViewDate(new Date(year, month + 1, 1));
  };

  const handleToday = () => {
    const today = new Date();
    setSlideDirection(today > viewDate ? 1 : -1);
    setViewDate(today);
    onDateSelect(todayStr);
  };

  const handleMonthChange = (newMonth: number) => {
    setSlideDirection(newMonth > month ? 1 : -1);
    setViewDate(new Date(year, newMonth, 1));
  };

  const handleYearChange = (newYear: number) => {
    setSlideDirection(newYear > year ? 1 : -1);
    setViewDate(new Date(newYear, month, 1));
  };

  const calendarGrid = useMemo(() => {
    const firstDayIndex = new Date(year, month, 1).getDay();
    const daysInCurrentMonth = new Date(year, month + 1, 0).getDate();
    const daysInPrevMonth = new Date(year, month, 0).getDate();

    const cells: {
      dateKey: string;
      dayNum: number;
      isCurrentMonth: boolean;
      isToday: boolean;
      isSelected: boolean;
      eventCount: number;
      targetDate: Date;
    }[] = [];

    // Preceding days
    for (let i = firstDayIndex - 1; i >= 0; i--) {
      const dayNum = daysInPrevMonth - i;
      const d = new Date(year, month - 1, dayNum);
      const dateKey = formatDateKey(d);
      cells.push({
        dateKey,
        dayNum,
        isCurrentMonth: false,
        isToday: dateKey === todayStr,
        isSelected: dateKey === selectedDate,
        eventCount: events[dateKey]?.length || 0,
        targetDate: d,
      });
    }

    // Current month days
    for (let i = 1; i <= daysInCurrentMonth; i++) {
      const d = new Date(year, month, i);
      const dateKey = formatDateKey(d);
      cells.push({
        dateKey,
        dayNum: i,
        isCurrentMonth: true,
        isToday: dateKey === todayStr,
        isSelected: dateKey === selectedDate,
        eventCount: events[dateKey]?.length || 0,
        targetDate: d,
      });
    }

    // Trailing days
    const totalCells = cells.length <= 35 ? 35 : 42;
    const remainingDays = totalCells - cells.length;
    for (let i = 1; i <= remainingDays; i++) {
      const d = new Date(year, month + 1, i);
      const dateKey = formatDateKey(d);
      cells.push({
        dateKey,
        dayNum: i,
        isCurrentMonth: false,
        isToday: dateKey === todayStr,
        isSelected: dateKey === selectedDate,
        eventCount: events[dateKey]?.length || 0,
        targetDate: d,
      });
    }

    return cells;
  }, [year, month, todayStr, selectedDate, events]);

  const monthEventCount = useMemo(() => {
    const monthPrefix = `${year}-${String(month + 1).padStart(2, '0')}`;
    return Object.keys(events).reduce((acc, dateKey) => {
      if (dateKey.startsWith(monthPrefix)) {
        return acc + (events[dateKey]?.length || 0);
      }
      return acc;
    }, 0);
  }, [events, year, month]);

  const currentYearNow = new Date().getFullYear();
  const yearOptions = useMemo(() => {
    const yrs: number[] = [];
    for (let y = currentYearNow - 3; y <= currentYearNow + 4; y++) {
      yrs.push(y);
    }
    return yrs;
  }, [currentYearNow]);

  return (
    <div className="full-calendar-container glass-card">
      <div className="full-calendar-header">
        <div className="calendar-title-group">
          <div className="calendar-selectors">
            <select
              value={month}
              onChange={(e) => handleMonthChange(parseInt(e.target.value))}
              className="calendar-select month-select"
              aria-label="Select month"
            >
              {MONTH_NAMES.map((mName, idx) => (
                <option key={mName} value={idx}>
                  {mName}
                </option>
              ))}
            </select>

            <select
              value={year}
              onChange={(e) => handleYearChange(parseInt(e.target.value))}
              className="calendar-select year-select"
              aria-label="Select year"
            >
              {yearOptions.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
          </div>

          {monthEventCount > 0 && (
            <span className="month-event-pill">
              {monthEventCount} {monthEventCount === 1 ? 'event' : 'events'}
            </span>
          )}
        </div>

        <div className="calendar-controls">
          <button
            type="button"
            onClick={handleToday}
            className="calendar-today-btn"
            title="Jump to today"
          >
            <RotateCcw size={13} style={{ marginRight: '4px' }} />
            Today
          </button>

          <button
            type="button"
            onClick={handlePrevMonth}
            className="calendar-nav-btn"
            title="Previous month"
            aria-label="Previous month"
          >
            <ChevronLeft size={18} />
          </button>

          <button
            type="button"
            onClick={handleNextMonth}
            className="calendar-nav-btn"
            title="Next month"
            aria-label="Next month"
          >
            <ChevronRight size={18} />
          </button>
        </div>
      </div>

      <div className="calendar-weekdays-grid">
        {WEEKDAYS.map((wd) => (
          <div key={wd} className="calendar-weekday-cell">
            {wd}
          </div>
        ))}
      </div>

      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={`${year}-${month}`}
          initial={{ opacity: 0, x: slideDirection * 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -slideDirection * 20 }}
          transition={{ duration: 0.18, ease: 'easeInOut' }}
          className="calendar-days-grid"
        >
          {calendarGrid.map((cell) => {
            const hasEvent = cell.eventCount > 0;

            return (
              <button
                key={cell.dateKey}
                type="button"
                onClick={() => {
                  if (!cell.isCurrentMonth) {
                    setViewDate(new Date(cell.targetDate.getFullYear(), cell.targetDate.getMonth(), 1));
                  }
                  onDateSelect(cell.dateKey);
                }}
                className={`calendar-day-cell ${cell.isCurrentMonth ? 'in-month' : 'out-month'} ${
                  cell.isSelected ? 'selected' : ''
                } ${cell.isToday ? 'today' : ''} ${hasEvent ? 'has-event' : ''}`}
                title={`${cell.dateKey}${hasEvent ? ` (${cell.eventCount} event${cell.eventCount > 1 ? 's' : ''})` : ''}`}
              >
                <span className="calendar-day-text">{cell.dayNum}</span>

                {hasEvent && (
                  <div className="calendar-event-indicators">
                    {Array.from({ length: Math.min(cell.eventCount, 3) }).map((_, i) => (
                      <span key={i} className="event-dot" />
                    ))}
                  </div>
                )}
              </button>
            );
          })}
        </motion.div>
      </AnimatePresence>

      <style>{`
        .full-calendar-container {
          width: 100%;
          border-radius: 20px;
          padding: 16px 18px 20px;
          margin-bottom: 24px;
          box-shadow: var(--shadow-premium);
          border: 1px solid var(--border-light);
          background: var(--bg-glass);
          backdrop-filter: blur(16px);
        }

        .full-calendar-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 16px;
          gap: 12px;
          flex-wrap: wrap;
        }

        .calendar-title-group {
          display: flex;
          align-items: center;
          gap: 10px;
          flex-wrap: wrap;
        }

        .calendar-selectors {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .calendar-select {
          background: rgba(255, 255, 255, 0.07);
          color: var(--text-primary);
          border: 1px solid var(--border-light);
          border-radius: 12px;
          padding: 6px 10px;
          font-family: var(--font-space-grotesk);
          font-size: 16px;
          font-weight: 700;
          cursor: pointer;
          outline: none;
          transition: all 0.2s ease;
        }

        .calendar-select:hover {
          border-color: rgba(var(--secondary-neon), 0.5);
          background: rgba(255, 255, 255, 0.12);
        }

        .calendar-select option {
          background: var(--bg-secondary, #1e1e1e);
          color: var(--text-primary, #fff);
          font-family: var(--font-inter);
          font-size: 14px;
        }

        .month-event-pill {
          font-size: 11px;
          font-weight: 600;
          color: rgb(22, 192, 122);
          background: rgba(22, 192, 122, 0.12);
          border: 1px solid rgba(22, 192, 122, 0.25);
          padding: 4px 10px;
          border-radius: 100px;
          letter-spacing: 0.3px;
        }

        .calendar-controls {
          display: flex;
          align-items: center;
          gap: 6px;
        }

        .calendar-today-btn {
          display: flex;
          align-items: center;
          background: rgba(255, 255, 255, 0.06);
          color: var(--text-secondary);
          border: 1px solid var(--border-light);
          padding: 6px 12px;
          border-radius: 10px;
          font-size: 12px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .calendar-today-btn:hover {
          color: var(--text-primary);
          background: rgba(var(--secondary-neon), 0.15);
          border-color: rgba(var(--secondary-neon), 0.4);
        }

        .calendar-nav-btn {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 34px;
          height: 34px;
          border-radius: 10px;
          background: rgba(255, 255, 255, 0.06);
          border: 1px solid var(--border-light);
          color: var(--text-primary);
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .calendar-nav-btn:hover {
          background: rgba(var(--secondary-neon), 0.2);
          border-color: rgba(var(--secondary-neon), 0.5);
          transform: translateY(-1px);
        }

        .calendar-weekdays-grid {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 6px;
          margin-bottom: 8px;
          text-align: center;
        }

        .calendar-weekday-cell {
          font-size: 12px;
          font-weight: 700;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: 0.5px;
          padding: 4px 0;
        }

        .calendar-days-grid {
          display: grid;
          grid-template-columns: repeat(7, 1fr);
          gap: 6px;
        }

        .calendar-day-cell {
          position: relative;
          aspect-ratio: 1;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          border-radius: 14px;
          border: 1px solid transparent;
          background: transparent;
          cursor: pointer;
          transition: all 0.18s cubic-bezier(0.4, 0, 0.2, 1);
          padding: 4px;
          user-select: none;
        }

        .calendar-day-cell.in-month {
          color: var(--text-primary);
        }

        .calendar-day-cell.out-month {
          color: var(--text-muted);
          opacity: 0.35;
        }

        .calendar-day-cell:hover {
          background: rgba(255, 255, 255, 0.08);
          border-color: rgba(var(--secondary-neon), 0.25);
          transform: translateY(-1px);
        }

        .calendar-day-cell.today {
          border-color: rgba(var(--secondary-neon), 0.5);
          background: rgba(var(--secondary-neon), 0.08);
        }

        .calendar-day-cell.today .calendar-day-text {
          color: rgb(var(--secondary-neon));
          font-weight: 800;
        }

        .calendar-day-cell.selected {
          background: linear-gradient(135deg, rgba(22, 192, 122, 0.95), rgba(16, 150, 95, 0.9)) !important;
          color: #ffffff !important;
          border-color: rgba(22, 192, 122, 0.8) !important;
          box-shadow: 0 4px 14px rgba(22, 192, 122, 0.45);
          transform: scale(1.04);
        }

        .calendar-day-cell.selected .calendar-day-text {
          color: #ffffff !important;
          font-weight: 800;
        }

        .calendar-day-cell.selected .event-dot {
          background: #ffffff !important;
        }

        .calendar-day-text {
          font-size: 14px;
          font-weight: 600;
          line-height: 1;
        }

        .calendar-event-indicators {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 2px;
          margin-top: 4px;
          height: 4px;
        }

        .event-dot {
          width: 4px;
          height: 4px;
          border-radius: 50%;
          background: rgb(22, 192, 122);
          box-shadow: 0 0 4px rgba(22, 192, 122, 0.6);
        }

        @media (max-width: 640px) {
          .full-calendar-container {
            padding: 12px;
          }
          .calendar-select {
            font-size: 14px;
            padding: 4px 8px;
          }
          .calendar-day-cell {
            border-radius: 10px;
          }
          .calendar-day-text {
            font-size: 12px;
          }
          .calendar-weekday-cell {
            font-size: 10px;
          }
        }
      `}</style>
    </div>
  );
};
