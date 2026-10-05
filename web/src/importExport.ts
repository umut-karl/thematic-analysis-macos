import JSZip from 'jszip';
import type { Worksheet } from 'exceljs';
import type { AnalysisProject, Interview, TranscriptSegment } from './domain';
import { emptyDetails, migrateLegacyPrototype, selectedText, themePathName, validateProject } from './domain';

const headerAliases: Record<string, string[]> = {
  order: ['sıra', 'sira', 'sıra no', 'sira no', 'order', 'index', '#'],
  part: ['parça', 'parca', 'bölüm', 'bolum', 'part', 'section'],
  speaker: ['konuşmacı', 'konusmaci', 'speaker', 'kişi', 'kisi'],
  start: ['başlangıç', 'baslangic', 'başlangıç zamanı', 'start', 'start time'],
  end: ['bitiş', 'bitis', 'bitiş zamanı', 'end', 'end time'],
  text: ['metin', 'transkript', 'transcript', 'text', 'ifade', 'alıntı', 'alinti'],
};

function canonical(value: unknown): string {
  return String(value ?? '').trim().toLocaleLowerCase('tr-TR');
}

function findColumn(headers: unknown[], field: keyof typeof headerAliases): number {
  const aliases = headerAliases[field];
  return headers.findIndex((header) => aliases.includes(canonical(header)));
}

function rowsToSegments(rows: unknown[][]): TranscriptSegment[] {
  if (!rows.length) return [];
  const headers = rows[0];
  const indexes = {
    order: findColumn(headers, 'order'), part: findColumn(headers, 'part'),
    speaker: findColumn(headers, 'speaker'), start: findColumn(headers, 'start'),
    end: findColumn(headers, 'end'), text: findColumn(headers, 'text'),
  };
  if (indexes.text < 0) throw new Error('Metin/transkript sütunu bulunamadı.');
  return rows.slice(1).flatMap((row, index) => {
    const text = String(row[indexes.text] ?? '').trim();
    if (!text) return [];
    const rawOrder = indexes.order >= 0 ? Number(row[indexes.order]) : index + 1;
    const rawPart = indexes.part >= 0 ? Number(row[indexes.part]) : Number.NaN;
    return [{
      id: crypto.randomUUID(),
      order: Number.isFinite(rawOrder) && rawOrder > 0 ? Math.trunc(rawOrder) : index + 1,
      part: Number.isFinite(rawPart) ? Math.trunc(rawPart) : null,
      speaker: indexes.speaker >= 0 ? String(row[indexes.speaker] ?? '').trim() : '',
      start: indexes.start >= 0 ? String(row[indexes.start] ?? '').trim() : '',
      end: indexes.end >= 0 ? String(row[indexes.end] ?? '').trim() : '',
      text,
    }];
  }).sort((a, b) => a.order - b.order).map((segment, index) => ({ ...segment, order: index + 1 }));
}

export async function parseTranscript(file: File): Promise<TranscriptSegment[]> {
  const extension = file.name.split('.').pop()?.toLowerCase();
  if (file.size > 25 * 1024 * 1024) throw new Error('Transkript dosyası 25 MB sınırını aşıyor.');
  if (!extension || !['xlsx', 'csv', 'tsv', 'txt', 'md'].includes(extension)) throw new Error('Desteklenmeyen transkript dosyası.');
  if (extension === 'txt' || extension === 'md') {
    const text = await file.text();
    return text.split(/\n\s*\n|\n/).map((line) => line.trim()).filter(Boolean).map((line, index) => ({
      id: crypto.randomUUID(), order: index + 1, part: null, speaker: '', start: '', end: '', text: line,
    }));
  }
  if (extension === 'csv' || extension === 'tsv') {
    const rows = parseDelimited(await file.text(), extension === 'tsv' ? '\t' : ',');
    const segments = rowsToSegments(rows);
    if (!segments.length) throw new Error('Dosyada içe aktarılabilecek transkript satırı yok.');
    return segments;
  }
  const { default: ExcelJS } = await import('exceljs');
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(await file.arrayBuffer());
  const firstSheet = workbook.worksheets[0];
  if (!firstSheet) throw new Error('Çalışma kitabında okunabilir sayfa yok.');
  const rows: unknown[][] = [];
  firstSheet.eachRow({ includeEmpty: false }, (row) => {
    const values = row.values as unknown[];
    rows.push(values.slice(1).map(cellText));
  });
  const segments = rowsToSegments(rows);
  if (!segments.length) throw new Error('Dosyada içe aktarılabilecek transkript satırı yok.');
  return segments;
}

export function createInterview(
  participant: string,
  interviewName: string,
  segments: TranscriptSegment[],
  details = emptyDetails(),
): Interview {
  return {
    id: crypto.randomUUID(), participant: participant.trim(),
    name: interviewName.trim() || `${participant.trim()} Transkripti`,
    participantDetails: details, importedAt: new Date().toISOString(), segments, codingUnits: [],
  };
}

export async function readProjectBackup(file: File): Promise<{ project: AnalysisProject; migrated: boolean }> {
  let input: unknown;
  if (file.name.toLowerCase().endsWith('.zip')) {
    const zip = await JSZip.loadAsync(await file.arrayBuffer());
    const entry = Object.values(zip.files).find((item) => item.name.endsWith('Proje-Verisi.json'));
    if (!entry) throw new Error('Arşivde Proje-Verisi.json bulunamadı.');
    input = JSON.parse(await entry.async('string'));
  } else {
    input = JSON.parse(await file.text());
  }
  const validated = (() => { try { return validateProject(input); } catch { return null; } })();
  if (validated) return { project: validated, migrated: false };
  const migrated = migrateLegacyPrototype(input);
  if (migrated) return { project: migrated, migrated: true };
  throw new Error('Yedek dosyası desteklenen proje şemasına uymuyor.');
}

export function downloadJSON(project: AnalysisProject): void {
  downloadBlob(
    new Blob([JSON.stringify(validateProject(project), null, 2)], { type: 'application/json;charset=utf-8' }),
    `${safeName(project.name)}-Proje-Verisi.json`,
  );
}

export async function exportTranscriptXLSX(interview: Interview): Promise<void> {
  const { default: ExcelJS } = await import('exceljs');
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Transkript');
  sheet.addRow(['Sıra', 'Parça', 'Konuşmacı', 'Başlangıç', 'Bitiş', 'Metin']);
  for (const segment of [...interview.segments].sort((a, b) => a.order - b.order)) {
    sheet.addRow([segment.order, segment.part ?? '', segment.speaker, segment.start, segment.end, segment.text]);
  }
  styleWorksheet(sheet);
  downloadBlob(new Blob([await workbook.xlsx.writeBuffer()], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), `${safeName(interview.participant)}-Transkript.xlsx`);
}

export async function exportQuotesXLSX(project: AnalysisProject): Promise<void> {
  const rows = project.interviews.flatMap((interview) => interview.codingUnits.map((unit) => {
    const segments = interview.segments.filter((segment) => unit.segmentIDs.includes(segment.id)).sort((a, b) => a.order - b.order);
    return {
      Katılımcı: interview.participant, Görüşme: interview.name,
      Konuşmacı: segments[0]?.speaker ?? '',
      Zaman: `${segments[0]?.start ?? ''}–${segments.at(-1)?.end ?? ''}`,
      Alıntı: selectedText(interview, unit.segmentIDs),
      'Tema Yolları': unit.themeIDs.map((id) => themePathName(project, id)).join(' | '),
      'Analitik Not': unit.memo,
    };
  }));
  const { default: ExcelJS } = await import('exceljs');
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Kodlanmış Alıntılar');
  const headers = ['Katılımcı', 'Görüşme', 'Konuşmacı', 'Zaman', 'Alıntı', 'Tema Yolları', 'Analitik Not'];
  sheet.addRow(headers);
  for (const row of rows) sheet.addRow(headers.map((header) => row[header as keyof typeof row]));
  styleWorksheet(sheet);
  downloadBlob(new Blob([await workbook.xlsx.writeBuffer()], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), `${safeName(project.name)}-Kodlanmis-Alintilar.xlsx`);
}

function parseDelimited(text: string, delimiter: string): string[][] {
  const rows: string[][] = []; let row: string[] = []; let cell = ''; let quoted = false;
  const normalized = text.replace(/^\uFEFF/, '');
  for (let index = 0; index < normalized.length; index += 1) {
    const character = normalized[index];
    if (character === '"') {
      if (quoted && normalized[index + 1] === '"') { cell += '"'; index += 1; }
      else quoted = !quoted;
    } else if (character === delimiter && !quoted) { row.push(cell); cell = ''; }
    else if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && normalized[index + 1] === '\n') index += 1;
      row.push(cell); rows.push(row); row = []; cell = '';
    } else cell += character;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function cellText(value: unknown): string {
  if (value == null) return '';
  if (typeof value === 'object' && 'text' in value) return String((value as { text: unknown }).text ?? '');
  if (typeof value === 'object' && 'result' in value) return String((value as { result: unknown }).result ?? '');
  return String(value);
}

function styleWorksheet(sheet: Worksheet): void {
  const header = sheet.getRow(1);
  header.font = { bold: true, color: { argb: 'FFFFFFFF' } };
  header.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF087AF5' } };
  header.alignment = { vertical: 'middle' };
  sheet.views = [{ state: 'frozen', ySplit: 1 }];
  sheet.columns.forEach((column, index) => { column.width = index === sheet.columns.length - 1 ? 70 : index > 3 ? 26 : 18; });
  sheet.eachRow((row, index) => { if (index > 1) row.alignment = { vertical: 'top', wrapText: true }; });
}

function safeName(value: string): string {
  return value.replace(/[/:\\?%*|"<>]/g, '-').trim() || 'Tematik-Analiz';
}

function downloadBlob(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url; anchor.download = name; document.body.append(anchor); anchor.click(); anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1_000);
}
