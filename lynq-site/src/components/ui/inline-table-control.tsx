import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Pencil, Trash2, Check, X } from 'lucide-react';

/* ─────────────────────────────────────────────
   Types
───────────────────────────────────────────── */
export interface TableItem {
  id: string;
  type: string;          // 'Expense' | 'Income'
  category: string;
  method: string;
  amount: string;
  description?: string;
  transaction_date?: string;
}

interface InlineTableControlProps {
  data: TableItem[];
  onUpdate?: (item: TableItem) => void;
  onDelete?: (id: string) => void;
  className?: string;
  isEditable?: boolean;
}

/* ─────────────────────────────────────────────
   Helpers
───────────────────────────────────────────── */
function formatINR(value: string | number) {
  const n = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(n)) return '—';
  return n.toLocaleString('en-IN');
}

function formatDate(iso?: string) {
  if (!iso) return null;
  const d = new Date(iso);
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

/* ─────────────────────────────────────────────
   Motion config — GPU-composited spring
───────────────────────────────────────────── */
const EXPAND_SPRING = {
  type: 'spring' as const,
  stiffness: 420,
  damping: 38,
  mass: 0.85,
};

const FADE_IN = {
  initial: { opacity: 0, y: 6 },
  animate: { opacity: 1, y: 0 },
  exit:    { opacity: 0, y: 4 },
  transition: { duration: 0.18, ease: [0.25, 0.46, 0.45, 0.94] as [number, number, number, number] },
};

/* ─────────────────────────────────────────────
   Single Row
───────────────────────────────────────────── */
interface RowProps {
  item: TableItem;
  isEditable: boolean;
  onEditSave: (updated: TableItem) => void;
  onEditDelete: (id: string) => void;
}

const LedgerRow: React.FC<RowProps> = ({ item, isEditable, onEditSave, onEditDelete }) => {
  const [isEditing, setIsEditing] = useState(false);
  const [draft, setDraft] = useState<TableItem>(item);
  const categoryRef = useRef<HTMLInputElement>(null);

  const isIncome = item.type === 'Income';

  // sync external data changes
  useEffect(() => {
    if (!isEditing) setDraft(item);
  }, [item, isEditing]);

  const openEdit = () => {
    setDraft({ ...item });
    setIsEditing(true);
    setTimeout(() => categoryRef.current?.focus(), 120);
  };

  const cancelEdit = () => {
    setDraft({ ...item });
    setIsEditing(false);
  };

  const saveEdit = () => {
    const amt = parseFloat(draft.amount);
    if (isNaN(amt) || amt <= 0) { alert('Amount must be a positive number.'); return; }
    if (!draft.category.trim())  { alert('Category cannot be empty.');        return; }
    if (!draft.method.trim())    { alert('Method/Source cannot be empty.');    return; }
    onEditSave(draft);
    setIsEditing(false);
  };

  const set = (field: keyof TableItem) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    setDraft(p => ({ ...p, [field]: e.target.value }));

  return (
    <motion.div
      layout
      transition={EXPAND_SPRING}
      className="ltc-row"
      data-editing={isEditing}
      style={{ willChange: 'transform' }}
    >
      {/* ── Display strip ── */}
      <div className="ltc-row__strip">
        {/* Col 1 — Type + Category */}
        <div className="ltc-col ltc-col--main">
          <span className={`ltc-type-badge ${isIncome ? 'ltc-type-badge--income' : 'ltc-type-badge--expense'}`}>
            {item.type}
          </span>
          <span className="ltc-category">{item.category}</span>
          {item.transaction_date && (
            <span className="ltc-date">{formatDate(item.transaction_date)}</span>
          )}
        </div>

        {/* Col 2 — Method */}
        <div className="ltc-col ltc-col--method">
          <span className="ltc-method">{item.method}</span>
        </div>

        {/* Col 3 — Amount */}
        <div className="ltc-col ltc-col--amount">
          <span className="ltc-currency">₹</span>
          <span className={`ltc-amount ${isIncome ? 'ltc-amount--income' : ''}`}>
            {formatINR(item.amount)}
          </span>
        </div>

        {/* Col 4 — Actions */}
        {isEditable && (
          <div className="ltc-col ltc-col--actions">
            <button
              className="ltc-btn ltc-btn--icon"
              onClick={openEdit}
              aria-label="Edit"
              title="Edit entry"
            >
              <Pencil size={15} strokeWidth={2} className="ltc-icon" />
            </button>
            <button
              className="ltc-btn ltc-btn--icon ltc-btn--danger"
              onClick={() => {
                if (window.confirm('Delete this entry?')) onEditDelete(item.id);
              }}
              aria-label="Delete"
              title="Delete entry"
            >
              <Trash2 size={15} strokeWidth={2} className="ltc-icon" />
            </button>
          </div>
        )}
      </div>

      {/* ── Expanded Edit Panel ── */}
      <AnimatePresence initial={false}>
        {isEditing && (
          <motion.div
            key="edit-panel"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={EXPAND_SPRING}
            style={{ overflow: 'hidden', willChange: 'height, opacity' }}
          >
            <motion.div
              className="ltc-edit-panel"
              {...FADE_IN}
            >
              {/* Row 1: Type + Category */}
              <div className="ltc-edit-row">
                <div className="ltc-edit-field ltc-edit-field--sm">
                  <label className="ltc-label">Type</label>
                  <select
                    className="ltc-input ltc-select"
                    value={draft.type}
                    onChange={set('type')}
                  >
                    <option value="Expense">Expense</option>
                    <option value="Income">Income</option>
                  </select>
                </div>

                <div className="ltc-edit-field ltc-edit-field--lg">
                  <label className="ltc-label">Category</label>
                  <input
                    ref={categoryRef}
                    className="ltc-input"
                    type="text"
                    value={draft.category}
                    onChange={set('category')}
                    placeholder="e.g. Equipment Purchase"
                  />
                </div>
              </div>

              {/* Row 2: Method + Amount */}
              <div className="ltc-edit-row">
                <div className="ltc-edit-field">
                  <label className="ltc-label">Method / Source</label>
                  <input
                    className="ltc-input"
                    type="text"
                    value={draft.method}
                    onChange={set('method')}
                    placeholder="e.g. Direct, Execom"
                  />
                </div>

                <div className="ltc-edit-field ltc-edit-field--sm">
                  <label className="ltc-label">Amount (₹)</label>
                  <input
                    className="ltc-input ltc-input--mono"
                    type="number"
                    min="0"
                    step="0.01"
                    value={draft.amount}
                    onChange={set('amount')}
                    placeholder="0.00"
                  />
                </div>
              </div>

              {/* Row 3: Description (optional) */}
              <div className="ltc-edit-row">
                <div className="ltc-edit-field" style={{ flex: 1 }}>
                  <label className="ltc-label">Description <span className="ltc-label-opt">(optional)</span></label>
                  <textarea
                    className="ltc-input ltc-textarea"
                    value={draft.description || ''}
                    onChange={set('description')}
                    placeholder="Additional notes…"
                    rows={2}
                  />
                </div>
              </div>

              {/* Row 4: Action buttons */}
              <motion.div
                className="ltc-edit-actions"
                initial={{ opacity: 0, y: 4 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.08, duration: 0.2 }}
              >
                <button
                  className="ltc-btn ltc-btn--cancel"
                  onClick={cancelEdit}
                >
                  <X size={14} strokeWidth={2.5} className="ltc-icon" />
                  Cancel
                </button>
                <button
                  className="ltc-btn ltc-btn--save"
                  onClick={saveEdit}
                >
                  <Check size={14} strokeWidth={2.5} className="ltc-icon" />
                  Save
                </button>
              </motion.div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      <style>{`
        /* ── Row container ── */
        .ltc-row {
          display: flex;
          flex-direction: column;
          border-bottom: 1px solid var(--ltc-divider, rgba(0,0,0,0.055));
          transition: background 0.18s ease;
        }
        .ltc-row:last-child { border-bottom: none; }
        .ltc-row:hover:not([data-editing='true']) {
          background: rgba(217, 125, 85, 0.025);
        }
        .ltc-row[data-editing='true'] {
          background: rgba(217, 125, 85, 0.035);
          border-bottom-color: transparent;
        }

        /* ── Strip (always-visible row) ── */
        .ltc-row__strip {
          display: grid;
          grid-template-columns: 1.7fr 1fr 1fr auto;
          align-items: center;
          gap: 16px;
          padding: 14px 20px;
        }

        /* ── Columns ── */
        .ltc-col { display: flex; flex-direction: column; gap: 2px; }
        .ltc-col--method { flex-direction: row; align-items: center; }
        .ltc-col--amount { flex-direction: row; align-items: baseline; gap: 1px; }
        .ltc-col--actions {
          flex-direction: row;
          align-items: center;
          gap: 6px;
        }

        /* ── Type badge ── */
        .ltc-type-badge {
          font-family: 'Space Grotesk', sans-serif;
          font-size: 11.5px;
          font-weight: 700;
          letter-spacing: 0.3px;
          padding: 2px 8px;
          border-radius: 20px;
          display: inline-flex;
          align-self: flex-start;
          margin-bottom: 2px;
        }
        .ltc-type-badge--expense {
          background: rgba(217, 125, 85, 0.12);
          color: rgb(197, 100, 55);
        }
        .ltc-type-badge--income {
          background: rgba(22, 192, 122, 0.12);
          color: rgb(16, 162, 102);
        }

        /* ── Text elements ── */
        .ltc-category {
          font-family: 'Space Grotesk', sans-serif;
          font-size: 13.5px;
          font-weight: 600;
          color: var(--text-primary, #141414);
          line-height: 1.3;
        }
        .ltc-date {
          font-size: 11px;
          color: var(--text-muted, #888);
          font-family: 'Inter', sans-serif;
          letter-spacing: 0.1px;
        }
        .ltc-method {
          font-family: 'Inter', sans-serif;
          font-size: 13px;
          font-weight: 500;
          color: var(--text-secondary, #4a4a4a);
        }
        .ltc-currency {
          font-family: 'Inter', sans-serif;
          font-size: 11px;
          color: var(--text-muted, #888);
          margin-right: 1px;
          line-height: 1;
          align-self: center;
        }
        .ltc-amount {
          font-family: 'Space Grotesk', sans-serif;
          font-size: 14px;
          font-weight: 700;
          color: var(--text-primary, #141414);
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.2px;
        }
        .ltc-amount--income { color: rgb(16, 162, 102); }

        /* ── Icon Buttons ── */
        /* Force SVG icons to always render at their correct size */
        .ltc-icon {
          display: inline-block !important;
          width: 15px !important;
          height: 15px !important;
          min-width: 15px !important;
          flex-shrink: 0 !important;
          vertical-align: middle;
        }

        .ltc-btn--icon {
          display: flex;
          align-items: center;
          justify-content: center;
          width: 30px;
          height: 30px;
          border-radius: 8px;
          color: #888;
          background: transparent;
          border: none;
          cursor: pointer;
          opacity: 0.5;
          transition: background 0.15s ease, color 0.15s ease, transform 0.12s ease, opacity 0.15s ease;
        }
        .ltc-btn--icon:hover {
          background: rgba(0,0,0,0.06);
          color: #222222;
          opacity: 1;
          transform: scale(1.08);
        }
        .ltc-btn--icon:active { transform: scale(0.93); }
        .ltc-row:hover .ltc-btn--icon { opacity: 0.8; }
        .ltc-btn--danger:hover {
          background: rgba(239,68,68,0.08) !important;
          color: rgb(215, 50, 50) !important;
          opacity: 1 !important;
        }

        /* ── Expanded edit panel ── */
        .ltc-edit-panel {
          padding: 0 20px 18px 20px;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        .ltc-edit-row {
          display: flex;
          gap: 12px;
          flex-wrap: wrap;
        }
        .ltc-edit-field {
          display: flex;
          flex-direction: column;
          gap: 5px;
          flex: 1;
          min-width: 120px;
        }
        .ltc-edit-field--sm { flex: 0 0 130px; }
        .ltc-edit-field--lg { flex: 2; }

        /* ── Labels ── */
        .ltc-label {
          font-family: 'Space Grotesk', sans-serif;
          font-size: 10.5px;
          font-weight: 700;
          letter-spacing: 0.6px;
          text-transform: uppercase;
          color: var(--text-muted, #888);
        }
        .ltc-label-opt {
          font-weight: 400;
          text-transform: none;
          letter-spacing: 0;
          font-size: 10px;
        }

        /* ── Inputs ── */
        .ltc-input {
          font-family: 'Inter', sans-serif;
          font-size: 13px;
          font-weight: 500;
          padding: 9px 12px;
          border-radius: 10px;
          border: 1.5px solid rgba(217,125,85,0.15);
          background: var(--bg-primary, #f8f9fa);
          color: var(--text-primary, #141414);
          outline: none;
          transition: border-color 0.15s ease, box-shadow 0.15s ease;
          width: 100%;
        }
        .ltc-input:focus {
          border-color: rgba(217,125,85,0.5);
          box-shadow: 0 0 0 3px rgba(217,125,85,0.08);
        }
        .ltc-select {
          cursor: pointer;
          appearance: none;
          background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23888' stroke-width='2.5'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
          background-repeat: no-repeat;
          background-position: right 10px center;
          padding-right: 30px;
        }
        .ltc-input--mono {
          font-family: 'Space Grotesk', sans-serif;
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
        .ltc-textarea {
          resize: none;
          line-height: 1.5;
        }

        /* ── Save / Cancel buttons ── */
        .ltc-edit-actions {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          gap: 8px;
          padding-top: 4px;
        }
        .ltc-btn {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 8px 16px;
          border-radius: 10px;
          font-family: 'Space Grotesk', sans-serif;
          font-size: 13px;
          font-weight: 700;
          cursor: pointer;
          border: none;
          transition: transform 0.12s ease, box-shadow 0.15s ease, background 0.15s ease;
        }
        .ltc-btn:active { transform: scale(0.95); }

        .ltc-btn--cancel {
          background: rgba(0,0,0,0.05);
          color: var(--text-secondary, #4a4a4a);
        }
        .ltc-btn--cancel:hover {
          background: rgba(0,0,0,0.09);
        }

        .ltc-btn--save {
          background: rgb(22, 192, 122);
          color: #ffffff;
          box-shadow: 0 4px 14px rgba(22,192,122,0.28);
        }
        .ltc-btn--save:hover {
          box-shadow: 0 6px 20px rgba(22,192,122,0.38);
          transform: translateY(-1px);
        }
        .ltc-btn--save:active {
          transform: translateY(0) scale(0.96);
          box-shadow: 0 2px 8px rgba(22,192,122,0.2);
        }
      `}</style>
    </motion.div>
  );
};

/* ─────────────────────────────────────────────
   Main Export — InlineTableControl
───────────────────────────────────────────── */
export const InlineTableControl: React.FC<InlineTableControlProps> = ({
  data,
  onUpdate,
  onDelete,
  className = '',
  isEditable = true,
}) => {
  const [items, setItems] = useState<TableItem[]>(data);

  useEffect(() => {
    setItems(data);
  }, [data]);

  const handleSave = (updated: TableItem) => {
    setItems(prev => prev.map(i => (i.id === updated.id ? updated : i)));
    onUpdate?.(updated);
  };

  const handleDelete = (id: string) => {
    setItems(prev => prev.filter(i => i.id !== id));
    onDelete?.(id);
  };

  if (items.length === 0) {
    return (
      <div className={`ltc-empty ${className}`}>
        No transactions recorded yet.
        <style>{`
          .ltc-empty {
            padding: 40px 20px;
            text-align: center;
            font-family: 'Inter', sans-serif;
            font-size: 14px;
            color: var(--text-muted, #888);
          }
        `}</style>
      </div>
    );
  }

  return (
    <div className={`ltc-root ${className}`}>
      {/* Header */}
      <div className="ltc-header">
        <div className="ltc-header__cell ltc-header__cell--main">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg>
          Expense / Income
        </div>
        <div className="ltc-header__cell">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"/><path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"/><path d="M4 22h16"/><path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"/><path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"/><path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"/></svg>
          Method
        </div>
        <div className="ltc-header__cell">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/></svg>
          Amount
        </div>
        {isEditable && <div className="ltc-header__cell ltc-header__cell--actions" />}
      </div>

      {/* Rows */}
      <div className="ltc-body">
        {items.map(item => (
          <LedgerRow
            key={item.id}
            item={item}
            isEditable={isEditable}
            onEditSave={handleSave}
            onEditDelete={handleDelete}
          />
        ))}
      </div>

      <style>{`
        /* ── Root: borderless container ── */
        .ltc-root {
          width: 100%;
          border-radius: 16px;
          overflow: hidden;
          background: var(--bg-secondary, #ffffff);
          /* No outer border per spec */
        }

        /* ── Column header ── */
        .ltc-header {
          display: grid;
          grid-template-columns: 1.7fr 1fr 1fr auto;
          gap: 16px;
          padding: 11px 20px;
          border-bottom: 1.5px solid rgba(217,125,85,0.1);
          background: rgba(217,125,85,0.028);
        }
        .ltc-header__cell {
          display: flex;
          align-items: center;
          gap: 6px;
          font-family: 'Space Grotesk', sans-serif;
          font-size: 10.5px;
          font-weight: 800;
          letter-spacing: 0.8px;
          text-transform: uppercase;
          color: var(--text-muted, #888);
          user-select: none;
        }
        .ltc-header__cell--main { /* already first */ }
        .ltc-header__cell--actions { min-width: 66px; }

        /* ── Body ── */
        .ltc-body { display: flex; flex-direction: column; }
      `}</style>
    </div>
  );
};
