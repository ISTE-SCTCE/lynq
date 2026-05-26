import React, { useState, useEffect } from 'react';
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

  return (
    <div 
      className={`w-full overflow-x-auto rounded-2xl border shadow-sm ${className}`} 
      style={{ 
        minWidth: '100%',
        backgroundColor: 'var(--bg-secondary)',
        borderColor: 'var(--border-light)',
        color: 'var(--text-primary)'
      }}
    >
      <table className="w-full border-collapse text-left text-sm" style={{ color: 'var(--text-primary)' }}>
        <thead>
          <tr 
            className="border-b font-semibold uppercase tracking-wider text-[11px]"
            style={{ 
              borderColor: 'var(--border-light)',
              color: 'var(--text-secondary)',
              backgroundColor: 'rgba(0, 0, 0, 0.01)'
            }}
          >
            <th className="py-4 px-6">
              <span className="flex items-center gap-2">
                <FaRegCreditCard size={16} /> Expense
              </span>
            </th>
            <th className="py-4 px-6">
              <span className="flex items-center gap-2">
                <GoStack size={16} /> Method
              </span>
            </th>
            <th className="py-4 px-6 text-right sm:text-left">
              <span className="flex items-center gap-2 justify-end sm:justify-start">
                <BsArrowUpRightSquare size={16} /> Amount
              </span>
            </th>
            <th className="py-4 px-6 text-right"></th>
          </tr>
        </thead>
        <tbody>
          {items.map((item) => {
            const isEditing = editingId === item.id;
            const isIncome = item.type === 'Income';

            return (
              <tr 
                key={item.id} 
                className="border-b transition-colors duration-150"
                style={{ 
                  borderColor: 'var(--border-light)',
                }}
              >
                {isEditing ? (
                  <>
                    {/* EDITING ROW */}
                    <td className="py-3 px-6">
                      <div className="flex flex-col gap-1.5 max-w-[220px]">
                        {/* Dynamic selector for type (Expense/Income) */}
                        <select
                          value={editValues?.type || 'Expense'}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, type: e.target.value } : null
                            )
                          }
                          className="w-full border rounded-lg px-2 py-1 text-xs outline-none"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'rgba(217, 125, 85, 0.15)',
                            color: 'var(--text-primary)'
                          }}
                        >
                          <option value="Expense" style={{ color: '#000' }}>Expense</option>
                          <option value="Income" style={{ color: '#000' }}>Income</option>
                        </select>
                        {/* Text input for Category */}
                        <input
                          type="text"
                          value={editValues?.category || ''}
                          onChange={(e) =>
                            setEditValues((prev) =>
                              prev ? { ...prev, category: e.target.value } : null
                            )
                          }
                          placeholder="Category"
                          className="w-full border rounded-lg px-2 py-1 text-xs font-bold outline-none"
                          style={{
                            backgroundColor: 'var(--bg-primary)',
                            borderColor: 'rgba(217, 125, 85, 0.15)',
                            color: 'var(--text-primary)'
                          }}
                        />
                      </div>
                    </td>
                    <td className="py-3 px-6">
                      <input
                        type="text"
                        value={editValues?.method || ''}
                        onChange={(e) =>
                          setEditValues((prev) =>
                            prev ? { ...prev, method: e.target.value } : null
                          )
                        }
                        placeholder="Method/Source"
                        className="w-full border rounded-lg px-2 py-1 text-xs outline-none max-w-[150px]"
                        style={{
                          backgroundColor: 'var(--bg-primary)',
                          borderColor: 'rgba(217, 125, 85, 0.15)',
                          color: 'var(--text-primary)'
                        }}
                      />
                    </td>
                    <td className="py-3 px-6">
                      <input
                        type="number"
                        value={editValues?.amount || ''}
                        onChange={(e) =>
                          setEditValues((prev) =>
                            prev ? { ...prev, amount: e.target.value } : null
                          )
                        }
                        placeholder="Amount"
                        className="w-full border rounded-lg px-2 py-1 text-xs font-bold outline-none text-right sm:text-left max-w-[120px]"
                        style={{
                          backgroundColor: 'var(--bg-primary)',
                          borderColor: 'rgba(217, 125, 85, 0.15)',
                          color: 'var(--text-primary)'
                        }}
                      />
                    </td>
                    <td className="py-3 px-6 text-right">
                      <div className="flex items-center gap-2 justify-end">
                        <button
                          onClick={() => {
                            setEditingId(null);
                            setEditValues(null);
                          }}
                          className="p-1 rounded-lg transition-colors flex items-center justify-center"
                          style={{
                            backgroundColor: 'rgba(0, 0, 0, 0.05)',
                            color: 'var(--text-secondary)'
                          }}
                          title="Cancel"
                        >
                          <X size={14} />
                        </button>
                        <button
                          onClick={handleDone}
                          className="p-1 rounded-lg text-white transition-colors flex items-center justify-center"
                          style={{
                            backgroundColor: 'rgb(22, 192, 122)'
                          }}
                          title="Save"
                        >
                          <Check size={14} />
                        </button>
                      </div>
                    </td>
                  </>
                ) : (
                  <>
                    {/* DISPLAY ROW */}
                    <td className="py-4 px-6">
                      <div className="flex flex-col gap-1">
                        <span className="font-bold text-sm tracking-wide" style={{ color: 'var(--text-primary)' }}>
                          {item.type}
                        </span>
                        <span className="text-xs font-normal" style={{ color: 'var(--text-secondary)' }}>
                          {item.category}
                          {item.transaction_date && ` • ${new Date(item.transaction_date).toLocaleDateString()}`}
                        </span>
                      </div>
                    </td>
                    <td className="py-4 px-6 font-semibold text-sm" style={{ color: 'var(--text-secondary)' }}>
                      {item.method}
                    </td>
                    <td className="py-4 px-6 font-bold text-sm text-right sm:text-left">
                      <span className="font-normal mr-0.5" style={{ color: 'var(--text-muted)' }}>₹</span>
                      <span 
                        className="font-bold"
                        style={{ color: isIncome ? 'rgb(22, 192, 122)' : 'var(--text-primary)' }}
                      >
                        {parseFloat(item.amount).toLocaleString('en-IN')}
                      </span>
                    </td>
                    <td className="py-4 px-6 text-right">
                      {isEditable ? (
                        <div className="flex items-center gap-3 justify-end">
                          <button
                            title="Edit"
                            onClick={() => {
                              setEditValues({ ...item });
                              setEditingId(item.id);
                            }}
                            className="transition-colors active:scale-110"
                            style={{ color: 'var(--text-muted)' }}
                          >
                            <Pencil size={16} strokeWidth={2} />
                          </button>
                          {onDelete && (
                            <button
                              title="Delete"
                              onClick={() => {
                                if (window.confirm("Are you sure you want to delete this entry?")) {
                                  onDelete(item.id);
                                }
                              }}
                              className="transition-colors active:scale-110"
                              style={{ color: 'var(--text-muted)' }}
                            >
                              <Trash size={16} strokeWidth={2} />
                            </button>
                          )}
                        </div>
                      ) : (
                        <div style={{ width: '16px' }} />
                      )}
                    </td>
                  </>
                )}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
};

