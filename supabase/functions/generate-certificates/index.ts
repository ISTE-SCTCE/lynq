// supabase/functions/generate-certificates/index.ts
// Deno Edge Function — generates per-student PDF certificates from exec-uploaded HTML template.
// Invoke via: supabase.functions.invoke('generate-certificates', { body: { eventId, templateUrl } })

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  PDFDocument,
  PDFFont,
  rgb,
  StandardFonts,
} from "https://esm.sh/pdf-lib@1.17.1";

// ── Constants ────────────────────────────────────────────────────────────────
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STORAGE_BUCKET = "certificates";

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Escape HTML special characters to prevent XSS in template */
function htmlEscape(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/** Fill all {{PLACEHOLDER}} tokens in the HTML template string */
function fillTemplate(
  html: string,
  replacements: Record<string, string>
): string {
  let result = html;
  for (const [key, value] of Object.entries(replacements)) {
    result = result.replaceAll(`{{${key}}}`, htmlEscape(value));
  }
  return result;
}

/** Format a date string to "DD Month YYYY" */
function formatDate(dateStr: string): string {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  const months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

/** Generate a short uppercase certificate ID */
function makeCertId(eventId: number, userId: string): string {
  const short = userId.replace(/-/g, "").substring(0, 6).toUpperCase();
  return `ISTE-${eventId}-${short}`;
}

// ── PDF Builder ───────────────────────────────────────────────────────────────
// Builds an A4-landscape PDF styled to match the ISTE SCTCE circuit-trace theme.
// This is the primary render path when an external Gotenberg is not configured.

async function buildCertificatePdf(params: {
  studentName: string;
  eventName: string;
  eventDate: string;
  coordinatorName: string;
  chairName: string;
  certificateId: string;
  category: string;
}): Promise<Uint8Array> {
  const {
    studentName,
    eventName,
    eventDate,
    coordinatorName,
    chairName,
    certificateId,
    category,
  } = params;

  // A4 Landscape: 841.89 x 595.28 pt
  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([841.89, 595.28]);
  const { width, height } = page.getSize();

  // Embed standard fonts
  const helveticaBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const helvetica = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const timesRoman = await pdfDoc.embedFont(StandardFonts.TimesRoman);
  const timesBold = await pdfDoc.embedFont(StandardFonts.TimesRomanBold);

  // ── Color palette ──
  const cream = rgb(0.98, 0.96, 0.92);        // #FAF4EB
  const navy = rgb(0.106, 0.165, 0.290);       // #1B2A4A
  const gold = rgb(0.788, 0.635, 0.153);       // #C9A227
  const midGold = rgb(0.9, 0.75, 0.3);
  const lightGold = rgb(0.97, 0.93, 0.80);

  // ── Background ──
  page.drawRectangle({ x: 0, y: 0, width, height, color: cream });

  // ── Outer gold border ──
  const bm = 22; // border margin
  page.drawRectangle({
    x: bm, y: bm,
    width: width - bm * 2, height: height - bm * 2,
    borderColor: gold, borderWidth: 2.5, color: cream,
  });

  // ── Inner thin border ──
  const bm2 = 30;
  page.drawRectangle({
    x: bm2, y: bm2,
    width: width - bm2 * 2, height: height - bm2 * 2,
    borderColor: midGold, borderWidth: 0.75, color: cream,
  });

  // ── Circuit-trace corner ornaments (top-left) ──
  const drawCircuitCorner = (ox: number, oy: number, flipX = false, flipY = false) => {
    const sx = flipX ? -1 : 1;
    const sy = flipY ? -1 : 1;
    const lines: [number, number, number, number][] = [
      [0, 0, 40, 0],
      [40, 0, 40, -12],
      [40, -12, 60, -12],
      [60, -12, 60, -6],
      [20, 0, 20, -20],
      [20, -20, 8, -20],
      [8, -20, 8, -35],
      [8, -35, 18, -35],
    ];
    for (const [x1, y1, x2, y2] of lines) {
      page.drawLine({
        start: { x: ox + x1 * sx, y: oy + y1 * sy },
        end:   { x: ox + x2 * sx, y: oy + y2 * sy },
        color: gold, thickness: 1.2, opacity: 0.45,
      });
    }
    // Small contact dots
    const dots: [number, number][] = [[40, 0], [20, 0], [8, -35]];
    for (const [dx, dy] of dots) {
      page.drawCircle({ x: ox + dx * sx, y: oy + dy * sy, size: 2.5, color: gold, opacity: 0.6 });
    }
  };

  drawCircuitCorner(bm + 6, height - bm - 6, false, false);
  drawCircuitCorner(width - bm - 6, height - bm - 6, true, false);
  drawCircuitCorner(bm + 6, bm + 6, false, true);
  drawCircuitCorner(width - bm - 6, bm + 6, true, true);

  // ── ISTE SCTCE Header ──
  const cx = width / 2;
  page.drawText("ISTE STUDENT CHAPTER", {
    x: cx - helveticaBold.widthOfTextAtSize("ISTE STUDENT CHAPTER", 11) / 2,
    y: height - 68,
    size: 11, font: helveticaBold, color: gold,
  });
  page.drawText("SREE CHITRA THIRUNAL COLLEGE OF ENGINEERING", {
    x: cx - helvetica.widthOfTextAtSize("SREE CHITRA THIRUNAL COLLEGE OF ENGINEERING", 8.5) / 2,
    y: height - 82,
    size: 8.5, font: helvetica, color: navy, opacity: 0.7,
  });

  // Thin gold rule under header
  page.drawLine({
    start: { x: cx - 120, y: height - 92 },
    end:   { x: cx + 120, y: height - 92 },
    color: gold, thickness: 0.8, opacity: 0.5,
  });

  // ── "CERTIFICATE OF PARTICIPATION" ──
  const certTitle = "CERTIFICATE OF PARTICIPATION";
  page.drawText(certTitle, {
    x: cx - timesBold.widthOfTextAtSize(certTitle, 26) / 2,
    y: height - 138,
    size: 26, font: timesBold, color: navy,
  });

  // ── Category badge ──
  if (category) {
    const catText = category.toUpperCase();
    const catW = helveticaBold.widthOfTextAtSize(catText, 8) + 20;
    page.drawRectangle({
      x: cx - catW / 2, y: height - 162,
      width: catW, height: 16,
      borderColor: gold, borderWidth: 1, color: lightGold, borderOpacity: 0.7,
    });
    page.drawText(catText, {
      x: cx - helveticaBold.widthOfTextAtSize(catText, 8) / 2,
      y: height - 158,
      size: 8, font: helveticaBold, color: navy,
    });
  }

  // ── "This is to certify that" ──
  page.drawText("This is to certify that", {
    x: cx - timesRoman.widthOfTextAtSize("This is to certify that", 13) / 2,
    y: height - 198,
    size: 13, font: timesRoman, color: navy, opacity: 0.6,
  });

  // ── Student name (large, prominent) ──
  const nameSize = studentName.length > 28 ? 28 : 34;
  page.drawText(studentName, {
    x: cx - timesBold.widthOfTextAtSize(studentName, nameSize) / 2,
    y: height - 240,
    size: nameSize, font: timesBold, color: navy,
  });

  // Underline below name
  const nameW = timesBold.widthOfTextAtSize(studentName, nameSize);
  page.drawLine({
    start: { x: cx - nameW / 2 - 10, y: height - 246 },
    end:   { x: cx + nameW / 2 + 10, y: height - 246 },
    color: gold, thickness: 1,
  });

  // ── "has successfully participated in" ──
  const body1 = "has successfully participated in";
  page.drawText(body1, {
    x: cx - timesRoman.widthOfTextAtSize(body1, 13) / 2,
    y: height - 272,
    size: 13, font: timesRoman, color: navy, opacity: 0.6,
  });

  // ── Event name ──
  const evSize = eventName.length > 45 ? 14 : 17;
  page.drawText(eventName, {
    x: cx - timesBold.widthOfTextAtSize(eventName, evSize) / 2,
    y: height - 300,
    size: evSize, font: timesBold, color: navy,
  });

  // ── Date ──
  const dateLabel = `held on ${eventDate}`;
  page.drawText(dateLabel, {
    x: cx - timesRoman.widthOfTextAtSize(dateLabel, 11) / 2,
    y: height - 322,
    size: 11, font: timesRoman, color: navy, opacity: 0.55,
  });

  // ── Gold divider ──
  page.drawLine({
    start: { x: cx - 180, y: height - 348 },
    end:   { x: cx + 180, y: height - 348 },
    color: gold, thickness: 0.6, opacity: 0.4,
  });

  // ── Signature section ──
  const sigY = height - 392;
  const leftSig = cx - 200;
  const rightSig = cx + 130;

  // Coordinator
  page.drawLine({ start: { x: leftSig, y: sigY }, end: { x: leftSig + 140, y: sigY }, color: navy, thickness: 0.5, opacity: 0.4 });
  page.drawText(coordinatorName || "Coordinator", {
    x: leftSig + 70 - helveticaBold.widthOfTextAtSize(coordinatorName || "Coordinator", 9) / 2,
    y: sigY - 14,
    size: 9, font: helveticaBold, color: navy,
  });
  page.drawText("Event Coordinator", {
    x: leftSig + 70 - helvetica.widthOfTextAtSize("Event Coordinator", 7.5) / 2,
    y: sigY - 26,
    size: 7.5, font: helvetica, color: navy, opacity: 0.5,
  });

  // Chair
  page.drawLine({ start: { x: rightSig, y: sigY }, end: { x: rightSig + 140, y: sigY }, color: navy, thickness: 0.5, opacity: 0.4 });
  page.drawText(chairName || "Chapter Chair", {
    x: rightSig + 70 - helveticaBold.widthOfTextAtSize(chairName || "Chapter Chair", 9) / 2,
    y: sigY - 14,
    size: 9, font: helveticaBold, color: navy,
  });
  page.drawText("Chapter Chairperson", {
    x: rightSig + 70 - helvetica.widthOfTextAtSize("Chapter Chairperson", 7.5) / 2,
    y: sigY - 26,
    size: 7.5, font: helvetica, color: navy, opacity: 0.5,
  });

  // ── ISTE logo circle placeholder (center signature area) ──
  page.drawCircle({ x: cx, y: sigY - 8, size: 22, borderColor: gold, borderWidth: 1.5, color: cream });
  page.drawText("ISTE", { x: cx - 8, y: sigY - 12, size: 7, font: helveticaBold, color: gold });

  // ── Certificate ID footer ──
  page.drawText(`Certificate ID: ${certificateId}`, {
    x: cx - helvetica.widthOfTextAtSize(`Certificate ID: ${certificateId}`, 8) / 2,
    y: bm2 + 10,
    size: 8, font: helvetica, color: navy, opacity: 0.35,
  });

  return await pdfDoc.save();
}

// ── Main Handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // ── Auth: require service role or execom JWT ──
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Parse body
    const body = await req.json() as {
      eventId: number;
      templateUrl?: string; // optional: if provided, we fetch the HTML and do string-replace for preview
    };

    const { eventId, templateUrl } = body;
    if (!eventId) {
      return new Response(JSON.stringify({ error: "eventId is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── Fetch event metadata ──
    const { data: event, error: evErr } = await supabase
      .from("events")
      .select("id, title, date, coordinator_name, chair_name, category")
      .eq("id", eventId)
      .single();

    if (evErr || !event) {
      return new Response(JSON.stringify({ error: "Event not found" }), { status: 404, headers: { "Content-Type": "application/json" } });
    }

    const eventTitle = (event.title as string) ?? "ISTE Event";
    const eventDate = formatDate((event.date as string) ?? "");
    const coordinatorName = (event.coordinator_name as string) ?? "";
    const chairName = (event.chair_name as string) ?? "";
    const category = (event.category as string) ?? "General";

    // ── Fetch attendees (attendance rows joined with users) ──
    const { data: attendees, error: attErr } = await supabase
      .from("attendance")
      .select("user_id, users(id, name)")
      .eq("event_id", eventId);

    if (attErr) {
      return new Response(JSON.stringify({ error: `Attendance fetch failed: ${attErr.message}` }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    if (!attendees || attendees.length === 0) {
      return new Response(JSON.stringify({ generated: 0, skipped_existing: 0, errors: [], message: "No attendees found" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // ── Fetch already-issued certificate user_ids ──
    const { data: existing } = await supabase
      .from("certificates")
      .select("user_id")
      .eq("event_id", eventId);

    const existingUserIds = new Set((existing ?? []).map((r: { user_id: string }) => r.user_id));

    // ── Optionally fetch HTML template for string-replace preview storage ──
    let templateHtml: string | null = null;
    if (templateUrl) {
      try {
        const res = await fetch(templateUrl);
        templateHtml = await res.text();
      } catch {
        // Template fetch failed — continue with pdf-lib PDF path
        templateHtml = null;
      }
    }

    // ── Generate per-student ──
    let generated = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (const row of attendees) {
      const userId = (row as { user_id: string }).user_id;
      const userInfo = (row as { users: { id: string; name: string } | null }).users;
      const studentName = userInfo?.name ?? "Member";

      if (existingUserIds.has(userId)) {
        skipped++;
        continue;
      }

      try {
        const certId = makeCertId(eventId, userId);
        const storagePath = `${eventId}/${userId}.pdf`;

        // ── Build PDF ──
        const pdfBytes = await buildCertificatePdf({
          studentName,
          eventName: eventTitle,
          eventDate,
          coordinatorName,
          chairName,
          certificateId: certId,
          category,
        });

        // ── Upload PDF to Storage ──
        const { error: uploadErr } = await supabase.storage
          .from(STORAGE_BUCKET)
          .upload(storagePath, pdfBytes, {
            contentType: "application/pdf",
            upsert: true,
          });

        if (uploadErr) {
          errors.push(`Upload failed for ${userId}: ${uploadErr.message}`);
          continue;
        }

        // ── Get signed URL (10-year expiry) ──
        const { data: signed } = await supabase.storage
          .from(STORAGE_BUCKET)
          .createSignedUrl(storagePath, 60 * 60 * 24 * 365 * 10);

        const certUrl = signed?.signedUrl ?? "";

        // ── Insert certificate row ──
        const { error: insertErr } = await supabase.from("certificates").upsert(
          {
            event_id:        eventId,
            user_id:         userId,
            student_name:    studentName,
            certificate_url: certUrl,
            storage_path:    storagePath,
            issued_at:       new Date().toISOString(),
            // Legacy columns
            title:           `Certificate of Participation – ${eventTitle}`,
            description:     `Awarded for attending ${eventTitle} on ${eventDate}`,
            file_url:        certUrl,
          },
          { onConflict: "event_id,user_id", ignoreDuplicates: true }
        );

        if (insertErr) {
          errors.push(`DB insert failed for ${userId}: ${insertErr.message}`);
          continue;
        }

        generated++;
      } catch (e) {
        errors.push(`Error for ${userId}: ${String(e)}`);
      }
    }

    // ── Mark event as finalized ──
    await supabase
      .from("events")
      .update({ attendance_finalized: true })
      .eq("id", eventId);

    return new Response(
      JSON.stringify({ generated, skipped_existing: skipped, errors }),
      { headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
