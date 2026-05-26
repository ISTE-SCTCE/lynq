import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence, LayoutGroup } from 'motion/react';
import { Pencil, X, Check, Trash } from 'lucide-react';
import { GoStack } from 'react-icons/go';
import { BsArrowUpRightSquare } from 'react-icons/bs';
import { FaRegCreditCard } from 'react-icons/fa6';

export interface TableItem {
  id: string;
  type: string; // 'Expense' | 'Income'
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

export const InlineTableControl: React.FC<InlineTableControlProps> = ({
  data,
  onUpdate,
  onDelete,
  className = '',
  isEditable = true,
}) => {
  const [items, setItems] = useState<TableItem[]>(data);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValues, setEditValues] = useState<TableItem | null>(null);

  useEffect(() => {
    setItems(data);
  }, [data]);

  const handleDone = () => {
    if (editValues) {
      // Validate inputs
      const amountVal = parseFloat(editValues.amount);
      if (isNaN(amountVal) || amountVal <= 0) {
        alert("Validation Error: Amount must be a valid positive number.");
        return;
      }
      if (!editValues.category.trim()) {
        alert("Validation Error: Category cannot be empty.");
        return;
      }
      if (!editValues.method.trim()) {
        alert("Validation Error: Method/Source cannot be empty.");
        return;
      }

      const updatedItems = items.map((item) =>
        item.id === editValues.id ? editValues : item,
      );
      setItems(updatedItems);
      onUpdate?.(editValues);
      setEditingId(null);
      setEditValues(null);
    }
  };

  const springConfig = {
    type: 'spring' as const,
    stiffness: 380,
    damping: 32,
  };

  return (
    <div 
      className={`w-full rounded-2xl border shadow-sm ${className}`} 
      style={{ 
        minWidth: '100%',
        backgroundColor: 'var(--bg-secondary)',
        borderColor: 'var(--border-light)',
        color: 'var(--text-primary)',
        overflow: 'hidden'
      }}
    >
      {/* HEADER GRID */}
      <div 
        className="grid grid-cols-[1.5fr_1fr_1fr_60px] gap-4 px-6 py-4 border-b font-semibold uppercase tracking-wider text-[11px]"
        style={{ 
          borderColor: 'var(--border-light)',
          color: 'var(--text-secondary)',
          backgroundColor: 'rgba(0, 0, 0, 0.01)'
        }}
      >
        <div className="flex items-center gap-2">
          <FaRegCreditCard size={14} /> Expense
        </div>
        <div className="flex items-center gap-2">
          <GoStack size={14} /> Method
        </div>
        <div className="flex items-center gap-2 justify-end sm:justify-start">
          <BsArrowUpRightSquare size={14} /> Amount
        </div>
        <div></div>
      </div>

      {/* BODY ROWS */}
      <LayoutGroup>
        <div className="flex flex-col">
          {items.map((item) => {
            const isEditing = editingId === item.id;
            const isIncome = item.type === 'Income';

            return (
              <motion.div 
                key={item.id}
                layout
                transition={springConfig}
                className="grid grid-cols-[1.5fr_1fr_1fr_60px] gap-4 px-6 py-4 border-b items-center transition-colors duration-150"
                style={{ 
                  borderColor: 'var(--border-light)',
                }}
                onMouseEnter={(e) => {
                  if (!isEditing) e.currentTarget.style.backgroundColor = 'rgba(217, 125, 85, 0.01)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = 'transparent';
                }}
              >
                <AnimatePresence mode="wait">
                  {isEditing ? (
                    <>
                      {/* EDITING MODE */}
                      <motion.div 
                        key={`edit-col1-${item.id}`}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0, x: -8 }}
                        transition={{ duration: 0.12 }}
                        className="flex flex-col gap-1.5 max-w-[220px]"
                      >
                        <select
                          value={editValues?.type || 'Expense'}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, type: e.target.value } : null
                            )
                          }
                          className="w-full border rounded-lg px-2.5 py-1.5 text-xs outline-none transition-all focus:ring-2 focus:ring-emerald-500/20"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'var(--border-light)',
                            color: 'var(--text-primary)'
                          }}
                        >
                          <option value="Expense" style={{ color: '#000' }}>Expense</option>
                          <option value="Income" style={{ color: '#000' }}>Income</option>
                        </select>
                        <input
                          type="text"
                          value={editValues?.category || ''}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, category: e.target.value } : null
                            )
                          }
                          placeholder="Category"
                          className="w-full border rounded-lg px-2.5 py-1.5 text-xs font-bold outline-none transition-all focus:ring-2 focus:ring-emerald-500/20"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'var(--border-light)',
                            color: 'var(--text-primary)'
                          }}
                        />
                      </motion.div>

                      <motion.div
                        key={`edit-col2-${item.id}`}
                        initial={{ opacity: 0, scale: 0.96 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0.96 }}
                        transition={{ duration: 0.12 }}
                      >
                        <input
                          type="text"
                          value={editValues?.method || ''}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, method: e.target.value } : null
                            )
                          }
                          placeholder="Method"
                          className="w-full border rounded-lg px-2.5 py-1.5 text-xs outline-none transition-all focus:ring-2 focus:ring-emerald-500/20 max-w-[150px]"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'var(--border-light)',
                            color: 'var(--text-primary)'
                          }}
                        />
                      </motion.div>

                      <motion.div
                        key={`edit-col3-${item.id}`}
                        initial={{ opacity: 0, scale: 0.96 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0.96 }}
                        transition={{ duration: 0.12 }}
                      >
                        <input
                          type="number"
                          value={editValues?.amount || ''}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, amount: e.target.value } : null
                            )
                          }
                          placeholder="Amount"
                          className="w-full border rounded-lg px-2.5 py-1.5 text-xs font-bold outline-none transition-all focus:ring-2 focus:ring-emerald-500/20 text-right sm:text-left max-w-[120px]"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'var(--border-light)',
                            color: 'var(--text-primary)'
                          }}
                        />
                      </motion.div>

                      <motion.div 
                        key={`edit-col4-${item.id}`}
                        initial={{ opacity: 0, scale: 0.85 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0.85 }}
                        transition={springConfig}
                        className="flex items-center gap-1.5 justify-end"
                      >
                        <button
                          onClick={() => {
                            setEditingId(null);
                            setEditValues(null);
                          }}
                          className="p-1.5 rounded-lg flex items-center justify-center transition-all hover:bg-neutral-100 dark:hover:bg-neutral-800"
                          style={{ color: 'var(--text-secondary)' }}
                          title="Cancel"
                        >
                          <X size={15} />
                        </button>
                        <button
                          onClick={handleDone}
                          className="p-1.5 rounded-lg text-white flex items-center justify-center transition-all shadow-sm hover:scale-105 active:scale-95"
                          style={{ backgroundColor: 'rgb(22, 192, 122)' }}
                          title="Save"
                        >
                          <Check size={15} />
                        </button>
                      </motion.div>
                    </>
                  ) : (
                    <>
                      {/* DISPLAY MODE */}
                      <motion.div 
                        key={`display-col1-${item.id}`}
                        layoutId={`type-cat-${item.id}`}
                        className="flex flex-col gap-0.5"
                      >
                        <motion.span 
                          layoutId={`type-txt-${item.id}`}
                          className="font-bold text-sm tracking-wide" 
                          style={{ color: 'var(--text-primary)' }}
                        >
                          {item.type}
                        </motion.span>
                        <motion.span 
                          layoutId={`cat-txt-${item.id}`}
                          className="text-xs font-normal" 
                          style={{ color: 'var(--text-secondary)' }}
                        >
                          {item.category}
                          {item.transaction_date && ` • ${new Date(item.transaction_date).toLocaleDateString()}`}
                        </motion.span>
                      </motion.div>

                      <motion.span 
                        key={`display-col2-${item.id}`}
                        layoutId={`method-txt-${item.id}`}
                        className="font-semibold text-sm" 
                        style={{ color: 'var(--text-secondary)' }}
                      >
                        {item.method}
                      </motion.span>

                      <motion.div 
                        key={`display-col3-${item.id}`}
                        layoutId={`amount-container-${item.id}`}
                        className="font-bold text-sm text-right sm:text-left"
                      >
                        <span className="font-normal mr-0.5" style={{ color: 'var(--text-muted)' }}>₹</span>
                        <span 
                          className="font-bold"
                          style={{ color: isIncome ? 'rgb(22, 192, 122)' : 'var(--text-primary)' }}
                        >
                          {parseFloat(item.amount).toLocaleString('en-IN')}
                        </span>
                      </motion.div>

                      <motion.div 
                        key={`display-col4-${item.id}`}
                        layoutId={`actions-container-${item.id}`}
                        className="flex items-center gap-3 justify-end"
                      >
                        {isEditable ? (
                          <>
                            <button
                              title="Edit"
                              onClick={() => {
                                setEditValues({ ...item });
                                setEditingId(item.id);
                              }}
                              className="transition-all hover:scale-115 active:scale-90"
                              style={{ color: 'var(--text-muted)' }}
                              onMouseEnter={(e) => e.currentTarget.style.color = 'var(--text-primary)'}
                              onMouseLeave={(e) => e.currentTarget.style.color = 'var(--text-muted)'}
                            >
                              <Pencil size={15} strokeWidth={2} />
                            </button>
                            {onDelete && (
                              <button
                                title="Delete"
                                onClick={() => {
                                  if (window.confirm("Are you sure you want to delete this entry?")) {
                                    onDelete(item.id);
                                  }
                                }}
                                className="transition-all hover:scale-115 active:scale-90"
                                style={{ color: 'var(--text-muted)' }}
                                onMouseEnter={(e) => e.currentTarget.style.color = 'var(--accent-red)'}
                                onMouseLeave={(e) => e.currentTarget.style.color = 'var(--text-muted)'}
                              >
                                <Trash size={15} strokeWidth={2} />
                              </button>
                            )}
                          </>
                        ) : (
                          <div style={{ width: '15px' }} />
                        )}
                      </motion.div>
                    </>
                  )}
                </AnimatePresence>
              </motion.div>
            );
          })}
        </div>
      </LayoutGroup>
    </div>
  );
};
