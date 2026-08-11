// src/screens/events/CertificateTemplateCalibrator.tsx
// Visual calibration tool: execom uploads a background image, clicks where
// each field should go, adjusts size/align/color, saves coordinates to
// events.certificate_field_positions. No more guessing pixel numbers.

import React, { useState, useEffect, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Upload, Save, Trash2, Loader, Image as ImageIcon } from 'lucide-react';
import { supabase } from '../../core/supabase-client';
import { GlassCard } from '../../shared/components/GlassCard';
import { NavBar } from '../../shared/components/NavBar';

type FieldKey =
  | 'student_name'
  | 'event_name'
  | 'event_date'
  | 'certificate_id'
  | 'coordinator_name'
  | 'chair_name';

type FieldConfig = {
  x: number;
  y: number; // stored in PDF coordinate space (origin bottom-left)
  size: number;
  align: 'left' | 'center' | 'right';
  font: 'Helvetica' | 'HelveticaBold' | 'TimesRoman' | 'TimesRomanBold';
  color: string;
};

const FIELD_LABELS: Record<FieldKey, string> = {
  student_name:     'Student Name',
  event_name:       'Event Name',
  event_date:       'Event Date',
  certificate_id:   'Certificate ID',
  coordinator_name: 'Coordinator Name',
  chair_name:       'Chair Name',
};

const FIELD_ORDER: FieldKey[] = [
  'student_name', 'event_name', 'event_date',
  'certificate_id', 'coordinator_name', 'chair_name',
];

const DEFAULT_FIELD: Omit<FieldConfig, 'x' | 'y'> = {
  size:  20,
  align: 'center',
  font:  'HelveticaBold',
  color: '#1B2A4A',
};

export const CertificateTemplateCalibrator: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving]   = useState(false);
  const [eventTitle, setEventTitle] = useState('');

  const [imageUrl,      setImageUrl]      = useState<string | null>(null);
  const [imageFile,     setImageFile]     = useState<File | null>(null);
  const [imgNaturalSize, setImgNaturalSize] = useState({ width: 0, height: 0 });

  const [fields,      setFields]      = useState<Partial<Record<FieldKey, FieldConfig>>>({});
  const [activeField, setActiveField] = useState<FieldKey>('student_name');

  const imgRef = useRef<HTMLImageElement>(null);

  // ── Load event ──────────────────────────────────────────────────────────────
  useEffect(() => {
    const load = async () => {
      if (!id) return;
      setIsLoading(true);
      const { data, error } = await supabase
        .from('events')
        .select('title, certificate_image_url, certificate_field_positions')
        .eq('id', parseInt(id))
        .maybeSingle();

      if (!error && data) {
        setEventTitle(data.title ?? '');
        if (data.certificate_image_url)     setImageUrl(data.certificate_image_url);
        if (data.certificate_field_positions) {
          setFields(data.certificate_field_positions as Record<FieldKey, FieldConfig>);
        }
      }
      setIsLoading(false);
    };
    load();
  }, [id]);

  // ── File picker ──────────────────────────────────────────────────────────────
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setImageFile(file);
    setImageUrl(URL.createObjectURL(file));
  };

  // ── Upload background image → certificate_templates bucket ───────────────────
  const handleUploadImage = async () => {
    if (!imageFile || !id) return;
    setIsSaving(true);
    try {
      const ext  = imageFile.name.split('.').pop() || 'png';
      const path = `${id}/background_${Date.now()}.${ext}`;

      const { error: uploadErr } = await supabase.storage
        .from('certificate_templates')
        .upload(path, imageFile, { contentType: imageFile.type, upsert: true });

      if (uploadErr) throw uploadErr;

      const { data: { publicUrl } } = supabase.storage
        .from('certificate_templates')
        .getPublicUrl(path);

      setImageUrl(publicUrl);
      setImageFile(null); // clear pending file — now using the persisted public URL

      const { error: updateErr } = await supabase
        .from('events')
        .update({
          certificate_template_type: 'image',
          certificate_image_url:     publicUrl,
        })
        .eq('id', parseInt(id));

      if (updateErr) throw updateErr;

      alert('Template image uploaded! Now click on the preview to place each field.');
    } catch (e: any) {
      alert('Upload failed: ' + e.message);
    } finally {
      setIsSaving(false);
    }
  };

  // ── Click-to-place handler ───────────────────────────────────────────────────
  // Converts displayed-pixel coords → natural-image pixel coords
  // → PDF coordinate space (y-flipped, origin bottom-left).
  const handleImageClick = (e: React.MouseEvent<HTMLImageElement>) => {
    if (!imgRef.current) return;
    const rect   = imgRef.current.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const clickY = e.clientY - rect.top;

    const scaleX = imgRef.current.naturalWidth  / rect.width;
    const scaleY = imgRef.current.naturalHeight / rect.height;

    const naturalX = clickX * scaleX;
    const naturalY = clickY * scaleY;

    // PDF origin is bottom-left; image origin is top-left → flip Y
    const pdfX = Math.round(naturalX);
    const pdfY = Math.round(imgRef.current.naturalHeight - naturalY);

    setFields((prev) => ({
      ...prev,
      [activeField]: {
        ...DEFAULT_FIELD,
        ...(prev[activeField] ?? {}),
        x: pdfX,
        y: pdfY,
      },
    }));
  };

  const handleImageLoad = () => {
    if (imgRef.current) {
      setImgNaturalSize({
        width:  imgRef.current.naturalWidth,
        height: imgRef.current.naturalHeight,
      });
    }
  };

  // ── Field property updates ───────────────────────────────────────────────────
  const updateFieldProp = <K extends keyof FieldConfig>(
    field: FieldKey,
    prop: K,
    value: FieldConfig[K]
  ) => {
    setFields((prev) => {
      const existing = prev[field];
      if (!existing) return prev;
      return { ...prev, [field]: { ...existing, [prop]: value } };
    });
  };

  const clearField = (field: FieldKey) => {
    setFields((prev) => {
      const next = { ...prev };
      delete next[field];
      return next;
    });
  };

  // ── Save field positions ─────────────────────────────────────────────────────
  const handleSave = async () => {
    if (!id) return;
    setIsSaving(true);
    try {
      const { error } = await supabase
        .from('events')
        .update({ certificate_field_positions: fields })
        .eq('id', parseInt(id));

      if (error) throw error;
      alert('Field positions saved! Certificates will use this layout going forward.');
    } catch (e: any) {
      alert('Save failed: ' + e.message);
    } finally {
      setIsSaving(false);
    }
  };

  // ── Convert stored PDF coords → display pixel position for marker overlay ────
  const markerDisplayPos = (
    config: FieldConfig,
    displayWidth: number,
    displayHeight: number
  ) => {
    const scaleX = displayWidth  / (imgNaturalSize.width  || 1);
    const scaleY = displayHeight / (imgNaturalSize.height || 1);
    return {
      left: config.x * scaleX,
      top:  (imgNaturalSize.height - config.y) * scaleY,
    };
  };

  // ── Loading state ────────────────────────────────────────────────────────────
  if (isLoading) {
    return (
      <div style={{ height: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '12px' }}>
        <Loader size={32} className="spinner" />
        <span>Loading template...</span>
      </div>
    );
  }

  const activeConfig = fields[activeField];

  return (
    <div style={{ padding: '16px 20px', minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      {/* Header */}
      <header style={{ display: 'flex', alignItems: 'center', height: '60px', marginBottom: '16px' }}>
        <button
          onClick={() => navigate(-1)}
          style={{ background: 'none', border: 'none', color: 'var(--text-primary)', cursor: 'pointer', marginRight: '16px' }}
        >
          <ArrowLeft size={20} />
        </button>
        <h2 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 800, fontSize: '20px', margin: 0 }}>
          Certificate Template — {eventTitle}
        </h2>
      </header>

      {/* Step 1: Upload background image */}
      <GlassCard padding="20px" style={{ marginBottom: '16px' }}>
        <h3 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '16px', margin: '0 0 12px 0', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <ImageIcon size={18} /> Background Image
        </h3>
        <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 12px 0' }}>
          Upload a PNG/JPG at A4 landscape resolution (recommended: 2481×1754px @ 300 DPI).
          Leave blank space where names/dates will be printed.
        </p>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
          <input
            type="file"
            accept="image/png,image/jpeg"
            id="template-image-file"
            style={{ display: 'none' }}
            onChange={handleFileChange}
          />
          <button
            onClick={() => document.getElementById('template-image-file')?.click()}
            className="role-filter-chip"
            style={{ cursor: 'pointer' }}
          >
            Choose Image
          </button>
          <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
            {imageFile
              ? imageFile.name
              : imageUrl
                ? 'Current template loaded'
                : 'No image selected'}
          </span>
          {imageFile && (
            <button
              onClick={handleUploadImage}
              disabled={isSaving}
              className="role-filter-chip active"
              style={{
                cursor: 'pointer',
                background: 'rgb(22, 192, 122)',
                border: 'none',
                color: 'white',
                display: 'flex',
                alignItems: 'center',
                gap: '6px',
              }}
            >
              {isSaving ? <Loader size={14} className="spinner" /> : <Upload size={14} />}
              Upload
            </button>
          )}
        </div>
      </GlassCard>

      {/* Step 2: Calibrate — only shown once an image is available */}
      {imageUrl && (
        <div style={{ display: 'flex', gap: '16px', flex: 1, marginBottom: '80px' }}>

          {/* Left panel: field list + property controls */}
          <GlassCard padding="16px" style={{ width: '280px', flexShrink: 0 }}>
            <h4 style={{ fontFamily: 'var(--font-space-grotesk)', fontWeight: 700, fontSize: '14px', margin: '0 0 6px 0' }}>
              Fields
            </h4>
            <p style={{ fontSize: '11px', color: 'var(--text-muted)', margin: '0 0 12px 0' }}>
              Select a field, then click the image to place it.
            </p>

            {FIELD_ORDER.map((key) => {
              const placed = !!fields[key];
              return (
                <div
                  key={key}
                  onClick={() => setActiveField(key)}
                  style={{
                    padding: '10px 12px',
                    marginBottom: '6px',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    border: activeField === key
                      ? '1px solid rgb(22,192,122)'
                      : '1px solid var(--border-light)',
                    background: activeField === key
                      ? 'rgba(22,192,122,0.08)'
                      : 'transparent',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                  }}
                >
                  <span style={{ fontSize: '13px', color: placed ? 'white' : 'var(--text-muted)' }}>
                    {FIELD_LABELS[key]}{placed ? ' ✓' : ''}
                  </span>
                  {placed && (
                    <Trash2
                      size={13}
                      style={{ color: '#ef4444', cursor: 'pointer' }}
                      onClick={(e) => { e.stopPropagation(); clearField(key); }}
                    />
                  )}
                </div>
              );
            })}

            {/* Property controls — only shown when the active field is placed */}
            {activeConfig && (
              <div style={{ marginTop: '16px', paddingTop: '16px', borderTop: '1px solid var(--border-light)' }}>
                <label style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'block', marginBottom: '4px' }}>
                  Font Size: {activeConfig.size}px
                </label>
                <input
                  type="range" min={8} max={60}
                  value={activeConfig.size}
                  onChange={(e) => updateFieldProp(activeField, 'size', parseInt(e.target.value))}
                  style={{ width: '100%', marginBottom: '12px' }}
                />

                <label style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'block', marginBottom: '4px' }}>
                  Alignment
                </label>
                <select
                  value={activeConfig.align}
                  onChange={(e) => updateFieldProp(activeField, 'align', e.target.value as FieldConfig['align'])}
                  style={{ width: '100%', marginBottom: '12px', padding: '6px', borderRadius: '6px', background: 'rgba(255,255,255,0.05)', color: 'white', border: '1px solid var(--border-light)' }}
                >
                  <option value="left">Left</option>
                  <option value="center">Center</option>
                  <option value="right">Right</option>
                </select>

                <label style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'block', marginBottom: '4px' }}>
                  Font
                </label>
                <select
                  value={activeConfig.font}
                  onChange={(e) => updateFieldProp(activeField, 'font', e.target.value as FieldConfig['font'])}
                  style={{ width: '100%', marginBottom: '12px', padding: '6px', borderRadius: '6px', background: 'rgba(255,255,255,0.05)', color: 'white', border: '1px solid var(--border-light)' }}
                >
                  <option value="Helvetica">Helvetica</option>
                  <option value="HelveticaBold">Helvetica Bold</option>
                  <option value="TimesRoman">Times Roman</option>
                  <option value="TimesRomanBold">Times Roman Bold</option>
                </select>

                <label style={{ fontSize: '11px', color: 'var(--text-muted)', display: 'block', marginBottom: '4px' }}>
                  Color
                </label>
                <input
                  type="color"
                  value={activeConfig.color}
                  onChange={(e) => updateFieldProp(activeField, 'color', e.target.value)}
                  style={{ width: '100%', height: '32px', borderRadius: '6px', border: '1px solid var(--border-light)', cursor: 'pointer' }}
                />

                {/* Coord readout — helpful for debugging / manual entry */}
                <p style={{ fontSize: '10px', color: 'var(--text-muted)', marginTop: '10px', marginBottom: 0 }}>
                  PDF coords: x={activeConfig.x}, y={activeConfig.y}
                </p>
              </div>
            )}

            <button
              onClick={handleSave}
              disabled={isSaving || Object.keys(fields).length === 0}
              style={{
                width: '100%',
                marginTop: '20px',
                padding: '12px',
                borderRadius: '10px',
                background: Object.keys(fields).length > 0
                  ? '#f59e0b'
                  : 'rgba(255,255,255,0.05)',
                color: Object.keys(fields).length > 0 ? 'white' : 'var(--text-muted)',
                border: 'none',
                fontWeight: 700,
                fontSize: '14px',
                cursor: Object.keys(fields).length > 0 ? 'pointer' : 'default',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: '8px',
              }}
            >
              {isSaving
                ? <><Loader size={16} className="spinner" /> Saving...</>
                : <><Save size={16} /> Save Positions</>
              }
            </button>
          </GlassCard>

          {/* Right panel: image preview with click-to-place + marker overlay */}
          <div style={{ flex: 1, position: 'relative', display: 'flex', justifyContent: 'center', alignItems: 'flex-start' }}>
            <div style={{ position: 'relative', maxWidth: '100%' }}>
              <img
                ref={imgRef}
                src={imageUrl}
                onLoad={handleImageLoad}
                onClick={handleImageClick}
                alt="Certificate template"
                style={{
                  maxWidth: '100%',
                  borderRadius: '8px',
                  cursor: 'crosshair',
                  display: 'block',
                  border: '1px solid var(--border-light)',
                }}
              />

              {/* Field position markers */}
              {imgRef.current &&
                Object.entries(fields).map(([key, config]) => {
                  const rect = imgRef.current!.getBoundingClientRect();
                  const pos  = markerDisplayPos(config, rect.width, rect.height);
                  const isActive = key === activeField;
                  return (
                    <div
                      key={key}
                      style={{
                        position: 'absolute',
                        left: pos.left,
                        top:  pos.top,
                        transform: 'translate(-50%, -50%)',
                        pointerEvents: 'none',
                      }}
                    >
                      <div style={{
                        width: '10px',
                        height: '10px',
                        borderRadius: '50%',
                        background: isActive ? 'rgb(22,192,122)' : '#f59e0b',
                        border: '2px solid white',
                        boxShadow: '0 0 0 2px rgba(0,0,0,0.3)',
                      }} />
                      <span style={{
                        position: 'absolute',
                        top: '12px',
                        left: '50%',
                        transform: 'translateX(-50%)',
                        fontSize: '10px',
                        color: 'white',
                        background: 'rgba(0,0,0,0.7)',
                        padding: '2px 6px',
                        borderRadius: '4px',
                        whiteSpace: 'nowrap',
                      }}>
                        {FIELD_LABELS[key as FieldKey]}
                      </span>
                    </div>
                  );
                })
              }
            </div>
          </div>
        </div>
      )}

      <NavBar />

      <style>{`
        .spinner { animation: spin 1s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
      `}</style>
    </div>
  );
};
